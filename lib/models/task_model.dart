import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'task_enums.dart';

part 'task_model.g.dart';

@HiveType(typeId: 0)
class TaskModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String? description;

  @HiveField(3)
  TaskPriority priority;

  @HiveField(4)
  TaskStatus status;

  @HiveField(5)
  TaskSource source;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  DateTime? dueAt;

  @HiveField(8)
  DateTime? completedAt;

  @HiveField(9)
  String? feedback;

  @HiveField(10)
  FeedbackType? feedbackType;

  @HiveField(11)
  DateTime? updatedAt;

  @HiveField(12)
  int completedItems;

  @HiveField(13)
  int totalItems;

  @HiveField(14)
  String? projectKey;

  @HiveField(15)
  String? planPath;

  @HiveField(16)
  String? phase;

  @HiveField(17)
  String? backend;

  TaskModel({
    String? id,
    required this.title,
    this.description,
    this.priority = TaskPriority.p2,
    this.status = TaskStatus.pending,
    this.source = TaskSource.manual,
    DateTime? createdAt,
    this.dueAt,
    this.completedAt,
    this.feedback,
    this.feedbackType,
    this.updatedAt,
    this.completedItems = 0,
    this.totalItems = 0,
    this.projectKey,
    this.planPath,
    this.phase,
    this.backend,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  TaskModel copyWith({
    String? title,
    String? description,
    TaskPriority? priority,
    TaskStatus? status,
    TaskSource? source,
    DateTime? dueAt,
    DateTime? completedAt,
    String? feedback,
    FeedbackType? feedbackType,
    int? completedItems,
    int? totalItems,
    String? projectKey,
    String? planPath,
    String? phase,
    String? backend,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      source: source ?? this.source,
      createdAt: createdAt,
      dueAt: dueAt ?? this.dueAt,
      completedAt: completedAt ?? this.completedAt,
      feedback: feedback ?? this.feedback,
      feedbackType: feedbackType ?? this.feedbackType,
      updatedAt: DateTime.now(),
      completedItems: completedItems ?? this.completedItems,
      totalItems: totalItems ?? this.totalItems,
      projectKey: projectKey ?? this.projectKey,
      planPath: planPath ?? this.planPath,
      phase: phase ?? this.phase,
      backend: backend ?? this.backend,
    );
  }

  bool get isOverdue {
    if (dueAt == null) return false;
    if (status == TaskStatus.completed || status == TaskStatus.cancelled) {
      return false;
    }
    return DateTime.now().isAfter(dueAt!);
  }

  bool get isDueToday {
    if (dueAt == null) return false;
    final now = DateTime.now();
    return dueAt!.year == now.year &&
        dueAt!.month == now.month &&
        dueAt!.day == now.day;
  }
}
