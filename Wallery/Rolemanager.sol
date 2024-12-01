pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RoleManager is AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WALL_OWNER_ROLE = keccak256("WALL_OWNER_ROLE");
    bytes32 public constant PAINTER_ROLE = keccak256("PAINTER_ROLE");
    bytes32 public constant GALLERY_OWNER_ROLE = keccak256("GALLERY_OWNER_ROLE");
    bytes32 public constant SPONSOR_ROLE = keccak256("SPONSOR_ROLE");

    struct UserInfo {
        string firstName;
        string lastName;
        string email;
        string organization;
        address walletAddress;
    }

    struct UserInfoRequest {
        address requester;
        UserInfo info;
        bool isUpdate;
        bool pending;
        bool approved;
    }

    struct RoleRequest {
        address requester;
        bytes32 role;
        string reason;
        bool pending;
        bool approved;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(address => UserInfoRequest) public userInfoRequests;
    mapping(address => mapping(bytes32 => RoleRequest)) public roleRequests;
    RoleRequest[] public pendingRequests;

    event UserInfoRequested(address indexed requester, bool isUpdate);
    event UserInfoRequestApproved(address indexed requester);
    event UserInfoRequestRejected(address indexed requester);
    event UserInfoUpdated(address indexed user);
    event RoleRequested(address indexed requester, bytes32 indexed role, string reason);
    event RoleRequestApproved(address indexed requester, bytes32 indexed role);
    event RoleRequestRejected(address indexed requester, bytes32 indexed role);
    event RoleAssigned(address indexed user, bytes32 indexed role);
    event RoleRevoked(address indexed user, bytes32 indexed role);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function requestUserInfo(
        string memory firstName,
        string memory lastName,
        string memory email,
        string memory organization
    ) public whenNotPaused {
        require(bytes(firstName).length > 0, "First name required");
        require(bytes(lastName).length > 0, "Last name required");
        require(bytes(email).length > 0, "Email required");
        
        UserInfo memory info = UserInfo({
            firstName: firstName,
            lastName: lastName,
            email: email,
            organization: organization,
            walletAddress: msg.sender
        });

        bool isUpdate = userInfo[msg.sender].walletAddress != address(0);
        
        userInfoRequests[msg.sender] = UserInfoRequest({
            requester: msg.sender,
            info: info,
            isUpdate: isUpdate,
            pending: true,
            approved: false
        });

        emit UserInfoRequested(msg.sender, isUpdate);
    }

    function approveUserInfoRequest(address requester) public onlyRole(ADMIN_ROLE) whenNotPaused {
        UserInfoRequest storage request = userInfoRequests[requester];
        require(request.pending, "No pending request");

        request.pending = false;
        request.approved = true;
        userInfo[requester] = request.info;

        emit UserInfoRequestApproved(requester);
        emit UserInfoUpdated(requester);
    }

    function rejectUserInfoRequest(address requester) public onlyRole(ADMIN_ROLE) whenNotPaused {
        UserInfoRequest storage request = userInfoRequests[requester];
        require(request.pending, "No pending request");

        request.pending = false;
        request.approved = false;

        emit UserInfoRequestRejected(requester);
    }

    function getUserInfo(address user) public view returns (
        string memory firstName,
        string memory lastName,
        string memory email,
        string memory organization,
        address walletAddress
    ) {
        UserInfo memory info = userInfo[user];
        return (
            info.firstName,
            info.lastName,
            info.email,
            info.organization,
            info.walletAddress
        );
    }

    /**
     * @dev Request a role with a reason
     * @param _role The role being requested
     * @param _reason The reason for requesting the role
     */
    function requestRole(bytes32 _role, string memory _reason) public whenNotPaused {
        require(!hasRole(_role, msg.sender), "Already has role");
        require(bytes(_reason).length > 0, "Reason required");
        require(!roleRequests[msg.sender][_role].pending, "Request already pending");

        RoleRequest memory request = RoleRequest({
            requester: msg.sender,
            role: _role,
            reason: _reason,
            pending: true,
            approved: false
        });

        roleRequests[msg.sender][_role] = request;
        pendingRequests.push(request);

        emit RoleRequested(msg.sender, _role, _reason);
    }

    /**
     * @dev Approve a role request
     * @param _requester Address of the user who requested the role
     * @param _role The role that was requested
     */
    function approveRoleRequest(address _requester, bytes32 _role) public onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_requester != address(0), "Invalid address");
        RoleRequest storage request = roleRequests[_requester][_role];
        require(request.pending, "No pending request");

        request.pending = false;
        request.approved = true;
        _removeFromPendingRequests(_requester, _role);
        _grantRole(_role, _requester);

        emit RoleRequestApproved(_requester, _role);
        emit RoleAssigned(_requester, _role);
    }

    /**
     * @dev Reject a role request
     * @param _requester Address of the user who requested the role
     * @param _role The role that was requested
     */
    function rejectRoleRequest(address _requester, bytes32 _role) public onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_requester != address(0), "Invalid address");
        RoleRequest storage request = roleRequests[_requester][_role];
        require(request.pending, "No pending request");

        request.pending = false;
        request.approved = false;
        _removeFromPendingRequests(_requester, _role);

        emit RoleRequestRejected(_requester, _role);
    }

    /**
     * @dev Directly assign a role (admin bypass)
     * @param _user Address to assign the role to
     * @param _role Role to assign
     */
    function assignRole(address _user, bytes32 _role) public onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_user != address(0), "Invalid address");
        _grantRole(_role, _user);
        emit RoleAssigned(_user, _role);
    }

    /**
     * @dev Revoke a role
     * @param _user Address to revoke the role from
     * @param _role Role to revoke
     */
    function revokeRole(address _user, bytes32 _role) public onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_user != address(0), "Invalid address");
        _revokeRole(_role, _user);
        emit RoleRevoked(_user, _role);
    }

    /**
     * @dev Get all pending role requests
     */
    function getPendingRequests() public view returns (RoleRequest[] memory) {
        return pendingRequests;
    }

    /**
     * @dev Get specific role request details
     */
    function getRoleRequest(address _requester, bytes32 _role) public view returns (
        address requester,
        bytes32 role,
        string memory reason,
        bool pending,
        bool approved
    ) {
        RoleRequest memory request = roleRequests[_requester][_role];
        return (
            request.requester,
            request.role,
            request.reason,
            request.pending,
            request.approved
        );
    }

    /**
     * @dev Remove a request from pending requests array
     */
    function _removeFromPendingRequests(address _requester, bytes32 _role) private {
        for (uint i = 0; i < pendingRequests.length; i++) {
            if (pendingRequests[i].requester == _requester && pendingRequests[i].role == _role) {
                // Move the last element to the position being deleted
                pendingRequests[i] = pendingRequests[pendingRequests.length - 1];
                pendingRequests.pop();
                break;
            }
        }
    }

    // Pause/Unpause functionality
    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}