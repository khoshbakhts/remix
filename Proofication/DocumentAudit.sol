// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract DocumentAudit is Ownable, Pausable {

    struct Document {
        address owner;
        uint256 timestamp;
        string registrantName;
        string organization;
        string identifier;
    }

    mapping(bytes32 => Document) private documents;

    // Event emitted when a document is registered
    event DocumentRegistered(
        bytes32 indexed documentHash,
        address indexed owner,
        string registrantName,
        string organization,
        string identifier
    );

    // Event emitted when ownership is transferred
    event OwnershipTransferred(
        bytes32 indexed documentHash,
        address indexed oldOwner,
        address indexed newOwner
    );

    // Constructor that sets the initial owner of the contract
    constructor() Ownable(msg.sender) {}

    // Registers a new document
    function registerDocument(
        bytes32 documentHash,
        string memory registrantName,
        string memory organization,
        string memory identifier
    ) public whenNotPaused {
        require(!isDocumentRegistered(documentHash), "Document already registered.");

        documents[documentHash] = Document({
            owner: msg.sender,
            timestamp: block.timestamp,
            registrantName: registrantName,
            organization: organization,
            identifier: identifier
        });

        emit DocumentRegistered(documentHash, msg.sender, registrantName, organization, identifier);
    }

    // Checks if a document hash is already registered
    function isDocumentRegistered(bytes32 documentHash) public view returns (bool) {
        return documents[documentHash].timestamp != 0;
    }

    // Retrieves all details of a registered document
    function getDocumentDetails(bytes32 documentHash)
        public view returns (
            address owner,
            uint256 timestamp,
            string memory registrantName,
            string memory organization,
            string memory identifier
        )
    {
        require(isDocumentRegistered(documentHash), "Document not found.");

        Document storage doc = documents[documentHash];
        return (doc.owner, doc.timestamp, doc.registrantName, doc.organization, doc.identifier);
    }

    // Transfers ownership of a document to a new address
    function transferDocumentOwnership(bytes32 documentHash, address newOwner) public whenNotPaused {
        require(isDocumentRegistered(documentHash), "Document not found.");
        require(msg.sender == documents[documentHash].owner, "Only the owner can transfer ownership.");
        require(newOwner != address(0), "New owner cannot be the zero address.");

        address oldOwner = documents[documentHash].owner;
        documents[documentHash].owner = newOwner;

        emit OwnershipTransferred(documentHash, oldOwner, newOwner);
    }

    // Returns the current owner of a specified document
    function getDocumentOwner(bytes32 documentHash) public view returns (address) {
        require(isDocumentRegistered(documentHash), "Document not found.");
        return documents[documentHash].owner;
    }

    // Verifies if a document exists in the contract
    function verifyDocument(bytes32 documentHash) public view returns (bool) {
        return isDocumentRegistered(documentHash);
    }

    // Returns the timestamp of when the document was registered
    function getDocumentTimestamp(bytes32 documentHash) public view returns (uint256) {
        require(isDocumentRegistered(documentHash), "Document not found.");
        return documents[documentHash].timestamp;
    }

    // Pauses the contract for maintenance or security reasons
    function pauseContract() public onlyOwner {
        _pause();
    }

    // Unpauses the contract
    function unpauseContract() public onlyOwner {
        _unpause();
    }
}
