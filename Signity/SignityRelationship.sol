// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISignToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ISignityNFT {
    function getSignDetails(uint256 tokenId) external view returns (
        uint256 id,
        address owner,
        string memory homeLocation,
        uint256 wage,
        address currentHolder,
        bool isPickedUp,
        uint256 lastDropTime,
        string memory currentLocation,
        uint256 totalMoves,
        uint256 totalDistance
    );
}

contract SignityRelationship {
    // Structs
    struct Marriage {
        uint256 signId1;
        uint256 signId2;
        uint256 marriageDate;
        bool isActive;
        uint256[] children;  // Array of child sign IDs
    }

    struct Child {
        uint256 parentSign1;
        uint256 parentSign2;
        uint256 birthDate;
        bool exists;
    }

    // Events
    event MarriageProposed(uint256 indexed signId1, uint256 indexed signId2);
    event MarriageAccepted(uint256 indexed signId1, uint256 indexed signId2, uint256 marriageDate);
    event MarriageDivorced(uint256 indexed signId1, uint256 indexed signId2, uint256 divorceDate);
    event ChildBorn(uint256 indexed parentSign1, uint256 indexed parentSign2, uint256 indexed childSignId);

    // Constants
    uint256 public constant DIVORCE_COOLDOWN = 90 days;  // 3 months
    uint256 public constant CHILD_COOLDOWN = 180 days;   // 6 months
    uint256 public constant MAX_CHILDREN = 5;

    // State variables
    address public immutable owner;
    ISignToken public signToken;
    ISignityNFT public signityNFT;
    
    // Mappings
    mapping(uint256 => Marriage) public marriages;  // signId1 => Marriage
    mapping(uint256 => uint256) public spouseOf;   // signId => spouse's signId
    mapping(uint256 => Child) public children;     // childSignId => Child
    mapping(uint256 => uint256) public lastChildBirth;  // signId => timestamp
    mapping(uint256 => uint256) public lastDivorceDate; // signId => timestamp
    mapping(uint256 => uint256) public proposalTo;  // from signId => to signId
    mapping(uint256 => uint256) public proposalExpiry;  // signId => timestamp

    constructor(address _signToken, address _signityNFT) {
        owner = msg.sender;
        signToken = ISignToken(_signToken);
        signityNFT = ISignityNFT(_signityNFT);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SignityRelationship: caller is not the owner");
        _;
    }

    modifier onlySignOwner(uint256 signId) {
        (,address signOwner,,,,,,,,) = signityNFT.getSignDetails(signId);
        require(signOwner == msg.sender, "SignityRelationship: caller is not sign owner");
        _;
    }

    // Marriage functions
    function proposeMarriage(uint256 fromSignId, uint256 toSignId) external onlySignOwner(fromSignId) {
        require(!isMarried(fromSignId), "SignityRelationship: sign already married");
        require(!isMarried(toSignId), "SignityRelationship: target sign already married");
        require(block.timestamp > lastDivorceDate[fromSignId] + DIVORCE_COOLDOWN, "SignityRelationship: divorce cooldown active");
        require(block.timestamp > lastDivorceDate[toSignId] + DIVORCE_COOLDOWN, "SignityRelationship: target divorce cooldown active");
        
        proposalTo[fromSignId] = toSignId;
        proposalExpiry[fromSignId] = block.timestamp + 7 days;
        
        emit MarriageProposed(fromSignId, toSignId);
    }

    function acceptMarriage(uint256 toSignId, uint256 fromSignId) external onlySignOwner(toSignId) {
        require(proposalTo[fromSignId] == toSignId, "SignityRelationship: no valid proposal");
        require(block.timestamp <= proposalExpiry[fromSignId], "SignityRelationship: proposal expired");
        require(!isMarried(fromSignId) && !isMarried(toSignId), "SignityRelationship: one sign is married");

        Marriage storage newMarriage = marriages[fromSignId];
        newMarriage.signId1 = fromSignId;
        newMarriage.signId2 = toSignId;
        newMarriage.marriageDate = block.timestamp;
        newMarriage.isActive = true;

        spouseOf[fromSignId] = toSignId;
        spouseOf[toSignId] = fromSignId;

        // Clear proposal
        proposalTo[fromSignId] = 0;
        proposalExpiry[fromSignId] = 0;

        emit MarriageAccepted(fromSignId, toSignId, block.timestamp);
    }

    function divorce(uint256 signId) external onlySignOwner(signId) {
        require(isMarried(signId), "SignityRelationship: sign not married");
        
        uint256 spouseId = spouseOf[signId];
        Marriage storage marriage = marriages[signId];
        
        marriage.isActive = false;
        spouseOf[signId] = 0;
        spouseOf[spouseId] = 0;
        
        lastDivorceDate[signId] = block.timestamp;
        lastDivorceDate[spouseId] = block.timestamp;
        
        emit MarriageDivorced(signId, spouseId, block.timestamp);
    }

    // Child functions
    function requestChild(uint256 signId) external onlySignOwner(signId) {
        require(isMarried(signId), "SignityRelationship: sign not married");
        uint256 spouseId = spouseOf[signId];
        Marriage storage marriage = marriages[signId];
        
        require(marriage.children.length < MAX_CHILDREN, "SignityRelationship: max children reached");
        require(block.timestamp > lastChildBirth[signId] + CHILD_COOLDOWN, "SignityRelationship: child cooldown active");
        
        // Random chance of child (50%)
        if (_random(block.timestamp) % 2 == 1) {
            uint256 childSignId = _createChildSign(signId, spouseId);
            marriage.children.push(childSignId);
            lastChildBirth[signId] = block.timestamp;
            lastChildBirth[spouseId] = block.timestamp;
            
            emit ChildBorn(signId, spouseId, childSignId);
        }
    }

    // View functions
    function isMarried(uint256 signId) public view returns (bool) {
        return spouseOf[signId] != 0;
    }

    function getMarriageDetails(uint256 signId) external view returns (Marriage memory) {
        return marriages[signId];
    }

    function getChildDetails(uint256 childSignId) external view returns (Child memory) {
        return children[childSignId];
    }

    // Internal functions
    function _createChildSign(uint256 parent1, uint256 parent2) internal returns (uint256) {
        uint256 childSignId = uint256(keccak256(abi.encodePacked(parent1, parent2, block.timestamp, _random(block.timestamp))));
        
        children[childSignId] = Child({
            parentSign1: parent1,
            parentSign2: parent2,
            birthDate: block.timestamp,
            exists: true
        });
        
        return childSignId;
    }

    function _random(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, seed)));
    }
}