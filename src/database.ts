import sqlite3 from 'sqlite3';
import { Database } from 'sqlite3';

const db: Database = new sqlite3.Database('./game.db', (err) => {
    if (err) console.error("DB Connection Error:", err.message);
    else console.log("💾 SQLite Database Connected.");
});

db.serialize(() => {
    // Table User (Leaderboard)
    db.run(`CREATE TABLE IF NOT EXISTS users (
        address TEXT PRIMARY KEY,
        hash_balance REAL DEFAULT 0,
        last_seen TEXT
    )`);

    // Table Missions
    db.run(`CREATE TABLE IF NOT EXISTS missions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT,
        mission_key TEXT,
        target INTEGER,
        progress INTEGER DEFAULT 0,
        claimed BOOLEAN DEFAULT 0,
        date TEXT,
        UNIQUE(address, mission_key, date)
    )`);
});

export default db;