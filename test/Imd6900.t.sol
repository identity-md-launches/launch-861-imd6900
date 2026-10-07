// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Imd6900} from "../src/Imd6900.sol";

/// @dev Test-only factory. No token-specific constructor configuration is required.
contract TokenFactoryFixture {
    address private immutable controller = msg.sender;

    function deploy(bytes32 salt) external returns (Imd6900) {
        require(msg.sender == controller, "fixture controller only");
        return new Imd6900{salt: salt}();
    }

    function send(Imd6900 token, address to, uint256 amount) external returns (bool) {
        require(msg.sender == controller, "fixture controller only");
        return token.transfer(to, amount);
    }
}

contract Imd6900Test is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address private constant DEPLOYER = address(0xD3);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    Imd6900 private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new Imd6900();
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "Imd6900");
        assertEq(token.symbol(), "IMD6900");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
    }

    function testConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(ALICE);
        Imd6900 fresh = new Imd6900();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(ALICE), SUPPLY);
        assertEq(fresh.balanceOf(DEPLOYER), 0);
    }

    function testCreate2MintsToFactoryAndLaunchTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("Imd6900 local launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Imd6900).creationCode))
                    )
                )
            )
        );
        vm.prank(address(this), BOB);
        Imd6900 launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(BOB), 0);

        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 seed = SUPPLY / 2; // Test allocation only; no production economics are selected here.
        uint256 remainder = SUPPLY - swarm - seed;
        assertTrue(factory.send(launched, distributor, swarm));
        assertTrue(factory.send(launched, pool, seed));
        assertTrue(factory.send(launched, BOB, remainder));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), seed);
        assertEq(launched.balanceOf(BOB), remainder);

        vm.prank(distributor);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(ALICE), swarm);

        // Exercise both token transfer directions. This fixture does not implement a DEX.
        vm.prank(pool);
        assertTrue(launched.transfer(ALICE, 25 ether));
        assertEq(launched.balanceOf(ALICE), swarm + 25 ether);
        assertEq(launched.balanceOf(pool), seed - 25 ether);
        vm.prank(ALICE);
        assertTrue(launched.transfer(pool, 25 ether));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(pool), seed);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 10 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 10 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 10 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testWholeSupplyCanBeTransferred() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromUnfundedAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferPreservesBalance() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalEmitsEventCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(DEPLOYER, SPENDER, 100 ether);
        vm.startPrank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 100 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 100 ether);
        assertTrue(token.approve(SPENDER, 20 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 20 ether);
        assertEq(token.allowance(DEPLOYER, BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function testTransferFromEmitsEventAndConsumesFiniteAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 40 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 40 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 60 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 40 ether);
        assertEq(token.balanceOf(ALICE), 40 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 60 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromKeepsMaximumAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
    }

    function testTransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, DEPLOYER, 10 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testTransferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.startPrank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
        assertEq(token.allowance(DEPLOYER, address(0)), 0);
    }

    function testTransferFromRejectsInsufficientAllowanceWithoutChangingState() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 11);
        assertEq(token.allowance(DEPLOYER, SPENDER), 10);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferFromRestoresAllowanceWhenBalanceIsInsufficient() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testTransferFromRestoresAllowanceWhenRecipientIsZero() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 100);
        assertEq(token.allowance(DEPLOYER, SPENDER), 100);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromRejectsZeroSender() public {
        // OpenZeppelin validates the allowance owner before reaching its transfer validation.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
    }

    function testDeployerCannotSpendAnotherHoldersTokensWithoutApproval() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testNoMintBurnFreezeOrUpgradeEntrypoints() public {
        bytes[] memory calls = new bytes[](24);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", ALICE, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("setOwner(address)", ALICE);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[7] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[8] = abi.encodeWithSignature("unpause()");
        calls[9] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[12] = abi.encodeWithSignature("blocklist(address)", ALICE);
        calls[13] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[14] = abi.encodeWithSignature("freezeAccount(address)", ALICE);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[16] = abi.encodeWithSignature("setBlocked(address,bool)", ALICE, true);
        calls[17] = abi.encodeWithSignature("lock(address)", ALICE);
        calls[18] = abi.encodeWithSignature("disableTransfers()");
        calls[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[20] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[21] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[22] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[23] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", ALICE, bytes(""));

        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(DEPLOYER);
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100 ether);
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - 100 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testRejectsNativeCurrency() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(ALICE.balance, 1 ether);
    }

    function testRuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != DEPLOYER);
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDelegatedTransferConservesSupply(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 allowance = bound(rawAllowance, amount, type(uint256).max);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, allowance);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.allowance(DEPLOYER, SPENDER), allowance == type(uint256).max ? allowance : allowance - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzCannotTransferAboveBalance(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, amount)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
