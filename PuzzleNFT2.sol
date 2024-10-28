// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract PuzzleNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    uint256 public constant TOTAL_IMAGES = 60;
    address public puzzleGameContract;
    mapping(address => bool) private hasMinted;
    mapping(uint256 => uint256) public tokenImageId;
    mapping(address => uint256[]) private ownerTokens;
    mapping(address => uint256) private mintCount;
    uint256 public constant MAX_FREE_MINTS = 5;

    constructor() ERC721("PuzzleNFT", "PNFT") Ownable(msg.sender) {}

    function setPuzzleGameContract(address _puzzleGameContract)
        public
        onlyOwner
    {
        puzzleGameContract = _puzzleGameContract;
    }

    // Override _transfer to update ownerTokens mapping
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address from) {
        address previousOwner = super._update(to, tokenId, auth);

        // Remove token from previous owner's array
        if (previousOwner != address(0)) {
            _removeTokenFromOwnerArray(previousOwner, tokenId);
        }

        // Add token to new owner's array
        if (to != address(0)) {
            ownerTokens[to].push(tokenId);
        }

        return previousOwner;
    }

    // Helper function to remove a token from an owner's array
    function _removeTokenFromOwnerArray(address owner, uint256 tokenId)
        private
    {
        uint256[] storage tokens = ownerTokens[owner];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                // Move the last element to the position being deleted
                tokens[i] = tokens[tokens.length - 1];
                // Remove the last element
                tokens.pop();
                break;
            }
        }
    }

function mintToken() public {
    require(mintCount[msg.sender] < MAX_FREE_MINTS, "Maximum free tokens already minted");
    require(_tokenIdCounter.current() < TOTAL_IMAGES * 1000, "Maximum tokens minted");

    uint256 tokenId = _tokenIdCounter.current();
    _tokenIdCounter.increment();

    uint256 imageId = getRandomImageId(msg.sender);

    tokenImageId[tokenId] = imageId;
    _safeMint(msg.sender, tokenId);
    mintCount[msg.sender]++;

    string memory tokenUri = string(abi.encodePacked("https://qold.bitra.market/wp-includes/puzzle/", uint2str(imageId), ".json"));
    _setTokenURI(tokenId, tokenUri);

    setApprovalForAll(puzzleGameContract, true);
}

    function ownerMintToken(address to, uint256 specificImageId)
        public
        onlyOwner
    {
        require(
            specificImageId > 0 && specificImageId <= TOTAL_IMAGES,
            "Invalid image ID."
        );

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        tokenImageId[tokenId] = specificImageId;
        _safeMint(to, tokenId);

        // The ownerTokens mapping is now updated in _update

        string memory tokenUri = string(
            abi.encodePacked(
                "https://qold.bitra.market/wp-includes/puzzle/",
                uint2str(specificImageId),
                ".json"
            )
        );
        _setTokenURI(tokenId, tokenUri);

        setApprovalForAll(puzzleGameContract, true);
    }

    function getRandomImageId(address user) internal view returns (uint256) {
        uint256 randomHash = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.difficulty, user))
        );
        return (randomHash % TOTAL_IMAGES) + 1;
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        return ownerTokens[owner];
    }

    function remainingFreeMints(address user) public view returns (uint256) {
        return MAX_FREE_MINTS - mintCount[user];
    }
}
