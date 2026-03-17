#!/usr/bin/env node

/**
 * 项目解析器 - 统一管理项目名称与目录映射
 */

const fs = require('fs');
const path = require('path');
const { loadConfig } = require('./config-loader');

class ProjectResolver {
  constructor(configPath = null) {
    if (configPath) {
      this.config = this._loadCustomConfig(configPath);
      this._configDir = path.dirname(configPath);
    } else {
      this.config = loadConfig();
      this._configDir = __dirname;
    }
    this.registry = this.config.projects?.registry || {};
    this.aliases = this.config.projects?.aliases || {};
    this.categories = this.config.projects?.categories || {};

    // 流程验证脚本可强制使用本地 registry
    if (process.env.VERIFY_USE_LOCAL_STORE === '1') {
      this._useRemote = false;
    } else {
      // When taskApiUrl 或 TASK_API_URL 配置时，使用远程解析器（与 Proxy 任务体系联动）
      this._useRemote = !!(process.env.TASK_API_URL || this.config.settings?.taskApiUrl);
    }
    if (this._useRemote) {
      const ProjectResolverRemote = require('./project-resolver-remote');
      this._remote = new ProjectResolverRemote();
    }
  }

  _loadCustomConfig(configPath) {
    if (!fs.existsSync(configPath)) {
      console.warn(`⚠️ 配置文件不存在: ${configPath}`);
      return { projects: {} };
    }

    try {
      return JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    } catch (err) {
      console.error(`[project-resolver] Failed to load config: ${err.message}`);
      return { projects: {} };
    }
  }

  /**
   * 解析项目键（支持别名，支持远程）
   */
  resolve(projectKey) {
    if (!projectKey) {
      throw new Error('项目键不能为空');
    }

    // Remote mode: delegate to ProjectResolverRemote (returns Promise)
    if (this._useRemote) {
      return this._remote.resolve(projectKey);
    }

    // 1. 检查别名
    const actualKey = this.aliases[projectKey] || projectKey;

    // 2. 获取项目信息
    const project = this.registry[actualKey];
    if (!project) {
      // 尝试从路径推断
      if (fs.existsSync(projectKey) && fs.statSync(projectKey).isDirectory()) {
        return this.inferProjectFromPath(projectKey);
      }
      throw new Error(`项目未注册: ${projectKey} (尝试解析为: ${actualKey})`);
    }

    // 项目路径必须为绝对路径，且以 config 所在目录为基准解析相对路径，避免 plan 写到错误目录
    let projectPath = project.path;
    if (projectPath && !path.isAbsolute(projectPath)) {
      projectPath = path.join(this._configDir || __dirname, projectPath);
    }
    projectPath = projectPath ? path.resolve(projectPath) : projectPath;

    if (projectPath && !fs.existsSync(projectPath)) {
      console.warn(`⚠️ 项目路径不存在: ${projectPath}`);
    }

    return {
      key: actualKey,
      name: project.name || actualKey,
      path: projectPath,
      type: project.type || 'unknown',
      techStack: project.techStack || [],
      owner: project.owner || 'unknown',
      status: project.status || 'unknown',
      description: project.description || '',
      ...project
    };
  }

  /**
   * 从路径推断项目信息
   */
  inferProjectFromPath(projectPath) {
    const dirName = path.basename(projectPath);

    // 检测项目类型
    const type = this.detectProjectType(projectPath);

    // 检测技术栈
    const techStack = this.detectTechStack(projectPath);

    return {
      key: dirName,
      name: dirName,
      path: projectPath,
      type,
      techStack,
      owner: 'unknown',
      status: 'discovered',
      description: `自动发现的项目: ${dirName}`
    };
  }

  /**
   * 检测项目类型
   */
  detectProjectType(projectPath) {
    const files = fs.readdirSync(projectPath);

    if (files.includes('package.json')) return 'nodejs';
    if (files.includes('composer.json')) return 'php';
    if (files.includes('pom.xml')) return 'java';
    if (files.includes('requirements.txt') && files.includes('manage.py')) return 'django';
    if (files.includes('go.mod')) return 'go';
    if (files.includes('Cargo.toml')) return 'rust';
    if (files.includes('Gemfile')) return 'ruby';

    return 'unknown';
  }

  /**
   * 检测技术栈
   */
  detectTechStack(projectPath) {
    const techStack = [];
    const files = fs.readdirSync(projectPath);

    // 根据文件检测
    if (files.includes('package.json')) {
      techStack.push('Node.js');
      try {
        const pkg = JSON.parse(fs.readFileSync(path.join(projectPath, 'package.json'), 'utf-8'));
        if (pkg.dependencies?.react || pkg.devDependencies?.react) techStack.push('React');
        if (pkg.dependencies?.vue || pkg.devDependencies?.vue) techStack.push('Vue');
        if (pkg.dependencies?.express || pkg.devDependencies?.express) techStack.push('Express');
      } catch (e) {
        // 忽略解析错误
      }
    }

    if (files.includes('composer.json')) {
      techStack.push('PHP');
      try {
        const composer = JSON.parse(fs.readFileSync(path.join(projectPath, 'composer.json'), 'utf-8'));
        if (composer.require?.['laravel/framework']) techStack.push('Laravel');
        if (composer.require?.['hyperf/framework']) techStack.push('Hyperf');
      } catch (e) {
        // 忽略解析错误
      }
    }

    if (files.includes('requirements.txt')) techStack.push('Python');
    if (files.includes('pom.xml')) techStack.push('Java');
    if (files.includes('go.mod')) techStack.push('Go');
    if (files.includes('Cargo.toml')) techStack.push('Rust');

    return techStack;
  }

  /**
   * 按分类获取项目
   */
  getByCategory(category) {
    const projectKeys = this.categories[category] || [];
    return projectKeys.map(key => this.resolve(key)).filter(Boolean);
  }

  /**
   * 获取所有项目
   */
  listAll() {
    if (this._useRemote) {
      return this._remote.listAll();
    }
    return Object.keys(this.registry).map(key => this.resolve(key)).filter(Boolean);
  }

  /**
   * 搜索项目
   */
  search(query) {
    const results = [];

    for (const [key, project] of Object.entries(this.registry)) {
      const searchableText = [
        key,
        project.name || '',
        project.description || '',
        ...(project.techStack || []),
        project.type || ''
      ].join(' ').toLowerCase();

      if (searchableText.includes(query.toLowerCase())) {
        results.push(this.resolve(key));
      }
    }

    return results;
  }

  /**
   * 验证项目配置
   */
  validate() {
    const issues = [];

    // 检查注册表
    for (const [key, project] of Object.entries(this.registry)) {
      if (!project.path) {
        issues.push(`❌ 项目 ${key}: 缺少path字段`);
      } else if (!fs.existsSync(project.path)) {
        issues.push(`⚠️ 项目 ${key}: 路径不存在: ${project.path}`);
      }

      if (!project.name) {
        issues.push(`⚠️ 项目 ${key}: 缺少name字段`);
      }
    }

    // 检查别名
    for (const [alias, target] of Object.entries(this.aliases)) {
      if (!this.registry[target]) {
        issues.push(`❌ 别名 ${alias} 指向不存在的项目: ${target}`);
      }
    }

    // 检查分类
    for (const [category, keys] of Object.entries(this.categories)) {
      for (const key of keys) {
        if (!this.registry[key]) {
          issues.push(`❌ 分类 ${category} 包含不存在的项目: ${key}`);
        }
      }
    }

    return {
      valid: issues.length === 0,
      issues,
      stats: {
        totalProjects: Object.keys(this.registry).length,
        totalAliases: Object.keys(this.aliases).length,
        totalCategories: Object.keys(this.categories).length
      }
    };
  }

  /**
   * 生成项目摘要
   */
  generateSummary() {
    const projects = this.listAll();

    return {
      timestamp: new Date().toISOString(),
      total: projects.length,
      byType: projects.reduce((acc, project) => {
        acc[project.type] = (acc[project.type] || 0) + 1;
        return acc;
      }, {}),
      byStatus: projects.reduce((acc, project) => {
        acc[project.status] = (acc[project.status] || 0) + 1;
        return acc;
      }, {}),
      projects: projects.map(p => ({
        key: p.key,
        name: p.name,
        type: p.type,
        status: p.status,
        owner: p.owner,
        path: p.path
      }))
    };
  }
}

// 命令行接口
if (require.main === module) {
  const resolver = new ProjectResolver();
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case 'list':
      const projects = resolver.listAll();
      console.log('📋 项目列表:');
      console.log('='.repeat(80));
      projects.forEach((project, index) => {
        console.log(`\n${index + 1}. ${project.name} (${project.key})`);
        console.log(`   路径: ${project.path}`);
        console.log(`   类型: ${project.type} | 状态: ${project.status} | 负责人: ${project.owner}`);
        console.log(`   技术栈: ${project.techStack.join(', ') || '未知'}`);
      });
      break;

    case 'info':
      const projectKey = args[1];
      if (!projectKey) {
        console.error('❌ 请指定项目键');
        process.exit(1);
      }
      try {
        const project = resolver.resolve(projectKey);
        console.log('📊 项目详情:');
        console.log('='.repeat(80));
        console.log(JSON.stringify(project, null, 2));
      } catch (error) {
        console.error(`❌ ${error.message}`);
      }
      break;

    case 'category':
      const category = args[1];
      if (!category) {
        console.error('❌ 请指定分类');
        process.exit(1);
      }
      const categoryProjects = resolver.getByCategory(category);
      console.log(`📁 分类 "${category}" 的项目:`);
      categoryProjects.forEach((project, index) => {
        console.log(`  ${index + 1}. ${project.name} (${project.key})`);
      });
      break;

    case 'search':
      const query = args[1];
      if (!query) {
        console.error('❌ 请指定搜索关键词');
        process.exit(1);
      }
      const results = resolver.search(query);
      console.log(`🔍 搜索 "${query}" 的结果:`);
      results.forEach((project, index) => {
        console.log(`  ${index + 1}. ${project.name} (${project.key}) - ${project.description}`);
      });
      break;

    case 'validate':
      const validation = resolver.validate();
      console.log('🔍 项目配置验证:');
      console.log('='.repeat(80));
      if (validation.valid) {
        console.log('✅ 所有配置有效');
      } else {
        console.log('❌ 发现以下问题:');
        validation.issues.forEach(issue => console.log(`  ${issue}`));
      }
      console.log('\n📊 统计信息:');
      console.log(`  项目总数: ${validation.stats.totalProjects}`);
      console.log(`  别名总数: ${validation.stats.totalAliases}`);
      console.log(`  分类总数: ${validation.stats.totalCategories}`);
      break;

    case 'summary':
      const summary = resolver.generateSummary();
      console.log('📈 项目摘要:');
      console.log('='.repeat(80));
      console.log(JSON.stringify(summary, null, 2));
      break;

    case 'help':
    default:
      console.log('📖 项目解析器使用说明:');
      console.log('='.repeat(80));
      console.log('命令:');
      console.log('  list                    - 列出所有项目');
      console.log('  info <projectKey>       - 查看项目详情');
      console.log('  category <category>     - 按分类查看项目');
      console.log('  search <query>          - 搜索项目');
      console.log('  validate                - 验证项目配置');
      console.log('  summary                 - 生成项目摘要');
      console.log('  help                    - 显示帮助');
      console.log('\n示例:');
      console.log('  node project-resolver.js list');
      console.log('  node project-resolver.js info s2c_DataHarbor');
      console.log('  node project-resolver.js search php');
      console.log('  node project-resolver.js validate');
  }
}

module.exports = ProjectResolver;