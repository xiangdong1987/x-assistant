#!/usr/bin/env node

/**
 * Input validation utilities for software development skills
 * Provides validation for task parameters, project keys, and command inputs
 */

const fs = require('fs');
const path = require('path');
const { loadConfig } = require('./config-loader');

class InputValidator {
  constructor(configPath = null) {
    this.config = configPath ? this._loadCustomConfig(configPath) : loadConfig();
    this.validProjectKeys = this.extractProjectKeys();
  }

  _loadCustomConfig(configPath) {
    if (!fs.existsSync(configPath)) {
      console.warn(`⚠️ Configuration file not found: ${configPath}`);
      return { projects: {} };
    }

    try {
      return JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    } catch (err) {
      console.error(`[input-validator] Failed to load config: ${err.message}`);
      return { projects: {} };
    }
  }

  extractProjectKeys() {
    // Extract project keys from configuration
    const projects = this.config.projects || {};

    if (typeof projects === 'string' && projects.includes('Managed remotely')) {
      // Remote project management - will need to fetch dynamically
      return [];
    }

    if (projects.registry && typeof projects.registry === 'object') {
      return Object.keys(projects.registry);
    }

    return [];
  }

  /**
   * Validate task title
   */
  validateTitle(title) {
    if (!title || typeof title !== 'string') {
      return { valid: false, error: 'Task title is required and must be a string' };
    }

    const trimmed = title.trim();
    if (trimmed.length === 0) {
      return { valid: false, error: 'Task title cannot be empty' };
    }

    if (trimmed.length > 200) {
      return { valid: false, error: 'Task title cannot exceed 200 characters' };
    }

    return { valid: true, value: trimmed };
  }

  /**
   * Validate task description
   */
  validateDescription(description, title) {
    if (!description || typeof description !== 'string') {
      // Description can be same as title if not provided
      const titleValidation = this.validateTitle(title);
      if (titleValidation.valid) {
        return { valid: true, value: titleValidation.value };
      }
      return { valid: false, error: 'Task description is required and must be a string' };
    }

    const trimmed = description.trim();
    if (trimmed.length === 0) {
      const titleValidation = this.validateTitle(title);
      if (titleValidation.valid) {
        return { valid: true, value: titleValidation.value };
      }
      return { valid: false, error: 'Task description cannot be empty' };
    }

    if (trimmed.length > 1000) {
      return { valid: false, error: 'Task description cannot exceed 1000 characters' };
    }

    return { valid: true, value: trimmed };
  }

  /**
   * Validate project key
   */
  validateProjectKey(projectKey) {
    if (!projectKey || typeof projectKey !== 'string') {
      return { valid: false, error: 'Project key is required and must be a string' };
    }

    const trimmed = projectKey.trim();
    if (trimmed.length === 0) {
      return { valid: false, error: 'Project key cannot be empty' };
    }

    // Check if project key exists in configuration
    if (this.validProjectKeys.length > 0 && !this.validProjectKeys.includes(trimmed)) {
      return {
        valid: false,
        error: `Project key '${trimmed}' not found in configuration. Valid keys: ${this.validProjectKeys.join(', ')}`
      };
    }

    return { valid: true, value: trimmed };
  }

  /**
   * Validate priority level
   */
  validatePriority(priority) {
    const validPriorities = ['low', 'medium', 'high', 'critical'];
    const defaultPriority = 'medium';

    if (!priority) {
      return { valid: true, value: defaultPriority };
    }

    if (typeof priority !== 'string') {
      return { valid: false, error: 'Priority must be a string' };
    }

    const normalized = priority.toLowerCase().trim();
    if (!validPriorities.includes(normalized)) {
      return {
        valid: false,
        error: `Invalid priority '${priority}'. Valid values: ${validPriorities.join(', ')}`
      };
    }

    return { valid: true, value: normalized };
  }

  /**
   * Validate task creation parameters
   */
  validateTaskCreation(title, description, projectKey, priority = 'medium') {
    const titleResult = this.validateTitle(title);
    if (!titleResult.valid) {
      return titleResult;
    }

    const descriptionResult = this.validateDescription(description, title);
    if (!descriptionResult.valid) {
      return descriptionResult;
    }

    const projectKeyResult = this.validateProjectKey(projectKey);
    if (!projectKeyResult.valid) {
      return projectKeyResult;
    }

    const priorityResult = this.validatePriority(priority);
    if (!priorityResult.valid) {
      return priorityResult;
    }

    return {
      valid: true,
      values: {
        title: titleResult.value,
        description: descriptionResult.value,
        projectKey: projectKeyResult.value,
        priority: priorityResult.value
      }
    };
  }

  /**
   * Validate file path for security
   */
  validateFilePath(filePath, allowedBaseDir = null) {
    if (!filePath || typeof filePath !== 'string') {
      return { valid: false, error: 'File path is required and must be a string' };
    }

    const normalized = path.normalize(filePath).trim();

    // Check for path traversal attempts
    if (normalized.includes('..') || normalized.startsWith('/') || normalized.includes('~')) {
      return { valid: false, error: 'Invalid file path: path traversal not allowed' };
    }

    // If allowedBaseDir is provided, ensure path is within it
    if (allowedBaseDir) {
      const resolved = path.resolve(allowedBaseDir, normalized);
      const baseResolved = path.resolve(allowedBaseDir);

      if (!resolved.startsWith(baseResolved)) {
        return { valid: false, error: 'File path must be within the allowed directory' };
      }
    }

    return { valid: true, value: normalized };
  }

  /**
   * Validate command arguments
   */
  validateCommandArgs(command, args, expectedCount) {
    if (!command || typeof command !== 'string') {
      return { valid: false, error: 'Command is required' };
    }

    if (!Array.isArray(args)) {
      return { valid: false, error: 'Arguments must be an array' };
    }

    if (expectedCount !== undefined && args.length < expectedCount) {
      return {
        valid: false,
        error: `Command '${command}' requires at least ${expectedCount} arguments, got ${args.length}`
      };
    }

    return { valid: true, value: { command, args } };
  }
}

// Export for use in other modules
if (require.main === module) {
  // Command line testing interface
  const validator = new InputValidator();

  const testCases = [
    { title: 'Test Task', description: 'Test Description', projectKey: 'test-project', priority: 'medium' },
    { title: '', description: 'Test', projectKey: 'test', priority: 'medium' },
    { title: 'Valid', description: '', projectKey: 'test', priority: 'invalid' },
    { title: 'A'.repeat(201), description: 'Test', projectKey: 'test', priority: 'medium' }
  ];

  console.log('Input Validator Test Results:');
  console.log('='.repeat(50));

  testCases.forEach((test, index) => {
    const result = validator.validateTaskCreation(
      test.title,
      test.description,
      test.projectKey,
      test.priority
    );

    console.log(`Test ${index + 1}: ${result.valid ? '✅ PASS' : '❌ FAIL'}`);
    if (!result.valid) {
      console.log(`  Error: ${result.error}`);
    }
    console.log();
  });
}

module.exports = InputValidator;