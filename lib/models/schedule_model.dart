class ScheduleStatus {
  static const scheduled = 'scheduled';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static List<String> allowedTransitions(String current) {
    switch (current) {
      case scheduled:
        return [inProgress, cancelled];
      case inProgress:
        return [completed, cancelled];
      default:
        return [];
    }
  }
}

class ScheduleItem {
  final int id;
  final String sourceKey;
  final String externalId;
  final String? externalVersion;
  final String domain; // dev, work_other, life
  final String? projectKey;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime? endTime;
  final bool allDay;
  final String status; // scheduled, cancelled, completed
  final String type; // meeting, deadline, social, etc.
  final List<String> tags;
  final List<AgendaLinkedTask>? linkedTasks;

  ScheduleItem({
    required this.id,
    required this.sourceKey,
    required this.externalId,
    this.externalVersion,
    required this.domain,
    this.projectKey,
    required this.title,
    this.description,
    required this.startTime,
    this.endTime,
    this.allDay = false,
    required this.status,
    required this.type,
    this.tags = const [],
    this.linkedTasks,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      id: json['id'] as int? ?? 0,
      sourceKey: json['sourceKey'] as String? ?? 'openclaw',
      externalId: json['externalId'] as String? ?? '',
      externalVersion: json['externalVersion'] as String?,
      domain: json['domain'] as String? ?? 'dev',
      projectKey: json['projectKey'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      allDay: json['allDay'] as bool? ?? false,
      status: json['status'] as String? ?? 'scheduled',
      type: json['type'] as String? ?? 'event',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      linkedTasks: (json['linkedTasks'] as List<dynamic>?)
          ?.map((e) => AgendaLinkedTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AgendaLinkedTask {
  final String taskId;
  final String status;
  final String title;

  AgendaLinkedTask({
    required this.taskId,
    required this.status,
    required this.title,
  });

  factory AgendaLinkedTask.fromJson(Map<String, dynamic> json) {
    return AgendaLinkedTask(
      taskId: json['taskId'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      title: json['title'] as String? ?? '',
    );
  }
}

class AgendaItem {
  final DateTime? time;
  final DateTime? endTime;
  final String title;
  final String? description;
  final String? projectKey;
  final String domain;
  final String type; // event or task
  final String? eventType;
  final String? scheduleItemId;
  final String? taskId;
  final String? status;
  final List<AgendaLinkedTask>? linkedTasks;

  AgendaItem({
    this.time,
    this.endTime,
    required this.title,
    this.description,
    this.projectKey,
    this.domain = 'dev',
    required this.type,
    this.eventType,
    this.scheduleItemId,
    this.taskId,
    this.status,
    this.linkedTasks,
  });

  factory AgendaItem.fromJson(Map<String, dynamic> json) {
    return AgendaItem(
      time: json['time'] != null ? DateTime.parse(json['time'] as String) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      projectKey: json['projectKey'] as String?,
      domain: json['domain'] as String? ?? 'dev',
      type: json['type'] as String? ?? 'event',
      eventType: json['eventType'] as String?,
      scheduleItemId: json['scheduleItemId']?.toString(),
      taskId: json['taskId'] as String?,
      status: json['status'] as String?,
      linkedTasks: (json['linkedTasks'] as List<dynamic>?)
          ?.map((e) => AgendaLinkedTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
