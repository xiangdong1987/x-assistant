#!/usr/bin/env node

/**
 * OpenClaw Sync Schedule Skill
 * Usage: node openclaw-sync-schedule-skill.js sync --payload-file=data/events/events.json
 *        (事件 payload 必须放在 data/events/ 下，新建/生成的文件勿放在技能根目录，详见 SKILL.md「生成/新建说明」)
 */

const fs = require('fs');
const path = require('path');
const scheduleStore = require('./schedule-store.js');
const linkStore = require('./link-store.js');
const taskStore = require('../software-dev/tasks-store-adapter.js');

async function sync(payloadFile) {
    if (!payloadFile || !fs.existsSync(payloadFile)) {
        console.log(`HANDOFF:${JSON.stringify({ ok: false, error: { code: 'INVALID_PARAMETER', message: 'Payload file not found' } })}`);
        return;
    }

    try {
        const raw = fs.readFileSync(payloadFile, 'utf-8');
        const { sourceKey, requestId, events } = JSON.parse(raw);

        const stats = {
            syncedCount: 0,
            created: [],
            updated: [],
            skipped: []
        };

        for (const event of events) {
            const result = scheduleStore.upsertScheduleItem(sourceKey || 'openclaw', event);
            const item = result.item;

            if (result.skipped) {
                stats.skipped.push({ externalId: item.externalId, reason: 'no_change' });
                continue;
            }

            stats.syncedCount++;
            if (result.created) {
                stats.created.push({ scheduleItemId: item.id, externalId: item.externalId });

                // Auto-create task rule
                // Rule: Meeting or Deadline in 'dev' domain should create a task
                if (item.domain === 'dev' && (item.type === 'meeting' || item.type === 'deadline' || (item.tags && item.tags.includes('#focus')))) {
                    const task = await taskStore.createTask({
                        title: `[Schedule] ${item.title}`,
                        description: item.description || item.title,
                        projectKey: item.projectKey || 'default',
                        priority: item.type === 'deadline' ? 'high' : 'medium'
                    });

                    linkStore.addLink(item.id, task.taskId || task.id, item.type === 'meeting' ? 'meeting' : 'prep');

                    // Update stats to include taskIds
                    const lastCreated = stats.created[stats.created.length - 1];
                    lastCreated.taskIds = [task.taskId || task.id];
                }
            } else if (result.updated) {
                stats.updated.push({ scheduleItemId: item.id, externalId: item.externalId, changes: ['content'] });

                // Update linked tasks if needed (e.g. status/planned time)
                const links = linkStore.getLinksByScheduleItem(item.id);
                for (const link of links) {
                    await taskStore.updateTask(link.taskId, {
                        title: `[Schedule] ${item.title}`,
                        description: item.description || item.title
                    });
                }
            }
        }

        console.log(`HANDOFF:${JSON.stringify({
            ok: true,
            skill: 'openclaw-sync-schedule',
            version: '1.0',
            sourceKey,
            requestId,
            data: stats,
            error: null
        })}`);

    } catch (e) {
        console.log(`HANDOFF:${JSON.stringify({ ok: false, error: { code: 'INTERNAL_ERROR', message: e.message } })}`);
    }
}

// ─── update command ───────────────────────────────────────────────────────────
function update(args) {
    const idArg = args.find(a => a.startsWith('--id='));
    const id = idArg ? idArg.split('=')[1] : null;
    if (!id) {
        console.log(`HANDOFF:${JSON.stringify({ ok: false, error: 'missing --id' })}`);
        return;
    }

    const fieldArgs = args.filter(a => a !== args[0] && !a.startsWith('--id='));
    const updates = {};
    for (const arg of fieldArgs) {
        const eq = arg.indexOf('=');
        if (eq > 0) {
            const key = arg.slice(2, eq);       // strip leading --
            const val = arg.slice(eq + 1);
            updates[key] = val;
        }
    }

    const item = scheduleStore.updateScheduleItem(id, updates);
    if (!item) {
        console.log(`HANDOFF:${JSON.stringify({ ok: false, error: `item ${id} not found` })}`);
        return;
    }
    console.log(`HANDOFF:${JSON.stringify({ ok: true, skill: 'openclaw-sync-schedule', action: 'update', item, error: null })}`);
}

// ─── delete command ───────────────────────────────────────────────────────────
function deleteItem(args) {
    const idArg = args.find(a => a.startsWith('--id='));
    const id = idArg ? idArg.split('=')[1] : null;
    if (!id) {
        console.log(`HANDOFF:${JSON.stringify({ ok: false, error: 'missing --id' })}`);
        return;
    }

    const ok = scheduleStore.deleteScheduleItem(id);
    console.log(`HANDOFF:${JSON.stringify({ ok, skill: 'openclaw-sync-schedule', action: 'delete', id, error: ok ? null : `item ${id} not found` })}`);
}

// ─── CLI routing ─────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const command = args[0];

if (command === 'sync') {
    const payloadArg = args.find(a => a.startsWith('--payload-file='));
    const payloadFile = payloadArg ? payloadArg.split('=')[1] : null;
    sync(payloadFile);
} else if (command === 'update') {
    update(args);
} else if (command === 'delete') {
    deleteItem(args);
} else {
    console.log('Usage: node openclaw-sync-schedule-skill.js <sync|update|delete> [options]');
}
