// lib/providers/mqtt_provider.dart - З MIDNIGHT RESET
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';
import 'dart:async';
import '../config/app_config.dart';
import '../config/connection_mode.dart';
import 'auth_provider.dart';
import 'device_provider.dart';
import '../models/energy_data.dart';
import '../services/energy_service.dart';

class MqttProvider with ChangeNotifier {
  MqttClient? _client;
  AuthProvider? _authProvider;
  DeviceProvider? _deviceProvider;
  final EnergyService _energyService = EnergyService();

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _connectionError;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  int _clientCounter = 1;

  StreamSubscription? _midnightResetSubscription;

  // Stream для реального часу
  final StreamController<Map<String, dynamic>> _energyStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get energyStream =>
      _energyStreamController.stream;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get connectionError => _connectionError;

  void updateAuth(AuthProvider authProvider) {
    _authProvider = authProvider;
    if (_authProvider?.isAuthenticated ?? false) {
      connect();

      // Підписуємось на midnight reset з EnergyService
      _listenToMidnightReset();
    } else {
      disconnect();
    }
  }

  void setDeviceProvider(DeviceProvider deviceProvider) {
    _deviceProvider = deviceProvider;
    _deviceProvider!.setMqttProvider(this);
    debugPrint('MQTT: DeviceProvider linked');
  }

  // === СЛУХАЄМО MIDNIGHT RESET З ENERGYSERVICE ===
  void _listenToMidnightReset() {
    _midnightResetSubscription?.cancel();
    _midnightResetSubscription =
        _energyService.midnightResetStream.listen((deviceId) {
      debugPrint('MQTT: Received midnight reset request for $deviceId');
      // Відправляємо команду на ESP32
      _sendResetEnergyCommand(deviceId);
    });
  }

  Future<void> _sendResetEnergyCommand(String deviceId) async {
    if (!_isConnected) {
      debugPrint('MQTT: Cannot send reset - not connected');
      return;
    }

    try {
      await publishCommand(deviceId, 'resetEnergy', true);
      debugPrint('✅ MQTT: Reset energy command sent to $deviceId');
    } catch (e) {
      debugPrint('❌ MQTT: Error sending reset command: $e');
    }
  }

  Future<void> connect() async {
    if (_client != null || _isConnecting) {
      debugPrint('MQTT: Already connected or connecting');
      return;
    }

    if (_authProvider?.token == null) {
      debugPrint('MQTT: No auth token available');
      return;
    }

    _isConnecting = true;
    _connectionError = null;
    notifyListeners();

    try {
      final clientId =
          'Flutter_${_clientCounter}_${DateTime.now().millisecondsSinceEpoch}';
      _clientCounter++;

      if (ConnectionMode.isRemoteMode) {
        _client = MqttServerClient('solar-mqtt.loca.lt', clientId);
        _client!.port = 443;
      } else {
        _client = MqttServerClient('192.168.68.120', clientId);
        _client!.port = 1883;
      }

      _client!.logging(on: kDebugMode);
      _client!.keepAlivePeriod = 60;
      _client!.autoReconnect = false;
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      if (AppConfig.mqttUsername.isNotEmpty) {
        connMessage.authenticateAs(
          AppConfig.mqttUsername,
          AppConfig.mqttPassword,
        );
      }

      _client!.connectionMessage = connMessage;

      debugPrint('MQTT: Connecting to broker...');
      await _client!.connect();
    } catch (e) {
      debugPrint('MQTT connection error: $e');
      _connectionError = 'Помилка підключення: ${e.toString()}';
      _isConnecting = false;
      _isConnected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    _isConnected = true;
    _isConnecting = false;
    _connectionError = null;
    _reconnectAttempts = 0;
    notifyListeners();

    debugPrint('MQTT: Connected successfully');
    _subscribeToTopics();
    _client!.updates!.listen(_handleMessage);
  }

  void _onDisconnected() {
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
    debugPrint('MQTT: Disconnected');

    if (_authProvider?.isAuthenticated ?? false) {
      _scheduleReconnect();
    }
  }

  void _subscribeToTopics() {
    if (_client == null || !_isConnected) return;

    try {
      _client!.subscribe('solar/+/status', MqttQos.atLeastOnce);
      _client!.subscribe('solar/+/online', MqttQos.atLeastOnce);
      _client!.subscribe('solar/+/response', MqttQos.atLeastOnce);
      _client!.subscribe('solar/+/confirmation', MqttQos.atLeastOnce);
      _client!.subscribe('solar/+/energy', MqttQos.atLeastOnce);

      debugPrint('MQTT: Subscribed to all topics');
    } catch (e) {
      debugPrint('MQTT: Error subscribing to topics: $e');
    }
  }

  void _handleMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final topic = message.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (message.payload as MqttPublishMessage).payload.message,
      );

      final topicParts = topic.split('/');
      if (topicParts.length < 3) continue;

      final deviceId = topicParts[1];
      final messageType = topicParts[2];

      try {
        switch (messageType) {
          case 'status':
            _handleStatusMessage(deviceId, payload);
            break;
          case 'online':
            _handleOnlineMessage(deviceId, payload);
            break;
          case 'response':
            _handleResponseMessage(deviceId, payload);
            break;
          case 'confirmation':
            _handleConfirmationMessage(deviceId, payload);
            break;
          case 'energy':
            _handleEnergyMessage(deviceId, payload);
            break;
        }
      } catch (e) {
        debugPrint('MQTT: Error handling message: $e');
      }
    }
  }

  void _handleStatusMessage(String deviceId, String payload) {
    try {
      final status = json.decode(payload);

      if (status['confirmationCode'] != null) {
        debugPrint(
            'MQTT: Received confirmation code: ${status['confirmationCode']}');
      }

      // КРИТИЧНО: Зберігаємо дані з STATUS
      if (status['powerKw'] != null && status['energyKwh'] != null) {
        final powerKw = (status['powerKw'] ?? 0).toDouble();
        final energyKwh = (status['energyKwh'] ?? 0).toDouble();
        final now = DateTime.now();

        final energyData = EnergyData(
          deviceId: deviceId,
          powerKw: powerKw,
          energyKwh: energyKwh,
          timestamp: now,
        );

        _saveEnergyDataSafely(deviceId, energyData, 'STATUS');

        _energyStreamController.add({
          'deviceId': deviceId,
          'powerKw': powerKw,
          'energyKwh': energyKwh,
          'timestamp': now,
          'type': 'status'
        });
      }

      _deviceProvider?.updateDeviceStatus(deviceId, {
        'online': true,
        'relayState': status['relayState'] ?? false,
        'wifiRSSI': status['wifiRSSI'],
        'uptime': status['uptime'],
        'freeHeap': status['freeHeap'],
        'powerKw': status['powerKw'],
        'energyKwh': status['energyKwh'],
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('MQTT: Error parsing status: $e');
    }
  }

  void _handleOnlineMessage(String deviceId, String payload) {
    final isOnline = payload.toLowerCase() == 'true' || payload == '1';
    debugPrint('MQTT: Device $deviceId is ${isOnline ? 'online' : 'offline'}');

    _deviceProvider?.updateDeviceStatus(deviceId, {
      'online': isOnline,
      'lastSeen': DateTime.now().toIso8601String(),
    });
  }

  void _handleResponseMessage(String deviceId, String payload) {
    try {
      final response = json.decode(payload);
      debugPrint('MQTT: Response from $deviceId: $payload');

      if (response['command'] == 'relay' && response['success'] == true) {
        _deviceProvider?.updateDeviceStatus(deviceId, {
          'relayState': response['state'] ?? false,
          'lastSeen': DateTime.now().toIso8601String(),
        });
      } else if (response['command'] == 'deviceAdded' &&
          response['success'] == true) {
        debugPrint('MQTT: Device $deviceId confirmed deviceAdded');
      }
      // ОБРОБКА resetEnergy ВІДПОВІДІ
      else if (response['command'] == 'resetEnergy' &&
          response['success'] == true) {
        debugPrint('✅ MQTT: Device $deviceId confirmed energy reset');

        // Повідомляємо UI про reset
        _energyStreamController.add({
          'deviceId': deviceId,
          'powerKw': 0.0,
          'energyKwh': 0.0,
          'timestamp': DateTime.now(),
          'type': 'midnight_reset',
          'message': 'Energy counter reset'
        });
      }
    } catch (e) {
      debugPrint('MQTT: Error parsing response: $e');
    }
  }

  void _handleConfirmationMessage(String deviceId, String payload) {
    debugPrint('MQTT: Confirmation code from $deviceId: $payload');
  }

  void _handleEnergyMessage(String deviceId, String payload) {
    try {
      final energyJson = json.decode(payload);

      final powerKw = (energyJson['powerKw'] ?? 0).toDouble();
      final energyKwh = (energyJson['energyKwh'] ?? 0).toDouble();
      final now = DateTime.now();

      final energyData = EnergyData(
        deviceId: deviceId,
        powerKw: powerKw,
        energyKwh: energyKwh,
        timestamp: now,
      );

      _saveEnergyDataSafely(deviceId, energyData, 'ENERGY');

      _energyStreamController.add({
        'deviceId': deviceId,
        'powerKw': powerKw,
        'energyKwh': energyKwh,
        'timestamp': now,
        'type': 'energy'
      });

      _deviceProvider?.updateDeviceStatus(deviceId, {
        'powerKw': powerKw,
        'energyKwh': energyKwh,
        'lastEnergyUpdate': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('MQTT: Error parsing energy data: $e');
    }
  }

  void _saveEnergyDataSafely(
      String deviceId, EnergyData energyData, String source) {
    try {
      _energyService.addEnergyData(deviceId, energyData).catchError((error) {
        debugPrint('❌ MQTT ($source): Error saving energy data: $error');
      });
    } catch (e) {
      debugPrint('❌ MQTT ($source): Critical error saving energy data: $e');
    }
  }

  Future<void> publishCommand(
      String deviceId, String command, dynamic state) async {
    if (_client == null || !_isConnected) {
      debugPrint('MQTT: Cannot send command - not connected');
      _connectionError = 'Не підключено до MQTT';
      notifyListeners();

      await connect();

      int attempts = 0;
      while (!_isConnected && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }

      if (!_isConnected) {
        throw Exception('MQTT не підключено');
      }
    }

    try {
      final topic = 'solar/$deviceId/command';
      final message = json.encode({
        'command': command,
        'state': state,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final builder = MqttClientPayloadBuilder();
      builder.addString(message);

      _client!.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      debugPrint('MQTT: Published to $topic: $message');

      if (command == 'relay' && _deviceProvider != null) {
        _deviceProvider!.updateDeviceStatus(deviceId, {
          'relayState': state,
        });
      }
    } catch (e) {
      debugPrint('MQTT: Error publishing command: $e');
      throw e;
    }
  }

  Future<void> requestDeviceStatus(String deviceId) async {
    if (!_isConnected) {
      debugPrint('MQTT: Cannot request status - not connected');
      return;
    }

    try {
      final topic = 'solar/$deviceId/request';
      final message = json.encode({
        'request': 'status',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      final builder = MqttClientPayloadBuilder();
      builder.addString(message);

      _client!.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      debugPrint('MQTT: Requested status from $deviceId');
    } catch (e) {
      debugPrint('MQTT: Error requesting status: $e');
    }
  }

  Future<void> sendDeviceAddedCommand(String deviceId) async {
    debugPrint('MQTT: Preparing to send deviceAdded command to $deviceId');

    if (!_isConnected) {
      debugPrint('MQTT: Not connected, trying to connect first...');
      await connect();

      int attempts = 0;
      while (!_isConnected && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }

      if (!_isConnected) {
        debugPrint('MQTT: Failed to connect for sending deviceAdded command');
        return;
      }
    }

    try {
      await publishCommand(deviceId, 'deviceAdded', true);
      debugPrint('MQTT: deviceAdded command sent successfully to $deviceId');

      await Future.delayed(const Duration(seconds: 1));
      await requestDeviceStatus(deviceId);
    } catch (e) {
      debugPrint('MQTT: Error sending deviceAdded command: $e');
    }
  }

  // === ВИПРАВЛЕНА ФУНКЦІЯ: Midnight reset з перевіркою MQTT ===
  Future<void> triggerMidnightReset(String deviceId) async {
    debugPrint('🕛 MQTT: Triggering midnight reset for $deviceId');

    try {
      // 1. СПОЧАТКУ очищуємо локальні дані (це завжди працює)
      await _energyService.performMidnightReset(deviceId, isAutomatic: false);
      debugPrint('✅ Step 1/2: Local data cleared');

      // 2. ПОТІМ пробуємо відправити команду на ESP32 (якщо MQTT підключений)
      if (_isConnected && _client != null) {
        try {
          await publishCommand(deviceId, 'resetEnergy', true);
          debugPrint('✅ Step 2/2: ESP32 reset command sent');
        } catch (e) {
          debugPrint(
              '⚠️ Step 2/2: ESP32 command failed (but local clear OK): $e');
          // Не кидаємо помилку - локальні дані вже очищені
        }
      } else {
        debugPrint('⚠️ Step 2/2: MQTT offline, only local clear performed');
      }

      // 3. Повідомляємо UI про успіх (навіть якщо MQTT офлайн)
      _energyStreamController.add({
        'deviceId': deviceId,
        'powerKw': 0.0,
        'energyKwh': 0.0,
        'timestamp': DateTime.now(),
        'type': 'midnight_reset',
        'message': _isConnected
            ? 'Manual midnight reset triggered'
            : 'Local data reset (MQTT offline)'
      });

      debugPrint('✅ MQTT: Midnight reset completed for $deviceId');
    } catch (e) {
      debugPrint('❌ MQTT: Error during midnight reset: $e');
      rethrow;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('MQTT: Max reconnect attempts reached');
      _connectionError = 'Не вдалося підключитися до MQTT сервера';
      notifyListeners();
      return;
    }

    _reconnectTimer?.cancel();

    final delay = Duration(seconds: 5 * (_reconnectAttempts + 1));
    _reconnectAttempts++;

    debugPrint(
        'MQTT: Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () {
      if (_authProvider?.isAuthenticated ?? false) {
        connect();
      }
    });
  }

  void disconnect() {
    debugPrint('MQTT: Disconnecting...');

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;

    if (_client != null) {
      _client!.disconnect();
      _client = null;
    }

    _isConnected = false;
    _isConnecting = false;
    _connectionError = null;
    notifyListeners();
  }

  Future<void> reconnect() async {
    debugPrint('MQTT: Manual reconnect requested');
    disconnect();
    await Future.delayed(const Duration(seconds: 1));
    await connect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _energyStreamController.close();
    _midnightResetSubscription?.cancel();
    _energyService.dispose();
    disconnect();
    super.dispose();
  }
}
