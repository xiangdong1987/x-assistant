// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_enums.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskStatusAdapter extends TypeAdapter<TaskStatus> {
  @override
  final int typeId = 1;

  @override
  TaskStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskStatus.pending;
      case 1:
        return TaskStatus.confirmed;
      case 2:
        return TaskStatus.inProgress;
      case 3:
        return TaskStatus.planned; // was waitingFeedback (legacy)
      case 4:
        return TaskStatus.completed;
      case 5:
        return TaskStatus.cancelled;
      case 6:
        return TaskStatus.failed;
      case 7:
        return TaskStatus.planning;
      case 8:
        return TaskStatus.coding;
      case 9:
        return TaskStatus.testing;
      case 10:
        return TaskStatus.submitting;
      default:
        return TaskStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, TaskStatus obj) {
    switch (obj) {
      case TaskStatus.pending:
        writer.writeByte(0);
        break;
      case TaskStatus.confirmed:
        writer.writeByte(1);
        break;
      case TaskStatus.inProgress:
        writer.writeByte(2);
        break;
      case TaskStatus.planned:
        writer.writeByte(3);
        break;
      case TaskStatus.completed:
        writer.writeByte(4);
        break;
      case TaskStatus.cancelled:
        writer.writeByte(5);
        break;
      case TaskStatus.failed:
        writer.writeByte(6);
        break;
      case TaskStatus.planning:
        writer.writeByte(7);
        break;
      case TaskStatus.coding:
        writer.writeByte(8);
        break;
      case TaskStatus.testing:
        writer.writeByte(9);
        break;
      case TaskStatus.submitting:
        writer.writeByte(10);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TaskPriorityAdapter extends TypeAdapter<TaskPriority> {
  @override
  final int typeId = 2;

  @override
  TaskPriority read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskPriority.p0;
      case 1:
        return TaskPriority.p1;
      case 2:
        return TaskPriority.p2;
      case 3:
        return TaskPriority.p3;
      default:
        return TaskPriority.p0;
    }
  }

  @override
  void write(BinaryWriter writer, TaskPriority obj) {
    switch (obj) {
      case TaskPriority.p0:
        writer.writeByte(0);
        break;
      case TaskPriority.p1:
        writer.writeByte(1);
        break;
      case TaskPriority.p2:
        writer.writeByte(2);
        break;
      case TaskPriority.p3:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskPriorityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TaskSourceAdapter extends TypeAdapter<TaskSource> {
  @override
  final int typeId = 3;

  @override
  TaskSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TaskSource.manual;
      case 1:
        return TaskSource.openClaw;
      case 2:
        return TaskSource.cursor;
      case 3:
        return TaskSource.skill;
      default:
        return TaskSource.manual;
    }
  }

  @override
  void write(BinaryWriter writer, TaskSource obj) {
    switch (obj) {
      case TaskSource.manual:
        writer.writeByte(0);
        break;
      case TaskSource.openClaw:
        writer.writeByte(1);
        break;
      case TaskSource.cursor:
        writer.writeByte(2);
        break;
      case TaskSource.skill:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FeedbackTypeAdapter extends TypeAdapter<FeedbackType> {
  @override
  final int typeId = 4;

  @override
  FeedbackType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FeedbackType.done;
      case 1:
        return FeedbackType.hasIssue;
      default:
        return FeedbackType.done;
    }
  }

  @override
  void write(BinaryWriter writer, FeedbackType obj) {
    switch (obj) {
      case FeedbackType.done:
        writer.writeByte(0);
        break;
      case FeedbackType.hasIssue:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
