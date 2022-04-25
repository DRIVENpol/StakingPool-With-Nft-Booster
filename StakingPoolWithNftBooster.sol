// @note SPDX License
// SPDX-License-Identifier: MIT

// @note pragma version
pragma solidity 0.8.10;

// @note libraries and interfaces
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// @note beginning of the smart contract
contract MasterChefV2 is Ownable, ReentrancyGuard {

    // @note using libraries
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // @note user's info
    struct UserInfo {
        uint256 amount;        
        uint256 rewardDebt; 
    }

    // @note pool info
    struct PoolInfo {
        IERC20 lpToken;          
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accTokensPerShare;
        uint16 depositFeeBP;
    }

    // @note varibles
    IERC20 public erc20Token; // Token for rewards
    IERC721 public nftAddress; // Nft address

    uint256 public tokensPerBlock; // Tokens emitted per block
    uint256 public BONUS_MULTIPLIER = 1; // Multiplier for early stakers
    uint256 public nftBoosted = 2; // 1  -nft boosted apy  2 = not boosted
    uint256 public nftBoostMagnitude = 0;

    address public feeAddress; // Address to receive fees
    address public devaddr; // Main dev address



    PoolInfo[] public poolInfo; // array with every pool
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Link an address to a pool with given Id
    uint256 public totalAllocPoint = 0; // Alloc points
    uint256 public startBlock; // When the staking starts

    // @note events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 tokensPerBlock);

    // @note constructor
    constructor(
        IERC20 _erc20Token,
        address _devaddr,
        address _feeAddress,
        uint256 _tokensPerBlock,
        uint256 _startBlock,
        IERC721 _nftAddress
    ) {
        erc20Token = _erc20Token;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        tokensPerBlock = _tokensPerBlock;
        startBlock = _startBlock;
        nftAddress = _nftAddress;
    }

    // @note return the no. of existing pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // @note mapping + bool variable in order to don't have duplicated pools
    mapping(IERC20 => bool) public poolExistence;

    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // @note add a new pool
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accTokensPerShare: 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // @note set the parameters for an existing pool
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // @note return the multiplier
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // @note compute the pending rewards for an user that staked in a given pool
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokensPerShare = pool.accTokensPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward = multiplier.mul(tokensPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTokensPerShare = accTokensPerShare.add(reward.mul(1e12).div(lpSupply));
        }

        if(nftBoosted == 1 && nftAddress.balanceOf(msg.sender) != 0) {
            return user.amount.mul(accTokensPerShare).div(1e12).sub(user.rewardDebt).mul(nftBoostMagnitude);
        } else {
             return user.amount.mul(accTokensPerShare).div(1e12).sub(user.rewardDebt);
        }
    }

   // @note update the pools and mint the tokens by calling "updatePool" function
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // @note
    // This function is called when a deposit / withdraw is occured
    // This function compute the rewards and mint the needed tokens
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = multiplier.mul(tokensPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        // **IMPORTANT**
        // Mint function is disabled as we will use tokens stored in this sc

        // Mint
        // erc20Token.mint(devaddr, reward.div(10));
        // erc20Token.mint(address(this), reward);

        // Update pool's variables
        pool.accTokensPerShare = pool.accTokensPerShare.add(reward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // @note deposit function in a given pool
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokensPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeTokenTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accTokensPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // @note withdraw function from a given pool
    // If there are no pending rewards, we withdraw the tokens
    // If there are pending rewards, we withdraw only the rewards
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Amount should be lower!");
        updatePool(_pid);

        uint256 pendingBefore = user.amount.mul(pool.accTokensPerShare).div(1e12).sub(user.rewardDebt);
        uint256 pending;

        if(nftBoosted == 1 && nftAddress.balanceOf(msg.sender) != 0) {
             pending = pendingBefore.mul(nftBoostMagnitude);
        } else {
            pending = pendingBefore;
        }
        
        if (pending > 0) {
            safeTokenTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokensPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // @note withdraw without receiveing rewards
    // Only for emergency
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // @note internal function for transfer
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = erc20Token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > bal) {
            transferSuccess =  erc20Token.transfer(_to, bal);
        } else {
            transferSuccess =  erc20Token.transfer(_to, _amount);
        }
        require(transferSuccess, "Transfer failed!");
    }

    // @note change the dev address
    function changeDev(address _devaddr) public {
        require(msg.sender == devaddr, "You are not the owner!");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    // @note change the fee receiver address
    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    // @note update the no. of tokens emitted / block
    function updateEmissionRate(uint256 _tokensPerBlock) public onlyOwner {
        massUpdatePools();
        tokensPerBlock = _tokensPerBlock;
        emit UpdateEmissionRate(msg.sender, _tokensPerBlock);
    }

    // @note toggle function for nft rewards
    function toggleNftRewards() public onlyOwner {
        if(nftBoosted ==1) {
            nftBoosted = 2;
        } else {
            nftBoosted =1;
        }
    }

    // @note set the nft Address
    function setNftAddress(IERC721 _newNftAddress) public onlyOwner {
        nftAddress = _newNftAddress;
    }

    // @note set boosted APY for NFT holders
    function setBoostedApyForNft(uint256 _multiplier) public onlyOwner {
        nftBoostMagnitude = _multiplier;
    }
}
