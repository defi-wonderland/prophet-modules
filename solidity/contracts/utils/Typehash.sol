// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

bytes32 constant _PLEDGE_FOR_DISPUTE_TYPEHASH =
  keccak256('pledgeForDispute(Request _request, Dispute _dispute,IAccessController.AccessControl _accessControl)');

bytes32 constant _PLEDGE_AGAINST_DISPUTE_TYPEHASH =
  keccak256('pledgeAgainstDispute(Request _request,Dispute _dispute,IAccessController.AccessControl _accessControl)');

bytes32 constant _CLAIM_PLEDGE_TYPEHASH =
  keccak256('claimPledge(Request _request,Dispute _dispute,AccessControl _accessControl)');

bytes32 constant _CLAIM_VOTE_TYPEHASH =
  keccak256('claimVote(Request _request,Dispute _dispute,AccessControl _accessControl)');

bytes32 constant _CAST_VOTE_TYPEHASH =
  keccak256('castVote(Request _request,Dispute _dispute,uint256 _numberOfVotes,AccessControl _accessControl)');
bytes32 constant _COMMIT_VOTE_TYPEHASH =
  keccak256('commitVote(Request _request,Dispute _dispute,bytes32 _commitment,AccessControl _accessControl)');
bytes32 constant _REVEAL_VOTE_TYPEHASH = keccak256(
  'revealVote(Request _request,Dispute _dispute,uint256 _numberOfVotes,bytes32 _salt,AccessControl _accessControl)'
);
