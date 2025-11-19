// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HashToken is ERC20, Ownable {
    constructor() ERC20("Cyber Hash", "HASH") Ownable(msg.sender) {}
    function mint(address to, uint256 amount) external onlyOwner { _mint(to, amount); }
    function burnByGame(address from, uint256 amount) external onlyOwner { _burn(from, amount); }
}

contract CyberArtifacts is ERC1155, ERC1155Burnable, Ownable {
    HashToken public hashToken;
    uint256 public constant BASE_COOLDOWN = 30; 

    struct ItemStats {
        uint8 itemType;   // 1=Art, 2=GPU, 3=VPN, 4=Soft, 5=Mat, 6=Cons
        uint256 statVal;  
        uint256 price;
        uint256 stakingYield; // NEW: $HASH generated per second
    }
    
    mapping(uint256 => ItemStats) public itemRegistry;
    
    struct PlayerRig { uint256 equippedGPU; uint256 equippedVPN; }
    struct ActiveBuff { uint256 activeUntil; uint256 statVal; }
    
    // --- STAKING DATA ---
    struct StakeInfo {
        uint256 amount;
        uint256 lastClaimTime;
    }
    // User -> ItemID -> Stake Info
    mapping(address => mapping(uint256 => StakeInfo)) public userStakes;
    
    mapping(address => PlayerRig) public playerRigs;
    mapping(address => ActiveBuff) public softwareBuff;
    mapping(address => uint256) public lastMined;
    mapping(address => mapping(uint256 => uint256)) public itemLevels;

    event MiningResult(address indexed user, uint256 tokenId, uint256 rng, bool isSpecial);
    event EnchantResult(address indexed user, uint256 itemId, uint256 newLevel, bool success);
    event ItemUsed(address indexed user, uint256 itemId, string effect);
    event StakingUpdate(address indexed user, uint256 itemId, uint256 amount, bool isStaked);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(address _tokenAddress) ERC1155("https://api.kingtech.site/meta/{id}.json") Ownable(msg.sender) {
        hashToken = HashToken(_tokenAddress);
        _setupRegistry();
    }

    function _setupRegistry() internal {
        // Yield Rate: 0.1 ether = 0.1 $HASH per detik
        
        // 1. ARTIFACTS (No Staking)
        itemRegistry[1] = ItemStats(1, 10 ether, 0, 0);
        itemRegistry[2] = ItemStats(1, 25 ether, 0, 0);
        itemRegistry[3] = ItemStats(1, 50 ether, 0, 0);
        itemRegistry[4] = ItemStats(1, 100 ether, 0, 0);
        itemRegistry[5] = ItemStats(1, 250 ether, 0, 0);
        itemRegistry[6] = ItemStats(1, 1000 ether, 0, 0);
        itemRegistry[7] = ItemStats(1, 5000 ether, 0, 0);
        itemRegistry[8] = ItemStats(1, 25000 ether, 0, 10 ether); // Mythic bisa di stake (10/s)

        // 2. GPU (High Passive Income)
        itemRegistry[101] = ItemStats(2, 2, 0, 0.1 ether); 
        itemRegistry[102] = ItemStats(2, 5, 0, 0.5 ether);  
        itemRegistry[103] = ItemStats(2, 10, 0, 2 ether); 
        itemRegistry[104] = ItemStats(2, 15, 0, 10 ether); 

        // 3. VPN (Medium Passive Income)
        itemRegistry[201] = ItemStats(3, 100, 0, 0.05 ether);
        itemRegistry[202] = ItemStats(3, 500, 0, 0.2 ether);
        itemRegistry[203] = ItemStats(3, 1500, 0, 0.8 ether);
        itemRegistry[204] = ItemStats(3, 3000, 0, 4 ether);
        itemRegistry[205] = ItemStats(3, 8000, 0, 20 ether);

        // 4. SOFTWARE & MATS (No Staking)
        itemRegistry[301] = ItemStats(4, 1000, 100 ether, 0);
        itemRegistry[302] = ItemStats(4, 5000, 500 ether, 0);
        itemRegistry[303] = ItemStats(4, 20000, 2000 ether, 0);
        itemRegistry[401] = ItemStats(5, 0, 50 ether, 0);  
        itemRegistry[402] = ItemStats(5, 0, 200 ether, 0); 
        itemRegistry[499] = ItemStats(5, 0, 0, 0);         
        itemRegistry[501] = ItemStats(6, 0, 150 ether, 0); 
        itemRegistry[502] = ItemStats(6, 0, 500 ether, 0); 
    }

    // --- STAKING SYSTEM ---
    function stakeItem(address user, uint256 itemId, uint256 amount) external onlyOwner {
        require(balanceOf(user, itemId) >= amount, "Not enough items");
        require(itemRegistry[itemId].stakingYield > 0, "Not stakeable");
        
        // 1. Claim pending rewards first
        _claimReward(user, itemId);

        // 2. Take Item (Burn temporary)
        _burn(user, itemId, amount);

        // 3. Update Data
        userStakes[user][itemId].amount += amount;
        userStakes[user][itemId].lastClaimTime = block.timestamp;
        
        emit StakingUpdate(user, itemId, userStakes[user][itemId].amount, true);
    }

    function unstakeItem(address user, uint256 itemId, uint256 amount) external onlyOwner {
        require(userStakes[user][itemId].amount >= amount, "Not enough staked");
        
        // 1. Claim pending rewards first
        _claimReward(user, itemId);

        // 2. Update Data
        userStakes[user][itemId].amount -= amount;
        userStakes[user][itemId].lastClaimTime = block.timestamp;

        // 3. Return Item
        _mint(user, itemId, amount, "");
        
        emit StakingUpdate(user, itemId, userStakes[user][itemId].amount, false);
    }

    function claimRewards(address user) external onlyOwner {
        // Loop manual di backend atau claim per item ID?
        // Agar hemat gas, kita biarkan backend panggil per item atau user claim all via backend loop
        // Di sini kita buat fungsi helper internal saja
    }

    function claimItemReward(address user, uint256 itemId) external onlyOwner {
        _claimReward(user, itemId);
    }

    function _claimReward(address user, uint256 itemId) internal {
        StakeInfo storage info = userStakes[user][itemId];
        if (info.amount > 0) {
            uint256 secondsElapsed = block.timestamp - info.lastClaimTime;
            uint256 rate = itemRegistry[itemId].stakingYield;
            
            // Reward = seconds * rate * amount
            uint256 reward = secondsElapsed * rate * info.amount;
            
            if (reward > 0) {
                hashToken.mint(user, reward);
                emit RewardClaimed(user, reward);
            }
            info.lastClaimTime = block.timestamp;
        } else {
            // Jika baru pertama kali stake, set timer
            info.lastClaimTime = block.timestamp;
        }
    }

    function getPendingReward(address user, uint256 itemId) public view returns (uint256) {
        StakeInfo memory info = userStakes[user][itemId];
        if (info.amount == 0) return 0;
        uint256 secondsElapsed = block.timestamp - info.lastClaimTime;
        return secondsElapsed * itemRegistry[itemId].stakingYield * info.amount;
    }
    
    function getStakedAmount(address user, uint256 itemId) public view returns (uint256) {
        return userStakes[user][itemId].amount;
    }

    // --- MINING SYSTEM (Sama seperti v6) ---
    function mineArtifact(address user) external onlyOwner {
        uint256 cooldownTime = BASE_COOLDOWN;
        uint256 gpuId = playerRigs[user].equippedGPU;
        if (gpuId != 0) {
            uint256 reduction = itemRegistry[gpuId].statVal;
            uint256 lvl = itemLevels[user][gpuId];
            uint256 totalRed = reduction + lvl; 
            if (totalRed >= cooldownTime) cooldownTime = 5; 
            else cooldownTime -= totalRed;
        }
        require(block.timestamp >= lastMined[user] + cooldownTime, "Overheat");
        lastMined[user] = block.timestamp;

        uint256 totalLuck = 0;
        uint256 vpnId = playerRigs[user].equippedVPN;
        if (vpnId != 0) {
            uint256 base = itemRegistry[vpnId].statVal;
            uint256 lvl = itemLevels[user][vpnId];
            totalLuck += base + ((base * lvl * 20) / 100);
        }
        if (softwareBuff[user].activeUntil > block.timestamp) totalLuck += softwareBuff[user].statVal;

        uint256 rng = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, user))) % 100000;
        uint256 droppedId;
        bool isSpecial = false;

        if (rng < (3000 + (totalLuck / 5))) { 
            isSpecial = true;
            uint256 subRng = uint256(keccak256(abi.encodePacked(rng, user))) % 100;
            if (subRng < 30) droppedId = 401; 
            else if (subRng < 50) droppedId = 101; 
            else if (subRng < 70) droppedId = 201; 
            else if (subRng < 80) droppedId = 102; 
            else if (subRng < 90) droppedId = 202; 
            else if (subRng < 95) droppedId = 402; 
            else droppedId = 499; 
        } else {
            if (rng < 50 + totalLuck) droppedId = 8;       
            else if (rng < 250 + totalLuck) droppedId = 7; 
            else if (rng < 1000 + totalLuck) droppedId = 6;
            else if (rng < 3000 + totalLuck) droppedId = 5;
            else if (rng < 7000 + totalLuck) droppedId = 4;
            else if (rng < 15000 + totalLuck) droppedId = 3;
            else if (rng < 35000 + totalLuck) droppedId = 2;
            else droppedId = 1;
        }
        _mint(user, droppedId, 1, "");
        emit MiningResult(user, droppedId, rng, isSpecial);
    }

    // --- UTILS (Sama seperti v6) ---
    function enchantItem(address user, uint256 targetItemId, uint256 materialId) external onlyOwner {
        require(balanceOf(user, targetItemId) > 0, "No target");
        require(balanceOf(user, materialId) > 0, "No material");
        uint256 lvl = itemLevels[user][targetItemId];
        uint256 chance = 0;
        if (materialId == 401) { require(lvl < 3); chance = 80 - (lvl * 20); } 
        else if (materialId == 402) { require(lvl < 6); chance = 70 - (lvl * 10); } 
        else if (materialId == 499) { require(lvl >= 6 && lvl < 10); chance = 100; } 
        else revert("Invalid Mat");
        _burn(user, materialId, 1);
        uint256 rng = uint256(keccak256(abi.encodePacked(block.timestamp, user))) % 100;
        if (rng < chance) {
            itemLevels[user][targetItemId]++;
            emit EnchantResult(user, targetItemId, lvl+1, true);
        } else {
            emit EnchantResult(user, targetItemId, lvl, false);
        }
    }
    function useConsumable(address user, uint256 itemId) external onlyOwner {
        require(balanceOf(user, itemId) > 0, "No item");
        ItemStats memory stats = itemRegistry[itemId];
        require(stats.itemType == 6, "Not consumable");
        _burn(user, itemId, 1);
        if (itemId == 501) { lastMined[user] = 0; emit ItemUsed(user, itemId, "CD_RESET"); } 
        else if (itemId == 502) { 
            uint256 r = uint256(keccak256(abi.encodePacked(block.timestamp, user))) % 900;
            hashToken.mint(user, (100+r) * 1 ether);
            emit ItemUsed(user, itemId, "CRATE_OPEN");
        }
    }
    function adminRewardHash(address to, uint256 amount) external onlyOwner { hashToken.mint(to, amount); }
    function adminMint(address to, uint256 itemId, uint256 amount) external onlyOwner { _mint(to, itemId, amount, ""); }
    function equipItem(address user, uint256 itemId) external onlyOwner {
        require(balanceOf(user, itemId) > 0, "Not owned");
        ItemStats memory stats = itemRegistry[itemId];
        if (stats.itemType == 2) playerRigs[user].equippedGPU = itemId;
        else if (stats.itemType == 3) playerRigs[user].equippedVPN = itemId;
        else revert("Not equippable");
    }
    function buySoftware(address user, uint256 itemId) external onlyOwner {
        ItemStats memory stats = itemRegistry[itemId];
        require(stats.itemType == 4, "Not software");
        hashToken.burnByGame(user, stats.price);
        softwareBuff[user] = ActiveBuff(block.timestamp + 1 hours, stats.statVal);
    }
    function salvageArtifact(address user, uint256 tokenId, uint256 amount) external onlyOwner {
        ItemStats memory stats = itemRegistry[tokenId];
        require(stats.itemType == 1, "Only artifacts");
        require(balanceOf(user, tokenId) >= amount, "Not enough");
        _burn(user, tokenId, amount);
        hashToken.mint(user, stats.statVal * amount);
    }
    function getPlayerStats(address user) external view returns (uint256[5] memory) {
        uint256 cooldown = BASE_COOLDOWN;
        uint256 gpu = playerRigs[user].equippedGPU;
        if (gpu != 0) {
            uint256 reduction = itemRegistry[gpu].statVal;
            uint256 lvl = itemLevels[user][gpu];
            uint256 totalRed = reduction + lvl;
            if (totalRed >= cooldown) cooldown = 5; else cooldown -= totalRed;
        }
        uint256 luck = 0;
        uint256 vpn = playerRigs[user].equippedVPN;
        if (vpn != 0) {
            uint256 base = itemRegistry[vpn].statVal;
            uint256 lvl = itemLevels[user][vpn];
            luck += base + ((base * lvl * 20) / 100);
        }
        if (softwareBuff[user].activeUntil > block.timestamp) luck += softwareBuff[user].statVal;
        uint256 buffT = 0;
        if (softwareBuff[user].activeUntil > block.timestamp) buffT = softwareBuff[user].activeUntil - block.timestamp;
        return [cooldown, luck, gpu, vpn, buffT];
    }
    function getItemLevel(address user, uint256 itemId) external view returns (uint256) { return itemLevels[user][itemId]; }
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids) public view override returns (uint256[] memory) { return super.balanceOfBatch(accounts, ids); }
    function balanceOf(address account, uint256 id) public view override returns (uint256) { return super.balanceOf(account, id); }
}