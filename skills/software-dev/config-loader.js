const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const CONFIG_PATH = path.join(__dirname, 'config.json');

function loadConfig() {
    if (!fs.existsSync(CONFIG_PATH)) {
        console.error('[config-loader] config.json not found, using defaults');
        return { settings: {} };
    }
    try {
        const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
        // Resolve env vars for sensitive fields
        if (config.settings?.openclawGateway?.token === '' && process.env.OPENCLAW_TOKEN) {
            config.settings.openclawGateway.token = process.env.OPENCLAW_TOKEN;
        }
        if (config.database?.password === '' && process.env.DB_PASSWORD) {
            config.database.password = process.env.DB_PASSWORD;
        }
        return config;
    } catch (err) {
        console.error(`[config-loader] Failed to load config: ${err.message}`);
        return { settings: {} };
    }
}

module.exports = { loadConfig, CONFIG_PATH };
