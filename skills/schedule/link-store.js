#!/usr/bin/env node

/**
 * Link Store (Schedule-Task mapping persistence)
 */

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, 'data');
const LINKS_FILE = path.join(DATA_DIR, 'links.json');

function ensureDataDir() {
    if (!fs.existsSync(DATA_DIR)) {
        fs.mkdirSync(DATA_DIR, { recursive: true });
    }
}

function loadLinks() {
    ensureDataDir();
    if (!fs.existsSync(LINKS_FILE)) {
        return [];
    }
    try {
        const raw = fs.readFileSync(LINKS_FILE, 'utf-8');
        return JSON.parse(raw);
    } catch (e) {
        return [];
    }
}

function saveLinks(links) {
    ensureDataDir();
    fs.writeFileSync(LINKS_FILE, JSON.stringify(links, null, 2), 'utf-8');
}

function addLink(scheduleItemId, taskId, linkType = 'main_work') {
    const links = loadLinks();
    const exists = links.find(
        l => String(l.scheduleItemId) === String(scheduleItemId) && l.taskId === taskId
    );

    if (exists) return exists;

    const newLink = {
        id: Date.now().toString(36) + Math.random().toString(36).substr(2, 5),
        scheduleItemId: String(scheduleItemId),
        taskId,
        linkType,
        createdAt: new Date().toISOString()
    };

    links.push(newLink);
    saveLinks(links);
    return newLink;
}

function getLinksByScheduleItem(scheduleItemId) {
    const links = loadLinks();
    return links.filter(l => String(l.scheduleItemId) === String(scheduleItemId));
}

function getLinksByTask(taskId) {
    const links = loadLinks();
    return links.filter(l => l.taskId === taskId);
}

module.exports = {
    addLink,
    getLinksByScheduleItem,
    getLinksByTask,
    loadLinks
};
