// lib/models/energy_mode.dart
class EnergyMode {
  final String deviceId;
  final String currentMode; // 'solar' або 'grid'
  final DateTime lastChanged;
  final String changedBy; // 'manual', 'schedule', 'default'

  EnergyMode({
    required this.deviceId,
    required this.currentMode,
    required this.lastChanged,
    required this.changedBy,
  });

  factory EnergyMode.fromJson(Map<String, dynamic> json) {
    return EnergyMode(
      deviceId: json['deviceId'],
      currentMode: json['currentMode'],
      lastChanged: DateTime.parse(json['lastChanged']),
      changedBy: json['changedBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'currentMode': currentMode,
      'lastChanged': lastChanged.toIso8601String(),
      'changedBy': changedBy,
    };
  }

  bool get isSolar => currentMode == 'solar';
  bool get isGrid => currentMode == 'grid';

  EnergyMode copyWith({
    String? deviceId,
    String? currentMode,
    DateTime? lastChanged,
    String? changedBy,
  }) {
    return EnergyMode(
      deviceId: deviceId ?? this.deviceId,
      currentMode: currentMode ?? this.currentMode,
      lastChanged: lastChanged ?? this.lastChanged,
      changedBy: changedBy ?? this.changedBy,
    );
  }

  @override
  String toString() {
    return 'EnergyMode(deviceId: $deviceId, currentMode: $currentMode, changedBy: $changedBy)';
  }
}

class EnergyModeHistory {
  final int id;
  final String deviceId;
  final String? fromMode;
  final String toMode;
  final String changedBy;
  final int? scheduleId;
  final String? scheduleName;
  final DateTime timestamp;

  EnergyModeHistory({
    required this.id,
    required this.deviceId,
    this.fromMode,
    required this.toMode,
    required this.changedBy,
    this.scheduleId,
    this.scheduleName,
    required this.timestamp,
  });

  factory EnergyModeHistory.fromJson(Map<String, dynamic> json) {
    return EnergyModeHistory(
      id: json['id'],
      deviceId: json['device_id'],
      fromMode: json['from_mode'],
      toMode: json['to_mode'],
      changedBy: json['changed_by'],
      scheduleId: json['schedule_id'],
      scheduleName: json['schedule_name'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  String get displayText {
    final from = fromMode ?? 'none';
    final source = changedBy == 'schedule' && scheduleName != null
        ? 'розклад "$scheduleName"'
        : changedBy == 'manual'
            ? 'вручну'
            : 'автоматично';
    return '$from → $toMode ($source)';
  }
}
