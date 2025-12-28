// lib/providers/energy_provider.dart
import 'package:flutter/foundation.dart';
import '../models/energy_mode.dart';
import '../models/energy_schedule.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class EnergyProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  AuthProvider? _authProvider;

  // Поточні режими для кожного пристрою
  final Map<String, EnergyMode> _energyModes = {};

  // Розклади для кожного пристрою
  final Map<String, List<EnergySchedule>> _schedules = {};

  // Історія для кожного пристрою
  final Map<String, List<EnergyModeHistory>> _history = {};

  bool _isLoading = false;
  String? _error;

  // Getters
  Map<String, EnergyMode> get energyModes => _energyModes;
  Map<String, List<EnergySchedule>> get schedules => _schedules;
  Map<String, List<EnergyModeHistory>> get history => _history;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Отримання режиму для конкретного пристрою
  EnergyMode? getEnergyMode(String deviceId) {
    return _energyModes[deviceId];
  }

  // Отримання розкладів для конкретного пристрою
  List<EnergySchedule> getSchedules(String deviceId) {
    return _schedules[deviceId] ?? [];
  }

  // Отримання історії для конкретного пристрою
  List<EnergyModeHistory> getHistory(String deviceId) {
    return _history[deviceId] ?? [];
  }

  void updateAuth(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  // ============ ENERGY MODE METHODS ============

  // Завантаження поточного режиму
  Future<void> loadEnergyMode(String deviceId) async {
    if (_authProvider?.token == null) {
      debugPrint('EnergyProvider: No token available');
      return;
    }

    try {
      debugPrint('EnergyProvider: Loading energy mode for $deviceId');

      final mode = await _apiService.getEnergyMode(
        _authProvider!.token,
        deviceId,
      );

      if (mode != null) {
        _energyModes[deviceId] = mode;
        debugPrint(
            'EnergyProvider: ✅ Loaded mode: ${mode.currentMode} (changed by: ${mode.changedBy})');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error loading energy mode: $e');
      _error = 'Помилка завантаження режиму енергії';
      notifyListeners();
    }
  }

  // Зміна режиму енергії (ручна)
  Future<bool> setEnergyMode(String deviceId, String mode) async {
    if (_authProvider?.token == null) {
      debugPrint('EnergyProvider: No token available');
      return false;
    }

    try {
      debugPrint('EnergyProvider: Setting energy mode for $deviceId → $mode');

      _isLoading = true;
      _error = null;
      notifyListeners();

      // ОПТИМІСТИЧНЕ ОНОВЛЕННЯ UI
      final oldMode = _energyModes[deviceId];
      _energyModes[deviceId] = EnergyMode(
        deviceId: deviceId,
        currentMode: mode,
        lastChanged: DateTime.now(),
        changedBy: 'manual',
      );
      notifyListeners();

      final success = await _apiService.setEnergyMode(
        _authProvider!.token,
        deviceId,
        mode,
      );

      if (success) {
        debugPrint('EnergyProvider: ✅ Energy mode changed successfully');

        // Перезавантажуємо актуальний стан з сервера
        await loadEnergyMode(deviceId);

        return true;
      } else {
        debugPrint('EnergyProvider: ❌ Failed to change energy mode');

        // Повертаємо старий режим якщо помилка
        if (oldMode != null) {
          _energyModes[deviceId] = oldMode;
        }

        _error = 'Не вдалося змінити режим';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error setting energy mode: $e');

      // Перезавантажуємо з сервера при помилці
      await loadEnergyMode(deviceId);

      _error = 'Помилка зміни режиму';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Завантаження історії перемикань
  Future<void> loadEnergyModeHistory(String deviceId, {int limit = 50}) async {
    if (_authProvider?.token == null) return;

    try {
      debugPrint('EnergyProvider: Loading energy mode history for $deviceId');

      final historyList = await _apiService.getEnergyModeHistory(
        _authProvider!.token,
        deviceId,
        limit: limit,
      );

      _history[deviceId] = historyList;
      debugPrint(
          'EnergyProvider: ✅ Loaded ${historyList.length} history records');
      notifyListeners();
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error loading history: $e');
    }
  }

  // ============ SCHEDULES METHODS ============

  // Завантаження розкладів
  Future<void> loadSchedules(String deviceId) async {
    if (_authProvider?.token == null) return;

    try {
      debugPrint('EnergyProvider: Loading schedules for $deviceId');

      final schedulesList = await _apiService.getEnergySchedules(
        _authProvider!.token,
        deviceId,
      );

      _schedules[deviceId] = schedulesList;
      debugPrint('EnergyProvider: ✅ Loaded ${schedulesList.length} schedules');
      notifyListeners();
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error loading schedules: $e');
      _error = 'Помилка завантаження розкладів';
      notifyListeners();
    }
  }

  // Створення нового розкладу
  Future<bool> createSchedule(String deviceId, EnergySchedule schedule) async {
    if (_authProvider?.token == null) return false;

    try {
      debugPrint('EnergyProvider: Creating schedule for $deviceId');

      _isLoading = true;
      _error = null;
      notifyListeners();

      final createdSchedule = await _apiService.createEnergySchedule(
        _authProvider!.token,
        deviceId,
        schedule,
      );

      if (createdSchedule != null) {
        debugPrint('EnergyProvider: ✅ Schedule created');

        // Перезавантажуємо список розкладів
        await loadSchedules(deviceId);

        return true;
      } else {
        debugPrint('EnergyProvider: ❌ Failed to create schedule');
        _error = 'Не вдалося створити розклад';
        return false;
      }
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error creating schedule: $e');
      _error = 'Помилка створення розкладу';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Оновлення розкладу
  Future<bool> updateSchedule(
    String deviceId,
    int scheduleId,
    EnergySchedule schedule,
  ) async {
    if (_authProvider?.token == null) return false;

    try {
      debugPrint('EnergyProvider: Updating schedule $scheduleId');

      _isLoading = true;
      _error = null;
      notifyListeners();

      final updatedSchedule = await _apiService.updateEnergySchedule(
        _authProvider!.token,
        deviceId,
        scheduleId,
        schedule,
      );

      if (updatedSchedule != null) {
        debugPrint('EnergyProvider: ✅ Schedule updated');

        // Перезавантажуємо список розкладів
        await loadSchedules(deviceId);

        return true;
      } else {
        debugPrint('EnergyProvider: ❌ Failed to update schedule');
        _error = 'Не вдалося оновити розклад';
        return false;
      }
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error updating schedule: $e');
      _error = 'Помилка оновлення розкладу';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Видалення розкладу
  Future<bool> deleteSchedule(String deviceId, int scheduleId) async {
    if (_authProvider?.token == null) return false;

    try {
      debugPrint('EnergyProvider: Deleting schedule $scheduleId');

      _isLoading = true;
      _error = null;
      notifyListeners();

      final success = await _apiService.deleteEnergySchedule(
        _authProvider!.token,
        deviceId,
        scheduleId,
      );

      if (success) {
        debugPrint('EnergyProvider: ✅ Schedule deleted');

        // Видаляємо з локального списку
        if (_schedules.containsKey(deviceId)) {
          _schedules[deviceId]!
              .removeWhere((schedule) => schedule.id == scheduleId);
        }

        notifyListeners();
        return true;
      } else {
        debugPrint('EnergyProvider: ❌ Failed to delete schedule');
        _error = 'Не вдалося видалити розклад';
        return false;
      }
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error deleting schedule: $e');
      _error = 'Помилка видалення розкладу';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Вимкнення/увімкнення розкладу
  Future<bool> toggleSchedule(
      String deviceId, int scheduleId, bool isEnabled) async {
    if (_authProvider?.token == null) return false;

    try {
      debugPrint('EnergyProvider: Toggling schedule $scheduleId → $isEnabled');

      final success = await _apiService.toggleEnergySchedule(
        _authProvider!.token,
        deviceId,
        scheduleId,
        isEnabled,
      );

      if (success) {
        debugPrint('EnergyProvider: ✅ Schedule toggled');

        // Оновлюємо локально
        if (_schedules.containsKey(deviceId)) {
          final index = _schedules[deviceId]!
              .indexWhere((schedule) => schedule.id == scheduleId);
          if (index != -1) {
            _schedules[deviceId]![index] =
                _schedules[deviceId]![index].copyWith(isEnabled: isEnabled);
          }
        }

        notifyListeners();
        return true;
      } else {
        debugPrint('EnergyProvider: ❌ Failed to toggle schedule');
        return false;
      }
    } catch (e) {
      debugPrint('EnergyProvider: ❌ Error toggling schedule: $e');
      return false;
    }
  }

  // Очищення помилки
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Очищення даних для пристрою (при видаленні пристрою)
  void clearDeviceData(String deviceId) {
    _energyModes.remove(deviceId);
    _schedules.remove(deviceId);
    _history.remove(deviceId);
    notifyListeners();
  }
}
