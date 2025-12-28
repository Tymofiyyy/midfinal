// lib/services/api_service.dart - ПОВНА ВЕРСІЯ З ENERGY MODE ТА RANGE SCHEDULES
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/energy_data.dart';
import '../models/daily_energy_summary.dart';
import '../models/energy_mode.dart';
import '../models/energy_schedule.dart';

class ApiService {
  late final Dio _dio;
  String? _currentToken;
  bool _isConnected = true;
  DateTime? _lastConnectionCheck;

  Future<String?> Function()? _tokenRefreshCallback;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      error: true,
      requestHeader: false,
      responseHeader: false,
      logPrint: (obj) {
        if (kDebugMode) {
          debugPrint('API: $obj');
        }
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_currentToken != null) {
          options.headers['Authorization'] = 'Bearer $_currentToken';
          debugPrint('API: Using token for ${options.path}');
        } else {
          debugPrint('API: ⚠️ No token available for ${options.path}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        _isConnected = true;
        _lastConnectionCheck = DateTime.now();
        handler.next(response);
      },
      onError: (error, handler) async {
        debugPrint(
            'API: ❌ Error ${error.response?.statusCode} for ${error.requestOptions.path}');

        if (error.response?.statusCode == 401) {
          debugPrint('API: 🔑 Token expired - attempting refresh...');

          if (_tokenRefreshCallback != null) {
            try {
              final newToken = await _tokenRefreshCallback!();
              if (newToken != null && newToken != _currentToken) {
                _currentToken = newToken;
                debugPrint('API: ✅ Token refreshed, retrying request...');

                final options = error.requestOptions;
                options.headers['Authorization'] = 'Bearer $newToken';

                try {
                  final response = await _dio.fetch(options);
                  handler.resolve(response);
                  return;
                } catch (retryError) {
                  debugPrint('API: ❌ Retry failed: $retryError');
                }
              }
            } catch (refreshError) {
              debugPrint('API: ❌ Token refresh failed: $refreshError');
            }
          }
        }

        if (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout) {
          _isConnected = false;
          debugPrint('API: 🔴 Connection issues detected');
        }

        handler.next(error);
      },
    ));
  }

  void setToken(String? token) {
    _currentToken = token;
    debugPrint('API: 🔑 Token ${token != null ? "set" : "cleared"}');
  }

  void setTokenRefreshCallback(Future<String?> Function() callback) {
    _tokenRefreshCallback = callback;
    debugPrint('API: 🔄 Token refresh callback set');
  }

  String? get currentToken => _currentToken;
  bool get isConnected => _isConnected;

  Future<bool> checkConnection() async {
    if (_isConnected &&
        _lastConnectionCheck != null &&
        DateTime.now().difference(_lastConnectionCheck!).inSeconds < 30) {
      return true;
    }

    try {
      debugPrint('API: 🔍 Checking connection...');

      final response = await _dio.get(
        '/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final isOk = response.statusCode == 200;
      _isConnected = isOk;
      _lastConnectionCheck = DateTime.now();

      debugPrint('API: ${isOk ? "✅" : "❌"} Connection check result: $isOk');
      return isOk;
    } catch (e) {
      _isConnected = false;
      debugPrint('API: ❌ Connection check failed: $e');
      return false;
    }
  }

  Future<T?> _safeApiCall<T>(Future<T> Function() apiCall,
      [String? operation]) async {
    try {
      if (_currentToken == null && operation != 'health') {
        debugPrint('API: ⚠️ No token for operation: $operation');
        return null;
      }

      return await apiCall();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        debugPrint('API: 🔑 Auth error for $operation - token may be expired');
      } else if (e.type == DioExceptionType.connectionError) {
        debugPrint('API: 🔴 Connection error for $operation');
        _isConnected = false;
      } else {
        debugPrint('API: ❌ Error for $operation: ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('API: ❌ Unexpected error for $operation: $e');
      return null;
    }
  }

  // ============ AUTHENTICATION ============

  Future<Map<String, dynamic>> testLogin() async {
    try {
      final response = await _dio.post('/auth/test', data: {
        'email': 'test@solar.com',
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> authenticateWithGoogle(String idToken) async {
    try {
      final response = await _dio.post('/auth/google', data: {
        'credential': idToken,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser([String? token]) async {
    return await _safeApiCall(() async {
      final options = token != null
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null;

      final response = await _dio.get('/auth/me', options: options);
      return response.data;
    }, 'getCurrentUser');
  }

  // ============ DEVICES ============

  Future<List<dynamic>> getDevices([String? token]) async {
    final result = await _safeApiCall(() async {
      final options = token != null
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null;

      final response = await _dio.get('/devices', options: options);
      return response.data;
    }, 'getDevices');

    return result ?? [];
  }

  Future<Map<String, dynamic>?> addDevice(
    String? token,
    String deviceId,
    String confirmationCode,
    String? name,
  ) async {
    return await _safeApiCall(() async {
      final options = token != null
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null;

      final response = await _dio.post(
        '/devices',
        data: {
          'deviceId': deviceId,
          'confirmationCode': confirmationCode,
          'name': name,
        },
        options: options,
      );
      return response.data;
    }, 'addDevice');
  }

  Future<bool> deleteDevice(String? token, String deviceId) async {
    final result = await _safeApiCall(() async {
      final options = token != null
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null;

      await _dio.delete('/devices/$deviceId', options: options);
      return true;
    }, 'deleteDevice');

    return result ?? false;
  }

  Future<bool> controlDevice(
    String? token,
    String deviceId,
    String command,
    bool state,
  ) async {
    final result = await _safeApiCall(() async {
      final options = token != null
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null;

      await _dio.post(
        '/devices/$deviceId/control',
        data: {
          'command': command,
          'state': state,
        },
        options: options,
      );
      return true;
    }, 'controlDevice');

    return result ?? false;
  }

  Future<bool> shareDevice(String? token, String deviceId, String email) async {
    final result = await _safeApiCall(() async {
      final options = token != null
          ? Options(headers: {'Authorization': 'Bearer $token'})
          : null;

      await _dio.post(
        '/devices/$deviceId/share',
        data: {'email': email},
        options: options,
      );
      return true;
    }, 'shareDevice');

    return result ?? false;
  }

  // ============ ЕНЕРГЕТИЧНІ ДАНІ ============

  Future<List<EnergyData>> getEnergyData(
    String? token,
    String deviceId, {
    String period = '24h',
    int limit = 1000,
  }) async {
    final result = await _safeApiCall(() async {
      debugPrint('API: 📊 Getting energy data for $deviceId, period: $period');

      final response = await _dio.get(
        '/devices/$deviceId/energy',
        queryParameters: {
          'period': period,
          'limit': limit.toString(),
        },
      );

      final data = response.data['data'] as List;
      final energyDataList =
          data.map((json) => EnergyData.fromJson(json)).toList();

      debugPrint(
          'API: ✅ Retrieved ${energyDataList.length} energy data points');
      return energyDataList;
    }, 'getEnergyData');

    return result ?? [];
  }

  Future<bool> addEnergyData(
    String? token,
    String deviceId,
    EnergyData energyData,
  ) async {
    final result = await _safeApiCall(() async {
      await _dio.post(
        '/devices/$deviceId/energy',
        data: {
          'powerKw': energyData.powerKw,
          'energyKwh': energyData.energyKwh,
          'timestamp': energyData.timestamp.toIso8601String(),
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      return true;
    }, 'addEnergyData');

    return result ?? false;
  }

  Future<bool> clearEnergyData(String? token, String deviceId) async {
    final result = await _safeApiCall(() async {
      final response = await _dio.delete('/devices/$deviceId/energy');
      debugPrint(
          'API: 🗑️ Energy data cleared - ${response.data['deletedCount']} records');
      return true;
    }, 'clearEnergyData');

    return result ?? false;
  }

  Future<Map<String, dynamic>?> getEnergyStats(
    String? token,
    String deviceId, {
    String period = '24h',
  }) async {
    return await _safeApiCall(() async {
      final response = await _dio.get(
        '/devices/$deviceId/energy/stats',
        queryParameters: {'period': period},
      );

      return response.data['stats'] as Map<String, dynamic>;
    }, 'getEnergyStats');
  }

  // ============ ДЕННА СТАТИСТИКА ============

  Future<bool> saveDailySummary(
    String? token,
    String deviceId,
    DailyEnergySummary summary,
  ) async {
    final result = await _safeApiCall(() async {
      debugPrint(
          'API: 💾 Saving daily summary for $deviceId, date: ${summary.date}');

      await _dio.post(
        '/devices/$deviceId/daily',
        data: {
          'date': summary.date.toIso8601String().split('T')[0],
          'totalEnergyKwh': summary.totalEnergyKwh,
          'maxPowerKw': summary.maxPowerKw,
          'avgPowerKw': summary.avgPowerKw,
          'dataPoints': summary.dataPoints,
        },
      );

      debugPrint(
          'API: ✅ Daily summary saved: ${summary.totalEnergyKwh.toStringAsFixed(2)} kWh');
      return true;
    }, 'saveDailySummary');

    return result ?? false;
  }

  Future<List<DailyEnergySummary>> getDailySummary(
    String? token,
    String deviceId, {
    int days = 30,
  }) async {
    final result = await _safeApiCall(() async {
      debugPrint(
          'API: 📅 Getting daily summary for $deviceId, last $days days');

      final response = await _dio.get(
        '/devices/$deviceId/daily',
        queryParameters: {'days': days.toString()},
      );

      final data = response.data['data'] as List;
      final summaries =
          data.map((json) => DailyEnergySummary.fromJson(json)).toList();

      debugPrint('API: ✅ Retrieved ${summaries.length} daily summaries');
      return summaries;
    }, 'getDailySummary');

    return result ?? [];
  }

  Future<List<DailyEnergySummary>> getDailySummaryByDateRange(
    String? token,
    String deviceId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final result = await _safeApiCall(() async {
      final response = await _dio.get(
        '/devices/$deviceId/daily/range',
        queryParameters: {
          'startDate': startDate.toIso8601String().split('T')[0],
          'endDate': endDate.toIso8601String().split('T')[0],
        },
      );

      final data = response.data['data'] as List;
      return data.map((json) => DailyEnergySummary.fromJson(json)).toList();
    }, 'getDailySummaryByDateRange');

    return result ?? [];
  }

  Future<bool> deleteDailySummary(
    String? token,
    String deviceId,
    DateTime date,
  ) async {
    final result = await _safeApiCall(() async {
      final dateStr = date.toIso8601String().split('T')[0];
      await _dio.delete('/devices/$deviceId/daily/$dateStr');

      debugPrint('API: 🗑️ Daily summary deleted for $dateStr');
      return true;
    }, 'deleteDailySummary');

    return result ?? false;
  }

  Future<Map<String, dynamic>?> getTotalDailyStats(
    String? token,
    String deviceId,
  ) async {
    return await _safeApiCall(() async {
      final response = await _dio.get('/devices/$deviceId/daily/stats');

      return response.data['stats'] as Map<String, dynamic>;
    }, 'getTotalDailyStats');
  }

  // ============ ENERGY MODE MANAGEMENT ============

  Future<EnergyMode?> getEnergyMode(String? token, String deviceId) async {
    return await _safeApiCall(() async {
      debugPrint('API: 📊 Getting energy mode for $deviceId');

      final response = await _dio.get('/devices/$deviceId/energy-mode');

      final mode = EnergyMode.fromJson(response.data);
      debugPrint('API: ✅ Current mode: ${mode.currentMode}');
      return mode;
    }, 'getEnergyMode');
  }

  Future<bool> setEnergyMode(
    String? token,
    String deviceId,
    String mode,
  ) async {
    final result = await _safeApiCall(() async {
      debugPrint('API: 🔄 Setting energy mode for $deviceId → $mode');

      await _dio.post(
        '/devices/$deviceId/energy-mode',
        data: {'mode': mode},
      );

      debugPrint('API: ✅ Energy mode changed successfully');
      return true;
    }, 'setEnergyMode');

    return result ?? false;
  }

  Future<List<EnergyModeHistory>> getEnergyModeHistory(
    String? token,
    String deviceId, {
    int limit = 50,
  }) async {
    final result = await _safeApiCall(() async {
      debugPrint('API: 📜 Getting energy mode history for $deviceId');

      final response = await _dio.get(
        '/devices/$deviceId/energy-mode/history',
        queryParameters: {'limit': limit.toString()},
      );

      final data = response.data['history'] as List;
      final history =
          data.map((json) => EnergyModeHistory.fromJson(json)).toList();

      debugPrint('API: ✅ Retrieved ${history.length} history records');
      return history;
    }, 'getEnergyModeHistory');

    return result ?? [];
  }

  // ============ ENERGY SCHEDULES MANAGEMENT ============
  // ОНОВЛЕНО: Підтримка TIME та RANGE розкладів

  Future<List<EnergySchedule>> getEnergySchedules(
    String? token,
    String deviceId,
  ) async {
    final result = await _safeApiCall(() async {
      debugPrint('API: 📅 Getting schedules for $deviceId');

      final response = await _dio.get('/devices/$deviceId/schedules');

      final data = response.data['schedules'] as List;
      final schedules =
          data.map((json) => EnergySchedule.fromJson(json)).toList();

      debugPrint('API: ✅ Retrieved ${schedules.length} schedules');
      return schedules;
    }, 'getEnergySchedules');

    return result ?? [];
  }

  Future<EnergySchedule?> createEnergySchedule(
    String? token,
    String deviceId,
    EnergySchedule schedule,
  ) async {
    return await _safeApiCall(() async {
      debugPrint('API: 📅 Creating schedule for $deviceId');
      debugPrint('   Name: ${schedule.name}');
      debugPrint('   Type: ${schedule.scheduleType}');
      if (schedule.isTimeSchedule) {
        debugPrint('   Time: ${schedule.timeString}');
      } else {
        debugPrint('   Range: ${schedule.rangeString}');
        debugPrint('   Secondary: ${schedule.secondaryMode}');
      }
      debugPrint('   Mode: ${schedule.targetMode}');
      debugPrint('   Repeat: ${schedule.repeatType}');

      final response = await _dio.post(
        '/devices/$deviceId/schedules',
        data: schedule.toApiJson(),
      );

      final createdSchedule =
          EnergySchedule.fromJson(response.data['schedule']);
      debugPrint('API: ✅ Schedule created with ID: ${createdSchedule.id}');
      return createdSchedule;
    }, 'createEnergySchedule');
  }

  Future<EnergySchedule?> updateEnergySchedule(
    String? token,
    String deviceId,
    int scheduleId,
    EnergySchedule schedule,
  ) async {
    return await _safeApiCall(() async {
      debugPrint('API: 📅 Updating schedule $scheduleId for $deviceId');

      final response = await _dio.put(
        '/devices/$deviceId/schedules/$scheduleId',
        data: schedule.toApiJson(),
      );

      final updatedSchedule =
          EnergySchedule.fromJson(response.data['schedule']);
      debugPrint('API: ✅ Schedule updated');
      return updatedSchedule;
    }, 'updateEnergySchedule');
  }

  Future<bool> deleteEnergySchedule(
    String? token,
    String deviceId,
    int scheduleId,
  ) async {
    final result = await _safeApiCall(() async {
      debugPrint('API: 🗑️ Deleting schedule $scheduleId for $deviceId');

      await _dio.delete('/devices/$deviceId/schedules/$scheduleId');

      debugPrint('API: ✅ Schedule deleted');
      return true;
    }, 'deleteEnergySchedule');

    return result ?? false;
  }

  Future<bool> toggleEnergySchedule(
    String? token,
    String deviceId,
    int scheduleId,
    bool isEnabled,
  ) async {
    final result = await _safeApiCall(() async {
      debugPrint('API: 🔄 Toggling schedule $scheduleId → $isEnabled');

      await _dio.put(
        '/devices/$deviceId/schedules/$scheduleId',
        data: {'isEnabled': isEnabled},
      );

      debugPrint('API: ✅ Schedule toggled');
      return true;
    }, 'toggleEnergySchedule');

    return result ?? false;
  }

  // ============ DEBUG ============

  Future<Map<String, dynamic>?> getDebugInfo([String? token]) async {
    return await _safeApiCall(() async {
      final response = await _dio.get('/debug/codes');
      return response.data;
    }, 'getDebugInfo');
  }

  // ============ ERROR HANDLING ============

  String _handleError(DioException error) {
    if (error.response != null) {
      final data = error.response!.data;
      if (data is Map && data.containsKey('error')) {
        return data['error'];
      }
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        _isConnected = false;
        return 'Timeout - перевірте підключення';
      case DioExceptionType.connectionError:
        _isConnected = false;
        return 'Помилка підключення до сервера';
      case DioExceptionType.badResponse:
        if (error.response?.statusCode == 401) {
          return 'Помилка авторизації - увійдіть знову';
        }
        return 'Помилка сервера: ${error.response?.statusCode}';
      default:
        return 'Невідома помилка: ${error.message}';
    }
  }
}
