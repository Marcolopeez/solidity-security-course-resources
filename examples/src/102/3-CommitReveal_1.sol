// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";


uint256 constant MIN_WINDOW = 2*60; // 2 minutes
uint256 constant MAX_WINDOW = 3*24*60*60; // 3 days

/**
    @notice This contract allows users to vote for a proposal following a Commit-and-reveal scheme.
        However, given the small space of replies (yes/no), it is possible to precalculate the commit hashes
        as the only additional info in the message is the sender address which is public. Rendering the 
        mechanism ineffective
    @custom:deployed-at INSERT ETHERSCAN URL
    @custom:exercise This contract is part of the examples at https://github.com/jcr-security/solidity-security-teaching-resources
 */
contract VotingContract is Ownable {

    /************************************** State vars and Structs *******************************************************/

    struct Proposal {
        string name;
        string description;
        uint256 commitBefore;
        uint256 revealBefore;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    // Window in seconds
    uint256 commitWindow; 
    uint256 revealWindow;

    uint256 public proposalCount;
    mapping(uint256 proposalID => Proposal) public proposals;
    mapping(address committer => mapping(uint256 proposalID => bytes32 commitHash)) public commits;


    /************************************** Events and modifiers *******************************************************/

    event VoteCommited(address user);
    event VoteRevealed(address user, bool vote);
    event VotingEndend(string name, string desc, uint256 forV, uint256 agV);

    
    modifier enforceWindowSize(uint256 commit, uint256 reveal) {
        require(
            commit >= MIN_WINDOW && commit <= MAX_WINDOW 
            && reveal >= MIN_WINDOW && reveal <= MAX_WINDOW, 
            "Minimum windows size of 2 minutes, max of 3 days"
        );
        _;
    }


    modifier validProposal(uint256 id) {
        require(id <= proposalCount, "Proposal not found");
        _;
    }


    modifier isCommitTime(uint256 id) { 
        require(block.timestamp <= proposals[id].commitBefore, "Not the time to Commit"); 
        _; 
    }


    modifier isRevealTime(uint256 id) { 
        require(
            block.timestamp <= proposals[id].revealBefore
            && block.timestamp > proposals[id].commitBefore,
            "Not the time to reveal!"); 
        _; 
    }
    

    /************************************** External *******************************************************/ 

    constructor(uint256 commit, uint256 reveal) enforceWindowSize(commit, reveal) Ownable(msg.sender) {      
        commitWindow = commit;
        revealWindow = reveal;
    }

    function modifyWindowSize(uint256 commit, uint256 reveal) 
        external 
        onlyOwner 
        enforceWindowSize(commit, reveal) 
    {
        commitWindow = commit;
        revealWindow = reveal;
    }

    // Function to submit a new proposal
    function submitProposal(string memory _name, string memory _description) 
        external
        onlyOwner 
        returns(uint256) 
    {
        uint256 newId = proposalCount;
        proposalCount++;

        proposals[newId] = Proposal(
            _name, 
            _description, 
            block.timestamp + commitWindow,
            block.timestamp + commitWindow + revealWindow,
            0, 
            0
        );

        return newId;
    }

    ///@notice Function to commit a vote for a specific proposal
    ///@dev  commitHash is of the format keccak256(abi.encodePacked(bool, msg.sender));
    ///@custom:fix In order to fix the vulnerability, the message should be keccak256(abi.encodePacked(bool, seed));
    ///  where seed is a random value generated by the user. This way, it is not possible to precalculate the 
    ///  commit hash to unveil the vote. Including msg.sender is not needed as it won't matter if our commit get replayed
    function commitVote(uint256 _proposalId, bytes32 commitHash)
        external 
        validProposal(_proposalId) 
        isCommitTime(_proposalId) 
    {
        require(commits[msg.sender][_proposalId] == 0, "The user has already voted for this proposal");
        commits[msg.sender][_proposalId] = commitHash; //is this hash really secret?

        emit VoteCommited(msg.sender);
    }

    // Function to reveal a vote for a specific proposal
    function revealVote(uint256 _proposalId, bool _vote, address _voter) external isRevealTime(_proposalId) {
        // Check that the user has a commit hash for the given proposal
        require(commits[msg.sender][_proposalId] != 0, "No commit hash found for this proposal");
        // Check that the vote matches the commit hash
        require(
            commits[msg.sender][_proposalId] == keccak256(abi.encodePacked(_vote, _voter)), 
            "Vote does not match commit hash"
        );

        // Update the vote count for the proposal
        if(_vote) {
            proposals[_proposalId].votesFor += 1;
        } else {
            proposals[_proposalId].votesAgainst += 1;
        }

        // Set commit to 0 to avoid revealking more than one
        commits[msg.sender][_proposalId] = 0;

        emit VoteRevealed(msg.sender, _vote);
    }

    function votingResults(uint256 id) 
        external   
        returns(string memory, string memory, uint, uint256) 
    {
        require(block.timestamp > proposals[id].revealBefore, "Reveal has not finished yet!");

        emit VotingEndend(proposals[id].name, 
            proposals[id].description, 
            proposals[id].votesFor, 
            proposals[id].votesAgainst);

        return (proposals[id].name, 
            proposals[id].description, 
            proposals[id].votesFor, 
            proposals[id].votesAgainst);
    }
}
