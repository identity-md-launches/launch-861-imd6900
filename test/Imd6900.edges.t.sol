// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Imd6900} from "../src/Imd6900.sol";

/// @dev Gives authorization tests a real intermediate caller distinct from tx.origin.
contract TokenCallerFixture {
    function move(Imd6900 token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function spend(Imd6900 token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev Complements the deployment and launch tests with allowance lifecycle and arithmetic edges.
/// forge-config: default.fuzz.runs = 1000
contract Imd6900EdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant DEPLOYER = address(0xD3);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    Imd6900 private token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new Imd6900();
    }

    function testOneWeiRoundTripPreservesBalancesAndApprovals() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        _approve(ALICE, SPENDER, 1);
        bytes32 beforeState = _stateDigest();
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, 1));
        assertEq(_stateDigest(), beforeState);
    }

    function testMaximumFiniteAllowanceDecrements() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferAmountRevertsEvenToSelf() public {
        bytes32 beforeState = _stateDigest();
        vm.startPrank(DEPLOYER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        token.transfer(ALICE, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        token.transfer(DEPLOYER, type(uint256).max);
        vm.stopPrank();
        assertEq(_stateDigest(), beforeState);
    }

    function testInfiniteAllowanceDoesNotPermitOverspending() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function testInfiniteAllowanceCanBeReplacedWithFiniteLimit() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        _approve(DEPLOYER, SPENDER, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        bytes32 beforeFailure = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(_stateDigest(), beforeFailure);
    }

    function testInfiniteAllowanceCanBeRevoked() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        _approve(DEPLOYER, SPENDER, 0);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function testSpentAllowanceDoesNotReturnWhenTokensAreReturned() public {
        _approve(DEPLOYER, SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, 1));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function testTransferFromByOwnerRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        _approve(DEPLOYER, DEPLOYER, 1);
        vm.prank(DEPLOYER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
    }

    function testApprovalCannotBeUsedByAnotherSpenderEvenWhenPayingApprovedSpender() public {
        _approve(DEPLOYER, SPENDER, SUPPLY);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, SPENDER, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function testTransferUsesImmediateCallerBalance() public {
        TokenCallerFixture caller = new TokenCallerFixture();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(caller), 0, 1));
        vm.prank(DEPLOYER, DEPLOYER);
        caller.move(token, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        vm.prank(DEPLOYER);
        assertTrue(token.transfer(address(caller), 1));
        vm.prank(DEPLOYER, DEPLOYER);
        assertTrue(caller.move(token, ALICE, 1));
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
    }

    function testTransferFromUsesImmediateCallerAllowance() public {
        TokenCallerFixture caller = new TokenCallerFixture();
        _approve(DEPLOYER, DEPLOYER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(caller), 0, 1));
        vm.prank(DEPLOYER, DEPLOYER);
        caller.spend(token, DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        _approve(DEPLOYER, address(caller), 1);
        vm.prank(DEPLOYER, DEPLOYER);
        assertTrue(caller.spend(token, DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, address(caller)), 0);
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
    }

    function testApproveZeroSpenderRejectsZeroAndMaximum() public {
        bytes32 beforeState = _stateDigest();
        vm.startPrank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, address(0)), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function testZeroTransferToZeroStillRevertsWithInfiniteAllowance() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function testTransferToTokenContractDoesNotBurn() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRepeatedPartialSpendingCannotExceedApproval(uint256 grantSeed, uint256 firstSeed) public {
        uint256 grant = bound(grantSeed, 1, SUPPLY - 1);
        uint256 first = bound(firstSeed, 0, grant);
        _approve(DEPLOYER, SPENDER, grant);
        // An unrelated allowance must survive every spend and the failed retry.
        _approve(DEPLOYER, BOB, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, first));
        assertEq(token.allowance(DEPLOYER, SPENDER), grant - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, grant - first));
        assertEq(token.balanceOf(ALICE), grant);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - grant);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.allowance(DEPLOYER, BOB), type(uint256).max);

        bytes32 beforeFailure = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(_stateDigest(), beforeFailure);
    }

    function testFuzzSplitTransfersEqualSingleTransfer(uint256 amountSeed, uint256 firstSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 first = bound(firstSeed, 0, amount);
        _approve(DEPLOYER, SPENDER, amount);
        uint256 snapshot = vm.snapshotState();
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        bytes32 singleTransferState = _stateDigest();
        assertTrue(vm.revertToStateAndDelete(snapshot));

        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(ALICE, first));
        assertTrue(token.transfer(ALICE, amount - first));
        vm.stopPrank();
        assertEq(_stateDigest(), singleTransferState);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.allowance(DEPLOYER, SPENDER), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRoundTripRestoresAllBalances(uint256 amountSeed, uint256 approval) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        _approve(DEPLOYER, SPENDER, approval);
        _approve(ALICE, SPENDER, approval);
        bytes32 beforeState = _stateDigest();
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, amount));
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzzFailedDelegatedTransferCanBeRetriedAfterFunding(uint256 balanceSeed, uint256 extraSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 extra = bound(extraSeed, 1, SUPPLY - balance);
        uint256 amount = balance + extra;
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, balance));
        _approve(ALICE, SPENDER, amount);
        bytes32 beforeFailure = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(_stateDigest(), beforeFailure);

        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, extra));
        // No new approval: failure must have restored the original spending capacity.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    /// @dev Snapshot the entire touched account set and its allowance matrix, including unrelated pairs.
    function _stateDigest() private view returns (bytes32 digest) {
        address[6] memory accounts = [DEPLOYER, ALICE, BOB, SPENDER, address(0), address(token)];
        digest = keccak256(abi.encode(token.totalSupply(), token.name(), token.symbol(), token.decimals()));
        for (uint256 i; i < accounts.length; ++i) {
            digest = keccak256(abi.encode(digest, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                digest = keccak256(abi.encode(digest, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}
