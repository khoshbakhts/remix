// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface PuzzleNFT {
    function tokenImageId(uint256 tokenId) external view returns (uint256);
}

contract PuzzleGame is Ownable, ERC1155 {
    PuzzleNFT public puzzleNFTContract;

    uint256 public puzzleCounter;
    uint256 public constant MEDAL_TOKEN_ID = 1;
    uint256 public constant PREMIUM_MEDAL_TOKEN_ID = 2;
    uint256 public constant PIECES_PER_PUZZLE = 6;

    struct Puzzle {
        uint256 puzzleId;
        uint256 bigImageId;
        address[] participants;
        mapping(uint256 => address) tokenContributors;
        uint256 piecesCompleted;
        address creator;
    }

    // Change puzzles mapping to private
    mapping(uint256 => Puzzle) private puzzles;
    mapping(address => bool) public hasCreatedPuzzle;
    mapping(address => uint256[]) private userInvolvedPuzzles;

    event PuzzleCreated(uint256 puzzleId, uint256 bigImageId, address creator);
    event TokenSubmitted(
        uint256 puzzleId,
        uint256 imageId,
        address contributor
    );
    event PuzzleCompleted(
        uint256 puzzleId,
        address[] participants,
        bool premiumMedal
    );

    // Struct for puzzle information return
    struct PuzzleInfo {
        uint256 puzzleId;
        uint256 bigImageId;
        address[] participants;
        uint256 piecesCompleted;
        address creator;
        bool[] receivedPieces; // Array indicating which pieces have been received
    }

    constructor(address _puzzleNFTContract)
        ERC1155("https://qold.bitra.market/wp-includes/puzzle/medals/{id}.json")
        Ownable(msg.sender)
    {
        puzzleNFTContract = PuzzleNFT(_puzzleNFTContract);
    }

    // New function to get puzzle information
    function getPuzzle(uint256 puzzleId)
        public
        view
        returns (PuzzleInfo memory)
    {
        require(
            puzzleId > 0 && puzzleId <= puzzleCounter,
            "Puzzle does not exist"
        );

        Puzzle storage puzzle = puzzles[puzzleId];
        bool[] memory receivedPieces = new bool[](PIECES_PER_PUZZLE);

        // Calculate the starting image ID for this puzzle
        uint256 startingImageId = (puzzle.bigImageId - 1) *
            PIECES_PER_PUZZLE +
            1;

        // Check which pieces have been received
        for (uint256 i = 0; i < PIECES_PER_PUZZLE; i++) {
            receivedPieces[i] =
                puzzle.tokenContributors[startingImageId + i] != address(0);
        }

        return
            PuzzleInfo({
                puzzleId: puzzle.puzzleId,
                bigImageId: puzzle.bigImageId,
                participants: puzzle.participants,
                piecesCompleted: puzzle.piecesCompleted,
                creator: puzzle.creator,
                receivedPieces: receivedPieces
            });
    }

    function createPuzzle() public {
        require(
            !hasCreatedPuzzle[msg.sender],
            "You can only create one puzzle."
        );

        uint256 bigImageId = getRandomBigImageId(msg.sender);
        puzzleCounter++;

        Puzzle storage newPuzzle = puzzles[puzzleCounter];
        newPuzzle.puzzleId = puzzleCounter;
        newPuzzle.bigImageId = bigImageId;
        newPuzzle.piecesCompleted = 0;
        newPuzzle.creator = msg.sender;
        hasCreatedPuzzle[msg.sender] = true;

        userInvolvedPuzzles[msg.sender].push(puzzleCounter);

        emit PuzzleCreated(puzzleCounter, bigImageId, msg.sender);
    }

    function ownerCreatePuzzle(uint256 bigImageId) public onlyOwner {
        require(bigImageId > 0 && bigImageId <= 10, "Invalid bigImageId");

        puzzleCounter++;
        Puzzle storage newPuzzle = puzzles[puzzleCounter];
        newPuzzle.puzzleId = puzzleCounter;
        newPuzzle.bigImageId = bigImageId;
        newPuzzle.piecesCompleted = 0;
        newPuzzle.creator = owner();

        userInvolvedPuzzles[owner()].push(puzzleCounter);

        emit PuzzleCreated(puzzleCounter, bigImageId, owner());
    }

    /*function userPuzzles(address user) public view returns (uint256[] memory) {
        return userInvolvedPuzzles[user];
    }*/
    function userPuzzles(address user) public view returns (uint256[] memory) {
        uint256 userPuzzleCount = userInvolvedPuzzles[user].length;
        uint256 ownerPuzzleCount = userInvolvedPuzzles[owner()].length;
        uint256 totalPuzzleCount = userPuzzleCount + ownerPuzzleCount;

        // Create a new array to hold both user's and owner's puzzles
        uint256[] memory combinedPuzzles = new uint256[](totalPuzzleCount);

        // Copy user's puzzles into the combined array
        for (uint256 i = 0; i < userPuzzleCount; i++) {
            combinedPuzzles[i] = userInvolvedPuzzles[user][i];
        }

        // Copy owner's puzzles into the combined array
        for (uint256 j = 0; j < ownerPuzzleCount; j++) {
            combinedPuzzles[userPuzzleCount + j] = userInvolvedPuzzles[owner()][
                j
            ];
        }

        return combinedPuzzles;
    }

    function getRandomBigImageId(address user) internal view returns (uint256) {
        uint256 randomHash = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.difficulty, user))
        );
        return (randomHash % 10) + 1;
    }

    function submitToken(uint256 puzzleId, uint256 tokenId) public {
        require(
            puzzles[puzzleId].puzzleId == puzzleId,
            "Puzzle does not exist."
        );
        require(
            puzzles[puzzleId].piecesCompleted < PIECES_PER_PUZZLE,
            "Puzzle already completed."
        );

        uint256 imageId = puzzleNFTContract.tokenImageId(tokenId);

        uint256 bigImageId = puzzles[puzzleId].bigImageId;
        uint256 startingImageId = (bigImageId - 1) * PIECES_PER_PUZZLE + 1;
        uint256 endingImageId = startingImageId + PIECES_PER_PUZZLE - 1;

        require(
            imageId >= startingImageId && imageId <= endingImageId,
            "Invalid token for this puzzle."
        );
        require(
            puzzles[puzzleId].tokenContributors[imageId] == address(0),
            "Token for this piece already submitted."
        );

        IERC721(address(puzzleNFTContract)).transferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        puzzles[puzzleId].tokenContributors[imageId] = msg.sender;
        puzzles[puzzleId].participants.push(msg.sender);
        puzzles[puzzleId].piecesCompleted++;

        bool alreadyInvolved = false;
        for (uint256 i = 0; i < userInvolvedPuzzles[msg.sender].length; i++) {
            if (userInvolvedPuzzles[msg.sender][i] == puzzleId) {
                alreadyInvolved = true;
                break;
            }
        }
        if (!alreadyInvolved) {
            userInvolvedPuzzles[msg.sender].push(puzzleId);
        }

        emit TokenSubmitted(puzzleId, imageId, msg.sender);

        if (puzzles[puzzleId].piecesCompleted == PIECES_PER_PUZZLE) {
            _completePuzzle(puzzleId);
        }
    }

    function _completePuzzle(uint256 puzzleId) internal {
        Puzzle storage puzzle = puzzles[puzzleId];

        bool premiumMedal = true;
        address firstContributor = puzzle.tokenContributors[
            (puzzle.bigImageId - 1) * PIECES_PER_PUZZLE + 1
        ];

        for (
            uint256 i = (puzzle.bigImageId - 1) * PIECES_PER_PUZZLE + 1;
            i <= puzzle.bigImageId * PIECES_PER_PUZZLE;
            i++
        ) {
            if (puzzle.tokenContributors[i] != firstContributor) {
                premiumMedal = false;
                break;
            }
        }

        for (
            uint256 i = (puzzle.bigImageId - 1) * PIECES_PER_PUZZLE + 1;
            i <= puzzle.bigImageId * PIECES_PER_PUZZLE;
            i++
        ) {
            address contributor = puzzle.tokenContributors[i];
            _mint(contributor, MEDAL_TOKEN_ID, 1, "");
        }

        if (premiumMedal) {
            _mint(firstContributor, PREMIUM_MEDAL_TOKEN_ID, 1, "");
        }

        emit PuzzleCompleted(puzzleId, puzzle.participants, premiumMedal);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "https://qold.bitra.market/wp-includes/puzzle/medals/",
                    uint2str(tokenId),
                    ".json"
                )
            );
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
}
