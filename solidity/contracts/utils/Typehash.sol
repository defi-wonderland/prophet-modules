// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

bytes32 constant _PLEDGE_FOR_DISPUTE_TYPEHASH = keccak256(
  'pledgeForDispute(IOracle.Request _request, IOracle.Dispute _dispute,IAccessController.AccessControl _accessControl)'
);

bytes32 constant _PLEDGE_AGAINST_DISPUTE_TYPEHASH = keccak256(
  'pledgeAgainstDispute(IOracle.Request _request, IOracle.Dispute _dispute,IAccessController.AccessControl _accessControl)'
);

bytes32 constant _CLAIM_VOTE_TYPEHASH = keccak256('');
bytes32 constant _CLAIM_PLEDGE_TYPEHASH = keccak256('');

bytes32 constant _RELEASE_UNUTILIZED_RESPONSE_TYPEHASH = keccak256('');
bytes32 constant _CAST_VOTE_TYPEHASH = keccak256('');
bytes32 constant _COMMIT_VOTE_TYPEHASH = keccak256('');
bytes32 constant _REVEAL_VOTE_TYPEHASH = keccak256('');
