class Device {
  final int id;
  final String deviceId;
  final String name;
  final bool isOwner;
  final DateTime addedAt;
  DeviceStatus? status;

  Device({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.isOwner,
    required this.addedAt,
    this.status,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'],
      deviceId: json['device_id'],
      name: json['name'],
      isOwner: json['is_owner'] ?? false,
      addedAt: DateTime.parse(json['added_at']),
      status: json['status'] != null
          ? DeviceStatus.fromJson(json['status'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'name': name,
      'is_owner': isOwner,
      'added_at': addedAt.toIso8601String(),
      'status': status?.toJson(),
    };
  }

  Device copyWith({DeviceStatus? status}) {
    return Device(
      id: id,
      deviceId: deviceId,
      name: name,
      isOwner: isOwner,
      addedAt: addedAt,
      status: status ?? this.status,
    );
  }
}

class DeviceStatus {
  final bool online;
  bool relayState;
  final int? wifiRSSI;
  final int? uptime;
  final int? freeHeap;
  final DateTime? lastSeen;
  final double? powerKw;
  final double? energyKwh;
  final DateTime? lastEnergyUpdate;

  DeviceStatus({
    required this.online,
    required this.relayState,
    this.wifiRSSI,
    this.uptime,
    this.freeHeap,
    this.lastSeen,
    this.powerKw,
    this.energyKwh,
    this.lastEnergyUpdate,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      online: json['online'] ?? false,
      relayState: json['relayState'] ?? false,
      wifiRSSI: json['wifiRSSI'],
      uptime: json['uptime'],
      freeHeap: json['freeHeap'],
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'])
          : null,
      powerKw: json['powerKw']?.toDouble(),
      energyKwh: json['energyKwh']?.toDouble(),
      lastEnergyUpdate: json['lastEnergyUpdate'] != null
          ? DateTime.parse(json['lastEnergyUpdate'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'online': online,
      'relayState': relayState,
      'wifiRSSI': wifiRSSI,
      'uptime': uptime,
      'freeHeap': freeHeap,
      'lastSeen': lastSeen?.toIso8601String(),
      'powerKw': powerKw,
      'energyKwh': energyKwh,
      'lastEnergyUpdate': lastEnergyUpdate?.toIso8601String(),
    };
  }
}
