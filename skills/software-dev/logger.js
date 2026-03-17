#!/usr/bin/env node

/**
 * Standardized logging utility for software development skills
 * Provides consistent, English-only logging with structured output
 */

class Logger {
  constructor(moduleName = 'software-dev-agent') {
    this.moduleName = moduleName;
    this.logLevel = process.env.LOG_LEVEL || 'info';
    this.levels = {
      error: 0,
      warn: 1,
      info: 2,
      debug: 3
    };
  }

  /**
   * Check if logging is enabled for given level
   */
  shouldLog(level) {
    return this.levels[level] <= this.levels[this.logLevel];
  }

  /**
   * Format log message with timestamp and module name
   */
  formatMessage(level, message) {
    const timestamp = new Date().toISOString();
    const levelUpper = level.toUpperCase();
    return `[${timestamp}] [${levelUpper}] [${this.moduleName}] ${message}`;
  }

  /**
   * Error level logging
   */
  error(message, error = null) {
    if (!this.shouldLog('error')) return;

    let fullMessage = message;
    if (error) {
      if (error instanceof Error) {
        fullMessage += `: ${error.message}`;
        if (this.logLevel === 'debug') {
          fullMessage += `\nStack: ${error.stack}`;
        }
      } else {
        fullMessage += `: ${error}`;
      }
    }

    console.error(this.formatMessage('error', fullMessage));
  }

  /**
   * Warning level logging
   */
  warn(message) {
    if (!this.shouldLog('warn')) return;
    console.warn(this.formatMessage('warn', message));
  }

  /**
   * Info level logging
   */
  info(message) {
    if (!this.shouldLog('info')) return;
    console.log(this.formatMessage('info', message));
  }

  /**
   * Debug level logging
   */
  debug(message) {
    if (!this.shouldLog('debug')) return;
    console.debug(this.formatMessage('debug', message));
  }

  /**
   * Success message (info level with success indicator)
   */
  success(message) {
    this.info(`✅ ${message}`);
  }

  /**
   * Task creation log
   */
  taskCreated(taskId, title, projectKey) {
    this.success(`Task created: id=${taskId} title="${title}" project=${projectKey}`);
  }

  /**
   * Plan generation log
   */
  planGenerated(taskId, planPath) {
    this.success(`Plan generated: task=${taskId} path=${planPath}`);
  }

  /**
   * Task status update log
   */
  statusUpdated(taskId, oldStatus, newStatus) {
    this.info(`Task status updated: ${taskId} ${oldStatus} → ${newStatus}`);
  }

  /**
   * Processing summary log
   */
  processingSummary(total, success, failed) {
    this.info(`Processing complete: total=${total} success=${success} failed=${failed}`);
  }

  /**
   * Command execution log
   */
  commandExecuted(command, args = []) {
    const argsStr = args.length > 0 ? ` ${args.join(' ')}` : '';
    this.debug(`Executing command: ${command}${argsStr}`);
  }

  /**
   * Configuration loaded log
   */
  configLoaded(configPath) {
    this.debug(`Configuration loaded from: ${configPath}`);
  }

  /**
   * Validation failure log
   */
  validationFailed(field, error) {
    this.warn(`Validation failed for ${field}: ${error}`);
  }

  /**
   * Start operation log
   */
  startOperation(operation) {
    this.info(`Starting operation: ${operation}`);
  }

  /**
   * Complete operation log
   */
  completeOperation(operation, durationMs = null) {
    let message = `Completed operation: ${operation}`;
    if (durationMs !== null) {
      message += ` (${durationMs}ms)`;
    }
    this.info(message);
  }
}

// Export singleton instance
const defaultLogger = new Logger();

// Also export class for custom instances
module.exports = {
  Logger,
  defaultLogger
};

// Command line testing interface
if (require.main === module) {
  console.log('Logger Test Output:');
  console.log('='.repeat(50));

  const testLogger = new Logger('logger-test');

  testLogger.error('This is an error message', new Error('Test error'));
  testLogger.warn('This is a warning message');
  testLogger.info('This is an info message');
  testLogger.debug('This is a debug message');
  testLogger.success('Operation completed successfully');
  testLogger.taskCreated('TASK-123', 'Test Task', 'test-project');
  testLogger.planGenerated('TASK-123', '/path/to/plan.md');
  testLogger.statusUpdated('TASK-123', 'pending', 'planned');
  testLogger.processingSummary(10, 8, 2);
  testLogger.commandExecuted('create-task', ['"Test"', '"Description"', 'project-key']);
  testLogger.configLoaded('/path/to/config.json');
  testLogger.validationFailed('title', 'Title cannot be empty');
  testLogger.startOperation('process-pending');
  testLogger.completeOperation('process-pending', 1250);

  console.log('\nTesting log levels:');
  console.log('='.repeat(50));

  const levels = ['error', 'warn', 'info', 'debug'];
  levels.forEach(level => {
    const levelLogger = new Logger('level-test');
    levelLogger.logLevel = level;
    console.log(`\nLog level: ${level}`);
    levelLogger.error('Error message');
    levelLogger.warn('Warning message');
    levelLogger.info('Info message');
    levelLogger.debug('Debug message');
  });
}