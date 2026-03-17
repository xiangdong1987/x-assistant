import 'package:hive/hive.dart';

import '../l10n/app_localizations.dart';
part 'task_enums.g.dart';

@HiveType(typeId: 1)
enum TaskStatus {
  @HiveField(0)
  pending, // 待确认

  @HiveField(1)
  confirmed, // 已确认，等待执行

  @HiveField(2)
  inProgress, // 执行中（兼容旧数据）

  @HiveField(3)
  planned, // 已计划（index 3 兼容旧 waitingFeedback）

  @HiveField(4)
  completed, // 已完成

  @HiveField(5)
  cancelled, // 已取消

  @HiveField(6)
  failed, // 执行失败，可重试

  @HiveField(7)
  planning, // 计划中

  @HiveField(8)
  coding, // 执行中（开发阶段）

  @HiveField(9)
  testing, // 测试中

  @HiveField(10)
  submitting; // 提交中

  String label(AppLocalizations l10n) {
    switch (this) {
      case TaskStatus.pending:
        return l10n.taskStatusPending;
      case TaskStatus.confirmed:
        return l10n.taskStatusConfirmed;
      case TaskStatus.inProgress:
        return l10n.taskStatusInProgress;
      case TaskStatus.planned:
        return l10n.taskStatusPlanned;
      case TaskStatus.completed:
        return l10n.taskStatusCompleted;
      case TaskStatus.cancelled:
        return l10n.taskStatusCancelled;
      case TaskStatus.failed:
        return l10n.taskStatusFailed;
      case TaskStatus.planning:
        return l10n.taskStatusPlanning;
      case TaskStatus.coding:
        return l10n.taskStatusCoding;
      case TaskStatus.testing:
        return l10n.taskStatusTesting;
      case TaskStatus.submitting:
        return l10n.taskStatusSubmitting;
    }
  }
}

@HiveType(typeId: 2)
enum TaskPriority {
  @HiveField(0)
  p0, // 紧急

  @HiveField(1)
  p1, // 高

  @HiveField(2)
  p2, // 中

  @HiveField(3)
  p3; // 低

  String label(AppLocalizations l10n) {
    switch (this) {
      case TaskPriority.p0:
        return l10n.taskPriorityP0;
      case TaskPriority.p1:
        return l10n.taskPriorityP1;
      case TaskPriority.p2:
        return l10n.taskPriorityP2;
      case TaskPriority.p3:
        return l10n.taskPriorityP3;
    }
  }
}

@HiveType(typeId: 3)
enum TaskSource {
  @HiveField(0)
  manual, // 手动创建

  @HiveField(1)
  openClaw, // OpenClaw 生成

  @HiveField(2)
  cursor, // Cursor Agent

  @HiveField(3)
  skill; // 技能自动创建

  String label(AppLocalizations l10n) {
    switch (this) {
      case TaskSource.manual:
        return l10n.sourceManual;
      case TaskSource.openClaw:
        return l10n.sourceOpenClaw;
      case TaskSource.cursor:
        return l10n.sourceCursor;
      case TaskSource.skill:
        return l10n.sourceSkill;
    }
  }
}

@HiveType(typeId: 4)
enum FeedbackType {
  @HiveField(0)
  done, // 已完成

  @HiveField(1)
  hasIssue; // 有问题

  String label(AppLocalizations l10n) {
    switch (this) {
      case FeedbackType.done:
        return l10n.feedbackTypeDone;
      case FeedbackType.hasIssue:
        return l10n.feedbackTypeHasIssue;
    }
  }
}
