// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

// Contract to manage wall registration in the Wallery platform
contract WallRegistry is AccessControl, Pausable {
    // Defining roles using AccessControl's role mechanism
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WALL_OWNER_ROLE = keccak256("WALL_OWNER_ROLE");

    // Reference to RoleManager contract
    IRoleManager public roleManager;

    // Struct to store wall registration details
    struct Wall {
        uint256 id;
        address owner;
        string metadata;
        bool approved;
    }

    // Counter for wall requests
    uint256 private wallCounter;

    // Mapping to store wall registration requests
    mapping(uint256 => Wall) public walls;

    // Event to be emitted when a new wall registration request is created
    event WallRequestCreated(uint256 indexed wallId, address indexed owner, string metadata);

    // Event to be emitted when a wall registration request is approved or rejected
    event WallRequestReviewed(uint256 indexed wallId, bool approved);

    // Constructor to set the RoleManager contract address
    constructor(address _roleManagerAddress) {
        require(_roleManagerAddress != address(0), "Invalid RoleManager address");
        roleManager = IRoleManager(_roleManagerAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // Function for wall owners to submit a new wall registration request
    function submitWallRequest(string memory _metadata) public {
        require(roleManager.hasRole(WALL_OWNER_ROLE, msg.sender), "Caller does not have WALL_OWNER_ROLE");
        wallCounter++;
        walls[wallCounter] = Wall(wallCounter, msg.sender, _metadata, false);
        emit WallRequestCreated(wallCounter, msg.sender, _metadata);
    }

    // Function for admin to approve a wall registration request
    function approveWallRequest(uint256 _wallId) public{
        require(roleManager.hasRole(ADMIN_ROLE, msg.sender),"Caller does not have WALL_OWNER_ROLE");
        require(_wallId > 0 && _wallId <= wallCounter, "Invalid wall ID");
        Wall storage wall = walls[_wallId];
        require(!wall.approved, "Wall already approved");
        wall.approved = true;
        emit WallRequestReviewed(_wallId, true);
    }

    // Function for admin to reject a wall registration request
    function rejectWallRequest(uint256 _wallId) public onlyRole(ADMIN_ROLE) {
        require(_wallId > 0 && _wallId <= wallCounter, "Invalid wall ID");
        Wall storage wall = walls[_wallId];
        require(!wall.approved, "Wall already approved");
        delete walls[_wallId];
        emit WallRequestReviewed(_wallId, false);
    }

    // Function to get wall details by ID
    function getWallDetails(uint256 _wallId) public view returns (Wall memory) {
        require(_wallId > 0 && _wallId <= wallCounter, "Invalid wall ID");
        return walls[_wallId];
    }

    // Function to transfer ownership of a wall, restricted to wall owner
    function transferWall(uint256 _wallId, address _newOwner) public {
        require(_wallId > 0 && _wallId <= wallCounter, "Invalid wall ID");
        require(walls[_wallId].owner == msg.sender, "You are not the owner of this wall");
        require(_newOwner != address(0), "Invalid new owner address");
        walls[_wallId].owner = _newOwner;
    }

    // Function to pause the contract, restricted to admin role holders
    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    // Function to unpause the contract, restricted to admin role holders
    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
