// lib/config/connection_mode.dart - З ДВОМА ТУНЕЛЯМИ
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionMode {
  static bool _isRemoteMode = false;

  // LOCAL URLs
  static const String localApiUrl = 'http://192.168.68.122:8080/api';
  static const String localMqttHost = '192.168.68.122';
  static const String localMqttWsUrl = 'ws://192.168.68.122:9001';

  // REMOTE URLs - ОНОВІТЬ ЦІ URL з ваших тунелів!
  // Для Localtunnel:
  static const String remoteApiUrl = 'https://solar-api.loca.lt/api';
  static const String remoteMqttWsUrl = 'wss://solar-mqtt.loca.lt';

  // АБО для Ngrok (замініть на ваші URL):
  // static const String remoteApiUrl = 'https://abc123.ngrok-free.app/api';
  // static const String remoteMqttWsUrl = 'wss://xyz789.ngrok-free.app';

  static bool get isRemoteMode => _isRemoteMode;

  // API URL
  static String get apiUrl => _isRemoteMode ? remoteApiUrl : localApiUrl;

  // MQTT WebSocket URL - тепер прямо на 9001 порт через окремий тунель
  static String get mqttWsUrl =>
      _isRemoteMode ? remoteMqttWsUrl : localMqttWsUrl;

  // Для сумісності
  static String get mqttHost =>
      _isRemoteMode ? 'solar-mqtt.loca.lt' : localMqttHost;
  static int get mqttPort => _isRemoteMode ? 443 : 1883;

  // Завантаження збереженого режиму
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isRemoteMode = prefs.getBool('remote_mode') ?? false;
  }

  // Перемикання режиму
  static Future<void> toggleMode() async {
    _isRemoteMode = !_isRemoteMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remote_mode', _isRemoteMode);
  }

  // Встановлення конкретного режиму
  static Future<void> setRemoteMode(bool isRemote) async {
    _isRemoteMode = isRemote;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remote_mode', _isRemoteMode);
  }

  // Оновлення URL тунелів динамічно
  static Future<void> updateTunnelUrls({
    String? apiTunnelUrl,
    String? mqttTunnelUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (apiTunnelUrl != null) {
      await prefs.setString('api_tunnel_url', apiTunnelUrl);
    }
    if (mqttTunnelUrl != null) {
      await prefs.setString('mqtt_tunnel_url', mqttTunnelUrl);
    }
  }

  // Отримання збережених URL тунелів
  static Future<Map<String, String?>> getSavedTunnelUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'api': prefs.getString('api_tunnel_url'),
      'mqtt': prefs.getString('mqtt_tunnel_url'),
    };
  }
}
