// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISigns {
    struct Location {
        int64 latitude;    // ~4 decimal places precision (-90 to +90)
        int64 longitude;   // ~4 decimal places precision (-180 to +180)
        uint64 timestamp;  // Good until year 2554
    }

    struct MovementRecord {
        Location fromLocation;
        Location toLocation;
        address carrier;
        uint96 wage;
    }

    function recordMovement(
        uint256 tokenId,
        address carrier,
        Location calldata fromLoc,
        Location calldata toLoc,
        uint256 wage,
        bytes32 contentHash
    ) external;
}