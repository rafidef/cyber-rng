import express from 'express';
import { ethers } from 'ethers';
import * as dotenv from 'dotenv';
import cors from 'cors';

dotenv.config();

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.PORT || 3000;
const PRIVATE_KEY = process.env.PRIVATE_KEY!;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS!;
const RPC_URL = process.env.POLYGON_AMOY_RPC;

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

app.get('/profile/:address', async (req, res) => {
    try {
        const stats = await gameContract.getPlayerStats(req.params.address);
        let balance = "0.0";
        if (tokenContract) {
            const raw = await tokenContract.balanceOf(req.params.address);
            balance = parseFloat(ethers.formatEther(raw)).toFixed(1);
        }
        const gpuId = stats[2].toString();
        const vpnId = stats[3].toString();
        
        // Get Equipment Levels
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

app.post('/mine', async (req, res) => {
    try {
        const { userAddress, signature } = req.body;
        if (ethers.verifyMessage("MINT_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        
        const tx = await gameContract.mineArtifact(userAddress);
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

app.post('/workshop/enchant', async (req, res) => {
    try {
        const { userAddress, signature, targetId, materialId } = req.body;
        if (ethers.verifyMessage("ENCHANT_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });

        console.log(`⚡ Enchanting Item #${targetId} for ${userAddress}`);
        const tx = await gameContract.enchantItem(userAddress, targetId, materialId);
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

app.post('/equip', async (req, res) => {
    try {
        const { userAddress, signature, itemId } = req.body;
        if (ethers.verifyMessage("EQUIP_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        const tx = await gameContract.equipItem(userAddress, itemId);
        await tx.wait();
        res.json({ success: true });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.post('/shop/software', async (req, res) => {
    try {
        const { userAddress, signature, itemId } = req.body;
        if (ethers.verifyMessage("BUY_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        const tx = await gameContract.buySoftware(userAddress, itemId);
        await tx.wait();
        res.json({ success: true });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.post('/salvage', async (req, res) => {
    try {
        const { userAddress, signature, tokenId, amount } = req.body;
        if (ethers.verifyMessage("SALVAGE_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Invalid Sig" });
        const tx = await gameContract.salvageArtifact(userAddress, tokenId, amount);
        await tx.wait();
        res.json({ success: true, message: "Salvage Complete" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.get('/inventory/:address', async (req, res) => {
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

app.listen(PORT, () => console.log(`🚀 CyberRNG v5.0 (5s CD) running on ${PORT}`));