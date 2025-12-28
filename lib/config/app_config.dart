// lib/config/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'connection_mode.dart';

class AppConfig {
  // Використовуємо динамічні URL з ConnectionMode
  static String get apiUrl => ConnectionMode.apiUrl;
  static String get mqttHost => ConnectionMode.mqttHost;
  static int get mqttPort => ConnectionMode.mqttPort;

  // Решта конфігурації з .env (для Google Auth та інших статичних налаштувань)
  static String get mqttUsername => dotenv.env['MQTT_USERNAME'] ?? '';
  static String get mqttPassword => dotenv.env['MQTT_PASSWORD'] ?? '';
  static String get googleClientId =>
      dotenv.env['GOOGLE_CLIENT_ID'] ??
      '691562298422-kpipttbf22p39363ci73kukfk4hm8c65.apps.googleusercontent.com';
}
