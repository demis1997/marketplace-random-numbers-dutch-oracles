// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import 'node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol';
import 'node_modules/@openzeppelin/contracts/access/Ownable.sol';
import 'node_modules/@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import 'node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol';
import 'vrf.sol';


contract NFT is ERC721A, Ownable, ReentrancyGuard {

  using Strings for uint256;
  bytes32 private commitment;
  bool private seedGenerated;
  bytes32 private randomSeed;
  bytes32 public merkleRoot;
  mapping(address => bytes32) private userSeeds;
  mapping(bytes32 => bool) public reserved;

  string public uriPrefix = '';
  string public uriSuffix = '.json';
  string public hiddenMetadataUri;

  
  uint256 public timer;
  uint256 public cost;
  uint256 public maxSupply;
  uint256 public maxMintAmountPerTx;

  bool public paused = true;
  bool public revealed = false;

  constructor(
    string memory _tokenName,
    string memory _tokenSymbol,
    uint256 _cost,
    uint256 _maxSupply,
    uint256 _maxMintAmountPerTx,
    string memory _hiddenMetadataUri,
    bytes32 _merkleRoot,
    string memory _merkleRootLink
  ) ERC721A(_tokenName, _tokenSymbol) {
    setCost(_cost);
    maxSupply = _maxSupply;
    setMaxMintAmountPerTx(_maxMintAmountPerTx);
    setHiddenMetadataUri(_hiddenMetadataUri);
    setMerkleRoot(_merkleRootLink);
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, 'Invalid mint amount!');
    require(totalSupply() + _mintAmount <= maxSupply, 'Max supply exceeded!');
    _;
  }

  modifier mintPriceCompliance(uint256 _mintAmount) {
    require(msg.value >= cost * _mintAmount, 'Insufficient funds!');
    _;
  }


  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {

    //we can save in calldata instead of memory to save gas because we will avoid copying all the time when accessing the arguments 
    require(!paused, 'The contract is paused!');
    bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
    require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), 'Invalid proof!');
    require(!reserved[leaf], 'Address already claimed!');
        //we are using a VRF here and assuming that the oracle service  allows us to verify this seed using a map 
        randomSeed = bytes32(keccak256(abi.encodePacked(userProvidedRandomness, commitment)));
        userSeeds[msg.sender] = randomSeed;
        reserved[leaf] = true;
    _safeMint(_msgSender(), _mintAmount);


    /*to save gas we can use something like this for storing the random seed to use Mstore instead of Sstore to save gas:
      assembly {
    Load the randomSeed slot
    let slot := sload(randomSeed_slot)
    Store randomSeed in memory
    mstore(slot, randomSeed)
  }
*/


  }
  
  function mintForAddress(uint256 _mintAmount, address _receiver) public mintCompliance(_mintAmount) onlyOwner {
      randomSeed = bytes32(keccak256(abi.encodePacked(incrementalNumber * 17361298479641281472013953812876492, commitment)));
      userSeeds[_receiver] = randomSeed;
    _safeMint(_receiver, _mintAmount);
  }

      function getUserSeed(address user) external view returns (bytes32) {
        return userSeeds[user];
    }

  function walletOfOwner(address _owner) public view returns (uint256[] memory) {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
    uint256 currentTokenId = _startTokenId();
    uint256 ownedTokenIndex = 0;
    address latestOwnerAddress;

    while (ownedTokenIndex < ownerTokenCount && currentTokenId < _currentIndex) {
      TokenOwnership memory ownership = _ownerships[currentTokenId];

      if (!ownership.burned) {
        if (ownership.addr != address(0)) {
          latestOwnerAddress = ownership.addr;
        }

        if (latestOwnerAddress == _owner) {
          ownedTokenIds[ownedTokenIndex] = currentTokenId;

          ownedTokenIndex++;
        }
      }

      currentTokenId++;
    }

    return ownedTokenIds;
  }

  function _startTokenId() internal view virtual override returns (uint256) {
    return 1;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    require(_exists(_tokenId), 'ERC721Metadata: URI query for nonexistent token');

    if (revealed == false) {
      return hiddenMetadataUri;
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : '';
  }

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
  }

  function setHiddenMetadataUri(string memory _hiddenMetadataUri) public onlyOwner {
    hiddenMetadataUri = _hiddenMetadataUri;
  }

  function setUriPrefix(string memory _uriPrefix) public onlyOwner {
    uriPrefix = _uriPrefix;
  }

  function setUriSuffix(string memory _uriSuffix) public onlyOwner {
    uriSuffix = _uriSuffix;
  }



  function setTimer(uint256 _timer){
    timer = _timer;

  }

  function setPaused(bool _state) public onlyOwner {
    require (block.timestamp >= start + timer);
    paused = _state;
  }

  function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
    _merkleRootLink = merkleRoot;
  }


  function withdraw() public onlyOwner nonReentrant {


    (bool os, ) = payable(owner()).call{value: address(this).balance}('');
    require(os);

  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }
}




/*
we need variables of startPrice, timer, priceDecrement, timeElapsed, priceDecrement and an auctionEnded variable to make sure that the auction ends when someone buys 


 function endAuction() public onlyOwner {
    require(!auctionEnded, "The auction has already ended.");
    require(!paused, "The contract is paused.");

    if (block.timestamp < timer + auctionDuration) {
      // End the auction prematurely if needed
      timer = block.timestamp - auctionDuration;
    }

    auctionEnded = true;
    paused = true;
  }


function getCurrentPrice() public view returns (uint256) {
  if (block.timestamp <= timer) {
    return startPrice;
  } else if (block.timestamp >= timer + auctionDuration) {
    return 0;
  } else {
    uint256 timeElapsed = block.timestamp - timer;
    uint256 currentPrice = startPrice - (priceDecrement * timeElapsed);
    return currentPrice;
}

function getDAPrice(startTime, stepNumber, currentTime, stepDecrement, stepDuration, startPrice, stepIndex ) {


stepIndex = elapsedTime100 /stepDuration10
10
currentPrice = startPrice20 - stepDecrement5 * stepIndex10
}
  }
}
function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) {
  require(!paused, "The contract is paused!");
  require(msg.value >= getCurrentPrice() * _mintAmount, "Insufficient funds!");
  bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
  require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), "Invalid proof!");
  require(!reserved[leaf], "Address already claimed!");
  randomSeed = bytes32(keccak256(abi.encodePacked(userProvidedRandomness, commitment)));
  userSeeds[msg.sender] = randomSeed;
  reserved[leaf] = true;
  _safeMint(_msgSender(), _mintAmount);
}
*/
