// lib/providers/device_provider.dart - ВИПРАВЛЕНИЙ з null safety
import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'mqtt_provider.dart';

class DeviceProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  AuthProvider? _authProvider;
  MqttProvider? _mqttProvider;

  List<Device> _devices = [];
  bool _isLoading = false;
  String? _error;

  List<Device> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void setMqttProvider(MqttProvider mqttProvider) {
    _mqttProvider = mqttProvider;
  }

  void updateAuth(AuthProvider authProvider) {
    _authProvider = authProvider;
    if (_authProvider?.isAuthenticated ?? false) {
      fetchDevices();
    }
  }

  Future<void> fetchDevices() async {
    if (_authProvider?.token == null) {
      debugPrint('DeviceProvider: No token available for fetching devices');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _apiService.getDevices(_authProvider!.token!);
      _devices = data.map<Device>((json) => Device.fromJson(json)).toList();
      debugPrint('DeviceProvider: Loaded ${_devices.length} devices');
    } catch (e) {
      _error = 'Помилка завантаження пристроїв';
      debugPrint('DeviceProvider: Error fetching devices: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addDevice(
      String deviceId, String confirmationCode, String? name) async {
    if (_authProvider?.token == null) {
      debugPrint('DeviceProvider: No token available for adding device');
      return false;
    }

    try {
      final deviceData = await _apiService.addDevice(
        _authProvider!.token!,
        deviceId,
        confirmationCode,
        name,
      );

      if (deviceData != null) {
        _devices.add(Device.fromJson(deviceData));
        notifyListeners();
        debugPrint('DeviceProvider: Device $deviceId added successfully');
        return true;
      } else {
        debugPrint('DeviceProvider: Failed to add device - no data returned');
        return false;
      }
    } catch (e) {
      debugPrint('DeviceProvider: Error adding device: $e');
      return false;
    }
  }

  Future<bool> toggleRelay(String deviceId, bool currentState) async {
    if (_authProvider?.token == null) {
      debugPrint('DeviceProvider: No token available for controlling device');
      return false;
    }

    try {
      // Оновлюємо локальний стан ВІДРАЗУ для швидкого відгуку
      final index = _devices.indexWhere((d) => d.deviceId == deviceId);
      if (index != -1 && _devices[index].status != null) {
        _devices[index].status!.relayState = !currentState;
        notifyListeners();
      }

      // Відправляємо команду на сервер
      final success = await _apiService.controlDevice(
        _authProvider!.token!,
        deviceId,
        'relay',
        !currentState,
      );

      if (success) {
        debugPrint('DeviceProvider: Relay toggled successfully for $deviceId');
        return true;
      } else {
        // Якщо помилка - повертаємо стан назад
        if (index != -1 && _devices[index].status != null) {
          _devices[index].status!.relayState = currentState;
          notifyListeners();
        }
        debugPrint('DeviceProvider: Failed to toggle relay for $deviceId');
        return false;
      }
    } catch (e) {
      debugPrint('DeviceProvider: Error toggling relay: $e');

      // Якщо помилка - повертаємо стан назад
      final index = _devices.indexWhere((d) => d.deviceId == deviceId);
      if (index != -1 && _devices[index].status != null) {
        _devices[index].status!.relayState = currentState;
        notifyListeners();
      }

      return false;
    }
  }

  Future<bool> deleteDevice(String deviceId) async {
    if (_authProvider?.token == null) {
      debugPrint('DeviceProvider: No token available for deleting device');
      return false;
    }

    try {
      final success =
          await _apiService.deleteDevice(_authProvider!.token!, deviceId);

      if (success) {
        _devices.removeWhere((d) => d.deviceId == deviceId);
        notifyListeners();
        debugPrint('DeviceProvider: Device $deviceId deleted successfully');
        return true;
      } else {
        debugPrint('DeviceProvider: Failed to delete device $deviceId');
        return false;
      }
    } catch (e) {
      debugPrint('DeviceProvider: Error deleting device: $e');
      return false;
    }
  }

  Future<bool> shareDevice(String deviceId, String email) async {
    if (_authProvider?.token == null) {
      debugPrint('DeviceProvider: No token available for sharing device');
      return false;
    }

    try {
      final success =
          await _apiService.shareDevice(_authProvider!.token!, deviceId, email);

      if (success) {
        debugPrint(
            'DeviceProvider: Device $deviceId shared successfully with $email');
        return true;
      } else {
        debugPrint('DeviceProvider: Failed to share device $deviceId');
        return false;
      }
    } catch (e) {
      debugPrint('DeviceProvider: Error sharing device: $e');
      return false;
    }
  }

  void updateDeviceStatus(String deviceId, Map<String, dynamic> status) {
    final index = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (index != -1) {
      final device = _devices[index];
      final currentStatus = device.status ??
          DeviceStatus(
            online: false,
            relayState: false,
          );

      // Update status fields - додаємо перевірки на null
      final updatedStatus = DeviceStatus(
        online: status['online'] ?? currentStatus.online,
        relayState: status['relayState'] ?? currentStatus.relayState,
        wifiRSSI: status['wifiRSSI'] ?? currentStatus.wifiRSSI,
        uptime: status['uptime'] ?? currentStatus.uptime,
        freeHeap: status['freeHeap'] ?? currentStatus.freeHeap,
        lastSeen: DateTime.now(),
        powerKw: status['powerKw']?.toDouble() ?? currentStatus.powerKw,
        energyKwh: status['energyKwh']?.toDouble() ?? currentStatus.energyKwh,
        lastEnergyUpdate: status['lastEnergyUpdate'] != null
            ? DateTime.tryParse(status['lastEnergyUpdate']) ??
                currentStatus.lastEnergyUpdate
            : currentStatus.lastEnergyUpdate,
      );

      _devices[index] = device.copyWith(status: updatedStatus);
      notifyListeners();
    }
  }
}
