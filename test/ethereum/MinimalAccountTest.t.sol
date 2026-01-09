// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    SendPackedUserOp sendPackedUserOp;
    ERC20Mock usdc;

    address randomUser = makeAddr("randomUser");
    uint256 constant AMOUNT = 1e18;
    uint256 constant INITIAL_DEPOSIT = 10e18;

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        sendPackedUserOp = new SendPackedUserOp();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();
        usdc = new ERC20Mock();
    }

    // USDC Mint
    // msg.sender -> MinimalAccount
    // mint some amount
    // USDC contract
    // come from EntryPoint

    function encodeMintCall() internal view returns (address dest, uint256 value, bytes memory functionData) {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        dest = address(usdc);
        value = 0;
        functionData = abi.encodeCall(ERC20Mock.mint, (address(minimalAccount), AMOUNT));
    }

    function testOwnerCanExecuteCommands() public {
        // Arrange
        (address dest, uint256 value, bytes memory functionData) = encodeMintCall();
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecuteCommands() public {
        // Arrange
        (address dest, uint256 value, bytes memory functionData) = encodeMintCall();

        // Act
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testRecoverSignedOp() public {
        // Arrange
        (address dest, uint256 value, bytes memory functionData) = encodeMintCall();
        bytes memory executeCallData = abi.encodeCall(MinimalAccount.execute, (dest, value, functionData));

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, address(minimalAccount), networkConfig);
        bytes32 userOperationHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(packedUserOp);

        // Act
        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);

        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    // 1. Sign user ops
    // 2. Call validate user ops
    // 3. Assert the return is correct
    function testValidationOfUserOps() public {
        // Arrange
        (address dest, uint256 value, bytes memory functionData) = encodeMintCall();
        bytes memory executeCallData = abi.encodeCall(MinimalAccount.execute, (dest, value, functionData));

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, address(minimalAccount), networkConfig);
        bytes32 userOperationHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(packedUserOp);
        uint256 missingAccountFunds = 1e18;

        // Act
        vm.prank(networkConfig.entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommands() public {
        // Arrange
        (address dest, uint256 value, bytes memory functionData) = encodeMintCall();
        bytes memory executeCallData = abi.encodeCall(MinimalAccount.execute, (dest, value, functionData));

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOperation(executeCallData, address(minimalAccount), networkConfig);

        vm.deal(address(minimalAccount), INITIAL_DEPOSIT);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        // Act
        vm.prank(randomUser, randomUser);
        IEntryPoint(networkConfig.entryPoint).handleOps(ops, payable(randomUser));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }
}

