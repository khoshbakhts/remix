// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ProductCertificate is Ownable {
    struct Certificate {
        string name;
        string issuedBy;
        uint256 issueDate;
        uint256 validUntil;
        bool isValid;
    }

    // نگاشت از شناسه محصول به گواهی‌ها
    mapping(string => Certificate[]) private _certificates;

    constructor() Ownable(msg.sender) {}

    // صدور گواهی جدید
    function issueCertificate(
        string memory productId,
        string memory name,
        string memory issuedBy,
        uint256 issueDate,
        uint256 validUntil
    ) public onlyOwner {
        Certificate memory cert = Certificate({
            name: name,
            issuedBy: issuedBy,
            issueDate: issueDate,
            validUntil: validUntil,
            isValid: true
        });
        
        _certificates[productId].push(cert);
    }

    // ابطال گواهی
    function revokeCertificate(string memory productId, uint256 certificateIndex) public onlyOwner {
        require(certificateIndex < _certificates[productId].length, "Certificate not found");
        _certificates[productId][certificateIndex].isValid = false;
    }

    // دریافت گواهی‌های محصول
    function getCertificates(string memory productId) public view returns (Certificate[] memory) {
        return _certificates[productId];
    }
}