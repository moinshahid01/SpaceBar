// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";



contract SpaceBar is Ownable, ReentrancyGuard, Pausable, AccessControl {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 public zontToken;
    uint256 public initialBalance = 50; 
    uint256 public playFee = 5; 

    struct User {
        uint256 balance;
        uint256 highScore;
        bool claimed; // Track if the user has claimed their initial balance
    }

     bytes32 public constant ADMIN = keccak256("ADMIN");
     bytes32 public constant GAMEMASTER = keccak256("GAMEMASTER");



    struct Match {
        uint256 matchId;
        address player1;
        address player2;
        uint256 player1Stake;
        uint256 player2Stake;
        uint256 startTime;
        bool player2Joined;
        bool completed;
        uint256 player1Score;
        uint256 player2Score;
    }

    mapping(address => User) public users;
    mapping(uint256 => Match) public matches;
    mapping(address => uint256[]) public userMatchHistory;
    mapping(address => uint256) public userCurrentMatch;
    uint256 public matchCounter;

    EnumerableSet.AddressSet private allUsers;

    constructor(address _zontTokenAddress) Ownable(msg.sender) {
        zontToken = IERC20(_zontTokenAddress);
        _grantRole(GAMEMASTER, msg.sender);
        _grantRole(ADMIN, msg.sender);

    }

    event MatchCreated(uint256 matchId, address indexed player1);
    event PlayerJoined(uint256 matchId, address indexed player2);
    event MatchCompleted(uint256 matchId, address indexed winner, uint256 player1Score, uint256 player2Score);
    event BalanceClaimed(address indexed user, uint256 amount);

    // Claim the initial balance
    function claim() external whenNotPaused {
        require(!users[msg.sender].claimed, "User has already claimed their balance");

        users[msg.sender] = User({
            balance: initialBalance,
            highScore: 0,
            claimed: true
        });

        allUsers.add(msg.sender);
        emit BalanceClaimed(msg.sender, initialBalance);
    }

    // Create match function
    function createMatch() external returns (bytes32) {
        require(users[msg.sender].balance >= playFee, "Insufficient balance to create a match");
        require(userCurrentMatch[msg.sender] == 0, "User already has an active match");

        // Deduct balance and create match
        users[msg.sender].balance = users[msg.sender].balance.sub(playFee);
        userCurrentMatch[msg.sender] = matchCounter + 1;

        matchCounter++;
        uint256 matchId = matchCounter;
        matches[matchId] = Match({
            matchId: matchId,
            player1: msg.sender,
            player2: address(0),
            player1Stake: playFee,
            player2Stake: 0,
            startTime: block.timestamp,
            player2Joined: false,
            completed: false,
            player1Score: 0,
            player2Score: 0
        });

        userMatchHistory[msg.sender].push(matchId);

        emit MatchCreated(matchId, msg.sender);

        return keccak256(abi.encode(matchId));
    }

    
    // Join an existing match
    function joinMatch(uint256 matchId) external {
        Match storage currentMatch = matches[matchId];
        require(currentMatch.player1 != address(0), "Match does not exist");
        require(currentMatch.player2 == address(0), "Match already has two players");
        require(currentMatch.startTime + 30 minutes >= block.timestamp, "Match has expired");
        require(currentMatch.player1 != msg.sender, "You cannot join your own match");
        require(block.timestamp < currentMatch.startTime + 30 minutes, "Match Expired");

        // Deduct balance and join match
        require(users[msg.sender].balance >= playFee, "Insufficient balance to join match");

        users[msg.sender].balance = users[msg.sender].balance.sub(playFee);
        currentMatch.player2 = msg.sender;
        currentMatch.player2Stake = playFee;
        currentMatch.player2Joined = true;

        userMatchHistory[msg.sender].push(matchId);

        emit PlayerJoined(matchId, msg.sender);
    }

    // Get all matches details with state
    function getAllMatches() external view returns (Match[] memory) {
        Match[] memory allMatches = new Match[](matchCounter);

        for (uint256 i = 0; i < matchCounter; i++) {
            allMatches[i] = matches[i + 1];
        }

        return allMatches;
    }

    // Get match history for a user
    function getUserMatches(address user) external view returns (Match[] memory) {
        uint256[] memory matchIds = userMatchHistory[user];
        Match[] memory userMatches = new Match[](matchIds.length);

        for (uint256 i = 0; i < matchIds.length; i++) {
            userMatches[i] = matches[matchIds[i]];
        }

        return userMatches;
    }

    // Get user balance
    function getUserBalance(address user) external view returns (uint256) {
        return users[user].balance;
    }

    // Refund function if match is not joined by the second player
    function refundMatch(uint256 matchId) external {
        Match storage currentMatch = matches[matchId];
        require(currentMatch.player2 == address(0), "Player 2 already joined");
        require(currentMatch.startTime + 30 minutes < block.timestamp, "Refund not allowed yet");

        // Refund player 1's stake
        users[currentMatch.player1].balance = users[currentMatch.player1].balance.add(playFee);
    }

    // Play match and determine winner
    function playMatch(uint256 matchId, uint256 player1Score, uint256 player2Score) external nonReentrant {
        Match storage currentMatch = matches[matchId];
        require(currentMatch.player2 != address(0), "Match does not have 2 players");
        require(!currentMatch.completed, "Match already completed");
        require(hasRole(GAMEMASTER,msg.sender) ,"You are not game master");

        currentMatch.player1Score = player1Score;
        currentMatch.player2Score = player2Score;

        currentMatch.completed = true;
        userCurrentMatch[msg.sender] == 0;

        address winner;
        if (player1Score > player2Score) {
            winner = currentMatch.player1;
            users[currentMatch.player1].balance = users[currentMatch.player1].balance.add(currentMatch.player1Stake).add(currentMatch.player2Stake);
        } else if (player2Score > player1Score) {
            winner = currentMatch.player2;
            users[currentMatch.player2].balance = users[currentMatch.player2].balance.add(currentMatch.player1Stake).add(currentMatch.player2Stake);
        }

        currentMatch.completed = true;
        userCurrentMatch[msg.sender] == 0;

        emit MatchCompleted(matchId, winner, player1Score, player2Score);
    }
}
