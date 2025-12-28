// lib/models/energy_schedule.dart
// ОНОВЛЕНО: Підтримка TIME та RANGE розкладів

class EnergySchedule {
  final int? id;
  final String deviceId;
  final int userId;
  final String name;
  final String targetMode; // 'solar' або 'grid'

  // Тип розкладу: 'time' або 'range'
  final String scheduleType;

  // Для TIME розкладу (конкретний час)
  final int? hour;
  final int? minute;

  // Для RANGE розкладу (діапазон часу)
  final int? startHour;
  final int? startMinute;
  final int? endHour;
  final int? endMinute;
  final String? secondaryMode; // Режим поза діапазоном

  // Загальні поля
  final String repeatType; // 'once', 'daily', 'weekly', 'weekdays', 'weekends'
  final List<int>? repeatDays; // 0-6 (неділя-субота) для weekly
  final bool isEnabled;
  final DateTime? lastExecuted;
  final DateTime? nextExecution;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EnergySchedule({
    this.id,
    required this.deviceId,
    required this.userId,
    required this.name,
    required this.targetMode,
    this.scheduleType = 'time',
    // TIME fields
    this.hour,
    this.minute,
    // RANGE fields
    this.startHour,
    this.startMinute,
    this.endHour,
    this.endMinute,
    this.secondaryMode,
    // Common fields
    required this.repeatType,
    this.repeatDays,
    required this.isEnabled,
    this.lastExecuted,
    this.nextExecution,
    this.createdAt,
    this.updatedAt,
  });

  // Перевірка типу розкладу
  bool get isTimeSchedule => scheduleType == 'time';
  bool get isRangeSchedule => scheduleType == 'range';

  factory EnergySchedule.fromJson(Map<String, dynamic> json) {
    return EnergySchedule(
      id: json['id'],
      deviceId: json['device_id'],
      userId: json['user_id'],
      name: json['name'],
      targetMode: json['target_mode'],
      scheduleType: json['schedule_type'] ?? 'time',
      // TIME fields
      hour: json['hour'],
      minute: json['minute'],
      // RANGE fields
      startHour: json['start_hour'],
      startMinute: json['start_minute'],
      endHour: json['end_hour'],
      endMinute: json['end_minute'],
      secondaryMode: json['secondary_mode'],
      // Common fields
      repeatType: json['repeat_type'],
      repeatDays: json['repeat_days'] != null
          ? List<int>.from(json['repeat_days'])
          : null,
      isEnabled: json['is_enabled'] ?? true,
      lastExecuted: json['last_executed'] != null
          ? DateTime.parse(json['last_executed'])
          : null,
      nextExecution: json['next_execution'] != null
          ? DateTime.parse(json['next_execution'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'device_id': deviceId,
      'user_id': userId,
      'name': name,
      'target_mode': targetMode,
      'schedule_type': scheduleType,
      // TIME fields
      if (hour != null) 'hour': hour,
      if (minute != null) 'minute': minute,
      // RANGE fields
      if (startHour != null) 'start_hour': startHour,
      if (startMinute != null) 'start_minute': startMinute,
      if (endHour != null) 'end_hour': endHour,
      if (endMinute != null) 'end_minute': endMinute,
      if (secondaryMode != null) 'secondary_mode': secondaryMode,
      // Common fields
      'repeat_type': repeatType,
      if (repeatDays != null) 'repeat_days': repeatDays,
      'is_enabled': isEnabled,
      if (lastExecuted != null)
        'last_executed': lastExecuted!.toIso8601String(),
      if (nextExecution != null)
        'next_execution': nextExecution!.toIso8601String(),
    };
  }

  // Для створення/оновлення через API
  Map<String, dynamic> toApiJson() {
    final Map<String, dynamic> data = {
      'name': name,
      'targetMode': targetMode,
      'scheduleType': scheduleType,
      'repeatType': repeatType,
      'isEnabled': isEnabled,
    };

    if (scheduleType == 'time') {
      data['hour'] = hour;
      data['minute'] = minute;
    } else if (scheduleType == 'range') {
      data['startHour'] = startHour;
      data['startMinute'] = startMinute;
      data['endHour'] = endHour;
      data['endMinute'] = endMinute;
      if (secondaryMode != null) {
        data['secondaryMode'] = secondaryMode;
      }
    }

    if (repeatDays != null) {
      data['repeatDays'] = repeatDays;
    }

    return data;
  }

  // Рядок часу для TIME розкладу
  String get timeString {
    if (isTimeSchedule && hour != null && minute != null) {
      final h = hour!.toString().padLeft(2, '0');
      final m = minute!.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '';
  }

  // Рядок діапазону для RANGE розкладу
  String get rangeString {
    if (isRangeSchedule &&
        startHour != null &&
        startMinute != null &&
        endHour != null &&
        endMinute != null) {
      final sh = startHour!.toString().padLeft(2, '0');
      final sm = startMinute!.toString().padLeft(2, '0');
      final eh = endHour!.toString().padLeft(2, '0');
      final em = endMinute!.toString().padLeft(2, '0');
      return '$sh:$sm - $eh:$em';
    }
    return '';
  }

  // Повний опис розкладу
  String get scheduleDescription {
    if (isTimeSchedule) {
      return 'О $timeString → $targetModeDisplay';
    } else {
      final effectiveSecondary =
          secondaryMode ?? (targetMode == 'solar' ? 'grid' : 'solar');
      final secondaryDisplay =
          effectiveSecondary == 'solar' ? 'Сонячна' : 'Міська';
      return '$rangeString → $targetModeDisplay, інакше $secondaryDisplay';
    }
  }

  String get repeatTypeDisplay {
    switch (repeatType) {
      case 'once':
        return 'Одноразово';
      case 'daily':
        return 'Щодня';
      case 'weekly':
        return 'Щотижня';
      case 'weekdays':
        return 'Пн-Пт';
      case 'weekends':
        return 'Сб-Нд';
      default:
        return repeatType;
    }
  }

  String get weekDaysDisplay {
    if (repeatDays == null || repeatDays!.isEmpty) return '';

    final dayNames = ['Нд', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
    return repeatDays!.map((day) => dayNames[day]).join(', ');
  }

  String get targetModeDisplay {
    return targetMode == 'solar' ? 'Сонячна' : 'Міська';
  }

  String get secondaryModeDisplay {
    if (secondaryMode == null) {
      // Автоматичний протилежний режим
      return targetMode == 'solar' ? 'Міська' : 'Сонячна';
    }
    return secondaryMode == 'solar' ? 'Сонячна' : 'Міська';
  }

  String get targetModeIcon {
    return targetMode == 'solar' ? '☀️' : '🏙️';
  }

  String get scheduleTypeDisplay {
    return isTimeSchedule ? 'Конкретний час' : 'Діапазон часу';
  }

  bool get isSolar => targetMode == 'solar';
  bool get isGrid => targetMode == 'grid';

  EnergySchedule copyWith({
    int? id,
    String? deviceId,
    int? userId,
    String? name,
    String? targetMode,
    String? scheduleType,
    int? hour,
    int? minute,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    String? secondaryMode,
    String? repeatType,
    List<int>? repeatDays,
    bool? isEnabled,
    DateTime? lastExecuted,
    DateTime? nextExecution,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EnergySchedule(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      targetMode: targetMode ?? this.targetMode,
      scheduleType: scheduleType ?? this.scheduleType,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      secondaryMode: secondaryMode ?? this.secondaryMode,
      repeatType: repeatType ?? this.repeatType,
      repeatDays: repeatDays ?? this.repeatDays,
      isEnabled: isEnabled ?? this.isEnabled,
      lastExecuted: lastExecuted ?? this.lastExecuted,
      nextExecution: nextExecution ?? this.nextExecution,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    if (isTimeSchedule) {
      return 'EnergySchedule(id: $id, name: $name, type: TIME, time: $timeString, mode: $targetMode, repeat: $repeatType, enabled: $isEnabled)';
    } else {
      return 'EnergySchedule(id: $id, name: $name, type: RANGE, range: $rangeString, mode: $targetMode/$secondaryMode, repeat: $repeatType, enabled: $isEnabled)';
    }
  }
}

// Enum для типів повторення
enum ScheduleRepeatType {
  once('once', 'Одноразово'),
  daily('daily', 'Щодня'),
  weekly('weekly', 'Щотижня (вибрані дні)'),
  weekdays('weekdays', 'Будні дні (Пн-Пт)'),
  weekends('weekends', 'Вихідні (Сб-Нд)');

  final String value;
  final String displayName;

  const ScheduleRepeatType(this.value, this.displayName);

  static ScheduleRepeatType fromString(String value) {
    return ScheduleRepeatType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => ScheduleRepeatType.once,
    );
  }
}

// Enum для типів розкладу
enum ScheduleType {
  time('time', 'Конкретний час', 'Перемикання в заданий час'),
  range('range', 'Діапазон часу', 'Один режим в діапазоні, інший - поза ним');

  final String value;
  final String displayName;
  final String description;

  const ScheduleType(this.value, this.displayName, this.description);

  static ScheduleType fromString(String value) {
    return ScheduleType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => ScheduleType.time,
    );
  }
}
