// lib/models/energy_data.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EnergyData {
  final String deviceId;
  final double powerKw;
  final double energyKwh;
  final DateTime timestamp;

  EnergyData({
    required this.deviceId,
    required this.powerKw,
    required this.energyKwh,
    required this.timestamp,
  });

  factory EnergyData.fromJson(Map<String, dynamic> json) {
    return EnergyData(
      deviceId: json['deviceId'],
      powerKw: (json['powerKw'] ?? 0).toDouble(),
      energyKwh: (json['energyKwh'] ?? 0).toDouble(),
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] * 1000)
          : DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'powerKw': powerKw,
      'energyKwh': energyKwh,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

// Клас для управління збереженими даними
class EnergyStorage {
  static const String _storageKey = 'energy_data_';

  static Future<void> saveData(String deviceId, List<EnergyData> data) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = data.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey + deviceId, json.encode(jsonData));
  }

  static Future<List<EnergyData>> loadData(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey + deviceId);
    if (jsonString == null) return [];

    final List<dynamic> jsonData = json.decode(jsonString);
    return jsonData.map((e) => EnergyData.fromJson(e)).toList();
  }

  static Future<void> clearData(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey + deviceId);
  }

  // Додає нові дані та видаляє старі (зберігаємо максимум 30 днів)
  static Future<void> addData(String deviceId, EnergyData newData) async {
    try {
      final existingData = await loadData(deviceId);
      existingData.add(newData);

      // Видаляємо дані старше 30 днів
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      existingData.removeWhere((data) => data.timestamp.isBefore(cutoffDate));

      // Обмежуємо кількість записів до 10000
      if (existingData.length > 10000) {
        existingData.removeRange(0, existingData.length - 10000);
      }

      await saveData(deviceId, existingData);
      print('Energy data saved: ${newData.powerKw} kW at ${newData.timestamp}');
    } catch (e) {
      print('Error adding energy data: $e');
    }
  }
}

// Extension EnergyDataFilter видалено - використовуйте з services/energy_service.dart
