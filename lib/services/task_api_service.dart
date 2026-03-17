import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../models/task_model.dart';
import '../models/task_enums.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0, noBoxingByDefault: true));

/// Service for task CRUD via proxy API
class TaskApiService {
  TaskApiService({
    required this.baseUrl,
    required this.token,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options.headers['Authorization'] = 'Bearer $token';
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 5);
  }

  final String baseUrl;
  final String token;
  final Dio _dio;

  /// Fetch all tasks
  Future<List<TaskModel>> getTasks({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final response = await _dio.get('$baseUrl/api/tasks$query');
    final data = response.data as Map<String, dynamic>;
    final tasks = data['tasks'] as List<dynamic>? ?? [];
    return tasks.map((e) => _taskFromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetch single task by id
  Future<TaskModel?> getTask(String id) async {
    try {
      final response = await _dio.get('$baseUrl/api/tasks/$id');
      return _taskFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Fetch task plan markdown text
  Future<String?> getTaskPlanText(String id) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/tasks/$id/plan',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data?.toString();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Open task in Cursor
  Future<bool> openInCursor(String id) async {
    try {
      await _dio.post('$baseUrl/api/tasks/$id/open-cursor');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 400) return false;
      rethrow;
    }
  }

  /// Open iTerm2 and focus on the tmux session for this task's agent
  Future<bool> tmuxFocus(String id) async {
    try {
      await _dio.post(
        '$baseUrl/api/tasks/$id/tmux-focus',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 500) return false;
      rethrow;
    }
  }

  /// Start an agent in a tmux session (ccr/cursor/claude).
  /// agent-start-skill.js records the tmux session on the task.
  Future<Map<String, dynamic>> agentStart(String id, String backend, {String? phase}) async {
    try {
      final query = <String, dynamic>{'backend': backend};
      if (phase != null) {
        query['phase'] = phase;
      }
      final response = await _dio.post(
        '$baseUrl/api/tasks/$id/agent-start',
        queryParameters: query,
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      return response.data as Map<String, dynamic>? ?? {};
    } catch (e) {
      rethrow;
    }
  }

  /// Create a new task
  Future<TaskModel> createTask({
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.p2,
    DateTime? dueAt,
    TaskSource source = TaskSource.manual,
    String? backend,
    String? projectKey,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      'priority': _priorityToString(priority),
      if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
      'source': _sourceToString(source),
      if (backend != null) 'backend': backend,
      if (projectKey != null && projectKey.isNotEmpty) 'projectKey': projectKey,
    };
    final response = await _dio.post('$baseUrl/api/tasks', data: body);
    return _taskFromJson(response.data as Map<String, dynamic>);
  }

  /// Update a task
  Future<TaskModel> updateTask(TaskModel task) async {
    final body = <String, dynamic>{
      'title': task.title,
      if (task.description != null) 'description': task.description,
      'priority': _priorityToString(task.priority),
      'status': _statusToString(task.status),
      'source': _sourceToString(task.source),
      if (task.dueAt != null) 'dueAt': task.dueAt!.toIso8601String(),
      if (task.phase != null && task.phase!.isNotEmpty) 'phase': task.phase,
      if (task.backend != null && task.backend!.isNotEmpty) 'backend': task.backend,
      if (task.projectKey != null && task.projectKey!.isNotEmpty) 'projectKey': task.projectKey,
    };
    final response = await _dio.put('$baseUrl/api/tasks/${task.id}', data: body);
    return _taskFromJson(response.data as Map<String, dynamic>);
  }

  /// Update task status
  Future<TaskModel?> updateStatus(String id, TaskStatus status) async {
    try {
      final response = await _dio.put('$baseUrl/api/tasks/$id', data: {
        'status': _statusToString(status),
      });
      return _taskFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Submit feedback for a task
  Future<TaskModel?> submitFeedback(
    String id,
    FeedbackType type,
    String? feedbackText,
  ) async {
    try {
      final body = <String, dynamic>{
        'feedback': feedbackText ?? '',
        'feedbackType': type == FeedbackType.done ? 'done' : 'hasIssue',
        if (type == FeedbackType.done) 'status': 'completed',
      };
      final response = await _dio.put('$baseUrl/api/tasks/$id', data: body);
      return _taskFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Execute a task plan using Claude Code or Cursor via proxy
  /// Returns map with success, logPath (optional) for execution trace
  Future<Map<String, dynamic>> executeTask(String id, String executor, {String? logPath}) async {
    try {
      final params = <String, dynamic>{'executor': executor};
      if (logPath != null && logPath.isNotEmpty) params['logPath'] = logPath;
      final response = await _dio.post(
        '$baseUrl/api/tasks/$id/execute',
        queryParameters: params,
      );
      return response.data as Map<String, dynamic>? ?? {};
    } catch (e) {
      _logger.e('Error executing task', error: e);
      rethrow;
    }
  }

  /// Generate plan for a task
  Future<Map<String, dynamic>> generatePlan(String id) async {
    try {
      final response = await _dio.post('$baseUrl/api/tasks/$id/generate-plan');
      return response.data as Map<String, dynamic>? ?? {};
    } catch (e) {
      _logger.e('Error generating plan', error: e);
      rethrow;
    }
  }

  /// Advance phase for a task
  Future<Map<String, dynamic>> phaseAdvance(String id, {String? phase}) async {
    try {
      final params = <String, dynamic>{};
      if (phase != null) params['phase'] = phase;
      final response = await _dio.post(
        '$baseUrl/api/tasks/$id/phase-advance',
        queryParameters: params,
      );
      return response.data as Map<String, dynamic>? ?? {};
    } catch (e) {
      _logger.e('Error advancing phase', error: e);
      rethrow;
    }
  }

  /// Run phase pipeline for a task
  Future<Map<String, dynamic>> phasePipeline(String id) async {
    try {
      final response = await _dio.post('$baseUrl/api/tasks/$id/phase-pipeline');
      return response.data as Map<String, dynamic>? ?? {};
    } catch (e) {
      _logger.e('Error running phase pipeline', error: e);
      rethrow;
    }
  }

  /// Auto-execute: generate plan if needed, then code + test + commit. Runs in background on server (202 Accepted); task continues even if app is closed.
  Future<Map<String, dynamic>> autoExecute(String id) async {
    try {
      final response = await _dio.post('$baseUrl/api/tasks/$id/auto-execute');
      // 202 Accepted = 已提交后台执行，视为成功
      final data = response.data as Map<String, dynamic>? ?? {};
      if (response.statusCode == 202) {
        data['success'] = true;
        data['accepted'] = true;
      }
      return data;
    } catch (e) {
      _logger.e('Error running auto-execute', error: e);
      rethrow;
    }
  }

  /// Delete a task
  Future<bool> deleteTask(String id) async {
    try {
      await _dio.delete('$baseUrl/api/tasks/$id');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  /// Clear all chat history on the backend
  Future<bool> clearChatHistory() async {
    try {
      await _dio.delete('$baseUrl/api/chat-history');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 503) return false;
      rethrow;
    }
  }

  /// Parses a task from JSON (API response or WebSocket payload). Public so
  /// WebSocket handler can merge pushed task into state for immediate UI update.
  TaskModel taskFromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      priority: _parsePriority(json['priority'] as String?),
      status: _parseStatus(json['status'] as String?),
      source: _parseSource(json['source'] as String?),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      dueAt: json['dueAt'] != null ? DateTime.tryParse(json['dueAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      feedback: json['feedback'] as String?,
      feedbackType: _parseFeedbackType(json['feedbackType'] as String?),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      completedItems: json['completedItems'] as int? ?? 0,
      totalItems: json['totalItems'] as int? ?? 0,
      projectKey: json['projectKey'] as String?,
      planPath: json['planPath'] as String?,
      phase: json['phase'] as String?,
      backend: json['backend'] as String?,
    );
  }

  TaskModel _taskFromJson(Map<String, dynamic> json) => taskFromJson(json);

  /// Parse priority string to enum. Static for reuse from other providers.
  static TaskPriority parsePriority(String? s) {
    switch (s) {
      case 'p0': return TaskPriority.p0;
      case 'p1': return TaskPriority.p1;
      case 'p3': return TaskPriority.p3;
      default: return TaskPriority.p2;
    }
  }

  TaskPriority _parsePriority(String? s) => parsePriority(s);

  String _priorityToString(TaskPriority p) {
    switch (p) {
      case TaskPriority.p0: return 'p0';
      case TaskPriority.p1: return 'p1';
      case TaskPriority.p3: return 'p3';
      default: return 'p2';
    }
  }

  /// Parse status string to enum. Static for reuse from other providers.
  static TaskStatus parseStatus(String? s) {
    switch (s) {
      case 'pending': return TaskStatus.pending;
      case 'confirmed': return TaskStatus.confirmed;
      case 'inProgress': return TaskStatus.inProgress;
      case 'waitingFeedback': return TaskStatus.planned; // legacy compat
      case 'completed': return TaskStatus.completed;
      case 'cancelled': return TaskStatus.cancelled;
      case 'planned': return TaskStatus.planned;
      case 'planning': return TaskStatus.planning;
      case 'coding': return TaskStatus.coding;
      case 'testing': return TaskStatus.testing;
      case 'submitting': return TaskStatus.submitting;
      case 'implemented': return TaskStatus.completed;
      case 'done': return TaskStatus.completed;
      case 'failed': return TaskStatus.failed;
      default: return TaskStatus.pending;
    }
  }

  TaskStatus _parseStatus(String? s) => parseStatus(s);

  String _statusToString(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending: return 'pending';
      case TaskStatus.confirmed: return 'confirmed';
      case TaskStatus.inProgress: return 'inProgress';
      case TaskStatus.completed: return 'completed';
      case TaskStatus.cancelled: return 'cancelled';
      case TaskStatus.planned: return 'planned';
      case TaskStatus.failed: return 'failed';
      case TaskStatus.planning: return 'planning';
      case TaskStatus.coding: return 'coding';
      case TaskStatus.testing: return 'testing';
      case TaskStatus.submitting: return 'submitting';
    }
  }

  TaskSource _parseSource(String? s) {
    switch (s) {
      case 'openClaw': return TaskSource.openClaw;
      case 'cursor': return TaskSource.cursor;
      case 'skill':
      case 'auto': return TaskSource.skill;
      default: return TaskSource.manual;
    }
  }

  String _sourceToString(TaskSource s) {
    switch (s) {
      case TaskSource.manual: return 'manual';
      case TaskSource.openClaw: return 'openClaw';
      case TaskSource.cursor: return 'cursor';
      case TaskSource.skill: return 'skill';
    }
  }

  FeedbackType? _parseFeedbackType(String? s) {
    switch (s) {
      case 'done': return FeedbackType.done;
      case 'hasIssue': return FeedbackType.hasIssue;
      default: return null;
    }
  }
}
