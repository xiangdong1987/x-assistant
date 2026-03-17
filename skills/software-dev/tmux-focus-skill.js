#!/usr/bin/env node

/**
 * Tmux Focus Skill
 *
 * Purpose: Open iTerm2 and switch to a specific tmux session/pane
 * Input: taskId OR session name + optional paneId
 * Output: Opens iTerm2 and attaches to the tmux session
 *
 * Requires: tmux, osascript (macOS)
 */

const { execSync } = require('child_process');
const path = require('path');

let tasksStore;
try {
    tasksStore = require('./tasks-store-adapter');
} catch (e) {
    tasksStore = null;
}

function execCommand(command, options = {}) {
    try {
        return execSync(command, {
            encoding: 'utf-8',
            stdio: 'pipe',
            ...options
        }).trim();
    } catch (error) {
        if (options.ignoreError) return null;
        throw new Error(`Command failed: ${command}\n${error.stderr || error.message}`);
    }
}

/**
 * List all active tmux sessions
 */
function listSessions() {
    const output = execCommand('tmux list-sessions -F "#{session_name} #{session_windows} #{session_attached}" 2>/dev/null || true');
    if (!output) return [];

    return output.split('\n').filter(Boolean).map(line => {
        const [name, windows, attached] = line.split(' ');
        return { name, windows: parseInt(windows), attached: attached === '1' };
    });
}

/**
 * Get pane details for a session/window
 */
function listPanes(session, window) {
    const target = window ? `${session}:${window}` : session;
    const output = execCommand(
        `tmux list-panes -t "${target}" -F "#{pane_index} #{pane_pid} #{pane_current_command} #{pane_title}" 2>/dev/null || true`
    );
    if (!output) return [];

    return output.split('\n').filter(Boolean).map(line => {
        const parts = line.split(' ');
        return {
            index: parts[0],
            pid: parts[1],
            command: parts[2],
            title: parts.slice(3).join(' ')
        };
    });
}

/**
 * Switch tmux to the target pane (in the background, non-interactive)
 */
function selectTmuxPane(paneId) {
    execCommand(`tmux select-pane -t "${paneId}"`, { ignoreError: true });
    const parts = paneId.split(':');
    if (parts.length >= 2) {
        const winPart = parts[1].split('.')[0];
        execCommand(`tmux select-window -t "${parts[0]}:${winPart}"`, { ignoreError: true });
    }
}

/**
 * Build the AppleScript that opens iTerm2 and attaches to the tmux session.
 * We open a normal shell tab (no startup command), then write the tmux attach
 * command into the running shell. This keeps the tab alive even after tmux detaches.
 */
function buildITermAppleScript(sessionName, paneId) {
    const selectCmd = paneId
        ? `tmux select-pane -t '${paneId}' 2>/dev/null; tmux select-window -t '${paneId}' 2>/dev/null; `
        : '';

    const attachCmd = `${selectCmd}tmux attach-session -t '${sessionName}'`;

    return `
tell application "iTerm2"
  activate
  if (count of windows) = 0 then
    create window with default profile
  end if
  tell current window
    create tab with default profile
    tell current session of current tab
      write text "${attachCmd.replace(/"/g, '\\"')}"
    end tell
  end tell
end tell
`.trim();
}


/**
 * Focus: open iTerm on the specified tmux session/pane
 */
async function focusTmux({ taskId, session, paneId, window: windowName }) {
    console.log('🖥️  Tmux Focus Skill');
    console.log('='.repeat(40));

    let targetSession = session;
    let targetPane = paneId;
    let targetWindow = windowName;

    // If taskId given, look up tmux metadata from task
    if (taskId && tasksStore) {
        console.log(`🔍 Looking up task: ${taskId}`);
        const task = await tasksStore.getTask(taskId);
        if (!task) {
            throw new Error(`Task not found: ${taskId}`);
        }

        console.log(`   Title: ${task.title}`);
        console.log(`   Status: ${task.status}`);

        const meta = task.tmuxSession || task.metadata?.tmuxSession;
        const metaPane = task.tmuxPaneId || task.metadata?.tmuxPaneId;
        const metaWindow = task.tmuxWindow || task.metadata?.tmuxWindow;

        if (meta) {
            targetSession = meta;
            targetPane = metaPane || targetPane;
            targetWindow = metaWindow || targetWindow;
            console.log(`   Tmux session: ${targetSession}`);
            if (targetPane) console.log(`   Pane: ${targetPane}`);
        } else {
            console.log('   ⚠️  No tmux metadata found on task. Will use projectKey as session name.');
            targetSession = task.projectKey || taskId;
        }
    }

    if (!targetSession) {
        throw new Error('Must provide either --taskId or --session');
    }

    // Check session exists
    const sessions = listSessions();
    const sessionNames = sessions.map(s => s.name);
    console.log(`\n📋 Active tmux sessions: ${sessionNames.join(', ') || '(none)'}`);

    if (!sessionNames.includes(targetSession)) {
        throw new Error(`Tmux session "${targetSession}" is not running. Start an agent first.`);
    }

    // Pre-select the pane in tmux so iTerm opens on the right pane
    if (targetPane) {
        console.log(`\n🎯 Selecting pane: ${targetPane}`);
        selectTmuxPane(targetPane);
    } else if (targetWindow) {
        console.log(`\n🎯 Selecting window: ${targetSession}:${targetWindow}`);
        execCommand(`tmux select-window -t "${targetSession}:${targetWindow}"`, { ignoreError: true });
    }

    // Build and run AppleScript to open iTerm
    console.log(`\n🚀 Opening iTerm2 → tmux session: ${targetSession}${targetPane ? ` pane: ${targetPane}` : ''}`);

    const appleScript = buildITermAppleScript(targetSession, targetPane);

    try {
        execCommand(`osascript -e '${appleScript.replace(/'/g, "'\\''")}'`);
        console.log('✅ iTerm2 opened and focused on tmux session');
    } catch (err) {
        console.error('⚠️  Could not open iTerm2 via AppleScript:', err.message);
        console.log('   Try manually: tmux attach-session -t', targetSession);
    }

    const handoff = {
        ok: true,
        skill: 'tmux.focus',
        version: '1.0',
        data: {
            focused: true,
            session: targetSession,
            window: targetWindow || null,
            paneId: targetPane || null
        },
        error: null
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);
    return handoff;
}

/**
 * List: show all tmux sessions and their panes
 */
function listAll() {
    console.log('📋 Tmux Sessions');
    console.log('='.repeat(40));

    const sessions = listSessions();
    if (sessions.length === 0) {
        console.log('No active tmux sessions.');
        const handoff = { ok: true, skill: 'tmux.focus', version: '1.0', data: { sessions: [] }, error: null };
        console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);
        return handoff;
    }

    const result = [];
    for (const s of sessions) {
        console.log(`\n🗂  Session: ${s.name} (${s.windows} windows${s.attached ? ', attached' : ''})`);
        const panes = listPanes(s.name, null);
        panes.forEach(p => {
            console.log(`     Pane ${p.index}: PID=${p.pid} CMD=${p.command}`);
        });
        result.push({ ...s, panes });
    }

    const handoff = { ok: true, skill: 'tmux.focus', version: '1.0', data: { sessions: result }, error: null };
    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);
    return handoff;
}

// ---------- CLI Interface ----------

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const command = args[0];

        const getArg = (prefix) => {
            const a = args.find(a => a.startsWith(`--${prefix}=`));
            return a ? a.split('=').slice(1).join('=') : null;
        };

        if (command === 'focus') {
            const taskId = getArg('taskId');
            const session = getArg('session');
            const paneId = getArg('paneId');
            const window = getArg('window');

            if (!taskId && !session) {
                console.log('Usage: node tmux-focus-skill.js focus --taskId=<id>');
                console.log('       node tmux-focus-skill.js focus --session=<name> [--paneId=<paneId>] [--window=<window>]');
                process.exit(1);
            }

            try {
                await focusTmux({ taskId, session, paneId, window });
                process.exit(0);
            } catch (err) {
                console.error(`\n❌ Error: ${err.message}`);
                const handoff = { ok: false, skill: 'tmux.focus', version: '1.0', data: {}, error: err.message };
                console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);
                process.exit(1);
            }

        } else if (command === 'list') {
            listAll();
            process.exit(0);

        } else {
            console.log('📋 Tmux Focus Skill');
            console.log('='.repeat(40));
            console.log('');
            console.log('Commands:');
            console.log('  focus --taskId=<id>                  Focus iTerm on task\'s tmux pane');
            console.log('  focus --session=<name>               Focus iTerm on tmux session');
            console.log('  focus --session=<name> --paneId=<id> Focus iTerm on specific pane');
            console.log('  list                                 List all tmux sessions and panes');
            process.exit(0);
        }
    })();
}

module.exports = { focusTmux, listSessions, listPanes };
