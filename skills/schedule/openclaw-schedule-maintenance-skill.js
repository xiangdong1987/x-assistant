#!/usr/bin/env node

/**
 * OpenClaw Schedule Maintenance Skill
 * Usage: node openclaw-schedule-maintenance-skill.js detect-duplicates
 */

const scheduleStore = require('./schedule-store.js');

function detectDuplicates() {
    const data = scheduleStore.loadData();
    const items = data.items;
    const duplicates = [];
    const processed = new Set();

    for (let i = 0; i < items.length; i++) {
        if (processed.has(items[i].id)) continue;

        const group = [items[i]];
        for (let j = i + 1; j < items.length; j++) {
            if (processed.has(items[j].id)) continue;

            // Match criteria: Same title and same startTime, but different externalId
            if (items[i].title === items[j].title &&
                items[i].startTime === items[j].startTime &&
                items[i].externalId !== items[j].externalId) {
                group.push(items[j]);
                processed.add(items[j].id);
            }
        }

        if (group.length > 1) {
            duplicates.push({
                groupId: `dup_${items[i].id}`,
                items: group.map(item => ({ scheduleItemId: item.id, externalId: item.externalId, sourceKey: item.sourceKey })),
                reason: 'same_time_and_title'
            });
        }
        processed.add(items[i].id);
    }

    console.log(`HANDOFF:${JSON.stringify({
        ok: true,
        skill: 'openclaw-schedule-maintenance',
        version: '1.0',
        action: 'detect-duplicates',
        data: { duplicates },
        error: null
    })}`);
}

// Simple CLI routing
const args = process.argv.slice(2);
const command = args[0];

if (command === 'detect-duplicates') {
    detectDuplicates();
} else {
    console.log('Usage: node openclaw-schedule-maintenance-skill.js detect-duplicates');
}
