// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskModelAdapter extends TypeAdapter<TaskModel> {
  @override
  final int typeId = 0;

  @override
  TaskModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskModel(
      id: fields[0] as String?,
      title: fields[1] as String,
      description: fields[2] as String?,
      priority: fields[3] as TaskPriority,
      status: fields[4] as TaskStatus,
      source: fields[5] as TaskSource,
      createdAt: fields[6] as DateTime?,
      dueAt: fields[7] as DateTime?,
      completedAt: fields[8] as DateTime?,
      feedback: fields[9] as String?,
      feedbackType: fields[10] as FeedbackType?,
      updatedAt: fields[11] as DateTime?,
      completedItems: fields[12] as int,
      totalItems: fields[13] as int,
      projectKey: fields[14] as String?,
      planPath: fields[15] as String?,
      phase: fields[16] as String?,
      backend: fields[17] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TaskModel obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.priority)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.source)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.dueAt)
      ..writeByte(8)
      ..write(obj.completedAt)
      ..writeByte(9)
      ..write(obj.feedback)
      ..writeByte(10)
      ..write(obj.feedbackType)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.completedItems)
      ..writeByte(13)
      ..write(obj.totalItems)
      ..writeByte(14)
      ..write(obj.projectKey)
      ..writeByte(15)
      ..write(obj.planPath)
      ..writeByte(16)
      ..write(obj.phase)
      ..writeByte(17)
      ..write(obj.backend);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
