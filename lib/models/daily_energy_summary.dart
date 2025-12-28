// lib/models/daily_energy_summary.dart
class DailyEnergySummary {
  final String deviceId;
  final DateTime date; // Тільки дата без часу
  final double totalEnergyKwh; // Загальна енергія за день
  final double maxPowerKw; // Максимальна потужність за день
  final double avgPowerKw; // Середня потужність за день
  final int dataPoints; // Кількість точок даних

  DailyEnergySummary({
    required this.deviceId,
    required this.date,
    required this.totalEnergyKwh,
    required this.maxPowerKw,
    required this.avgPowerKw,
    required this.dataPoints,
  });

  factory DailyEnergySummary.fromJson(Map<String, dynamic> json) {
    return DailyEnergySummary(
      deviceId: json['deviceId'],
      date: json['date'] is DateTime
          ? json['date']
          : DateTime.parse(json['date']),
      totalEnergyKwh: (json['totalEnergyKwh'] ?? 0).toDouble(),
      maxPowerKw: (json['maxPowerKw'] ?? 0).toDouble(),
      avgPowerKw: (json['avgPowerKw'] ?? 0).toDouble(),
      dataPoints: json['dataPoints'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'date': date.toIso8601String().split('T')[0], // Тільки дата YYYY-MM-DD
      'totalEnergyKwh': totalEnergyKwh,
      'maxPowerKw': maxPowerKw,
      'avgPowerKw': avgPowerKw,
      'dataPoints': dataPoints,
    };
  }

  // Створення з поточних даних
  static DailyEnergySummary fromEnergyData(
    String deviceId,
    DateTime date,
    List<dynamic> energyData,
  ) {
    if (energyData.isEmpty) {
      return DailyEnergySummary(
        deviceId: deviceId,
        date: date,
        totalEnergyKwh: 0,
        maxPowerKw: 0,
        avgPowerKw: 0,
        dataPoints: 0,
      );
    }

    // Беремо останнє значення енергії (накопичене)
    final lastEnergy = energyData.last['energyKwh']?.toDouble() ?? 0.0;

    // Знаходимо максимальну потужність
    double maxPower = 0.0;
    double sumPower = 0.0;
    int count = 0;

    for (var data in energyData) {
      final power = data['powerKw']?.toDouble() ?? 0.0;
      if (power > maxPower) maxPower = power;
      sumPower += power;
      count++;
    }

    final avgPower = count > 0 ? sumPower / count : 0.0;

    return DailyEnergySummary(
      deviceId: deviceId,
      date: date,
      totalEnergyKwh: lastEnergy,
      maxPowerKw: maxPower,
      avgPowerKw: avgPower,
      dataPoints: count,
    );
  }

  @override
  String toString() {
    return 'DailyEnergySummary(date: ${date.toString().split(' ')[0]}, '
        'energy: ${totalEnergyKwh.toStringAsFixed(2)} kWh, '
        'maxPower: ${maxPowerKw.toStringAsFixed(2)} kW)';
  }
}
