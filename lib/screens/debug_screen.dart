// lib/screens/debug_screen.dart - З ПОВНОЮ ДІАГНОСТИКОЮ API
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import '../providers/mqtt_provider.dart';
import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';
import '../services/energy_service.dart';
import '../services/api_service.dart';
import '../models/device.dart';
import '../config/app_config.dart';
import '../config/connection_mode.dart';

class DebugScreen extends StatefulWidget {
  final Device device;

  const DebugScreen({super.key, required this.device});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final EnergyService _energyService = EnergyService();
  final ApiService _apiService = ApiService();

  List<String> _mqttLogs = [];
  List<String> _apiLogs = [];
  List<String> _systemLogs = [];
  List<String> _diagnosticLogs = [];

  int _totalCacheSize = 0;
  int _mqttMessagesReceived = 0;
  int _apiRequestsSent = 0;
  int _apiFailures = 0;
  bool _isListening = false;

  StreamSubscription? _mqttSubscription;
  Timer? _statusTimer;
  Timer? _diagnosticTimer;

  @override
  void initState() {
    super.initState();
    _startListening();
    _addSystemLog('🚀 Debug screen started');
    _startDiagnosticChecks();

    // Оновлюємо статистику кожні 2 секунди
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {
          _totalCacheSize = _energyService.getCacheSize(widget.device.deviceId);
        });
      }
    });
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _statusTimer?.cancel();
    _diagnosticTimer?.cancel();
    super.dispose();
  }

  void _startDiagnosticChecks() {
    // Початкова діагностика
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performFullDiagnostic();
    });

    // Періодична діагностика кожні 30 секунд
    _diagnosticTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _performQuickDiagnostic();
      }
    });
  }

  Future<void> _performFullDiagnostic() async {
    _addDiagnosticLog('🔍 Starting full diagnostic...');

    // 1. Перевірка конфігурації
    _addDiagnosticLog('📋 Config check:');
    _addDiagnosticLog('  • API URL: ${AppConfig.apiUrl}');
    _addDiagnosticLog(
        '  • Connection Mode: ${ConnectionMode.isRemoteMode ? "Remote" : "Local"}');
    _addDiagnosticLog(
        '  • Current URL: ${ConnectionMode.isRemoteMode ? ConnectionMode.remoteApiUrl : ConnectionMode.localApiUrl}');

    // 2. Перевірка мережі
    await _checkNetworkConnectivity();

    // 3. Перевірка DNS
    await _checkDnsResolution();

    // 4. Перевірка API endpoint
    await _checkApiEndpoint();

    // 5. Перевірка токена
    await _checkTokenStatus();

    _addDiagnosticLog('✅ Full diagnostic completed');
  }

  Future<void> _performQuickDiagnostic() async {
    // Швидка перевірка API статусу
    final isConnected = await _apiService.checkConnection();
    if (!isConnected) {
      _apiFailures++;
      _addDiagnosticLog(
          '❌ Quick check: API not responding (failures: $_apiFailures)');

      // Якщо багато помилок підряд - запускаємо повну діагностику
      if (_apiFailures % 3 == 0) {
        _addDiagnosticLog('🔍 Too many failures, running full diagnostic...');
        await _performFullDiagnostic();
      }
    } else {
      if (_apiFailures > 0) {
        _addDiagnosticLog('✅ API recovered after $_apiFailures failures');
        _apiFailures = 0;
      }
    }
  }

  Future<void> _checkNetworkConnectivity() async {
    _addDiagnosticLog('🌐 Checking network connectivity...');

    try {
      // Перевірка загального інтернет-з'єднання
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _addDiagnosticLog('  ✅ Internet connectivity: OK');
      } else {
        _addDiagnosticLog('  ❌ Internet connectivity: FAILED');
        return;
      }
    } catch (e) {
      _addDiagnosticLog('  ❌ Internet connectivity: ERROR - $e');
      return;
    }

    // Перевірка локального з'єднання (якщо local mode)
    if (!ConnectionMode.isRemoteMode) {
      try {
        final result = await InternetAddress.lookup('192.168.68.115');
        _addDiagnosticLog('  ✅ Local network: Server reachable');
      } catch (e) {
        _addDiagnosticLog('  ❌ Local network: Server unreachable - $e');
      }
    }
  }

  Future<void> _checkDnsResolution() async {
    _addDiagnosticLog('🔍 Checking DNS resolution...');

    if (ConnectionMode.isRemoteMode) {
      try {
        // Перевірка Localtunnel DNS
        final result = await InternetAddress.lookup('solar-api.loca.lt');
        if (result.isNotEmpty) {
          _addDiagnosticLog(
              '  ✅ DNS: solar-api.loca.lt resolves to ${result.first.address}');
        } else {
          _addDiagnosticLog('  ❌ DNS: solar-api.loca.lt resolution failed');
        }
      } catch (e) {
        _addDiagnosticLog('  ❌ DNS: solar-api.loca.lt error - $e');
        _addDiagnosticLog(
            '  💡 Hint: Check if Localtunnel is running on server');
      }
    } else {
      _addDiagnosticLog('  ℹ️ DNS: Using local IP, no DNS resolution needed');
    }
  }

  Future<void> _checkApiEndpoint() async {
    _addDiagnosticLog('🔗 Checking API endpoint...');

    try {
      final isHealthy = await _apiService.checkConnection();
      if (isHealthy) {
        _addDiagnosticLog('  ✅ API Health: /health endpoint responding');
      } else {
        _addDiagnosticLog('  ❌ API Health: /health endpoint not responding');

        // Додаткові деталі
        _addDiagnosticLog('  🔍 Possible causes:');
        if (ConnectionMode.isRemoteMode) {
          _addDiagnosticLog('    • Localtunnel may be down');
          _addDiagnosticLog('    • Server may be stopped');
          _addDiagnosticLog('    • Firewall blocking connection');
        } else {
          _addDiagnosticLog('    • Server may be stopped (check npm start)');
          _addDiagnosticLog(
              '    • Wrong IP address (check 192.168.68.115:8080)');
          _addDiagnosticLog('    • Network connectivity issue');
        }
      }
    } catch (e) {
      _addDiagnosticLog('  ❌ API Health: Exception - $e');
    }
  }

  Future<void> _checkTokenStatus() async {
    _addDiagnosticLog('🔑 Checking auth token...');

    final token = _apiService.currentToken;
    if (token == null) {
      _addDiagnosticLog('  ❌ Token: Not available');
      _addDiagnosticLog('  💡 Solution: Try logging out and logging in again');
      return;
    }

    _addDiagnosticLog('  ✅ Token: Available (length: ${token.length})');

    if (token.startsWith('test-token')) {
      _addDiagnosticLog('  ℹ️ Token type: Test token');
    } else if (token.startsWith('web-temp-token')) {
      _addDiagnosticLog('  ℹ️ Token type: Web temporary token');
    } else {
      _addDiagnosticLog('  ℹ️ Token type: JWT token');
    }

    // Перевірка валідності токена
    try {
      final userData = await _apiService.getCurrentUser();
      if (userData != null) {
        _addDiagnosticLog('  ✅ Token validation: Valid');
      } else {
        _addDiagnosticLog('  ❌ Token validation: Invalid or expired');
        _addDiagnosticLog('  💡 Solution: Token needs refresh');
      }
    } catch (e) {
      _addDiagnosticLog('  ❌ Token validation: Error - $e');
    }
  }

  void _startListening() {
    setState(() => _isListening = true);

    // Слухаємо MQTT stream
    final mqttProvider = context.read<MqttProvider>();
    _mqttSubscription = mqttProvider.energyStream.listen((data) {
      if (data['deviceId'] == widget.device.deviceId) {
        _mqttMessagesReceived++;
        final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());

        setState(() {
          _mqttLogs.insert(
              0,
              '[$timestamp] MQTT ${data['type'].toString().toUpperCase()}: '
              '${data['powerKw']} kW, ${data['energyKwh']} kWh');

          if (_mqttLogs.length > 100) {
            _mqttLogs = _mqttLogs.take(100).toList();
          }

          _totalCacheSize = _energyService.getCacheSize(widget.device.deviceId);
        });

        _addSystemLog('📨 MQTT data processed and saved to cache');
      }
    });

    _addSystemLog('👂 Started listening to MQTT stream');
  }

  void _addSystemLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _systemLogs.insert(0, '[$timestamp] $message');
      if (_systemLogs.length > 50) {
        _systemLogs = _systemLogs.take(50).toList();
      }
    });
  }

  void _addApiLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _apiLogs.insert(0, '[$timestamp] $message');
      if (_apiLogs.length > 50) {
        _apiLogs = _apiLogs.take(50).toList();
      }
    });
  }

  void _addDiagnosticLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _diagnosticLogs.insert(0, '[$timestamp] $message');
      if (_diagnosticLogs.length > 100) {
        _diagnosticLogs = _diagnosticLogs.take(100).toList();
      }
    });
  }

  Future<void> _testApiConnection() async {
    _addApiLog('🔍 Manual API test started...');

    // Повна діагностика API
    await _performFullDiagnostic();

    try {
      final isConnected = await _apiService.checkConnection();
      _addApiLog(isConnected
          ? '✅ API connection successful'
          : '❌ API connection failed');

      if (isConnected) {
        final token = _apiService.currentToken;
        _addApiLog(
            '🔑 Token status: ${token != null ? "Available (${token.length} chars)" : "Missing"}');

        if (token != null) {
          _addApiLog('📊 Testing energy data API...');
          final energyData = await _apiService
              .getEnergyData(null, widget.device.deviceId, period: '1h');
          _addApiLog('📈 Energy API returned ${energyData.length} data points');
          _apiRequestsSent++;
        }
      } else {
        _addApiLog('💡 Check Diagnostic tab for detailed troubleshooting');
      }
    } catch (e) {
      _addApiLog('❌ API test failed: $e');
      _apiFailures++;
    }
  }

  Future<void> _switchConnectionMode() async {
    final currentMode = ConnectionMode.isRemoteMode ? "Remote" : "Local";
    final newMode = !ConnectionMode.isRemoteMode ? "Remote" : "Local";

    _addSystemLog('🔄 Switching from $currentMode to $newMode mode...');
    _addDiagnosticLog('🔄 Connection mode switch: $currentMode → $newMode');

    await ConnectionMode.setRemoteMode(!ConnectionMode.isRemoteMode);

    // Перезапускаємо діагностику
    await Future.delayed(const Duration(seconds: 1));
    await _performFullDiagnostic();

    _addSystemLog('✅ Switched to $newMode mode');
  }

  // ... (решта коду залишається такою ж, але додаємо нову вкладку Diagnostic)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🐛 Debug - ${widget.device.name}'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _performFullDiagnostic();
              _testApiConnection();
            },
            tooltip: 'Full Diagnostic',
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              setState(() {
                _mqttLogs.clear();
                _apiLogs.clear();
                _systemLogs.clear();
                _diagnosticLogs.clear();
              });
            },
            tooltip: 'Clear All Logs',
          ),
        ],
      ),
      body: Consumer3<MqttProvider, DeviceProvider, AuthProvider>(
        builder: (context, mqttProvider, deviceProvider, authProvider, _) {
          final currentDevice = deviceProvider.devices.firstWhere(
            (d) => d.deviceId == widget.device.deviceId,
            orElse: () => widget.device,
          );

          return Column(
            children: [
              // Статус панель (коротша)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: mqttProvider.isConnected
                      ? Colors.green[100]
                      : Colors.red[100],
                  border: Border(
                    bottom: BorderSide(
                      color:
                          mqttProvider.isConnected ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // MQTT Status
                        Icon(
                          mqttProvider.isConnected
                              ? Icons.wifi
                              : Icons.wifi_off,
                          color: mqttProvider.isConnected
                              ? Colors.green[800]
                              : Colors.red[800],
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'MQTT: ${mqttProvider.isConnected ? "OK" : "OFF"}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: mqttProvider.isConnected
                                ? Colors.green[800]
                                : Colors.red[800],
                          ),
                        ),

                        const SizedBox(width: 16),

                        // API Status
                        Icon(
                          _apiService.isConnected
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          color: _apiService.isConnected
                              ? Colors.blue
                              : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'API: ${_apiService.isConnected ? "OK" : "FAILED"}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _apiService.isConnected
                                ? Colors.blue
                                : Colors.red,
                          ),
                        ),

                        const Spacer(),

                        // Failures counter
                        if (_apiFailures > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Fails: $_apiFailures',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                            'Power: ${currentDevice.status?.powerKw?.toStringAsFixed(2) ?? "0.00"} kW',
                            style: const TextStyle(fontSize: 11)),
                        Text('Cache: $_totalCacheSize pts',
                            style: const TextStyle(fontSize: 11)),
                        Text(
                            'Mode: ${ConnectionMode.isRemoteMode ? "Remote" : "Local"}',
                            style: const TextStyle(fontSize: 11)),
                        Text('MQTT: $_mqttMessagesReceived msgs',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),

              // Кнопки управління
              Container(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ElevatedButton(
                      onPressed: _testApiConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      child: const Text('Test API',
                          style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton(
                      onPressed: _switchConnectionMode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      child: Text(
                        'Switch to ${!ConnectionMode.isRemoteMode ? "Remote" : "Local"}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _performFullDiagnostic,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      child: const Text('Diagnose',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),

              // Логи в табах (тепер 4 таби)
              Expanded(
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.grey[200],
                        child: const TabBar(
                          labelColor: Colors.black,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Colors.blue,
                          tabs: [
                            Tab(icon: Icon(Icons.wifi, size: 14), text: 'MQTT'),
                            Tab(icon: Icon(Icons.api, size: 14), text: 'API'),
                            Tab(
                                icon: Icon(Icons.medical_services, size: 14),
                                text: 'Diagnostic'),
                            Tab(
                                icon: Icon(Icons.settings, size: 14),
                                text: 'System'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // MQTT Logs
                            _buildLogView(
                              logs: _mqttLogs,
                              emptyMessage: 'Waiting for MQTT data...\n\n'
                                  'If no messages appear:\n'
                                  '• Check ESP32 WiFi connection\n'
                                  '• Ensure relay is ON\n'
                                  '• Verify MQTT broker IP\n\n'
                                  'Expected format:\n'
                                  '[14:23:15] MQTT STATUS: 2.45 kW, 123.45 kWh',
                              backgroundColor: Colors.green[50],
                            ),

                            // API Logs
                            _buildLogView(
                              logs: _apiLogs,
                              emptyMessage: 'API activity logs appear here.\n\n'
                                  'Click "Test API" button to check.\n\n'
                                  'If API fails, check Diagnostic tab\n'
                                  'for detailed troubleshooting.',
                              backgroundColor: Colors.blue[50],
                            ),

                            // Diagnostic Logs - НОВИЙ ТАБ
                            _buildLogView(
                              logs: _diagnosticLogs,
                              emptyMessage:
                                  'Diagnostic information will appear here.\n\n'
                                  'This tab shows detailed analysis of:\n'
                                  '• Network connectivity\n'
                                  '• DNS resolution\n'
                                  '• API endpoints\n'
                                  '• Token validation\n\n'
                                  'Click "Diagnose" to run full check.',
                              backgroundColor: Colors.red[50],
                            ),

                            // System Logs
                            _buildLogView(
                              logs: _systemLogs,
                              emptyMessage: 'System events appear here.',
                              backgroundColor: Colors.orange[50],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogView({
    required List<String> logs,
    required String emptyMessage,
    Color? backgroundColor,
  }) {
    return Container(
      color: backgroundColor ?? Colors.grey[50],
      child: logs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(4),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final isError = log.contains('❌');
                final isSuccess = log.contains('✅');
                final isWarning = log.contains('⚠️') || log.contains('💡');
                final isInfo = log.contains('ℹ️') || log.contains('🔍');

                Color? textColor;
                Color? backgroundColor;

                if (isError) {
                  textColor = Colors.red[700];
                  backgroundColor = Colors.red[50];
                } else if (isSuccess) {
                  textColor = Colors.green[700];
                  backgroundColor = Colors.green[50];
                } else if (isWarning) {
                  textColor = Colors.orange[700];
                  backgroundColor = Colors.orange[50];
                } else if (isInfo) {
                  textColor = Colors.blue[700];
                  backgroundColor = Colors.blue[50];
                }

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: BoxDecoration(
                    color: backgroundColor ??
                        (index % 2 == 0 ? Colors.white : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: textColor ?? Colors.black87,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
