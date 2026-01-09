// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title MinimalAccount — smart wallet implementing IAccount
/// @author George Usynin
/// @notice This contract allows executing transactions and validating user operations
contract MinimalAccount is IAccount, Ownable {
    /*///////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes);

    /*///////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint private immutable I_ENTRY_POINT;

    /*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param entryPoint The entry point contract for account abstraction
    constructor(IEntryPoint entryPoint) Ownable(msg.sender) {
        I_ENTRY_POINT = entryPoint;
    }

    /*///////////////////////////////////////////////////////////////
                          RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/
    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    /*///////////////////////////////////////////////////////////////
                             EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Executes a transaction from this account
    /// @param dest Destination address
    /// @param value Amount of ETH to send
    /// @param functionData Encoded function data
    function execute(address dest, uint256 value, bytes calldata functionData) external {
        _requireFromEntryPointOrOwner();
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccount__CallFailed(result);
        }
    }

    /// @notice Validates a user operation for account abstraction
    /// @param userOp Packed user operation struct
    /// @param userOpHash Hash of the user operation
    /// @param missingAccountFunds Amount of ETH to prefund
    /// @return validationData Returns SIG_VALIDATION_SUCCESS or SIG_VALIDATION_FAILED
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {
        _requireFromEntryPoint();
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /*///////////////////////////////////////////////////////////////
                              PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the entry point address
    /// @return Address of the entry point
    function getEntryPoint() public view returns (address) {
        return address(I_ENTRY_POINT);
    }

    /*///////////////////////////////////////////////////////////////
                             INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @dev Validates the signature of a user operation
    /// @param userOp Packed user operation struct
    /// @param userOpHash Hash of the user operation
    /// @return validationData Returns SIG_VALIDATION_SUCCESS or SIG_VALIDATION_FAILED
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /// @dev Pays the entry point prefund if needed
    /// @param amount Amount to send
    function _payPrefund(uint256 amount) internal {
        if (amount > 0) {
            (bool success,) = payable(msg.sender).call{value: amount}("");
            (success);
        }
    }

    /// @dev Ensures caller is either entry point or owner
    function _requireFromEntryPointOrOwner() internal view {
        if (msg.sender != address(I_ENTRY_POINT) && msg.sender != owner()) {
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
    }

    /// @dev Ensures caller is entry point
    function _requireFromEntryPoint() internal view {
        if (msg.sender != address(I_ENTRY_POINT)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
    }
}
