// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ISignToken {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract SignityToken is ISignToken, ReentrancyGuard {
    string public constant name = "Signity";
    string public constant symbol = "SGNT";
    uint8 public constant decimals = 18;
    uint256 private _totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    address public immutable owner;
    address public signityNFT;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "SignityToken: caller is not the owner");
        _;
    }
    
    modifier onlySignityNFT() {
        require(msg.sender == signityNFT, "SignityToken: caller is not SignityNFT");
        _;
    }

    // Admin functions
    function setSignityNFT(address _signityNFT) external onlyOwner {
        require(_signityNFT != address(0), "SignityToken: invalid SignityNFT address");
        signityNFT = _signityNFT;
    }
    
    // Token operations
    function mint(address to, uint256 amount) external override onlySignityNFT nonReentrant {
        require(to != address(0), "SignityToken: mint to the zero address");
        
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function burn(address from, uint256 amount) external override onlySignityNFT nonReentrant {
        require(from != address(0), "SignityToken: burn from the zero address");
        require(_balances[from] >= amount, "SignityToken: burn amount exceeds balance");
        
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
    
    function transfer(address to, uint256 amount) external override nonReentrant returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override nonReentrant returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "SignityToken: insufficient allowance");
        
        _transfer(from, to, amount);
        _approve(from, msg.sender, _allowances[from][msg.sender] - amount);
        return true;
    }
    
    // View functions
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }
    
    // Internal functions
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "SignityToken: transfer from the zero address");
        require(to != address(0), "SignityToken: transfer to the zero address");
        require(_balances[from] >= amount, "SignityToken: transfer amount exceeds balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
    
    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0), "SignityToken: approve from the zero address");
        require(spender != address(0), "SignityToken: approve to the zero address");
        
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }
}