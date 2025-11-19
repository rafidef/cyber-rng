import express from 'express';
import { ethers } from 'ethers';
import * as dotenv from 'dotenv';
import cors from 'cors';
import * as fs from 'fs'; // Import File System

dotenv.config();

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.PORT || 3000;
const PRIVATE_KEY = process.env.PRIVATE_KEY!;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS!;
const RPC_URL = process.env.POLYGON_AMOY_RPC;

// --- SIMPLE DATABASE SYSTEM ---
const DB_FILE = 'users.json';
let knownUsers: Set<string> = new Set();

// Load database saat server start
if (fs.existsSync(DB_FILE)) {
    try {
        const data = fs.readFileSync(DB_FILE, 'utf-8');
        const parsed = JSON.parse(data);
        if (Array.isArray(parsed)) {
            parsed.forEach((u: string) => knownUsers.add(u));
            console.log(`📂 Database Loaded: ${knownUsers.size} known hackers.`);
        }
    } catch (e) { console.error("Error loading DB, starting fresh."); }
}

// Fungsi untuk mencatat user baru
function registerUser(address: string) {
    const normalized = address.toLowerCase(); // Simpan dalam lowercase agar konsisten
    // Jika user belum ada di list, simpan dan update file
    // Kita simpan address asli (bukan normalized) di set untuk display, tapi cek duplikasi
    
    let exists = false;
    knownUsers.forEach(u => { if(u.toLowerCase() === normalized) exists = true; });

    if (!exists) {
        knownUsers.add(address);
        fs.writeFileSync(DB_FILE, JSON.stringify([...knownUsers]));
        console.log(`📝 New User Registered: ${address}`);
    }
}

// --- METADATA DATABASE ---
const ITEM_DB: Record<string, { name: string, type: string, stats: string }> = {
    "1": { name: "Lost Sector", type: "ARTIFACT", stats: "10 $HASH" },
    "2": { name: "Encoded Fragment", type: "ARTIFACT", stats: "50 $HASH" },
    "3": { name: "Encrypted Data", type: "ARTIFACT", stats: "200 $HASH" },
    "4": { name: "Root Access", type: "ARTIFACT", stats: "1000 $HASH" },
    "5": { name: "Genesis Block", type: "ARTIFACT", stats: "5000 $HASH" },
    "99": { name: "Corrupted Core", type: "SECRET", stats: "LIMIT BREAK MATERIAL" },
    "101": { name: "Integrated Chip", type: "GPU", stats: "Speed -1s" },
    "102": { name: "Mining Rig v1", type: "GPU", stats: "Speed -2s" },
    "103": { name: "Quantum Core", type: "GPU", stats: "Speed -3s" },
    "201": { name: "Free Proxy", type: "VPN", stats: "Luck +500" },
    "202": { name: "Private Node", type: "VPN", stats: "Luck +2000" },
    "203": { name: "Military Uplink", type: "VPN", stats: "Luck +5000" },
    "301": { name: "Script Kiddie", type: "SOFT", stats: "Luck +1000" },
    "302": { name: "Black Hat Tool", type: "SOFT", stats: "Luck +3000" },
    "401": { name: "Overclock Chip", type: "MAT", stats: "Enchant Material" }
};

const GAME_ABI = [
    "function mineArtifact(address recipient) external",
    "function salvageArtifact(address user, uint256 tokenId, uint256 amount) external",
    "function equipItem(address user, uint256 itemId) external",
    "function buySoftware(address user, uint256 itemId) external",
    "function enchantItem(address user, uint256 targetItemId, uint256 materialId) external",
    "function getPlayerStats(address user) external view returns (uint256[5])",
    "function getItemLevel(address user, uint256 itemId) external view returns (uint256)",
    "function balanceOfBatch(address[] accounts, uint256[] ids) public view returns (uint256[])",
    "function hashToken() public view returns (address)",
    "event MiningResult(address indexed user, uint256 tokenId, uint256 rng, bool isEquipment)",
    "event EnchantResult(address indexed user, uint256 itemId, uint256 newLevel, bool success)"
];
const TOKEN_ABI = ["function balanceOf(address account) public view returns (uint256)"];

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const gameContract = new ethers.Contract(CONTRACT_ADDRESS, GAME_ABI, wallet);

let tokenContract: ethers.Contract | null = null;
gameContract.hashToken().then((addr: string) => {
    tokenContract = new ethers.Contract(addr, TOKEN_ABI, wallet);
    console.log(`🔗 Token Linked: ${addr}`);
});

const getMetadata = (id: string) => ITEM_DB[id] || { name: "Unknown", type: "???", stats: "?" };

// --- ROUTES ---

// 1. LEADERBOARD (NEW)
app.get('/leaderboard', async (req, res) => {
    try {
        const users = [...knownUsers];
        const leaderboard = [];

        // Scan saldo setiap user
        for (const addr of users) {
            let balanceVal = 0;
            let balanceStr = "0.0";
            
            if (tokenContract) {
                try {
                    const raw = await tokenContract.balanceOf(addr);
                    balanceVal = Number(ethers.formatEther(raw));
                    balanceStr = balanceVal.toFixed(1);
                } catch(e) {}
            }
            leaderboard.push({ address: addr, balance: balanceStr, raw: balanceVal });
        }

        // Sort: Tertinggi ke Terendah
        leaderboard.sort((a, b) => b.raw - a.raw);

        // Ambil Top 10
        res.json({ top10: leaderboard.slice(0, 10) });
    } catch (error: any) {
        res.status(500).json({ error: error.message });
    }
});

// 2. PROFILE
app.get('/profile/:address', async (req, res) => {
    try {
        registerUser(req.params.address); // Register saat cek profile
        const stats = await gameContract.getPlayerStats(req.params.address);
        let balance = "0.0";
        if (tokenContract) {
            const raw = await tokenContract.balanceOf(req.params.address);
            balance = parseFloat(ethers.formatEther(raw)).toFixed(1);
        }
        const gpuId = stats[2].toString();
        const vpnId = stats[3].toString();
        
        let gpuName = "None", vpnName = "None";
        if (gpuId !== "0") {
            const lvl = await gameContract.getItemLevel(req.params.address, gpuId);
            gpuName = `${getMetadata(gpuId).name} (+${lvl})`;
        }
        if (vpnId !== "0") {
            const lvl = await gameContract.getItemLevel(req.params.address, vpnId);
            vpnName = `${getMetadata(vpnId).name} (+${lvl})`;
        }

        res.json({
            address: req.params.address,
            balance,
            stats: { cooldown: Number(stats[0]), luck: Number(stats[1]), buffTime: Number(stats[4]) },
            rig: { gpu: gpuName, vpn: vpnName }
        });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 3. MINE
app.post('/mine', async (req, res) => {
    try {
        const { userAddress, signature } = req.body;
        registerUser(userAddress); // Register
        
        if (ethers.verifyMessage("MINT_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        
        const tx = await gameContract.mineArtifact(userAddress, { gasLimit: 500000 }); // Gas Fix
        const receipt = await tx.wait();
        
        let result = null;
        for (const log of receipt.logs) {
            try {
                const parsed = gameContract.interface.parseLog(log);
                if (parsed && parsed.name === 'MiningResult') {
                    const id = parsed.args[1].toString();
                    result = { ...getMetadata(id), tokenId: id, isEquipment: parsed.args[3] };
                }
            } catch (e) {}
        }
        res.json({ success: true, txHash: tx.hash, data: result });
    } catch (e: any) { 
        if (e.message.includes("System Overheat")) return res.status(429).json({ error: "Overheat" });
        res.status(500).json({ error: e.message }); 
    }
});

// 4. WORKSHOP
app.post('/workshop/enchant', async (req, res) => {
    try {
        const { userAddress, signature, targetId, materialId } = req.body;
        registerUser(userAddress);

        if (ethers.verifyMessage("ENCHANT_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });

        console.log(`⚡ Enchanting Item #${targetId} for ${userAddress}`);
        const tx = await gameContract.enchantItem(userAddress, targetId, materialId, { gasLimit: 500000 });
        const receipt = await tx.wait();
        
        let success = false, newLevel = 0;
        for (const log of receipt.logs) {
            try {
                const parsed = gameContract.interface.parseLog(log);
                if (parsed && parsed.name === 'EnchantResult') {
                    newLevel = Number(parsed.args[2]);
                    success = parsed.args[3];
                }
            } catch (e) {}
        }
        res.json({ success, level: newLevel, message: success ? "Upgrade Successful!" : "Upgrade Failed (Chip Burned)" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 5. EQUIP
app.post('/equip', async (req, res) => {
    try {
        const { userAddress, signature, itemId } = req.body;
        registerUser(userAddress);
        if (ethers.verifyMessage("EQUIP_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        const tx = await gameContract.equipItem(userAddress, itemId, { gasLimit: 200000 });
        await tx.wait();
        res.json({ success: true });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 6. SHOP BUFF
app.post('/shop/software', async (req, res) => {
    try {
        const { userAddress, signature, itemId } = req.body;
        registerUser(userAddress);
        if (ethers.verifyMessage("BUY_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        const tx = await gameContract.buySoftware(userAddress, itemId, { gasLimit: 200000 });
        await tx.wait();
        res.json({ success: true });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 7. SALVAGE
app.post('/salvage', async (req, res) => {
    try {
        const { userAddress, signature, tokenId, amount } = req.body;
        registerUser(userAddress);
        if (ethers.verifyMessage("SALVAGE_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        const tx = await gameContract.salvageArtifact(userAddress, tokenId, amount, { gasLimit: 200000 });
        await tx.wait();
        res.json({ success: true, message: "Salvage Complete" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 8. INVENTORY
app.get('/inventory/:address', async (req, res) => {
    registerUser(req.params.address); // Register saat cek inventory
    const ids = [1,2,3,4,5, 99, 101,102,103, 201,202,203, 401];
    const accounts = Array(ids.length).fill(req.params.address);
    try {
        const bals = await gameContract.balanceOfBatch(accounts, ids);
        const items = ids.map((id, i) => {
            const qty = Number(bals[i]);
            if (qty > 0) return { id, ...getMetadata(id.toString()), qty };
            return null;
        }).filter(x => x);
        res.json({ items });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.listen(PORT, () => console.log(`🚀 CyberRNG v5.1 (Leaderboard) running on ${PORT}`));