#!/usr/bin/env node

/**
 * Agent Status Skill
 *
 * Purpose: Query agent status from tmux sessions
 * Input: (taskId) or (projectKey)
 * State: Returns running/stopped/unknown status
 * Command: status <taskId> | list <projectKey>
 *
 * Handles: TMUX pane status checking, task metadata retrieval
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
 * Check if pane is alive/running
 */
function isPaneAlive(paneId) {
  try {
    // Get pane pid
    const pid = execCommand(`tmux display-message -t "${paneId}" -p "#{pane_pid}" 2>/dev/null`);
    if (!pid) return false;

    // Check if process exists
    const check = execCommand(`ps -p ${pid} -o pid= 2>/dev/null`, { ignoreError: true });
    return check !== null && check !== '';
  } catch (error) {
    return false;
  }
}

/**
 * Get pane last lines of output
 */
function getPaneLastLines(paneId, lines = 10) {
  try {
    // Use capture-pane to get content
    const content = execCommand(`tmux capture-pane -t "${paneId}" -p -l ${lines} 2>/dev/null`);
    return content || '';
  } catch (error) {
    return '';
  }
}

/**
 * Get pane current working directory
 */
function getPaneCwd(paneId) {
  try {
    const cwd = execCommand(`tmux display-message -t "${paneId}" -p "#{pane_current_path}" 2>/dev/null`);
    return cwd || '';
  } catch (error) {
    return '';
  }
}

/**
 * Get pane status (running, stopped, unknown)
 */
function getPaneStatus(paneId) {
  try {
    const alive = isPaneAlive(paneId);
    if (!alive) {
      return 'stopped';
    }

    // Check if pane is active (has focus recently)
    const active = execCommand(`tmux display-message -t "${paneId}" -p "#{pane_active}" 2>/dev/null`);
    if (active === '1') {
      return 'active';
    }

    return 'running';
  } catch (error) {
    return 'unknown';
  }
}

/**
 * Main function to get agent status
 */
async function getAgentStatus(taskId) {
  console.log('📊 Agent Status Skill');
  console.log('='.repeat(40));
  console.log(`   Task ID: ${taskId}`);

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
    console.log(`   Task Status: ${task.status}`);

    // Check tmux metadata
    if (!tmuxMeta.tmuxPaneId) {
      console.log(`\n⚠️ No tmux metadata found for this task`);
      return {
        ok: true,
        skill: 'agent.status',
        version: '1.0',
        data: {
          taskId,
          title: task.title,
          status: task.status,
          paneStatus: 'untracked',
          tmux: null
        },
        error: null
      };
    }

    const paneId = tmuxMeta.tmuxPaneId;
    const paneStatus = getPaneStatus(paneId);
    const lastLines = getPaneLastLines(paneId, 10);
    const cwd = getPaneCwd(paneId);

    console.log(`   Pane ID: ${paneId}`);
    console.log(`   Pane Status: ${paneStatus}`);
    console.log(`   Session: ${tmuxMeta.tmuxSession}`);
    console.log(`   Window: ${tmuxMeta.tmuxWindow}`);
    if (cwd) console.log(`   CWD: ${cwd}`);
    if (tmuxMeta.backend) console.log(`   Backend: ${tmuxMeta.backend}`);
    if (tmuxMeta.lastExecLogPath) console.log(`   Log: ${tmuxMeta.lastExecLogPath}`);

    // Determine overall status
    let overallStatus = task.status;
    if (paneStatus === 'stopped' && task.status === 'developing') {
      overallStatus = 'stale';
    }

    // Output HANDOFF
    const handoff = {
      ok: true,
      skill: 'agent.status',
      version: '1.0',
      data: {
        taskId,
        title: task.title,
        status: overallStatus,
        taskStatus: task.status,
        paneStatus,
        tmux: {
          session: tmuxMeta.tmuxSession,
          window: tmuxMeta.tmuxWindow,
          paneId: tmuxMeta.tmuxPaneId,
          backend: tmuxMeta.backend,
          logPath: tmuxMeta.lastExecLogPath
        },
        paneInfo: {
          cwd,
          lastOutput: lastLines ? lastLines.split('\n').slice(-5) : []
        }
      },
      error: null
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);

    return {
      success: true,
      ...handoff
    };

  } catch (error) {
    console.error(`\n❌ Agent status query failed: ${error.message}`);

    const handoff = {
      ok: false,
      skill: 'agent.status',
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

/**
 * List all agents for a project
 */
async function listAgents(projectKey) {
  console.log('📋 Agent List');
  console.log('='.repeat(40));
  console.log(`   Project: ${projectKey}`);

  try {
    // Load all tasks for the project
    const allTasks = await tasksStore.loadTasks();
    const projectTasks = allTasks.tasks.filter(t => t.projectKey === projectKey);

    // Filter tasks with tmux metadata
    const agents = [];

    for (const task of projectTasks) {
      if (task.tmuxPaneId) {
        const paneStatus = getPaneStatus(task.tmuxPaneId);
        agents.push({
          taskId: task.taskId || task.id,
          title: task.title,
          status: task.status,
          paneStatus,
          backend: task.backend,
          tmux: {
            session: task.tmuxSession,
            window: task.tmuxWindow,
            paneId: task.tmuxPaneId
          }
        });
      }
    }

    console.log(`\n📊 Found ${agents.length} active agent(s)`);

    // Group by pane status
    const running = agents.filter(a => a.paneStatus === 'running' || a.paneStatus === 'active');
    const stopped = agents.filter(a => a.paneStatus === 'stopped');

    console.log(`   Running: ${running.length}`);
    console.log(`   Stopped: ${stopped.length}`);

    if (running.length > 0) {
      console.log(`\n🚀 Running Agents:`);
      running.forEach(a => {
        console.log(`   - ${a.taskId}: ${a.title}`);
        console.log(`     Pane: ${a.tmux.paneId}, Backend: ${a.backend}`);
      });
    }

    if (stopped.length > 0) {
      console.log(`\n⏹️ Stopped Agents (stale):`);
      stopped.forEach(a => {
        console.log(`   - ${a.taskId}: ${a.title}`);
        console.log(`     Pane: ${a.tmux.paneId}`);
      });
    }

    // Output HANDOFF
    const handoff = {
      ok: true,
      skill: 'agent.status',
      version: '1.0',
      data: {
        projectKey,
        totalAgents: agents.length,
        running: running.length,
        stopped: stopped.length,
        agents
      },
      error: null
    };

    console.log(`\nHANDOFF:${JSON.stringify(handoff, null, 2)}`);

    return {
      success: true,
      ...handoff
    };

  } catch (error) {
    console.error(`\n❌ Agent list failed: ${error.message}`);

    const handoff = {
      ok: false,
      skill: 'agent.status',
      version: '1.0',
      data: { projectKey },
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

    if (command === 'status') {
      const taskId = args[1];

      if (!taskId) {
        console.log('Usage: node agent-status-skill.js status <taskId>');
        console.log('');
        console.log('Example:');
        console.log('  node agent-status-skill.js status TASK-20260304-123');
        process.exit(1);
      }

      try {
        await getAgentStatus(taskId);
        process.exit(0);
      } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
      }
    } else if (command === 'list') {
      const projectKey = args[1];

      if (!projectKey) {
        console.log('Usage: node agent-status-skill.js list <projectKey>');
        console.log('');
        console.log('Example:');
        console.log('  node agent-status-skill.js list xassistant');
        process.exit(1);
      }

      try {
        await listAgents(projectKey);
        process.exit(0);
      } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
      }
    } else {
      console.log('📋 Agent Status Skill');
      console.log('='.repeat(40));
      console.log('');
      console.log('Available commands:');
      console.log('  status <taskId>');
      console.log('      Query status of a specific agent');
      console.log('');
      console.log('  list <projectKey>');
      console.log('      List all agents for a project');
      console.log('');
      console.log('Description:');
      console.log('  Queries the status of agents running in tmux.');
      console.log('  Returns pane status (running/stopped/active/unknown).');
      console.log('  Also provides last output lines for debugging.');
    }
  })();
}

module.exports = {
  getAgentStatus,
  listAgents,
  isPaneAlive,
  getPaneLastLines,
  getPaneStatus
};