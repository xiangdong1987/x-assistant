#!/usr/bin/env node

/**
 * OpenClaw Agenda Skill
 * Usage: node openclaw-agenda-skill.js agenda --from=2026-03-03 --to=2026-03-03
 */

const scheduleStore = require('./schedule-store.js');
const linkStore = require('./link-store.js');
const taskStore = require('../software-dev/tasks-store-adapter.js');

async function agenda(filters) {
    try {
        const items = scheduleStore.getItems(filters);
        const allTasks = await taskStore.loadTasks().then(d => d.tasks);

        const agendaItems = [];

        // Process Schedule Items
        for (const item of items) {
            const links = linkStore.getLinksByScheduleItem(item.id);
            const linkedTasks = links.map(l => {
                const t = allTasks.find(at => String(at.id) === String(l.taskId) || at.taskId === l.taskId);
                return t ? { taskId: t.taskId || t.id, status: t.status, title: t.title } : null;
            }).filter(Boolean);

            agendaItems.push({
                time: item.startTime,
                endTime: item.endTime,
                title: item.title,
                description: item.description,
                projectKey: item.projectKey,
                domain: item.domain,
                type: 'event', // UI indicator
                eventType: item.type,
                scheduleItemId: item.id,
                status: item.status,
                linkedTasks
            });
        }

        // Add unlinked tasks that match filters (simplified: add all pending/planned for now if project matches)
        // In a real scenario, we'd filter tasks by date if they have plannedAt/dueAt
        const unlinkedTasks = allTasks.filter(t => {
            const isLinked = agendaItems.some(ai => ai.linkedTasks && ai.linkedTasks.some(lt => lt.taskId === (t.taskId || t.id)));
            if (isLinked) return false;

            if (filters.projectKey && t.projectKey !== filters.projectKey) return false;
            if (t.status === 'done' || t.status === 'failed') return false;

            return true;
        });

        for (const t of unlinkedTasks) {
            agendaItems.push({
                time: t.plannedAt || null, // Tasks might not have exact time
                title: t.title,
                projectKey: t.projectKey,
                type: 'task',
                taskId: t.taskId || t.id,
                status: t.status
            });
        }

        // Sort by time
        agendaItems.sort((a, b) => {
            if (!a.time) return 1;
            if (!b.time) return -1;
            return a.time.localeCompare(b.time);
        });

        console.log(`HANDOFF:${JSON.stringify({
            ok: true,
            skill: 'openclaw-agenda',
            version: '1.0',
            from: filters.from,
            to: filters.to,
            data: { agenda: agendaItems },
            error: null
        })}`);

    } catch (e) {
        console.log(`HANDOFF:${JSON.stringify({ ok: false, error: { code: 'INTERNAL_ERROR', message: e.message } })}`);
    }
}

// Simple CLI routing
const args = process.argv.slice(2);
const command = args[0];

if (command === 'agenda') {
    const fromArg = args.find(a => a.startsWith('--from='));
    const toArg = args.find(a => a.startsWith('--to='));
    const projectArg = args.find(a => a.startsWith('--project='));
    const domainArg = args.find(a => a.startsWith('--domain='));

    agenda({
        from: fromArg ? fromArg.split('=')[1] : null,
        to: toArg ? toArg.split('=')[1] : null,
        projectKey: projectArg ? projectArg.split('=')[1] : null,
        domain: domainArg ? domainArg.split('=')[1] : null
    });
} else {
    console.log('Usage: node openclaw-agenda-skill.js agenda --from=ISO-DATE --to=ISO-DATE');
}
