// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract DocumentAudit is ERC2771Context, Ownable, Pausable {
    struct Document {
        address owner;
        uint256 timestamp;
        string registrantName;
        string organization;
        string identifier;
        bool isGasless;  // Track if document was registered via gasless tx
    }

    mapping(bytes32 => Document) private documents;
    mapping(address => bool) public gaslessEnabled;  // User preference for gasless transactions

    event DocumentRegistered(
        bytes32 indexed documentHash,
        address indexed owner,
        string registrantName,
        string organization,
        string identifier,
        bool isGasless
    );

    event OwnershipTransferred(
        bytes32 indexed documentHash,
        address indexed oldOwner,
        address indexed newOwner
    );

    event GaslessPreferenceUpdated(address indexed user, bool enabled);

    constructor(address trustedForwarder) 
        ERC2771Context(trustedForwarder) 
        Ownable(_msgSender()) 
    {}

    // Allow users to set their preference for gasless transactions
    function setGaslessPreference(bool enabled) external {
        gaslessEnabled[msg.sender] = enabled;
        emit GaslessPreferenceUpdated(msg.sender, enabled);
    }

    // Check if user has enabled gasless transactions
    function isGaslessEnabled(address user) public view returns (bool) {
        return gaslessEnabled[user];
    }

    // Register document with explicit gasless choice
    function registerDocument(
        bytes32 documentHash,
        string memory registrantName,
        string memory organization,
        string memory identifier,
        bool useGasless
    ) public whenNotPaused {
        require(!isDocumentRegistered(documentHash), "Document already registered.");
        
        // If using gasless, verify user preference is enabled
        if (useGasless) {
            require(gaslessEnabled[_msgSender()], "Gasless transactions not enabled for this user");
        }

        documents[documentHash] = Document({
            owner: _msgSender(),
            timestamp: block.timestamp,
            registrantName: registrantName,
            organization: organization,
            identifier: identifier,
            isGasless: useGasless
        });

        emit DocumentRegistered(
            documentHash, 
            _msgSender(), 
            registrantName, 
            organization, 
            identifier,
            useGasless
        );
    }

    // Regular transaction version (always uses msg.sender)
    function registerDocumentWithGas(
        bytes32 documentHash,
        string memory registrantName,
        string memory organization,
        string memory identifier
    ) public whenNotPaused {
        registerDocument(documentHash, registrantName, organization, identifier, false);
    }

    // Gasless version (uses _msgSender())
    function registerDocumentGasless(
        bytes32 documentHash,
        string memory registrantName,
        string memory organization,
        string memory identifier
    ) public whenNotPaused {
        registerDocument(documentHash, registrantName, organization, identifier, true);
    }

    function getDocumentDetails(bytes32 documentHash)
        public view returns (
            address owner,
            uint256 timestamp,
            string memory registrantName,
            string memory organization,
            string memory identifier,
            bool isGasless
        )
    {
        require(isDocumentRegistered(documentHash), "Document not found.");
        Document storage doc = documents[documentHash];
        return (
            doc.owner,
            doc.timestamp,
            doc.registrantName,
            doc.organization,
            doc.identifier,
            doc.isGasless
        );
    }

    function transferDocumentOwnership(bytes32 documentHash, address newOwner, bool useGasless) public whenNotPaused {
        require(isDocumentRegistered(documentHash), "Document not found.");
        if (useGasless) {
            require(gaslessEnabled[_msgSender()], "Gasless transactions not enabled for this user");
            require(_msgSender() == documents[documentHash].owner, "Only the owner can transfer ownership.");
        } else {
            require(msg.sender == documents[documentHash].owner, "Only the owner can transfer ownership.");
        }
        require(newOwner != address(0), "New owner cannot be the zero address.");

        address oldOwner = documents[documentHash].owner;
        documents[documentHash].owner = newOwner;

        emit OwnershipTransferred(documentHash, oldOwner, newOwner);
    }

    function isDocumentRegistered(bytes32 documentHash) public view returns (bool) {
        return documents[documentHash].timestamp != 0;
    }

    function getDocumentOwner(bytes32 documentHash) public view returns (address) {
        require(isDocumentRegistered(documentHash), "Document not found.");
        return documents[documentHash].owner;
    }

    function verifyDocument(bytes32 documentHash) public view returns (bool) {
        return isDocumentRegistered(documentHash);
    }

    function getDocumentTimestamp(bytes32 documentHash) public view returns (uint256) {
        require(isDocumentRegistered(documentHash), "Document not found.");
        return documents[documentHash].timestamp;
    }

    function pauseContract() public onlyOwner {
        _pause();
    }

    function unpauseContract() public onlyOwner {
        _unpause();
    }

    // Required overrides for ERC2771Context
    function _msgSender() internal view override(Context, ERC2771Context)
        returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context)
        returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength() internal view override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}