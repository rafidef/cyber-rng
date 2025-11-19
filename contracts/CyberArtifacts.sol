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
    
    // --- CONFIG ---
    uint256 public constant BASE_COOLDOWN = 30; // UPDATE: 30 DETIK

    struct ItemStats {
        uint8 itemType;   // 1=Art, 2=GPU, 3=VPN, 4=Soft, 5=Mat, 6=Cons
        uint256 statVal;  
        uint256 price;    
    }
    
    mapping(uint256 => ItemStats) public itemRegistry;
    
    struct PlayerRig { uint256 equippedGPU; uint256 equippedVPN; }
    struct ActiveBuff { uint256 activeUntil; uint256 statVal; }
    
    mapping(address => PlayerRig) public playerRigs;
    mapping(address => ActiveBuff) public softwareBuff;
    mapping(address => uint256) public lastMined;
    mapping(address => mapping(uint256 => uint256)) public itemLevels;

    event MiningResult(address indexed user, uint256 tokenId, uint256 rng, bool isSpecial);
    event EnchantResult(address indexed user, uint256 itemId, uint256 newLevel, bool success);
    event ItemUsed(address indexed user, uint256 itemId, string effect);

    constructor(address _tokenAddress) ERC1155("https://api.kingtech.site/meta/{id}.json") Ownable(msg.sender) {
        hashToken = HashToken(_tokenAddress);
        _setupRegistry();
    }

    function _setupRegistry() internal {
        // 1. ARTIFACTS (Salvage Value)
        itemRegistry[1] = ItemStats(1, 10 ether, 0);
        itemRegistry[2] = ItemStats(1, 25 ether, 0);
        itemRegistry[3] = ItemStats(1, 50 ether, 0);
        itemRegistry[4] = ItemStats(1, 100 ether, 0);
        itemRegistry[5] = ItemStats(1, 250 ether, 0);
        itemRegistry[6] = ItemStats(1, 1000 ether, 0);
        itemRegistry[7] = ItemStats(1, 5000 ether, 0);
        itemRegistry[8] = ItemStats(1, 25000 ether, 0); // Mythic

        // 2. GPU (Max reduction 20s, karena base 30s. Sisa 10s)
        itemRegistry[101] = ItemStats(2, 2, 0);  // -2s
        itemRegistry[102] = ItemStats(2, 5, 0);  // -5s
        itemRegistry[103] = ItemStats(2, 10, 0); // -10s
        itemRegistry[104] = ItemStats(2, 15, 0); // -15s

        // 3. VPN (Luck)
        itemRegistry[201] = ItemStats(3, 100, 0);
        itemRegistry[202] = ItemStats(3, 500, 0);
        itemRegistry[203] = ItemStats(3, 1500, 0);
        itemRegistry[204] = ItemStats(3, 3000, 0);
        itemRegistry[205] = ItemStats(3, 8000, 0);

        // 4. SOFTWARE (Shop)
        itemRegistry[301] = ItemStats(4, 1000, 100 ether);
        itemRegistry[302] = ItemStats(4, 5000, 500 ether);
        itemRegistry[303] = ItemStats(4, 20000, 2000 ether);

        // 5. MATERIALS
        itemRegistry[401] = ItemStats(5, 0, 50 ether);  // Silicon Scrap
        itemRegistry[402] = ItemStats(5, 0, 200 ether); // Overclock Chip
        itemRegistry[499] = ItemStats(5, 0, 0);         // Secret Core

        // 6. CONSUMABLES
        itemRegistry[501] = ItemStats(6, 0, 150 ether); // Thermal Paste
        itemRegistry[502] = ItemStats(6, 0, 500 ether); // Loot Crate
    }

    function mineArtifact(address user) external onlyOwner {
        // COOLDOWN Logic
        uint256 cooldownTime = BASE_COOLDOWN;
        uint256 gpuId = playerRigs[user].equippedGPU;
        if (gpuId != 0) {
            uint256 reduction = itemRegistry[gpuId].statVal;
            // GPU Level Bonus: Level * 1s reduction
            uint256 lvl = itemLevels[user][gpuId];
            uint256 totalRed = reduction + lvl; 
            
            if (totalRed >= cooldownTime) cooldownTime = 5; // Min 5 detik absolut
            else cooldownTime -= totalRed;
        }
        require(block.timestamp >= lastMined[user] + cooldownTime, "Overheat");
        lastMined[user] = block.timestamp;

        // LUCK Logic
        uint256 totalLuck = 0;
        uint256 vpnId = playerRigs[user].equippedVPN;
        if (vpnId != 0) {
            uint256 base = itemRegistry[vpnId].statVal;
            uint256 lvl = itemLevels[user][vpnId];
            totalLuck += base + ((base * lvl * 20) / 100);
        }
        if (softwareBuff[user].activeUntil > block.timestamp) totalLuck += softwareBuff[user].statVal;

        // RNG & DROP
        uint256 rng = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, user))) % 100000;
        uint256 droppedId;
        bool isSpecial = false;

        // Special Drop (Equip/Mat/Secret) - Chance based on Luck
        if (rng < (3000 + (totalLuck / 5))) { // Base 3% + Luck Boost
            isSpecial = true;
            uint256 subRng = uint256(keccak256(abi.encodePacked(rng, user))) % 100;
            if (subRng < 30) droppedId = 401; // Scrap
            else if (subRng < 50) droppedId = 101; 
            else if (subRng < 70) droppedId = 201; 
            else if (subRng < 80) droppedId = 102; 
            else if (subRng < 90) droppedId = 202; 
            else if (subRng < 95) droppedId = 402; // Chip
            else droppedId = 499; // SECRET
        } 
        else {
            // Artifacts
            if (rng < 50 + totalLuck) droppedId = 8;       // Mythic
            else if (rng < 250 + totalLuck) droppedId = 7; // Legendary
            else if (rng < 1000 + totalLuck) droppedId = 6;// Epic
            else if (rng < 3000 + totalLuck) droppedId = 5;
            else if (rng < 7000 + totalLuck) droppedId = 4;
            else if (rng < 15000 + totalLuck) droppedId = 3;
            else if (rng < 35000 + totalLuck) droppedId = 2;
            else droppedId = 1;
        }
        _mint(user, droppedId, 1, "");
        emit MiningResult(user, droppedId, rng, isSpecial);
    }

    function enchantItem(address user, uint256 targetItemId, uint256 materialId) external onlyOwner {
        require(balanceOf(user, targetItemId) > 0, "No target");
        require(balanceOf(user, materialId) > 0, "No material");
        uint256 lvl = itemLevels[user][targetItemId];
        
        uint256 chance = 0;
        if (materialId == 401) { // Scrap (Weak)
            require(lvl < 3); chance = 80 - (lvl * 20);
        } else if (materialId == 402) { // Chip (Std)
            require(lvl < 6); chance = 70 - (lvl * 10);
        } else if (materialId == 499) { // Core (Limit Break)
            require(lvl >= 6 && lvl < 10); chance = 100;
        } else revert("Invalid Mat");

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
        
        if (itemId == 501) { // Thermal Paste
            lastMined[user] = 0; 
            emit ItemUsed(user, itemId, "CD_RESET");
        } 
        else if (itemId == 502) { // Loot Crate
            uint256 r = uint256(keccak256(abi.encodePacked(block.timestamp, user))) % 900;
            hashToken.mint(user, (100+r) * 1 ether);
            emit ItemUsed(user, itemId, "CRATE_OPEN");
        }
    }

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

    function adminRewardHash(address to, uint256 amount) external onlyOwner { hashToken.mint(to, amount); }
    function adminMint(address to, uint256 itemId, uint256 amount) external onlyOwner { _mint(to, itemId, amount, ""); }

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