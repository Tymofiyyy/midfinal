// lib/screens/energy_chart_screen.dart - З 3 ГРАФІКАМИ (+ ДЕННА ІСТОРІЯ)
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';
import '../models/device.dart';
import '../models/energy_data.dart';
import '../models/daily_energy_summary.dart';
import '../services/energy_service.dart';
import '../providers/mqtt_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import 'debug_screen.dart';

class EnergyChartScreen extends StatefulWidget {
  final Device device;

  const EnergyChartScreen({super.key, required this.device});

  @override
  State<EnergyChartScreen> createState() => _EnergyChartScreenState();
}

class _EnergyChartScreenState extends State<EnergyChartScreen>
    with SingleTickerProviderStateMixin {
  List<EnergyData> _filteredData = [];
  List<DailyEnergySummary> _dailyHistory = []; // НОВИЙ: історія по днях
  String _selectedPeriod = '24h';
  bool _isLoading = true;
  StreamSubscription? _mqttSubscription;
  Timer? _autoSyncTimer;
  final EnergyService _energyService = EnergyService();

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  int _totalDataPoints = 0;
  DateTime? _lastUpdateTime;
  DateTime? _lastResetTime;
  bool _isOnline = false;
  bool _isSyncing = false;
  bool _isResetting = false;
  int _autoSyncCount = 0;

  final Map<String, String> _periodOptions = {
    '1h': '1 година',
    '6h': '6 годин',
    '24h': '24 години',
    '7d': '7 днів',
    '30d': '30 днів',
    'all': 'Весь час',
  };

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _loadData();
    _loadDailyHistory(); // НОВИЙ: завантаження історії
    _setupMqttListener();
    _startAutoSync();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _mqttSubscription?.cancel();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  void _startAutoSync() {
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isLoading && !_isResetting) {
        _autoSyncCount++;
        _loadData(isAutoSync: true);
      }
    });
  }

  void _setupMqttListener() {
    final mqttProvider = context.read<MqttProvider>();
    _mqttSubscription = mqttProvider.energyStream.listen((data) {
      if (data['deviceId'] == widget.device.deviceId && mounted) {
        setState(() {
          _lastUpdateTime = data['timestamp'] as DateTime;
          _isOnline = true;
        });

        if (data['type'] == 'midnight_reset') {
          print('🕛 UI: Received midnight reset notification');

          _animationController.forward().then((_) {
            _animationController.reverse();
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.restart_alt, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['message'] ?? '🕛 Midnight reset completed',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 3),
              ),
            );
          }

          // Перезавантажуємо ОБА списки
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && !_isLoading) {
              _loadData(isAutoSync: false);
              _loadDailyHistory(); // Оновлюємо історію після reset
            }
          });
        } else if (data['type'] != 'auto_sync') {
          _animationController.forward().then((_) {
            _animationController.reverse();
          });

          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && !_isLoading) {
              _loadData(isAutoSync: false);
            }
          });
        }
      }
    });
  }

  // НОВИЙ: Завантаження денної історії
  Future<void> _loadDailyHistory() async {
    try {
      final history =
          await _energyService.getDailyHistory(widget.device.deviceId);

      if (mounted) {
        setState(() {
          _dailyHistory = history;
        });
        print('📚 Loaded ${history.length} daily history records');
      }
    } catch (e) {
      print('Error loading daily history: $e');
    }
  }

  Future<void> _loadData({bool isAutoSync = false}) async {
    if (_isSyncing || _isResetting) return;

    try {
      setState(() {
        if (_filteredData.isEmpty || !isAutoSync) {
          _isLoading = true;
        }
        _isSyncing = true;
      });

      final data = await _energyService.getEnergyData(
        widget.device.deviceId,
        period: _selectedPeriod,
      );

      if (mounted) {
        setState(() {
          _filteredData = data;
          _totalDataPoints =
              _energyService.getCacheSize(widget.device.deviceId);
          _lastResetTime =
              _energyService.getLastResetTime(widget.device.deviceId);
          _isLoading = false;
          _isSyncing = false;
        });
      }
    } catch (e) {
      print('Error loading energy data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _testMidnightReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.science, color: Colors.orange),
            SizedBox(width: 8),
            Text('Test 00:00 Reset'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Це симулює автоматичне очищення о 00:00:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildResetStep('1', 'Збереже денну статистику'),
            _buildResetStep('2', 'Очистить поточні графіки'),
            _buildResetStep('3', 'Додасть точку в історію'),
            _buildResetStep('4', 'Скине ESP32 лічильник'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Денна статистика буде збережена!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Тест Reset'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isResetting = true);

      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('🧪 Зберігаю статистику та очищаю...'),
                ],
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }

        final mqttProvider = context.read<MqttProvider>();
        await mqttProvider.triggerMidnightReset(widget.device.deviceId);

        await Future.delayed(const Duration(seconds: 2));

        await _loadData(isAutoSync: false);
        await _loadDailyHistory(); // Оновлюємо історію

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('✅ Reset успішний! Історія збережена.'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        print('Error during test midnight reset: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Reset виконано локально (MQTT offline)'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isResetting = false);
        }
      }
    }
  }

  Widget _buildResetStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Future<void> _generateTestData() async {
    setState(() => _isLoading = true);

    try {
      await _energyService.generateTestData(widget.device.deviceId);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Тестові дані згенеровано')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Помилка: $e')),
        );
      }
    }
  }

  Future<void> _clearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистити дані?'),
        content: const Text(
            'Це видалить всі дані поточного дня (історія збережеться).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await _energyService.clearData(widget.device.deviceId);
        await _loadData();
        await _loadDailyHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🗑️ Дані поточного дня очищено')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Помилка: $e')),
          );
        }
      }
    }
  }

  Future<void> _syncWithServer() async {
    setState(() => _isSyncing = true);

    try {
      await _energyService.syncWithServer(widget.device.deviceId);
      await _loadData();
      await _loadDailyHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Синхронізація завершена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Помилка: $e')),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<MqttProvider, DeviceProvider, AuthProvider>(
      builder: (context, mqttProvider, deviceProvider, authProvider, _) {
        _isOnline = mqttProvider.isConnected;

        final currentDevice = deviceProvider.devices.firstWhere(
          (d) => d.deviceId == widget.device.deviceId,
          orElse: () => widget.device,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text('Енергія - ${currentDevice.name}'),
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            actions: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isOnline ? _pulseAnimation.value : 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isOnline ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isOnline ? Icons.cloud_done : Icons.cloud_off,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isOnline ? 'ONLINE' : 'OFFLINE',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: _isSyncing || _isResetting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _isSyncing || _isResetting
                    ? null
                    : () {
                        _loadData(isAutoSync: false);
                        _loadDailyHistory();
                      },
                tooltip: 'Оновити',
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'debug':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DebugScreen(device: currentDevice),
                        ),
                      );
                      break;
                    case 'test_midnight':
                      _testMidnightReset();
                      break;
                    case 'generate':
                      _generateTestData();
                      break;
                    case 'clear':
                      _clearData();
                      break;
                    case 'sync':
                      _syncWithServer();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'test_midnight',
                    child: Row(
                      children: [
                        Icon(Icons.science, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('🧪 Тест 00:00 Reset'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'debug',
                    child: Row(
                      children: [
                        Icon(Icons.bug_report, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Debug MQTT'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'sync',
                    child: Row(
                      children: [
                        Icon(Icons.sync, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Повна синхронізація'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'generate',
                    child: Row(
                      children: [
                        Icon(Icons.science, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Тестові дані'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Очистити день'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _isLoading && _filteredData.isEmpty && _dailyHistory.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildStatusPanel(currentDevice),
                    _buildPeriodSelector(),
                    if (_filteredData.isNotEmpty) _buildStatistics(),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildChartsWithTabs(currentDevice),
                    ),
                  ],
                ),
        );
      },
    );
  }

  // НОВИЙ: Графіки з табами (3 графіки)
  Widget _buildChartsWithTabs(Device device) {
    if (_filteredData.length < 2 && _dailyHistory.isEmpty) {
      return _buildEmptyState();
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.grey[200],
            child: const TabBar(
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Color(0xFF3B82F6),
              tabs: [
                Tab(icon: Icon(Icons.flash_on, size: 18), text: 'Потужність'),
                Tab(icon: Icon(Icons.battery_full, size: 18), text: 'Енергія'),
                Tab(
                    icon: Icon(Icons.calendar_today, size: 18),
                    text: 'Історія'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Графік потужності
                _filteredData.length < 2
                    ? _buildEmptyState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _ChartCard(
                          title: 'Потужність (kW)',
                          subtitle: 'Дані кожні 15 секунд',
                          child: SizedBox(
                            height: 250,
                            child: _buildPowerChart(),
                          ),
                        ),
                      ),
                // Графік енергії
                _filteredData.length < 2
                    ? _buildEmptyState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _ChartCard(
                          title: 'Накопичена енергія (kWh)',
                          subtitle: 'Дані кожні 15 секунд',
                          child: SizedBox(
                            height: 250,
                            child: _buildEnergyChart(),
                          ),
                        ),
                      ),
                // НОВИЙ: Графік денної історії
                _dailyHistory.isEmpty
                    ? _buildEmptyHistoryState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _ChartCard(
                              title: 'Денна статистика',
                              subtitle: 'Накопичена енергія за день',
                              child: SizedBox(
                                height: 250,
                                child: _buildDailyHistoryChart(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildDailyHistoryList(),
                          ],
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // НОВИЙ: Графік денної історії (bar chart)
  Widget _buildDailyHistoryChart() {
    if (_dailyHistory.isEmpty) return const SizedBox();

    // Беремо останні 30 днів
    final recentHistory = _dailyHistory.length > 30
        ? _dailyHistory.sublist(_dailyHistory.length - 30)
        : _dailyHistory;

    final spots = recentHistory.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        entry.value.totalEnergyKwh,
      );
    }).toList();

    if (spots.isEmpty) return const SizedBox();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: recentHistory
                .map((e) => e.totalEnergyKwh)
                .reduce((a, b) => a > b ? a : b) *
            1.2,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 &&
                    value.toInt() < recentHistory.length) {
                  final date = recentHistory[value.toInt()].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('dd\nMMM').format(date),
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 40,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 11),
                );
              },
              reservedSize: 35,
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        barGroups: recentHistory.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.totalEnergyKwh,
                gradient: LinearGradient(
                  colors: [
                    Colors.green[400]!,
                    Colors.green[700]!,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 16,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // НОВИЙ: Список денної історії
  Widget _buildDailyHistoryList() {
    if (_dailyHistory.isEmpty) return const SizedBox();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Деталі по днях',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: min(_dailyHistory.length, 10), // Показуємо останні 10
            itemBuilder: (context, index) {
              final reversedIndex = _dailyHistory.length - 1 - index;
              final summary = _dailyHistory[reversedIndex];

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green[100],
                  child: Icon(
                    Icons.calendar_today,
                    color: Colors.green[700],
                    size: 20,
                  ),
                ),
                title: Text(
                  DateFormat('dd MMMM yyyy').format(summary.date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Макс: ${summary.maxPowerKw.toStringAsFixed(2)} kW • '
                  'Сер: ${summary.avgPowerKw.toStringAsFixed(2)} kW • '
                  '${summary.dataPoints} точок',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${summary.totalEnergyKwh.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const Text(
                      'kWh',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_dailyHistory.length > 10)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '... та ще ${_dailyHistory.length - 10} днів',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Немає денної історії',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Після першого midnight reset\nтут з\'явиться історія',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _testMidnightReset,
            icon: const Icon(Icons.science),
            label: const Text('🧪 Створити першу точку'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(Device device) {
    final hasData = _filteredData.isNotEmpty;
    final currentPower = device.status?.powerKw ?? 0.0;
    final lastFetch = _energyService.getLastFetchTime(widget.device.deviceId);

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final timeToReset = nextMidnight.difference(now);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: hasData ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasData ? Colors.green : Colors.orange,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                hasData ? Icons.storage : Icons.hourglass_empty,
                color: hasData ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasData ? 'Автосинхронізація активна' : 'Очікування...',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'День: ${_filteredData.length} | Історія: ${_dailyHistory.length} днів',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (lastFetch != null)
                      Text(
                        'Синхр: ${DateFormat('HH:mm:ss').format(lastFetch)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      '${currentPower.toStringAsFixed(2)} kW',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange,
                      ),
                    ),
                    const Text(
                      'Зараз',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isSyncing || _isResetting) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  _isResetting ? 'Зберігаю історію...' : 'Синхронізація...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.purple[200]!),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.purple[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🕛 Auto reset + save history',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[700],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${timeToReset.inHours}:${(timeToReset.inMinutes % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple[700],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_lastResetTime != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last reset: ${DateFormat('HH:mm:ss dd.MM').format(_lastResetTime!)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.purple[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _periodOptions.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: _selectedPeriod == entry.key,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedPeriod = entry.key;
                    });
                    _loadData(isAutoSync: false);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    if (_filteredData.isEmpty) return const SizedBox();

    final powers = _filteredData.map((e) => e.powerKw).toList();
    final minPower = powers.reduce(min);
    final maxPower = powers.reduce(max);
    final avgPower = powers.reduce((a, b) => a + b) / powers.length;
    final lastPower = _filteredData.last.powerKw;
    final lastEnergy = _filteredData.last.energyKwh;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCard(
                title: 'Мін',
                value: '${minPower.toStringAsFixed(2)} kW',
                icon: Icons.arrow_downward,
                color: Colors.blue,
              ),
              _StatCard(
                title: 'Макс',
                value: '${maxPower.toStringAsFixed(2)} kW',
                icon: Icons.arrow_upward,
                color: Colors.red,
              ),
              _StatCard(
                title: 'Середнє',
                value: '${avgPower.toStringAsFixed(2)} kW',
                icon: Icons.trending_flat,
                color: Colors.purple,
              ),
              _StatCard(
                title: 'Зараз',
                value: '${lastPower.toStringAsFixed(2)} kW',
                icon: Icons.flash_on,
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCard(
                title: 'Сьогодні',
                value: '${lastEnergy.toStringAsFixed(1)} kWh',
                icon: Icons.battery_full,
                color: Colors.green,
              ),
              _StatCard(
                title: 'Днів',
                value: '${_dailyHistory.length}',
                icon: Icons.calendar_today,
                color: Colors.indigo,
              ),
              _StatCard(
                title: 'Точок',
                value: '${_filteredData.length}',
                icon: Icons.data_usage,
                color: Colors.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Немає даних',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _generateTestData,
            icon: const Icon(Icons.science),
            label: const Text('Тестові дані'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _testMidnightReset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('🧪 Тест 00:00'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerChart() {
    if (_filteredData.length < 2) return const SizedBox();

    final spots = _filteredData.map((data) {
      return FlSpot(
        data.timestamp.millisecondsSinceEpoch.toDouble(),
        data.powerKw,
      );
    }).toList();

    final double minX = spots.first.x;
    final double maxX = spots.last.x;
    final powers = spots.map((s) => s.y).toList();
    final double maxY = powers.reduce(max) * 1.2;
    const double minY = 0;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (maxX - minX) / 4,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    DateFormat('HH:mm').format(date),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY > 0 ? maxY : 5,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.orange,
            barWidth: 3,
            dotData: FlDotData(
              show: spots.length <= 288,
              getDotPainter: (spot, percent, barData, index) {
                final isLast = index == spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 5 : 2,
                  color:
                      isLast ? Colors.orange : Colors.orange.withOpacity(0.6),
                  strokeWidth: isLast ? 2 : 1,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withOpacity(0.3),
                  Colors.orange.withOpacity(0.1),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final date =
                    DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(2)} kW\n${DateFormat('HH:mm:ss').format(date)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEnergyChart() {
    if (_filteredData.length < 2) return const SizedBox();

    final spots = _filteredData.map((data) {
      return FlSpot(
        data.timestamp.millisecondsSinceEpoch.toDouble(),
        data.energyKwh,
      );
    }).toList();

    final double minX = spots.first.x;
    final double maxX = spots.last.x;
    final energies = spots.map((s) => s.y).toList();
    final double minY = energies.reduce(min) * 0.9;
    final double maxY = energies.reduce(max) * 1.1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (maxX - minX) / 4,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    DateFormat('HH:mm').format(date),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        minX: minX,
        maxX: maxX,
        minY: minY >= 0 ? minY : 0,
        maxY: maxY > 0 ? maxY : 10,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.green,
            barWidth: 3,
            dotData: FlDotData(
              show: spots.length <= 288,
              getDotPainter: (spot, percent, barData, index) {
                final isLast = index == spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 5 : 2,
                  color: isLast ? Colors.green : Colors.green.withOpacity(0.6),
                  strokeWidth: isLast ? 2 : 1,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.green.withOpacity(0.3),
                  Colors.green.withOpacity(0.1),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final date =
                    DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(2)} kWh\n${DateFormat('HH:mm:ss').format(date)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
