// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Imd6900} from "../src/Imd6900.sol";

/// @dev All balances stay within four actors. Invalid token calls must revert as expected;
/// an unexpected handler revert fails the campaign. Ghosts come from call inputs, never getters.
contract TokenHandler is Test {
    Imd6900 private immutable token;
    uint256 private immutable initialSupply;
    address[4] private actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) private sent;
    mapping(address => uint256) private received;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Imd6900 token_, uint256 supply_) {
        token = token_;
        initialSupply = supply_;
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function expectedBalance(address account) public view returns (uint256) {
        uint256 initial = account == actors[0] ? initialSupply : 0;
        return initial + received[account] - sent[account];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(amountSeed, 0, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 balance = expectedBalance(owner);
        uint256 limit = balance < allowed ? balance : allowed;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.balanceOf(owner), owner == to ? ownerBefore : ownerBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        _recordTransfer(owner, to, amount);
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    /// @dev Force nonzero delegated spending when random approvals and holders do not align.
    /// Also drives full-balance, self, and maximum-allowance transfers in every campaign.
    function approveAndSpendAll(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance(owner);
        uint256 approval = infinite ? type(uint256).max : amount;
        _approve(owner, spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (!infinite) expectedAllowance[owner][spender] = 0;
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectSpendAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        // Turn an infinite approval into the largest finite approval; do not discard the action.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            _approve(owner, spender, allowed);
        }
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function rejectSpendAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        // Keep the finite branch below max so a failed transfer really has an allowance to roll back.
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance(owner));
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        expectedAllowance[owner][spender] = amount;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        // Fixed supply and the closed recipient set guarantee at least one funded actor.
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(seed % actors.length + i) % actors.length];
            if (expectedBalance(candidate) > 0) return candidate;
        }
        revert("ghost accounting lost the supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract Imd6900InvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Imd6900 private token;
    TokenHandler private handler;

    function setUp() public {
        token = new Imd6900();
        handler = new TokenHandler(token, SUPPLY);
        token.transfer(handler.actor(0), SUPPLY);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.spend.selector;
        selectors[3] = handler.approveAndSpendAll.selector;
        selectors[4] = handler.rejectTransferAboveBalance.selector;
        selectors[5] = handler.rejectSpendAboveAllowance.selector;
        selectors[6] = handler.rejectSpendAboveBalance.selector;
        selectors[7] = handler.rejectZeroRecipient.selector;
        selectors[8] = handler.revokeAndRejectSpend.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address account = handler.actor(i);
            uint256 balance = token.balanceOf(account);
            assertEq(balance, handler.expectedBalance(account), "unaccounted movement of a holder's tokens");
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariantAllowancesMatchApprovalsAndSpending() public view {
        // Checking every pair detects accidental changes to an unrelated owner's or spender's allowance.
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actor(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actor(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
