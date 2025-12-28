// lib/services/energy_service.dart - З ДЕННОЮ СТАТИСТИКОЮ
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/energy_data.dart';
import '../models/daily_energy_summary.dart';
import '../services/api_service.dart';

class EnergyService {
  static final EnergyService _instance = EnergyService._internal();
  factory EnergyService() => _instance;
  EnergyService._internal() {
    _startMidnightChecker();
  }

  final ApiService _apiService = ApiService();

  // Кеш для поточних даних
  final Map<String, List<EnergyData>> _cache = {};
  final Map<String, DateTime> _lastFetch = {};
  final Map<String, DateTime> _lastMidnightReset = {};

  // НОВИЙ: Кеш для денної статистики (зберігається назавжди)
  final Map<String, List<DailyEnergySummary>> _dailyHistory = {};

  final Map<String, bool> _isSyncing = {};

  Timer? _midnightTimer;

  final StreamController<String> _midnightResetController =
      StreamController<String>.broadcast();

  Stream<String> get midnightResetStream => _midnightResetController.stream;

  void _startMidnightChecker() {
    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkMidnight();
    });
    print('✅ EnergyService: Midnight checker started');
  }

  Future<void> _checkMidnight() async {
    final now = DateTime.now();

    if (now.hour == 0 && now.minute < 5) {
      final today = DateTime(now.year, now.month, now.day);

      for (String deviceId in _cache.keys.toList()) {
        final lastReset = _lastMidnightReset[deviceId];

        if (lastReset == null || lastReset.isBefore(today)) {
          print('🕛 EnergyService: AUTO Midnight reset for $deviceId');
          await performMidnightReset(deviceId, isAutomatic: true);
        }
      }
    }
  }

  // === ГОЛОВНА ФУНКЦІЯ MIDNIGHT RESET З ЗБЕРЕЖЕННЯМ СТАТИСТИКИ ===
  Future<void> performMidnightReset(String deviceId,
      {bool isAutomatic = false}) async {
    try {
      print(
          '🕛 ${isAutomatic ? "AUTO" : "MANUAL"} Midnight reset starting for $deviceId...');

      // 1. ЗБЕРІГАЄМО ДЕННУ СТАТИСТИКУ перед очищенням
      await _saveDailySummary(deviceId);

      // 2. Очищуємо кеш поточного дня
      _cache.remove(deviceId);
      _lastFetch.remove(deviceId);

      // 3. Очищуємо локальне сховище поточного дня
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('energy_$deviceId');
      await prefs.remove('energy_last_fetch_$deviceId');

      // 4. Відправляємо команду на сервер
      try {
        final success = await _apiService.clearEnergyData(null, deviceId);
        if (success) {
          print('✅ Server database cleared for $deviceId');
        }
      } catch (e) {
        print('⚠️ Could not clear server data: $e');
      }

      // 5. Відправляємо команду на ESP32
      _midnightResetController.add(deviceId);

      // 6. Позначаємо час останнього reset
      _lastMidnightReset[deviceId] = DateTime.now();
      await prefs.setString(
          'energy_last_reset_$deviceId', DateTime.now().toIso8601String());

      print(
          '✅ Midnight reset completed for $deviceId (${isAutomatic ? "automatic" : "manual"})');
      print('📊 Daily summary saved, ready for new day data collection');
    } catch (e) {
      print('❌ Error during midnight reset for $deviceId: $e');
      rethrow;
    }
  }

  // === ЗБЕРЕЖЕННЯ ДЕННОЇ СТАТИСТИКИ ===
  Future<void> _saveDailySummary(String deviceId) async {
    try {
      final currentData = _cache[deviceId] ?? [];

      if (currentData.isEmpty) {
        print('ℹ️ No data to save for daily summary');
        return;
      }

      // Дата вчорашнього дня (бо зараз 00:00 нового дня)
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final date = DateTime(yesterday.year, yesterday.month, yesterday.day);

      // Створюємо статистику
      final summary = _createDailySummary(deviceId, date, currentData);

      // Завантажуємо існуючу історію
      await _loadDailyHistory(deviceId);

      // Додаємо нову статистику
      if (!_dailyHistory.containsKey(deviceId)) {
        _dailyHistory[deviceId] = [];
      }

      // Перевіряємо чи вже є запис за цю дату
      _dailyHistory[deviceId]!
          .removeWhere((s) => _isSameDay(s.date, summary.date));
      _dailyHistory[deviceId]!.add(summary);

      // Сортуємо за датою
      _dailyHistory[deviceId]!.sort((a, b) => a.date.compareTo(b.date));

      // Зберігаємо локально
      await _saveDailyHistoryToStorage(deviceId);

      // Відправляємо на сервер
      await _sendDailySummaryToServer(deviceId, summary);

      print(
          '💾 Daily summary saved: ${summary.totalEnergyKwh.toStringAsFixed(2)} kWh for ${date.toString().split(' ')[0]}');
    } catch (e) {
      print('❌ Error saving daily summary: $e');
    }
  }

  DailyEnergySummary _createDailySummary(
      String deviceId, DateTime date, List<EnergyData> data) {
    if (data.isEmpty) {
      return DailyEnergySummary(
        deviceId: deviceId,
        date: date,
        totalEnergyKwh: 0,
        maxPowerKw: 0,
        avgPowerKw: 0,
        dataPoints: 0,
      );
    }

    // Беремо останнє накопичене значення
    final totalEnergy = data.last.energyKwh;

    // Знаходимо максимальну та середню потужність
    double maxPower = 0.0;
    double sumPower = 0.0;

    for (var item in data) {
      if (item.powerKw > maxPower) maxPower = item.powerKw;
      sumPower += item.powerKw;
    }

    final avgPower = data.isNotEmpty ? sumPower / data.length : 0.0;

    return DailyEnergySummary(
      deviceId: deviceId,
      date: date,
      totalEnergyKwh: totalEnergy,
      maxPowerKw: maxPower,
      avgPowerKw: avgPower,
      dataPoints: data.length,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _saveDailyHistoryToStorage(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = _dailyHistory[deviceId] ?? [];

      final jsonList = history.map((e) => e.toJson()).toList();
      await prefs.setString('daily_history_$deviceId', json.encode(jsonList));

      print('💾 Saved ${history.length} daily records to local storage');
    } catch (e) {
      print('❌ Error saving daily history locally: $e');
    }
  }

  Future<void> _loadDailyHistory(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('daily_history_$deviceId');

      if (jsonString != null && jsonString.isNotEmpty) {
        final jsonList = json.decode(jsonString) as List;
        _dailyHistory[deviceId] =
            jsonList.map((e) => DailyEnergySummary.fromJson(e)).toList();

        print(
            '📚 Loaded ${_dailyHistory[deviceId]!.length} daily records from storage');
      } else {
        _dailyHistory[deviceId] = [];
      }
    } catch (e) {
      print('❌ Error loading daily history: $e');
      _dailyHistory[deviceId] = [];
    }
  }

  Future<void> _sendDailySummaryToServer(
      String deviceId, DailyEnergySummary summary) async {
    try {
      // Відправляємо на сервер (якщо є endpoint)
      await _apiService.saveDailySummary(null, deviceId, summary);
      print('📤 Daily summary sent to server');
    } catch (e) {
      print('⚠️ Could not send daily summary to server: $e');
      // Не критично - збережено локально
    }
  }

  // === ОТРИМАННЯ ДЕННОЇ ІСТОРІЇ ===
  Future<List<DailyEnergySummary>> getDailyHistory(String deviceId) async {
    await _loadDailyHistory(deviceId);
    return _dailyHistory[deviceId] ?? [];
  }

  // === ТЕСТОВА ФУНКЦІЯ ===
  Future<void> testMidnightReset(String deviceId) async {
    print('🧪 TEST: Simulating midnight reset for $deviceId');
    await performMidnightReset(deviceId, isAutomatic: false);
  }

  // === ОБРОБКА SERVER RESET ===
  Future<void> handleServerReset(String deviceId) async {
    print('🔄 EnergyService: Handling server reset for $deviceId');
    await performMidnightReset(deviceId, isAutomatic: false);
  }

  // === ДОДАВАННЯ MQTT ДАНИХ ===
  Future<void> addEnergyData(String deviceId, EnergyData data) async {
    try {
      if (_cache.containsKey(deviceId) && _cache[deviceId]!.isNotEmpty) {
        final lastData = _cache[deviceId]!.last;

        if (data.energyKwh < lastData.energyKwh * 0.5) {
          print(
              '🔄 Detected energy reset - clearing cache before adding new data');
          await performMidnightReset(deviceId, isAutomatic: false);
        }

        final timeDiff = data.timestamp.difference(lastData.timestamp);
        if (timeDiff.inHours > 6) {
          print('🕕 Large time gap detected - clearing cache');
          await performMidnightReset(deviceId, isAutomatic: false);
        }
      }

      if (!_cache.containsKey(deviceId)) {
        await _loadFromLocalStorage(deviceId);
        if (!_cache.containsKey(deviceId)) {
          _cache[deviceId] = [];
        }
      }

      _cache[deviceId]!.add(data);
      _cache[deviceId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      await _saveToLocalStorage(deviceId);
      _sendToAPI(deviceId, data);

      if (_cache[deviceId]!.length > 10000) {
        _cleanOldData(deviceId);
      }
    } catch (e) {
      print('EnergyService: Error adding MQTT data: $e');
    }
  }

  // === ОТРИМАННЯ ДАНИХ ===
  Future<List<EnergyData>> getEnergyData(String deviceId,
      {String period = '24h'}) async {
    try {
      if (!_cache.containsKey(deviceId)) {
        await _loadFromLocalStorage(deviceId);
      }

      if (_shouldFetchFromAPI(deviceId)) {
        _fetchFromAPI(deviceId, period);
      }

      final allData = _cache[deviceId] ?? [];
      final filteredData = _filterByPeriod(allData, period);

      return filteredData;
    } catch (e) {
      print('EnergyService: Error getting data: $e');
      return _filterByPeriod(_cache[deviceId] ?? [], period);
    }
  }

  // === ОЧИЩЕННЯ ДАНИХ ===
  Future<void> clearData(String deviceId) async {
    try {
      await performMidnightReset(deviceId, isAutomatic: false);
      print('EnergyService: Manual clear completed for $deviceId');
    } catch (e) {
      print('EnergyService: Error clearing data: $e');
    }
  }

  // === ГЕНЕРАЦІЯ ТЕСТОВИХ ДАНИХ ===
  Future<void> generateTestData(String deviceId) async {
    await clearData(deviceId);

    final now = DateTime.now();
    double totalEnergy = 0.0;

    const totalPoints = 5760;

    for (int i = 0; i < totalPoints; i++) {
      final timestamp =
          now.subtract(Duration(seconds: (totalPoints - i - 1) * 15));
      final hour = timestamp.hour;

      double power;
      if (hour >= 6 && hour < 18) {
        power = 1.5 + 2.0 * (1 - (hour - 12).abs() / 6) + (i % 20) * 0.05;
      } else {
        power = 0.05 + (i % 10) * 0.01;
      }

      totalEnergy += power * (15.0 / 3600.0);

      final energyData = EnergyData(
        deviceId: deviceId,
        powerKw: double.parse(power.toStringAsFixed(3)),
        energyKwh: double.parse(totalEnergy.toStringAsFixed(3)),
        timestamp: timestamp,
      );

      await addEnergyData(deviceId, energyData);

      if (i % 100 == 0) {
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }

    print('EnergyService: Generated test data');
  }

  // === ПРИВАТНІ МЕТОДИ ===

  bool _shouldFetchFromAPI(String deviceId) {
    final lastFetch = _lastFetch[deviceId];
    if (lastFetch == null) return true;
    return DateTime.now().difference(lastFetch).inSeconds > 5;
  }

  Future<void> _fetchFromAPI(String deviceId, String period) async {
    if (_isSyncing[deviceId] == true) return;

    try {
      _isSyncing[deviceId] = true;

      final apiData =
          await _apiService.getEnergyData(null, deviceId, period: period);

      if (apiData.isNotEmpty) {
        final existingData = _cache[deviceId] ?? [];

        if (existingData.isNotEmpty && apiData.isNotEmpty) {
          final lastLocal = existingData.last.energyKwh;
          final firstApi = apiData.first.energyKwh;

          if (firstApi < lastLocal * 0.5) {
            _cache[deviceId] = apiData;
          } else {
            final combinedData = <EnergyData>[];
            combinedData.addAll(existingData);

            for (final api in apiData) {
              final isDuplicate = existingData.any((local) =>
                  local.timestamp.difference(api.timestamp).inSeconds.abs() <
                  10);
              if (!isDuplicate) {
                combinedData.add(api);
              }
            }

            combinedData.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            _cache[deviceId] = combinedData;
          }
        } else {
          _cache[deviceId] = apiData;
        }

        await _saveToLocalStorage(deviceId);
        _lastFetch[deviceId] = DateTime.now();
      } else {
        _lastFetch[deviceId] = DateTime.now();
      }
    } catch (e) {
      print('EnergyService: API sync error: $e');
    } finally {
      _isSyncing[deviceId] = false;
    }
  }

  Future<void> _sendToAPI(String deviceId, EnergyData data) async {
    try {
      _apiService.addEnergyData(null, deviceId, data).catchError((error) {
        // Ігноруємо помилки
      });
    } catch (e) {
      // Не кидаємо помилку
    }
  }

  List<EnergyData> _filterByPeriod(List<EnergyData> data, String period) {
    final now = DateTime.now();

    switch (period) {
      case '1h':
        return data
            .where((d) => now.difference(d.timestamp).inHours <= 1)
            .toList();
      case '6h':
        return data
            .where((d) => now.difference(d.timestamp).inHours <= 6)
            .toList();
      case '24h':
        return data
            .where((d) => now.difference(d.timestamp).inHours <= 24)
            .toList();
      case '7d':
        return data
            .where((d) => now.difference(d.timestamp).inDays <= 7)
            .toList();
      case '30d':
        return data
            .where((d) => now.difference(d.timestamp).inDays <= 30)
            .toList();
      case 'all':
        return data;
      default:
        return data
            .where((d) => now.difference(d.timestamp).inHours <= 24)
            .toList();
    }
  }

  void _cleanOldData(String deviceId) {
    if (!_cache.containsKey(deviceId)) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final originalCount = _cache[deviceId]!.length;

    _cache[deviceId]!
        .removeWhere((data) => data.timestamp.isBefore(startOfDay));

    if (_cache[deviceId]!.length < originalCount) {
      print('EnergyService: Cleaned old records');
    }
  }

  Future<void> _saveToLocalStorage(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _cache[deviceId] ?? [];

      if (data.isEmpty) return;

      final jsonList = data.map((e) => e.toJson()).toList();
      await prefs.setString('energy_$deviceId', json.encode(jsonList));

      final lastFetch = _lastFetch[deviceId];
      if (lastFetch != null) {
        await prefs.setString(
            'energy_last_fetch_$deviceId', lastFetch.toIso8601String());
      }

      final lastReset = _lastMidnightReset[deviceId];
      if (lastReset != null) {
        await prefs.setString(
            'energy_last_reset_$deviceId', lastReset.toIso8601String());
      }
    } catch (e) {
      print('EnergyService: Error saving locally: $e');
    }
  }

  Future<void> _loadFromLocalStorage(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('energy_$deviceId');

      if (jsonString != null && jsonString.isNotEmpty) {
        final jsonList = json.decode(jsonString) as List;
        _cache[deviceId] = jsonList.map((e) => EnergyData.fromJson(e)).toList();
        _cache[deviceId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        final lastFetchString = prefs.getString('energy_last_fetch_$deviceId');
        if (lastFetchString != null) {
          _lastFetch[deviceId] = DateTime.parse(lastFetchString);
        }

        final lastResetString = prefs.getString('energy_last_reset_$deviceId');
        if (lastResetString != null) {
          _lastMidnightReset[deviceId] = DateTime.parse(lastResetString);
        }
      } else {
        _cache[deviceId] = [];
      }
    } catch (e) {
      print('EnergyService: Error loading from local storage: $e');
      _cache[deviceId] = [];
    }
  }

  // === ГЕТТЕРИ ===
  int getCacheSize(String deviceId) {
    return _cache[deviceId]?.length ?? 0;
  }

  DateTime? getLastFetchTime(String deviceId) {
    return _lastFetch[deviceId];
  }

  DateTime? getLastResetTime(String deviceId) {
    return _lastMidnightReset[deviceId];
  }

  bool isSyncing(String deviceId) {
    return _isSyncing[deviceId] ?? false;
  }

  Future<void> syncWithServer(String deviceId) async {
    try {
      await _fetchFromAPI(deviceId, 'all');
    } catch (e) {
      print('EnergyService: Full sync error: $e');
      rethrow;
    }
  }

  void dispose() {
    _midnightTimer?.cancel();
    _midnightResetController.close();
    print('EnergyService: Disposed');
  }
}
