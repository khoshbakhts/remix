// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

library SharesConstants {
    uint256 public constant TOTAL_SHARES = 100000;
}

contract PaintingShares is ERC20, Ownable {
    address public paintingNFT;
    uint256 public paintingId;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _paintingId,
        address _paintingNFT,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {
        paintingId = _paintingId;
        paintingNFT = _paintingNFT;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == paintingNFT, "Only PaintingNFT can mint");
        _mint(to, amount);
    }
}

contract PaintingSharesFactory is Ownable {
    using SharesConstants for uint256;
    
    address public paintingNFTContract;

    struct ShareHolder {
        address account;
        uint256 percentage;
    }

    struct ShareDistribution {
        address platformAdmin;
        address wallOwner;
        address galleryOwner;
        address painter;
        uint256 platformShares;
        uint256 wallOwnerShares;
        uint256 galleryOwnerShares;
        uint256 painterShares;
    }
    
    event SharesCreated(
        uint256 indexed paintingId, 
        address sharesContract,
        uint256 platformShares,
        uint256 wallOwnerShares,
        uint256 galleryOwnerShares,
        uint256 painterShares
    );

    constructor(
        address _paintingNFTContract,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_paintingNFTContract != address(0), "Invalid NFT contract");
        paintingNFTContract = _paintingNFTContract;
    }

    function createSharesForPainting(
        uint256 paintingId,
        address platformAdmin,
        address wallOwner,
        address galleryOwner,
        address painter,
        uint256 platformPercentage,
        uint256 wallOwnerPercentage,
        uint256 galleryOwnerPercentage
    ) external returns (address) {
        require(msg.sender == paintingNFTContract, "Only PaintingNFT contract");

        // Create shares contract
        address sharesContract = _createSharesContract(paintingId);

        // Calculate and distribute shares
        ShareDistribution memory distribution = _calculateShares(
            platformAdmin,
            wallOwner,
            galleryOwner,
            painter,
            platformPercentage,
            wallOwnerPercentage,
            galleryOwnerPercentage
        );

        _distributeShares(sharesContract, distribution);

        emit SharesCreated(
            paintingId, 
            sharesContract,
            distribution.platformShares,
            distribution.wallOwnerShares,
            distribution.galleryOwnerShares,
            distribution.painterShares
        );
        
        return sharesContract;
    }

    function _createSharesContract(uint256 paintingId) private returns (address) {
        string memory shareName = string(abi.encodePacked("Painting ", 
            _toString(paintingId), " Shares"));
        string memory shareSymbol = string(abi.encodePacked("PAINT", 
            _toString(paintingId)));

        PaintingShares sharesContract = new PaintingShares(
            shareName,
            shareSymbol,
            paintingId,
            paintingNFTContract,
            owner()
        );

        return address(sharesContract);
    }

    function _calculateShares(
        address platformAdmin,
        address wallOwner,
        address galleryOwner,
        address painter,
        uint256 platformPercentage,
        uint256 wallOwnerPercentage,
        uint256 galleryOwnerPercentage
    ) private pure returns (ShareDistribution memory) {
        uint256 platformShares = (SharesConstants.TOTAL_SHARES * platformPercentage) / 100;
        uint256 wallOwnerShares = (SharesConstants.TOTAL_SHARES * wallOwnerPercentage) / 100;
        uint256 galleryOwnerShares = (SharesConstants.TOTAL_SHARES * galleryOwnerPercentage) / 100;
        uint256 painterShares = SharesConstants.TOTAL_SHARES - platformShares - 
            wallOwnerShares - galleryOwnerShares;

        return ShareDistribution({
            platformAdmin: platformAdmin,
            wallOwner: wallOwner,
            galleryOwner: galleryOwner,
            painter: painter,
            platformShares: platformShares,
            wallOwnerShares: wallOwnerShares,
            galleryOwnerShares: galleryOwnerShares,
            painterShares: painterShares
        });
    }

    function _distributeShares(
        address sharesContract, 
        ShareDistribution memory distribution
    ) private {
        PaintingShares(sharesContract).mint(
            distribution.platformAdmin, 
            distribution.platformShares
        );
        PaintingShares(sharesContract).mint(
            distribution.wallOwner, 
            distribution.wallOwnerShares
        );
        PaintingShares(sharesContract).mint(
            distribution.galleryOwner, 
            distribution.galleryOwnerShares
        );
        PaintingShares(sharesContract).mint(
            distribution.painter, 
            distribution.painterShares
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function setPaintingNFTContract(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Invalid address");
        paintingNFTContract = _newAddress;
    }
}