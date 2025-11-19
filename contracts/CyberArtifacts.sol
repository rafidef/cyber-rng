// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Token Economy
contract HashToken is ERC20, Ownable {
    constructor() ERC20("Cyber Hash", "HASH") Ownable(msg.sender) {}
    function mint(address to, uint256 amount) external onlyOwner { _mint(to, amount); }
    function burnByGame(address from, uint256 amount) external onlyOwner { _burn(from, amount); }
}

contract CyberArtifacts is ERC1155, ERC1155Burnable, Ownable {
    HashToken public hashToken;

    // --- CONFIGURATION ---
    uint256 public constant BASE_COOLDOWN = 5; // 5 Detik (Fast Paced)

    // --- DATA STRUCTURES ---
    struct ItemStats {
        uint8 itemType;   // 1=Artifact, 2=GPU, 3=VPN, 4=Software, 5=Material
        uint256 statVal;  // Luck / Speed / Price
        uint256 price;    // Harga di shop (0 = Drop Only)
    }
    
    mapping(uint256 => ItemStats) public itemRegistry;

    // Equip Slots
    struct PlayerRig {
        uint256 equippedGPU;
        uint256 equippedVPN;
    }

    // Buff Sementara
    struct ActiveBuff {
        uint256 activeUntil;
        uint256 statVal;
    }

    mapping(address => PlayerRig) public playerRigs;
    mapping(address => ActiveBuff) public softwareBuff;
    mapping(address => uint256) public lastMined;
    
    // Level Item (User -> ItemID -> Level)
    mapping(address => mapping(uint256 => uint256)) public itemLevels;

    // --- EVENTS ---
    event MiningResult(address indexed user, uint256 tokenId, uint256 rng, bool isEquipment);
    event EnchantResult(address indexed user, uint256 itemId, uint256 newLevel, bool success);
    event ItemEquipped(address indexed user, uint256 itemId, string slot);

    constructor(address _tokenAddress) ERC1155("https://api.kingtech.site/meta/{id}.json") Ownable(msg.sender) {
        hashToken = HashToken(_tokenAddress);
        _setupRegistry();
    }

    function _setupRegistry() internal {
        // ARTIFACTS (1-90)
        itemRegistry[1] = ItemStats(1, 10 ether, 0);   // Common
        itemRegistry[2] = ItemStats(1, 50 ether, 0);   // Uncommon
        itemRegistry[3] = ItemStats(1, 200 ether, 0);  // Rare
        itemRegistry[4] = ItemStats(1, 1000 ether, 0); // Epic
        itemRegistry[5] = ItemStats(1, 5000 ether, 0); // Legendary
        
        // SECRET (99)
        itemRegistry[99] = ItemStats(1, 0, 0); // Corrupted Core (Limit Break Material)

        // EQUIPMENT GPU (101-199)
        itemRegistry[101] = ItemStats(2, 1, 0); // Integrated Chip (-1s)
        itemRegistry[102] = ItemStats(2, 2, 0); // Mining Rig (-2s)
        itemRegistry[103] = ItemStats(2, 3, 0); // Quantum Core (-3s)
        
        // EQUIPMENT VPN (201-299)
        itemRegistry[201] = ItemStats(3, 500, 0);  // Free Proxy (+500 Luck)
        itemRegistry[202] = ItemStats(3, 2000, 0); // Private Node (+2000 Luck)
        itemRegistry[203] = ItemStats(3, 5000, 0); // Military Uplink (+5000 Luck)

        // SOFTWARE (301-399)
        itemRegistry[301] = ItemStats(4, 1000, 100 ether); // Script Kiddie
        itemRegistry[302] = ItemStats(4, 3000, 500 ether); // Zero Day
        
        // MATERIAL (401)
        itemRegistry[401] = ItemStats(5, 0, 0); // Overclock Chip (Standard Enchant)
    }

    // --- MINING SYSTEM ---
    function mineArtifact(address user) external onlyOwner {
        // 1. Cooldown Logic
        uint256 cooldownTime = BASE_COOLDOWN;
        uint256 gpuId = playerRigs[user].equippedGPU;
        
        if (gpuId != 0) {
            uint256 reduction = itemRegistry[gpuId].statVal; // Base Stat
            // GPU Level Up logic: Tidak nambah speed reduction (karena base sudah kecil),
            // tapi mungkin nanti bisa nambah luck sedikit? Untuk sekarang simple aja.
            if (reduction >= cooldownTime) cooldownTime = 1; 
            else cooldownTime -= reduction;
        }

        require(block.timestamp >= lastMined[user] + cooldownTime, "System Overheat");
        lastMined[user] = block.timestamp;

        // 2. Luck Calculation
        uint256 totalLuck = 0;
        uint256 vpnId = playerRigs[user].equippedVPN;
        
        if (vpnId != 0) {
            uint256 baseLuck = itemRegistry[vpnId].statVal;
            uint256 lvl = itemLevels[user][vpnId];
            // Formula: Luck = Base + (Base * Level * 20%)
            totalLuck += baseLuck + ((baseLuck * lvl * 20) / 100);
        }
        
        if (softwareBuff[user].activeUntil > block.timestamp) {
            totalLuck += softwareBuff[user].statVal;
        }

        // 3. RNG & Drop
        uint256 rng = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, user))) % 100000;
        uint256 droppedId;
        bool isSpecial = false;

        // A. Equipment / Secret Drop Check (1% Base + Luck Bonus)
        // Luck 5000 (+5%) -> Total 6% chance
        if (rng < (100 + (totalLuck / 10))) { 
            isSpecial = true;
            uint256 subRng = uint256(keccak256(abi.encodePacked(rng, user))) % 100;
            
            if (subRng < 40) droppedId = 101;      // GPU 1
            else if (subRng < 70) droppedId = 201; // VPN 1
            else if (subRng < 85) droppedId = 102; // GPU 2
            else if (subRng < 95) droppedId = 202; // VPN 2
            else droppedId = 99;                   // SECRET: Corrupted Core
        } 
        // B. Material Drop Check (Overclock Chip) - 5% Flat Chance separate from artifacts
        else if (rng > 95000) {
            isSpecial = true;
            droppedId = 401; // Overclock Chip
        }
        // C. Artifact Drop
        else {
            if (rng < 100 + totalLuck) droppedId = 5;      // Legendary
            else if (rng < 1000 + totalLuck) droppedId = 4; // Epic
            else if (rng < 5000 + totalLuck) droppedId = 3; // Rare
            else if (rng < 20000 + totalLuck) droppedId = 2;// Uncommon
            else droppedId = 1;                             // Common
        }

        _mint(user, droppedId, 1, "");
        emit MiningResult(user, droppedId, rng, isSpecial);
    }

    // --- WORKSHOP: ENCHANT SYSTEM ---
    function enchantItem(address user, uint256 targetItemId, uint256 materialId) external onlyOwner {
        require(balanceOf(user, targetItemId) > 0, "No target item");
        require(balanceOf(user, materialId) > 0, "No material");
        
        uint256 currentLvl = itemLevels[user][targetItemId];

        // 1. STANDARD ENCHANT (Overclock Chip - 401)
        if (materialId == 401) {
            require(currentLvl < 5, "Max standard level. Need Core.");
            _burn(user, 401, 1);

            // Success Rate: 100% (Lvl 0) -> 40% (Lvl 4)
            uint256 chance = 100 - (currentLvl * 15);
            uint256 rng = uint256(keccak256(abi.encodePacked(block.timestamp, user))) % 100;
            
            if (rng < chance) {
                itemLevels[user][targetItemId]++;
                emit EnchantResult(user, targetItemId, currentLvl + 1, true);
            } else {
                emit EnchantResult(user, targetItemId, currentLvl, false);
            }
        }
        // 2. LIMIT BREAK (Corrupted Core - 99)
        else if (materialId == 99) {
            require(currentLvl >= 5, "Item too weak for Core");
            require(currentLvl < 10, "Absolute Max Level");
            _burn(user, 99, 1);

            // Limit Break Always Success (Reward for rare item)
            itemLevels[user][targetItemId]++;
            emit EnchantResult(user, targetItemId, currentLvl + 1, true);
        } 
        else {
            revert("Invalid material");
        }
    }

    // --- UTILS ---
    function equipItem(address user, uint256 itemId) external onlyOwner {
        require(balanceOf(user, itemId) > 0, "Not owned");
        ItemStats memory stats = itemRegistry[itemId];
        if (stats.itemType == 2) playerRigs[user].equippedGPU = itemId;
        else if (stats.itemType == 3) playerRigs[user].equippedVPN = itemId;
        else revert("Not equippable");
        emit ItemEquipped(user, itemId, stats.itemType == 2 ? "GPU" : "VPN");
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

    // Helper for Backend
    function getPlayerStats(address user) external view returns (uint256[5] memory) {
        // Returns: [Cooldown, Luck, GPU_ID, VPN_ID, BuffTime]
        uint256 cooldown = BASE_COOLDOWN;
        uint256 gpu = playerRigs[user].equippedGPU;
        if (gpu != 0) {
            if (itemRegistry[gpu].statVal >= cooldown) cooldown = 1; 
            else cooldown -= itemRegistry[gpu].statVal;
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
    
    function getItemLevel(address user, uint256 itemId) external view returns (uint256) {
        return itemLevels[user][itemId];
    }
}