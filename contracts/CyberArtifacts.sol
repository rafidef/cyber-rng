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
    
    // --- BALANCING CONFIG (HARDCORE) ---
    uint256 public constant BASE_COOLDOWN = 40; // Slower Base
    uint256 public constant MIN_COOLDOWN = 10;  // Speed Cap
    uint256 public constant MAX_BUFF_DURATION = 24 hours; // Hoarding Cap

    struct ItemStats {
        uint8 itemType;   
        uint256 statVal;  
        uint256 price;
        uint256 stakingYield;
    }
    
    mapping(uint256 => ItemStats) public itemRegistry;
    
    struct PlayerRig { uint256 equippedGPU; uint256 equippedVPN; }
    struct ActiveBuff { uint256 activeUntil; uint256 statVal; }
    struct StakeInfo { uint256 amount; uint256 lastClaimTime; }

    mapping(address => PlayerRig) public playerRigs;
    mapping(address => ActiveBuff) public softwareBuff;
    mapping(address => uint256) public lastMined;
    mapping(address => mapping(uint256 => uint256)) public itemLevels;
    mapping(address => mapping(uint256 => StakeInfo)) public userStakes;

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
        // 1. ARTIFACTS
        itemRegistry[1] = ItemStats(1, 10 ether, 0, 0);
        itemRegistry[2] = ItemStats(1, 25 ether, 0, 0);
        itemRegistry[3] = ItemStats(1, 50 ether, 0, 0);
        itemRegistry[4] = ItemStats(1, 100 ether, 0, 0);
        itemRegistry[5] = ItemStats(1, 250 ether, 0, 0);
        itemRegistry[6] = ItemStats(1, 1000 ether, 0, 0);
        itemRegistry[7] = ItemStats(1, 5000 ether, 0, 0);
        // Nerfed Mythic Yield (10 -> 1)
        itemRegistry[8] = ItemStats(1, 25000 ether, 0, 1 ether); 

        // 2. GPU (Speed) - Nerfed Yields
        itemRegistry[101] = ItemStats(2, 2, 0, 0.01 ether); 
        itemRegistry[102] = ItemStats(2, 5, 0, 0.05 ether);  
        itemRegistry[103] = ItemStats(2, 10, 0, 0.2 ether); 
        itemRegistry[104] = ItemStats(2, 15, 0, 1 ether); 

        // 3. VPN (Luck) - Nerfed Yields
        itemRegistry[201] = ItemStats(3, 100, 0, 0.01 ether);
        itemRegistry[202] = ItemStats(3, 500, 0, 0.05 ether);
        itemRegistry[203] = ItemStats(3, 1500, 0, 0.2 ether);
        itemRegistry[204] = ItemStats(3, 3000, 0, 0.8 ether);
        itemRegistry[205] = ItemStats(3, 8000, 0, 2.5 ether);

        // 4. SOFTWARE (Buffs) - NERFED STATS
        itemRegistry[301] = ItemStats(4, 300, 100 ether, 0);   // 300 Luck
        itemRegistry[302] = ItemStats(4, 1000, 500 ether, 0);  // 1000 Luck
        itemRegistry[303] = ItemStats(4, 2500, 2000 ether, 0); // 2500 Luck

        // 5. MATERIALS
        itemRegistry[401] = ItemStats(5, 0, 50 ether, 0);  
        itemRegistry[402] = ItemStats(5, 0, 200 ether, 0); 
        itemRegistry[499] = ItemStats(5, 0, 0, 0);         

        // 6. CONSUMABLES
        itemRegistry[501] = ItemStats(6, 0, 150 ether, 0); 
        itemRegistry[502] = ItemStats(6, 0, 500 ether, 0); 
    }

    // --- MINING (NO PITY) ---
    function mineArtifact(address user) external onlyOwner {
        // 1. Cooldown
        uint256 cooldownTime = BASE_COOLDOWN;
        uint256 gpuId = playerRigs[user].equippedGPU;
        if (gpuId != 0) {
            uint256 reduction = itemRegistry[gpuId].statVal;
            uint256 lvl = itemLevels[user][gpuId];
            uint256 totalRed = reduction + lvl; 
            if (totalRed >= (BASE_COOLDOWN - MIN_COOLDOWN)) cooldownTime = MIN_COOLDOWN; 
            else cooldownTime -= totalRed;
        }
        require(block.timestamp >= lastMined[user] + cooldownTime, "Overheat");
        lastMined[user] = block.timestamp;

        // 2. Luck
        uint256 totalLuck = 0;
        uint256 vpnId = playerRigs[user].equippedVPN;
        if (vpnId != 0) {
            uint256 base = itemRegistry[vpnId].statVal;
            uint256 lvl = itemLevels[user][vpnId];
            totalLuck += base + ((base * lvl * 20) / 100);
        }
        if (softwareBuff[user].activeUntil > block.timestamp) totalLuck += softwareBuff[user].statVal;

        // 3. RNG
        uint256 rng = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, user))) % 100000;
        uint256 droppedId;
        bool isSpecial = false;

        // Special Drop
        if (rng < (3000 + (totalLuck / 5))) { 
            isSpecial = true;
            uint256 subRng = uint256(keccak256(abi.encodePacked(rng, user))) % 1000;
            if (subRng < 300) droppedId = 401; 
            else if (subRng < 450) droppedId = 101; 
            else if (subRng < 600) droppedId = 201; 
            else if (subRng < 700) droppedId = 102; 
            else if (subRng < 800) droppedId = 202; 
            else if (subRng < 850) droppedId = 402; 
            else if (subRng < 890) droppedId = 103; 
            else if (subRng < 930) droppedId = 203; 
            else if (subRng < 960) droppedId = 104; 
            else if (subRng < 990) droppedId = 204; 
            else if (subRng < 995) droppedId = 205; 
            else droppedId = 499; 
        } 
        else {
            // Artifact Drop (Hardcore: No Pity)
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

    // --- SHOP (WITH DURATION CAP) ---
    function buyShopItem(address user, uint256 itemId) external onlyOwner {
        ItemStats memory stats = itemRegistry[itemId];
        require(stats.itemType == 4 || stats.itemType == 6, "Not sold");
        require(stats.price > 0, "No price");
        hashToken.burnByGame(user, stats.price);

        if (stats.itemType == 4) {
            // Buff Logic with Cap
            ActiveBuff storage current = softwareBuff[user];
            if (current.activeUntil > block.timestamp && current.statVal == stats.statVal) {
                uint256 newTime = current.activeUntil + 1 hours;
                if (newTime > block.timestamp + MAX_BUFF_DURATION) newTime = block.timestamp + MAX_BUFF_DURATION;
                current.activeUntil = newTime;
            } else {
                softwareBuff[user] = ActiveBuff(block.timestamp + 1 hours, stats.statVal);
            }
        } else {
            _mint(user, itemId, 1, "");
        }
    }

    // ... (Rest of functions: enchant, use, stake, unstake, etc. SAME AS v7.0) ...
    // COPY PASTE THE REST FROM PREVIOUS VERSION
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
    function stakeItem(address user, uint256 itemId, uint256 amount) external onlyOwner {
        require(balanceOf(user, itemId) >= amount, "Not enough items");
        require(itemRegistry[itemId].stakingYield > 0, "Not stakeable");
        _claimReward(user, itemId);
        _burn(user, itemId, amount);
        userStakes[user][itemId].amount += amount;
        userStakes[user][itemId].lastClaimTime = block.timestamp;
        emit StakingUpdate(user, itemId, userStakes[user][itemId].amount, true);
    }
    function unstakeItem(address user, uint256 itemId, uint256 amount) external onlyOwner {
        require(userStakes[user][itemId].amount >= amount, "Not enough staked");
        _claimReward(user, itemId);
        userStakes[user][itemId].amount -= amount;
        userStakes[user][itemId].lastClaimTime = block.timestamp;
        _mint(user, itemId, amount, "");
        emit StakingUpdate(user, itemId, userStakes[user][itemId].amount, false);
    }
    function claimItemReward(address user, uint256 itemId) external onlyOwner { _claimReward(user, itemId); }
    function _claimReward(address user, uint256 itemId) internal {
        StakeInfo storage info = userStakes[user][itemId];
        if (info.amount > 0) {
            uint256 secondsElapsed = block.timestamp - info.lastClaimTime;
            uint256 rate = itemRegistry[itemId].stakingYield;
            uint256 reward = secondsElapsed * rate * info.amount;
            if (reward > 0) { hashToken.mint(user, reward); emit RewardClaimed(user, reward); }
            info.lastClaimTime = block.timestamp;
        } else { info.lastClaimTime = block.timestamp; }
    }
    function getPendingReward(address user, uint256 itemId) public view returns (uint256) {
        StakeInfo memory info = userStakes[user][itemId];
        if (info.amount == 0) return 0;
        uint256 secondsElapsed = block.timestamp - info.lastClaimTime;
        return secondsElapsed * itemRegistry[itemId].stakingYield * info.amount;
    }
    function getStakedAmount(address user, uint256 itemId) public view returns (uint256) { return userStakes[user][itemId].amount; }
    function adminRewardHash(address to, uint256 amount) external onlyOwner { hashToken.mint(to, amount); }
    function adminMint(address to, uint256 itemId, uint256 amount) external onlyOwner { _mint(to, itemId, amount, ""); }
    function equipItem(address user, uint256 itemId) external onlyOwner {
        require(balanceOf(user, itemId) > 0, "Not owned");
        ItemStats memory stats = itemRegistry[itemId];
        if (stats.itemType == 2) playerRigs[user].equippedGPU = itemId;
        else if (stats.itemType == 3) playerRigs[user].equippedVPN = itemId;
        else revert("Not equippable");
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
            if (totalRed >= (BASE_COOLDOWN - MIN_COOLDOWN)) cooldown = MIN_COOLDOWN; else cooldown -= totalRed;
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