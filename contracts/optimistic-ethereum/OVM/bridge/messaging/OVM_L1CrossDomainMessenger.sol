// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Library Imports */
import { Lib_OVMCodec } from "../../../libraries/codec/Lib_OVMCodec.sol";
import { Lib_AddressResolver } from "../../../libraries/resolver/Lib_AddressResolver.sol";
import { Lib_AddressManager } from "../../../libraries/resolver/Lib_AddressManager.sol";
import { Lib_SecureMerkleTrie } from "../../../libraries/trie/Lib_SecureMerkleTrie.sol";
import { Lib_ReentrancyGuard } from "../../../libraries/utils/Lib_ReentrancyGuard.sol";

/* Interface Imports */
import { iOVM_L1CrossDomainMessenger } from "../../../iOVM/bridge/messaging/iOVM_L1CrossDomainMessenger.sol";
import { iOVM_CanonicalTransactionChain } from "../../../iOVM/chain/iOVM_CanonicalTransactionChain.sol";
import { iOVM_StateCommitmentChain } from "../../../iOVM/chain/iOVM_StateCommitmentChain.sol";

/* Contract Imports */
import { Abs_BaseCrossDomainMessenger } from "./Abs_BaseCrossDomainMessenger.sol";

import "hardhat/console.sol";

/**
 * @title OVM_L1CrossDomainMessenger
 * @dev The L1 Cross Domain Messenger contract sends messages from L1 to L2, and relays messages from L2 onto L1. 
 * In the event that a message sent from L1 to L2 is rejected for exceeding the L2 epoch gas limit, it can be resubmitted 
 * via this contract's replay function. 
 *
 * Compiler used: solc
 * Runtime target: EVM
 */
contract OVM_L1CrossDomainMessenger is iOVM_L1CrossDomainMessenger, Abs_BaseCrossDomainMessenger, Lib_AddressResolver {

    /***************
     * Constructor *
     ***************/

    /**
     * Pass a default zero address to the address resolver. This will be updated when initialized.
     */
    constructor()
        Lib_AddressResolver(address(0))
    {}

    /**
     * @param _libAddressManager Address of the Address Manager.
     */
    function initialize(
        address _libAddressManager
    )
        public
    {
        console.log("xxl OVM_L1CrossDomainMessenger initialize " );
        require(address(libAddressManager) == address(0), "L1CrossDomainMessenger already intialized.");
        libAddressManager = Lib_AddressManager(_libAddressManager);

        // console.log("libAddressManager");
        // console.log(libAddressManager);

        xDomainMsgSender = DEFAULT_XDOMAIN_SENDER;

        console.log("DEFAULT_XDOMAIN_SENDER");
        console.log(DEFAULT_XDOMAIN_SENDER);

    }


    /**********************
     * Function Modifiers *
     **********************/

    /**
     * Modifier to enforce that, if configured, only the OVM_L2MessageRelayer contract may successfully call a method.
     */
    modifier onlyRelayer() {
        address relayer = resolve("OVM_L2MessageRelayer");
        if (relayer != address(0)) {
            require(
                msg.sender == relayer,
                "Only OVM_L2MessageRelayer can relay L2-to-L1 messages."
            );
        }
        _;
    }


    /********************
     * Public Functions *
     ********************/

    /**
     * Relays a cross domain message to a contract.
     * @inheritdoc iOVM_L1CrossDomainMessenger
     */
    function relayMessage(
        address _target,
        address _sender,
        bytes memory _message,
        uint256 _messageNonce,
        L2MessageInclusionProof memory _proof
    )
        override
        public
        nonReentrant
        onlyRelayer()
    {
        console.log("xxl L1 OVM_L1CrossDomainMessenger relayMessage " );

        console.log("xxl L1 _getXDomainCalldata _target =%s,_sender=%s,_messageNonce=%d",_target,_sender,_messageNonce);
        console.log("_message");
        console.logBytes(_message);

        bytes memory xDomainCalldata = _getXDomainCalldata(
            _target,
            _sender,
            _message,
            _messageNonce
        );

        console.logBytes("xxl L1 xDomainCalldata");
        console.logBytes(xDomainCalldata);

        console.log("xxl L1 L2MessageInclusionProof ");

        console.log("xxl L1 L2MessageInclusionProof stateRoot");
        console.logBytes32(_proof.stateRoot);

        console.log("xxl L1 L2MessageInclusionProof ChainBatchHeader batchIndex=%d",_proof.stateRootBatchHeader.batchIndex);
        console.log("xxl L1 L2MessageInclusionProof ChainBatchHeader batchRoot");
        console.logBytes32(_proof.stateRootBatchHeader.batchRoot);
        console.log("xxl L1 L2MessageInclusionProof ChainBatchHeader batchSize=%d",_proof.stateRootBatchHeader.batchSize);
        console.log("xxl L1 L2MessageInclusionProof ChainBatchHeader prevTotalElements=%d",_proof.stateRootBatchHeader.prevTotalElements);
        console.log("xxl L1 L2MessageInclusionProof ChainBatchHeader extraData");
        console.logBytes(_proof.stateRootBatchHeader.extraData);

        console.log("xxl L1 L2MessageInclusionProof ChainInclusionProof index=%d",_proof.stateRootProof.index);
        uint sSzie = _proof.stateRootProof.siblings.length;
        console.log("xxl L1 L2MessageInclusionProof ChainInclusionProof siblings total=%d",sSzie);
        for (uint i = 0; i < sSzie; ++i){
            console.log("xxl L1 L2MessageInclusionProof ChainInclusionProof siblings i=%d",i);
            console.logBytes32(_proof.stateRootProof.siblings[i]);
        }
        
        console.log("xxl L1 L2MessageInclusionProof stateTrieWitness");
        console.logBytes(_proof.stateTrieWitness);
        console.log("xxl L1 L2MessageInclusionProof storageTrieWitness");
        console.logBytes(_proof.storageTrieWitness);

        //
        console.log("xxl L1 for case error start ....");
        require(
            _verifyXDomainMessage(
                xDomainCalldata,
                _proof
            ) == false,
            "Provided message could not be verified."
        );

        console.log("xxl L1 case error not work !");

        bytes32 xDomainCalldataHash = keccak256(xDomainCalldata);

        require(
            successfulMessages[xDomainCalldataHash] == false,
            "Provided message has already been received."
        );
        
        xDomainMsgSender = _sender;
        (bool success, ) = _target.call(_message);
        xDomainMsgSender = DEFAULT_XDOMAIN_SENDER;

        // Mark the message as received if the call was successful. Ensures that a message can be
        // relayed multiple times in the case that the call reverted.
        if (success == true) {
            successfulMessages[xDomainCalldataHash] = true;
            emit RelayedMessage(xDomainCalldataHash);
        }

        // Store an identifier that can be used to prove that the given message was relayed by some
        // user. Gives us an easy way to pay relayers for their work.
        bytes32 relayId = keccak256(
            abi.encodePacked(
                xDomainCalldata,
                msg.sender,
                block.number
            )
        );
        relayedMessages[relayId] = true;
    }

    /**
     * Replays a cross domain message to the target messenger.
     * @inheritdoc iOVM_L1CrossDomainMessenger
     */
    function replayMessage(
        address _target,
        address _sender,
        bytes memory _message,
        uint256 _messageNonce,
        uint32 _gasLimit
    )
        override
        public
    {
        console.log("xxl OVM_L1CrossDomainMessenger replayMessage " );

        bytes memory xDomainCalldata = _getXDomainCalldata(
            _target,
            _sender,
            _message,
            _messageNonce
        );

        require(
            sentMessages[keccak256(xDomainCalldata)] == true,
            "Provided message has not already been sent."
        );

        _sendXDomainMessage(xDomainCalldata, _gasLimit);
    }


    /**********************
     * Internal Functions *
     **********************/

    /**
     * Verifies that the given message is valid.
     * @param _xDomainCalldata Calldata to verify.
     * @param _proof Inclusion proof for the message.
     * @return Whether or not the provided message is valid.
     */
    function _verifyXDomainMessage(
        bytes memory _xDomainCalldata,
        L2MessageInclusionProof memory _proof
    )
        internal
        view
        returns (
            bool
        )
    {
        console.log("xxl OVM_L1CrossDomainMessenger _verifyXDomainMessage " );
        return (
            _verifyStateRootProof(_proof)
            && _verifyStorageProof(_xDomainCalldata, _proof)
        );
    }

    /**
     * Verifies that the state root within an inclusion proof is valid.
     * @param _proof Message inclusion proof.
     * @return Whether or not the provided proof is valid.
     */
    function _verifyStateRootProof(
        L2MessageInclusionProof memory _proof
    )
        internal
        view
        returns (
            bool
        )
    {
        console.log("xxl OVM_L1CrossDomainMessenger _verifyStateRootProof " );
        iOVM_StateCommitmentChain ovmStateCommitmentChain = iOVM_StateCommitmentChain(resolve("OVM_StateCommitmentChain"));

        return (
            ovmStateCommitmentChain.insideFraudProofWindow(_proof.stateRootBatchHeader) == false
            && ovmStateCommitmentChain.verifyStateCommitment(
                _proof.stateRoot,
                _proof.stateRootBatchHeader,
                _proof.stateRootProof
            )
        );
    }

    /**
     * Verifies that the storage proof within an inclusion proof is valid.
     * @param _xDomainCalldata Encoded message calldata.
     * @param _proof Message inclusion proof.
     * @return Whether or not the provided proof is valid.
     */
    function _verifyStorageProof(
        bytes memory _xDomainCalldata,
        L2MessageInclusionProof memory _proof
    )
        internal
        view
        returns (
            bool
        )
    {
        console.log("xxl OVM_L1CrossDomainMessenger _verifyStorageProof " );

        bytes32 storageKey = keccak256(
            abi.encodePacked(
                keccak256(
                    abi.encodePacked(
                        _xDomainCalldata,
                        resolve("OVM_L2CrossDomainMessenger")
                    )
                ),
                uint256(0)
            )
        );

        (
            bool exists,
            bytes memory encodedMessagePassingAccount
        ) = Lib_SecureMerkleTrie.get(
            abi.encodePacked(0x4200000000000000000000000000000000000000),
            _proof.stateTrieWitness,
            _proof.stateRoot
        );

        require(
            exists == true,
            "Message passing predeploy has not been initialized or invalid proof provided."
        );

        Lib_OVMCodec.EVMAccount memory account = Lib_OVMCodec.decodeEVMAccount(
            encodedMessagePassingAccount
        );

        return Lib_SecureMerkleTrie.verifyInclusionProof(
            abi.encodePacked(storageKey),
            abi.encodePacked(uint8(1)),
            _proof.storageTrieWitness,
            account.storageRoot
        );
    }

    /**
     * Sends a cross domain message.
     * @param _message Message to send.
     * @param _gasLimit OVM gas limit for the message.
     */
    function _sendXDomainMessage(
        bytes memory _message,
        uint256 _gasLimit
    )
        override
        internal
    {
        iOVM_CanonicalTransactionChain(resolve("OVM_CanonicalTransactionChain")).enqueue(
            resolve("OVM_L2CrossDomainMessenger"),
            _gasLimit,
            _message
        );
    }
}
