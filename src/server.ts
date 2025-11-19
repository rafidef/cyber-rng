import express from 'express';
import { ethers } from 'ethers';
import * as dotenv from 'dotenv';
import cors from 'cors';
import db from './database'; // Pastikan file src/database.ts sudah ada

dotenv.config();

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.PORT || 3000;
const PRIVATE_KEY = process.env.PRIVATE_KEY!;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS!;
const RPC_URL = process.env.POLYGON_AMOY_RPC;

// --- MASTER ITEM DATABASE ---
const ITEM_DB: Record<string, { name: string, type: string, stats: string, yield?: string }> = {
    // Artifacts
    "1": { name: "Corrupted File", type: "JUNK", stats: "10 $HASH" },
    "2": { name: "Glitched Log", type: "JUNK", stats: "25 $HASH" },
    "3": { name: "Encoded Fragment", type: "JUNK", stats: "50 $HASH" },
    "4": { name: "Decrypted Header", type: "JUNK", stats: "100 $HASH" },
    "5": { name: "VPN Log", type: "RARE", stats: "250 $HASH" },
    "6": { name: "Root Key", type: "EPIC", stats: "1000 $HASH" },
    "7": { name: "Zero Day", type: "LEGEND", stats: "5000 $HASH" },
    "8": { name: "Genesis Hash", type: "MYTHIC", stats: "25k $HASH" },

    // GPU (Speed & Staking Yield)
    "101": { name: "Integrated Chip", type: "GPU", stats: "Spd -2s", yield: "0.1" },
    "102": { name: "Overclocked APU", type: "GPU", stats: "Spd -5s", yield: "0.5" },
    "103": { name: "Mining Rig v1", type: "GPU", stats: "Spd -10s", yield: "2.0" },
    "104": { name: "Quantum Core", type: "GPU", stats: "Spd -15s", yield: "10.0" },

    // VPN (Luck & Staking Yield)
    "201": { name: "Public Proxy", type: "VPN", stats: "Luck +100", yield: "0.05" },
    "202": { name: "Tor Node", type: "VPN", stats: "Luck +500", yield: "0.2" },
    "203": { name: "Private Tunnel", type: "VPN", stats: "Luck +1500", yield: "0.8" },
    "204": { name: "Military Uplink", type: "VPN", stats: "Luck +3000", yield: "4.0" },
    "205": { name: "AI Neural Net", type: "VPN", stats: "Luck +8000", yield: "20.0" },

    // Software
    "301": { name: "Script Kiddie", type: "SOFT", stats: "Luck +1k" },
    "302": { name: "Black Hat Tool", type: "SOFT", stats: "Luck +5k" },
    "303": { name: "State Sponsored", type: "SOFT", stats: "Luck +20k" },

    // Materials
    "401": { name: "Silicon Scrap", type: "MAT", stats: "Enhance 1-3" },
    "402": { name: "Overclock Chip", type: "MAT", stats: "Enhance 1-6" },
    "499": { name: "Corrupted Core", type: "SECRET", stats: "Limit Break" },
    
    // Consumables
    "501": { name: "Thermal Paste", type: "CONS", stats: "Reset CD" },
    "502": { name: "Loot Crate", type: "CONS", stats: "Random Prize" }
};

const GAME_ABI = [
    // Actions
    "function mineArtifact(address recipient) external",
    "function salvageArtifact(address user, uint256 tokenId, uint256 amount) external",
    "function equipItem(address user, uint256 itemId) external",
    "function buySoftware(address user, uint256 itemId) external",
    "function enchantItem(address user, uint256 targetItemId, uint256 materialId) external",
    "function useConsumable(address user, uint256 itemId) external",
    
    // Staking
    "function stakeItem(address user, uint256 itemId, uint256 amount) external",
    "function unstakeItem(address user, uint256 itemId, uint256 amount) external",
    "function claimItemReward(address user, uint256 itemId) external",
    "function getPendingReward(address user, uint256 itemId) public view returns (uint256)",
    "function getStakedAmount(address user, uint256 itemId) public view returns (uint256)",

    // Admin
    "function adminRewardHash(address to, uint256 amount) external",
    
    // Views
    "function getPlayerStats(address user) external view returns (uint256[5])",
    "function getItemLevel(address user, uint256 itemId) external view returns (uint256)",
    "function balanceOfBatch(address[] accounts, uint256[] ids) public view returns (uint256[])",
    "function hashToken() public view returns (address)",
    
    // Events
    "event MiningResult(address indexed user, uint256 tokenId, uint256 rng, bool isSpecial)",
    "event EnchantResult(address indexed user, uint256 itemId, uint256 newLevel, bool success)",
    "event ItemUsed(address indexed user, uint256 itemId, string effect)"
];

const TOKEN_ABI = ["function balanceOf(address account) public view returns (uint256)"];

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const gameContract = new ethers.Contract(CONTRACT_ADDRESS, GAME_ABI, wallet);
let tokenContract: ethers.Contract | null = null;

// Init Token Contract
gameContract.hashToken().then((addr: string) => { 
    tokenContract = new ethers.Contract(addr, TOKEN_ABI, wallet);
    console.log(`🔗 Token Linked: ${addr}`);
}).catch((err: any) => console.log("Waiting for token..."));

const getMeta = (id: string) => ITEM_DB[id] || { name: "Unknown", type: "???", stats: "?" };

// --- DB HELPERS ---
function upsertUser(addr: string, bal: string) {
    db.run(`INSERT INTO users (address, hash_balance, last_seen) VALUES (?, ?, datetime('now'))
            ON CONFLICT(address) DO UPDATE SET hash_balance=?, last_seen=datetime('now')`, [addr, bal, bal]);
}

// --- MISSION LOGIC ---
const MISSION_POOL = [
    { type: "MINE_COUNT", desc: "Hack the Node %d times", min: 10, max: 25, rewardMult: 3 }, 
    { type: "SALVAGE_COUNT", desc: "Salvage %d Artifacts", min: 3, max: 8, rewardMult: 15 },
    { type: "SPEND_HASH", desc: "Spend %d $HASH", min: 100, max: 500, rewardMult: 0.5 },
    { type: "ENCHANT_ATTEMPT", desc: "Attempt Overclock %d times", min: 1, max: 3, rewardMult: 50 },
    { type: "FIND_EQUIP", desc: "Find any Hardware (GPU/VPN)", target: 1, fixedReward: 300 },
    { type: "USE_THERMAL", desc: "Use Thermal Paste", target: 1, fixedReward: 100 },
    { type: "STAKE_ITEM", desc: "Install Hardware to Server", target: 1, fixedReward: 100 },
    { type: "CLAIM_YIELD", desc: "Claim Passive Income", target: 1, fixedReward: 50 }
];

function generateMissions(addr: string) {
    const today = new Date().toISOString().split('T')[0];
    const shuffled = [...MISSION_POOL].sort(() => 0.5 - Math.random()).slice(0, 3); // Pick 3
    
    shuffled.forEach(tpl => {
        let target = 0, rewardVal = 0;
        if (tpl.fixedReward) {
            target = tpl.target || 1;
            rewardVal = tpl.fixedReward;
        } else {
            target = tpl.min! + Math.floor(Math.random() * (tpl.max! - tpl.min! + 1));
            rewardVal = Math.floor(target * tpl.rewardMult!);
        }
        const key = `${tpl.type}:${target}:${rewardVal}`;
        db.run(`INSERT OR IGNORE INTO missions (address, mission_key, target, date) VALUES (?, ?, ?, ?)`, [addr, key, target, today]);
    });
}

function trackMission(addr: string, type: string, val: number = 1) {
    const today = new Date().toISOString().split('T')[0];
    db.all(`SELECT * FROM missions WHERE address=? AND date=? AND claimed=0`, [addr, today], (e, rows) => {
        if(rows) rows.forEach((r:any) => {
            const [mType, mTarget] = r.mission_key.split(':');
            if (mType === type) {
                const newProg = Math.min(r.progress + val, Number(mTarget));
                if(newProg !== r.progress) db.run(`UPDATE missions SET progress=? WHERE id=?`, [newProg, r.id]);
            }
        });
    });
}

// --- ROUTES ---

// 1. MINE (Optimized with staticCall)
app.post('/mine', async (req, res) => {
    try {
        const { userAddress, signature } = req.body;
        
        // Auth Check
        if (ethers.verifyMessage("MINT_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) {
            return res.status(401).json({ error: "Invalid Sig" });
        }

        // --- STATIC CALL SIMULATION ---
        // Cek apakah akan gagal (revert) sebelum kirim TX asli
        try {
            await gameContract.mineArtifact.staticCall(userAddress);
        } catch (simError: any) {
            const msg = simError.reason || simError.message || "";
            if (msg.includes("Overheat") || msg.includes("System Overheat")) {
                return res.status(429).json({ error: "System Overheat" }); // Clean Error
            }
            // Jika error lain, biarkan lanjut (mungkin masalah network sesaat)
            console.log("Sim Warning:", msg);
        }

        // Send Transaction
        const tx = await gameContract.mineArtifact(userAddress, { gasLimit: 500000 });
        const receipt = await tx.wait();
        
        // Track Mission
        trackMission(userAddress, "MINE_COUNT", 1);

        // Parse Logs
        let result = null;
        for (const log of receipt.logs) {
            try {
                const parsed = gameContract.interface.parseLog(log);
                if (parsed && parsed.name === 'MiningResult') {
                    const id = Number(parsed.args[1]);
                    result = { ...getMeta(id.toString()), tokenId: id.toString(), isEquipment: parsed.args[3] };
                    
                    // Track Finds
                    if (result.isEquipment || id >= 100) trackMission(userAddress, "FIND_EQUIP", 1);
                }
            } catch (e) {}
        }
        res.json({ success: true, txHash: tx.hash, data: result });

    } catch (e: any) { 
        // Fallback Error
        const msg = e.reason || e.message;
        if(msg.includes("Overheat")) return res.status(429).json({error: "System Overheat"});
        res.status(500).json({ error: msg });
    }
});

// 2. PROFILE
app.get('/profile/:address', async (req, res) => {
    try {
        const stats = await gameContract.getPlayerStats(req.params.address);
        let balance = "0.0";
        if (tokenContract) {
            const raw = await tokenContract.balanceOf(req.params.address);
            balance = parseFloat(ethers.formatEther(raw)).toFixed(1);
        }
        upsertUser(req.params.address, balance);

        const gpuId = stats[2].toString();
        const vpnId = stats[3].toString();
        let gpuName = "None", vpnName = "None";
        
        if (gpuId !== "0") {
            const l = await gameContract.getItemLevel(req.params.address, gpuId);
            gpuName = `${getMeta(gpuId).name} (+${l})`;
        }
        if (vpnId !== "0") {
            const l = await gameContract.getItemLevel(req.params.address, vpnId);
            vpnName = `${getMeta(vpnId).name} (+${l})`;
        }

        res.json({
            address: req.params.address,
            balance,
            stats: { cooldown: Number(stats[0]), luck: Number(stats[1]), buffTime: Number(stats[4]) },
            rig: { gpu: gpuName, vpn: vpnName }
        });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 3. STAKING (Server Room)
app.get('/rig/status/:address', async (req, res) => {
    try {
        const addr = req.params.address;
        const stakeableIds = [101,102,103,104, 201,202,203,204,205];
        const data = [];
        
        for (const id of stakeableIds) {
            const amount = await gameContract.getStakedAmount(addr, id);
            if (amount > 0) {
                const pending = await gameContract.getPendingReward(addr, id);
                const meta = getMeta(id.toString());
                data.push({
                    id: id,
                    name: meta.name,
                    yieldRate: meta.yield,
                    staked: Number(amount),
                    pending: parseFloat(ethers.formatEther(pending)).toFixed(2)
                });
            }
        }
        res.json({ stakes: data });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.post('/rig/stake', async (req, res) => {
    try {
        const { userAddress, signature, itemId, amount } = req.body;
        if (ethers.verifyMessage("STAKE_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth Failed" });
        
        const tx = await gameContract.stakeItem(userAddress, itemId, amount, { gasLimit: 500000 });
        await tx.wait();
        
        trackMission(userAddress, "STAKE_ITEM", 1);
        res.json({ success: true, message: "Hardware Installed" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.post('/rig/unstake', async (req, res) => {
    try {
        const { userAddress, signature, itemId, amount } = req.body;
        if (ethers.verifyMessage("UNSTAKE_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth Failed" });
        const tx = await gameContract.unstakeItem(userAddress, itemId, amount, { gasLimit: 500000 });
        await tx.wait();
        res.json({ success: true, message: "Hardware Removed" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.post('/rig/claim', async (req, res) => {
    try {
        const { userAddress, signature, itemId } = req.body;
        if (ethers.verifyMessage("CLAIM_YIELD", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth Failed" });
        const tx = await gameContract.claimItemReward(userAddress, itemId, { gasLimit: 500000 });
        await tx.wait();
        trackMission(userAddress, "CLAIM_YIELD", 1);
        res.json({ success: true, message: "Yield Collected" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 4. WORKSHOP (Enchant)
app.post('/workshop/enchant', async (req, res) => {
    try {
        const { userAddress, signature, targetId, materialId } = req.body;
        if (ethers.verifyMessage("ENCHANT_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth" });

        const tx = await gameContract.enchantItem(userAddress, targetId, materialId, { gasLimit: 500000 });
        const receipt = await tx.wait();
        trackMission(userAddress, "ENCHANT_ATTEMPT", 1);

        let success = false, lvl = 0;
        for (const log of receipt.logs) {
            try {
                const p = gameContract.interface.parseLog(log);
                if(p && p.name === 'EnchantResult') { lvl = Number(p.args[2]); success = p.args[3]; }
            } catch(e){}
        }
        res.json({ success, level: lvl, message: success ? "Success!" : "Failed (Chip Lost)" });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

// 5. MISSIONS
app.get('/contracts/:address', (req, res) => {
    const addr = req.params.address;
    const today = new Date().toISOString().split('T')[0];
    db.all(`SELECT * FROM missions WHERE address=? AND date=?`, [addr, today], (e, rows) => {
        if (!rows || rows.length === 0) {
            generateMissions(addr);
            setTimeout(() => { db.all(`SELECT * FROM missions WHERE address=? AND date=?`, [addr, today], (e2, r2) => res.json(formatMissions(r2))); }, 200);
        } else res.json(formatMissions(rows));
    });
});

function formatMissions(rows: any[]) {
    return {
        date: new Date().toISOString().split('T')[0],
        missions: rows.map(r => {
            const [type, target, reward] = r.mission_key.split(':');
            let desc = `${type} ${target}`;
            if(type.includes("MINE")) desc=`Hack Node ${target}x`;
            else if(type.includes("SALVAGE")) desc=`Salvage ${target} items`;
            else if(type.includes("SPEND")) desc=`Spend ${target} $HASH`;
            else if(type.includes("ENCHANT")) desc=`Overclock ${target}x`;
            else if(type.includes("STAKE")) desc=`Install Hardware to Server`;
            else if(type.includes("CLAIM")) desc=`Claim Passive Income`;
            else if(type.includes("FIND")) desc=`Find Specific Item`;
            else if(type.includes("USE")) desc=`Use Consumable`;
            return { id: r.id, desc, progress: r.progress, target: Number(target), reward: `${reward} $HASH`, claimed: r.claimed === 1 };
        })
    };
}

app.post('/contracts/claim', async (req, res) => {
    const { userAddress, signature, missionId } = req.body;
    // Verify Sig (Simplified)
    db.get(`SELECT * FROM missions WHERE id=?`, [missionId], async (e, row: any) => {
        if (!row || row.address !== userAddress || row.progress < row.target || row.claimed === 1) return res.status(400).json({ error: "Invalid Claim" });
        const [,, reward] = row.mission_key.split(':');
        const tx = await gameContract.adminRewardHash(userAddress, ethers.parseEther(reward), { gasLimit: 500000 });
        await tx.wait();
        db.run(`UPDATE missions SET claimed=1 WHERE id=?`, [missionId]);
        res.json({ success: true, message: `Received ${reward} $HASH` });
    });
});

// 6. GENERAL ACTIONS
app.post('/salvage', async (req, res) => {
    try {
        const { userAddress, signature, tokenId, amount } = req.body;
        if (ethers.verifyMessage("SALVAGE_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth" });
        const tx = await gameContract.salvageArtifact(userAddress, tokenId, amount, { gasLimit: 200000 });
        await tx.wait();
        trackMission(userAddress, "SALVAGE_COUNT", amount);
        res.json({ success: true, message: "Salvage Complete" });
    } catch (e:any) { res.status(500).json({error: e.message}); }
});

app.post('/shop/software', async (req, res) => {
    try {
        const { userAddress, signature, itemId } = req.body;
        if (ethers.verifyMessage("BUY_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth" });
        const tx = await gameContract.buySoftware(userAddress, itemId, { gasLimit: 200000 });
        await tx.wait();
        trackMission(userAddress, "SPEND_HASH", 100);
        res.json({ success: true });
    } catch (e:any) { res.status(500).json({error: e.message}); }
});

app.post('/equip', async (req, res) => {
    const { userAddress, signature, itemId } = req.body;
    if (ethers.verifyMessage("EQUIP_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth" });
    const tx = await gameContract.equipItem(userAddress, itemId, { gasLimit: 200000 });
    await tx.wait();
    res.json({ success: true });
});

app.post('/use', async (req, res) => {
    const { userAddress, signature, itemId } = req.body;
    if (ethers.verifyMessage("USE_ACTION", signature).toLowerCase() !== userAddress.toLowerCase()) return res.status(401).json({ error: "Auth" });
    const tx = await gameContract.useConsumable(userAddress, itemId, { gasLimit: 200000 });
    await tx.wait();
    if(itemId == "501") trackMission(userAddress, "USE_THERMAL", 1);
    res.json({ success: true, message: "Item Used" });
});

app.get('/leaderboard', (req, res) => {
    db.all(`SELECT address, hash_balance FROM users ORDER BY hash_balance DESC LIMIT 10`, (err, rows) => res.json({ top10: rows }));
});

app.get('/inventory/:address', async (req, res) => {
    const ids = [1,2,3,4,5,6,7,8, 99, 101,102,103,104, 201,202,203,204,205, 301,302,303, 401,402,499, 501,502];
    const accounts = Array(ids.length).fill(req.params.address);
    try {
        const bals = await gameContract.balanceOfBatch(accounts, ids);
        const items = ids.map((id, i) => {
            const qty = Number(bals[i]);
            if (qty > 0) return { id, ...getMeta(id.toString()), qty };
            return null;
        }).filter(x => x);
        res.json({ items });
    } catch (e: any) { res.status(500).json({ error: e.message }); }
});

app.listen(PORT, () => console.log(`🚀 CyberRNG v7.1 (Stable) running on ${PORT}`));