#!/usr/bin/env node

/**
 * Schedule Store (JSON persistence)
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_DIR = path.join(__dirname, 'data');
const SCHEDULES_FILE = path.join(DATA_DIR, 'schedules.json');

function ensureDataDir() {
    if (!fs.existsSync(DATA_DIR)) {
        fs.mkdirSync(DATA_DIR, { recursive: true });
    }
}

function loadData() {
    ensureDataDir();
    if (!fs.existsSync(SCHEDULES_FILE)) {
        return {
            nextSeq: 1,
            sources: [
                { key: 'openclaw', displayName: 'OpenClaw' },
                { key: 'manual', displayName: 'Manual' }
            ],
            items: []
        };
    }
    try {
        const raw = fs.readFileSync(SCHEDULES_FILE, 'utf-8');
        return JSON.parse(raw);
    } catch (e) {
        return { nextSeq: 1, sources: [], items: [] };
    }
}

function saveData(data) {
    ensureDataDir();
    fs.writeFileSync(SCHEDULES_FILE, JSON.stringify(data, null, 2), 'utf-8');
}

/**
 * Calculate hash for idempotency check
 */
function calculateHash(item) {
    const content = JSON.stringify({
        title: item.title,
        description: item.description,
        startTime: item.startTime,
        endTime: item.endTime,
        projectKey: item.projectKey,
        domain: item.domain,
        type: item.type,
        status: item.status,
        allDay: item.allDay,
        tags: item.tags
    });
    return crypto.createHash('md5').update(content).digest('hex');
}

/**
 * Validates and sanitizes a schedule item before saving
 */
function sanitizeItem(item) {
    const validTypes = ['meeting', 'deadline', 'social', 'review', 'other'];
    const validStatuses = ['scheduled', 'in_progress', 'completed', 'cancelled'];
    const sanitized = { ...item };

    // Default fallback for type
    if (sanitized.type && !validTypes.includes(sanitized.type)) {
        sanitized.type = 'other';
    }

    // Default/validate status
    if (!sanitized.status || !validStatuses.includes(sanitized.status)) {
        sanitized.status = 'scheduled';
    }

    // Validate dates
    if (sanitized.startTime && isNaN(Date.parse(sanitized.startTime))) {
        throw new Error('Invalid startTime format');
    }
    if (sanitized.endTime && isNaN(Date.parse(sanitized.endTime))) {
        throw new Error('Invalid endTime format');
    }

    // Default domain
    if (!sanitized.domain) {
        sanitized.domain = 'dev';
    }

    return sanitized;
}

/**
 * Upsert a schedule item
 */
function upsertScheduleItem(sourceKey, itemData) {
    if (!sourceKey || !itemData.externalId) {
        throw new Error('sourceKey and externalId are required for upsert');
    }

    itemData = sanitizeItem(itemData);

    const data = loadData();
    const index = data.items.findIndex(
        i => i.sourceKey === sourceKey && i.externalId === String(itemData.externalId)
    );

    const hash = calculateHash(itemData);
    const now = new Date().toISOString();

    if (index !== -1) {
        const existing = data.items[index];
        // Check if update is needed
        if (existing.externalVersion === itemData.externalVersion && existing.hash === hash) {
            return { item: existing, updated: false, skipped: true };
        }

        const updated = {
            ...existing,
            ...itemData,
            hash,
            updatedAt: now,
            lastSyncedAt: now
        };
        data.items[index] = updated;
        saveData(data);
        return { item: updated, updated: true, skipped: false };
    } else {
        const newItem = {
            id: data.nextSeq++,
            sourceKey,
            ...itemData,
            hash,
            createdAt: now,
            updatedAt: now,
            lastSyncedAt: now
        };
        data.items.push(newItem);
        saveData(data);
        return { item: newItem, updated: false, created: true };
    }
}

function getItems(filters = {}) {
    const data = loadData();
    let results = data.items;

    if (filters.sourceKey) {
        results = results.filter(i => i.sourceKey === filters.sourceKey);
    }
    if (filters.projectKey) {
        results = results.filter(i => i.projectKey === filters.projectKey);
    }
    if (filters.domain) {
        results = results.filter(i => i.domain === filters.domain);
    }
    if (filters.from) {
        // If date-only (no T/Z), treat as start of day UTC
        const fromStr = filters.from.includes('T') ? filters.from : filters.from + 'T00:00:00Z';
        results = results.filter(i => i.startTime >= fromStr);
    }
    if (filters.to) {
        // If date-only, treat as end of day UTC so the whole day is included
        const toStr = filters.to.includes('T') ? filters.to : filters.to + 'T23:59:59Z';
        results = results.filter(i => i.startTime <= toStr);
    }

    return results;
}

function getItem(id) {
    const data = loadData();
    return data.items.find(i => String(i.id) === String(id)) || null;
}

function updateScheduleItem(id, updates) {
    const data = loadData();
    const index = data.items.findIndex(i => String(i.id) === String(id));
    if (index === -1) return null;
    const now = new Date().toISOString();
    let updated = {
        ...data.items[index],
        ...updates,
        updatedAt: now,
    };
    updated = sanitizeItem(updated);
    data.items[index] = updated;
    saveData(data);
    return data.items[index];
}

function deleteScheduleItem(id) {
    const data = loadData();
    const index = data.items.findIndex(i => String(i.id) === String(id));
    if (index === -1) return false;
    data.items.splice(index, 1);
    saveData(data);
    return true;
}

module.exports = {
    upsertScheduleItem,
    updateScheduleItem,
    deleteScheduleItem,
    getItems,
    getItem,
    loadData
};
