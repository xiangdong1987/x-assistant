#!/usr/bin/env node

/**
 * Agent Stop Skill
 *
 * Purpose: Stop agents running in tmux sessions
 * Input: (taskId)
 * State: Terminates pane, updates task status
 * Command: stop <taskId>
 *
 * Handles: TMUX pane killing, graceful shutdown, status update
 */

const { execSync } = require('child_process');
const tasksStore = require('./tasks-store-adapter');

/**
 * Execute command and return output
 */
function execCommand(command, options = {}) {
  try {
    return execSync(command, {
      encoding: 'utf-8',
      stdio: 'pipe',
      ...options
    }).trim();
  } catch (error) {
    if (options.ignoreError) return null;
    throw new Error(`Command failed: ${command}\n${error.message}`);
  }
}

/**
 * Kill tmux window (each task has its own window, so kill the whole window).
 * Falls back to kill-pane if window kill fails.
 */
function killPane(paneId, force = false) {
  try {
    if (!force) {
      execCommand(`tmux send-keys -t "${paneId}" C-c 2>/dev/null`, { ignoreError: true });
    }
    // Pane id can be %N (from agent-start) or session:window (legacy)
    if (paneId.startsWith('%')) {
      execCommand(`tmux kill-pane -t "${paneId}" 2>/dev/null`, { ignoreError: true });
    } else {
      const windowTarget = paneId.includes('.') ? paneId.split('.')[0] : paneId;
      execCommand(`tmux kill-window -t "${windowTarget}" 2>/dev/null`, { ignoreError: true });
    }
    return true;
  } catch (error) {
    try {
      execCommand(`tmux kill-pane -t "${paneId}" 2>/dev/null`, { ignoreError: true });
      return true;
    } catch (e) { /* ignore */ }
    console.error(`Failed to kill pane/window: ${error.message}`);
    return false;
  }
}

/**
 * Check if pane exists. Supports pane id (%N) or session:window[.pane].
 */
function paneExists(paneId) {
  try {
    if (paneId.startsWith('%')) {
      const result = execCommand(`tmux list-panes -a -F "#{pane_id}" 2>/dev/null || true`);
      return result && result.split('\n').some((id) => id.trim() === paneId);
    }
    const session = paneId.split(':')[0];
    const result = execCommand(`tmux list-panes -t "${session}" -F "#{pane_id}" 2>/dev/null || true`);
    if (!result) return false;
    const part = paneId.includes('.') ? paneId.split('.')[1] : paneId;
    return result.includes(part);
  } catch (error) {
    return false;
  }
}

/**
 * Clean up empty tmux session (no remaining windows).
 * Called after killing a window to garbage-collect the session.
 */
function cleanupEmptySession(sessionName) {
  if (!sessionName) return;
  try {
    const windowCount = execCommand(
      `tmux list-windows -t "${sessionName}" 2>/dev/null | wc -l`,
      { ignoreError: true }
    );
    if (windowCount && parseInt(windowCount.trim(), 10) === 0) {
      console.log(`   🧹 Session "${sessionName}" is empty, killing session`);
      execCommand(`tmux kill-session -t "${sessionName}" 2>/dev/null`, { ignoreError: true });
    }
  } catch (error) {
    // Session may already be gone
  }
}

/**
 * Stop agent gracefully (send interrupt, wait, then kill if needed)
 */
async function stopGracefully(taskId, options = {}) {
  const { timeout = 5000, force = false } = options;

  // Get tmux metadata
  const tmuxMeta = await tasksStore.getTmuxMetadata(taskId);
  if (!tmuxMeta || !tmuxMeta.tmuxPaneId) {
    throw new Error(`No tmux pane found for task: ${taskId}`);
  }

  const paneId = tmuxMeta.tmuxPaneId;
  console.log(`🛑 Stopping agent gracefully...`);
  console.log(`   Pane: ${paneId}`);

  // Send interrupt signal (Ctrl+C)
  console.log(`   Sending interrupt signal...`);
  execCommand(`tmux send-keys -t "${paneId}" C-c 2>/dev/null`, { ignoreError: true });

  // Wait for graceful shutdown
  const startTime = Date.now();
  let killed = false;

  while (Date.now() - startTime < timeout) {
    const exists = paneExists(paneId);
    if (!exists) {
      killed = true;
      console.log(`   ✅ Agent stopped gracefully`);
      break;
    }
    await new Promise(resolve => setTimeout(resolve, 500));
  }

  // Force kill if still alive
  if (!killed && force) {
    console.log(`   ⚡ Force killing pane...`);
    killed = killPane(paneId, true);
  } else if (!killed) {
    console.log(`   ⚠️ Agent still running, use --force to force kill`);
  }

  return killed;
}

/**
 * Main function to stop agent
 */
async function stopAgent(taskId, options = {}) {
  const { force = false, updateStatus = true } = options;

  console.log('🛑 Agent Stop Skill');
  console.log('='.repeat(40));
  console.log(`   Task ID: ${taskId}`);
  console.log(`   Force: ${force}`);

  try {
    // Get task with tmux metadata
    const tmuxMeta = await tasksStore.getTmuxMetadata(taskId);
    if (!tmuxMeta) {
      throw new Error(`Task not found: ${taskId}`);
    }

    const task = await tasksStore.getTask(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    console.log(`   Title: ${task.title}`);
    console.log(`   Current status: ${task.status}`);

    // Check if tmux pane exists
    if (!tmuxMeta.tmuxPaneId) {
      console.log(`\n⚠️ No tmux pane found for this task`);
      return {
        ok: true,
        skill: 'agent.stop',
        version: '1.0',
        data: {
          taskId,
          title: task.title,
          paneId: null,
          killed: false,
          message: 'No tmux pane associated with this task'
        },
        error: null
      };
    }

    const paneId = tmuxMeta.tmuxPaneId;
    const paneExistsNow = paneExists(paneId);

    if (!paneExistsNow) {
      console.log(`\n⚠️ Pane already does not exist: ${paneId}`);

      // Update task status if requested
      if (updateStatus && task.status === 'developing') {
        const transitionResult = await tasksStore.transitionTask(taskId, 'failed', { error: 'Agent stopped externally' });
        if (transitionResult.success) {
          console.log(`   Task status updated to: failed`);
        }
      }

      const handoff = {
        ok: true,
        skill: 'agent.stop',
        version: '1.0',
        data: {
          taskId,
          title: task.title,
          paneId,
          killed: false,
          newStatus: transitionResult?.success ? transitionResult.task.status : task.status,
          message: 'Pane already stopped'
        },
        error: null
      };

      console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);
      return { success: true, ...handoff };
    }

    // Kill the pane
    console.log(`\n🔥 Killing pane: ${paneId}`);
    const killed = killPane(paneId, force);

    if (killed) {
      console.log(`✅ Agent stopped successfully`);
    } else {
      console.log(`⚠️ Failed to kill pane (may already be dead)`);
    }

    // Update task status if requested
    let newStatus = task.status;
    if (updateStatus) {
      const errorMsg = force ? 'Agent force stopped' : 'Agent stopped by user';
      const transitionResult = await tasksStore.transitionTask(taskId, 'failed', { error: errorMsg });
      if (transitionResult.success) {
        newStatus = transitionResult.task.status;
        console.log(`   Task status updated to: ${newStatus}`);
      }
    }

    // Clear tmux metadata
    await tasksStore.updateTmuxMetadata(taskId, {
      backend: null,
      tmuxSession: null,
      tmuxWindow: null,
      tmuxPaneId: null,
      lastExecLogPath: null
    });
    console.log(`   TMUX metadata cleared`);

    // Clean up empty session if no windows remain
    if (tmuxMeta.tmuxSession) {
      cleanupEmptySession(tmuxMeta.tmuxSession);
    }

    // Output HANDOFF
    const handoff = {
      ok: true,
      skill: 'agent.stop',
      version: '1.0',
      data: {
        taskId,
        title: task.title,
        paneId,
        killed: true,
        newStatus,
        message: killed ? 'Agent stopped successfully' : 'Pane already stopped'
      },
      error: null
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);

    return {
      success: true,
      ...handoff
    };

  } catch (error) {
    console.error(`\n❌ Agent stop failed: ${error.message}`);

    const handoff = {
      ok: false,
      skill: 'agent.stop',
      version: '1.0',
      data: { taskId },
      error: error.message
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);

    return {
      success: false,
      ...handoff
    };
  }
}

// ---------- CLI Interface ----------

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const command = args[0];

    if (command === 'stop') {
      const taskId = args[1];
      const force = args.includes('--force');
      const noStatusUpdate = args.includes('--no-status-update');

      if (!taskId) {
        console.log('Usage: node agent-stop-skill.js stop <taskId> [--force] [--no-status-update]');
        console.log('');
        console.log('Arguments:');
        console.log('  taskId           Task ID to stop');
        console.log('');
        console.log('Options:');
        console.log('  --force          Force kill the pane immediately');
        console.log('  --no-status-update  Do not update task status');
        console.log('');
        console.log('Example:');
        console.log('  node agent-stop-skill.js stop TASK-20260304-123');
        console.log('  node agent-stop-skill.js stop TASK-20260304-123 --force');
        process.exit(1);
      }

      try {
        await stopAgent(taskId, { force, updateStatus: !noStatusUpdate });
        process.exit(0);
      } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
      }
    } else {
      console.log('🛑 Agent Stop Skill');
      console.log('='.repeat(40));
      console.log('');
      console.log('Available commands:');
      console.log('  stop <taskId> [--force] [--no-status-update]');
      console.log('      Stop the agent running in tmux for the specified task');
      console.log('');
      console.log('Arguments:');
      console.log('  taskId           Task ID to stop');
      console.log('');
      console.log('Options:');
      console.log('  --force          Force kill the pane (skip graceful shutdown)');
      console.log('  --no-status-update  Do not update task status to failed');
      console.log('');
      console.log('Description:');
      console.log('  Stops the agent running in the tmux pane.');
      console.log('  Sends Ctrl+C for graceful shutdown by default.');
      console.log('  Updates task status to "failed" after stopping.');
    }
  })();
}

module.exports = {
  stopAgent,
  stopGracefully,
  killPane,
  cleanupEmptySession
};