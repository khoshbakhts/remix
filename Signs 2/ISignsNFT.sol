// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ISigns.sol";

interface ISignsNFT {
    struct Sign {
        ISigns.Location home;
        ISigns.Location current;
        uint256 totalMoves;
        uint256 totalDistanceMeters;
        uint256 weight;
        address owner;
        bool isPickedUp;
        bytes32 contentHash;
        uint256 signWage;
    }
    
    function signs(uint256 tokenId) external view returns (
        ISigns.Location memory home,
        ISigns.Location memory current,
        uint256 totalMoves,
        uint256 totalDistanceMeters,
        uint256 weight,
        address owner,
        bool isPickedUp,
        bytes32 contentHash,
        uint256 signWage
    );
}