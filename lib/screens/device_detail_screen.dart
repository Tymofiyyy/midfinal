import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../models/device.dart';
import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';
import '../config/app_config.dart';
import 'energy_chart_screen.dart';
import 'dart:core';

class DeviceDetailScreen extends StatefulWidget {
  final Device device;

  const DeviceDetailScreen({
    super.key,
    required this.device,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Автоматичне оновлення кожні 2 секунди
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        context.read<DeviceProvider>().fetchDevices();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        actions: [
          if (widget.device.isOwner)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _showShareDialog(context),
            ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, deviceProvider, _) {
          final currentDevice = deviceProvider.devices.firstWhere(
            (d) => d.deviceId == widget.device.deviceId,
            orElse: () => widget.device,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.power_settings_new,
                          size: 64,
                          color: currentDevice.status?.relayState ?? false
                              ? const Color(0xFFFBBF24)
                              : Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          currentDevice.status?.relayState ?? false
                              ? 'Увімкнено'
                              : 'Вимкнено',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: currentDevice.status?.online ?? false
                                ? () => context
                                    .read<DeviceProvider>()
                                    .toggleRelay(
                                      currentDevice.deviceId,
                                      currentDevice.status?.relayState ?? false,
                                    )
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  currentDevice.status?.relayState ?? false
                                      ? Colors.red
                                      : const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              currentDevice.status?.relayState ?? false
                                  ? 'Вимкнути'
                                  : 'Увімкнути',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Energy Card
                if (currentDevice.status?.online ?? false)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Енергія',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.bar_chart),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EnergyChartScreen(
                                        device: currentDevice,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Column(
                                children: [
                                  const Icon(
                                    Icons.flash_on,
                                    color: Colors.orange,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${currentDevice.status?.powerKw?.toStringAsFixed(2) ?? "0.00"} kW',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'Потужність',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                width: 1,
                                height: 60,
                                color: Colors.grey[300],
                              ),
                              Column(
                                children: [
                                  const Icon(
                                    Icons.battery_charging_full,
                                    color: Colors.green,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${currentDevice.status?.energyKwh?.toStringAsFixed(2) ?? "0.00"} kWh',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'Загальна енергія',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EnergyChartScreen(
                                      device: currentDevice,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.show_chart),
                              label: const Text('Переглянути графіки'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Інформація про пристрій',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _InfoRow(
                          label: 'ID пристрою',
                          value: currentDevice.deviceId,
                        ),
                        _InfoRow(
                          label: 'Назва',
                          value: currentDevice.name,
                        ),
                        _InfoRow(
                          label: 'Статус',
                          value: currentDevice.status?.online ?? false
                              ? 'Онлайн'
                              : 'Офлайн',
                          valueColor: currentDevice.status?.online ?? false
                              ? Colors.green
                              : Colors.red,
                        ),
                        if (currentDevice.status?.online ?? false) ...[
                          _InfoRow(
                            label: 'WiFi сигнал',
                            value: '${currentDevice.status?.wifiRSSI ?? 0} dBm',
                          ),
                          _InfoRow(
                            label: 'Час роботи',
                            value: _formatUptime(
                                currentDevice.status?.uptime ?? 0),
                          ),
                          _InfoRow(
                            label: 'Вільна пам\'ять',
                            value: _formatMemory(
                                currentDevice.status?.freeHeap ?? 0),
                          ),
                        ],
                        _InfoRow(
                          label: 'Додано',
                          value: _formatDate(currentDevice.addedAt),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showShareDialog(BuildContext context) {
    final emailController = TextEditingController();
    List<Map<String, dynamic>> registeredUsers = [];
    bool isLoading = true;

    // Функція для завантаження користувачів
    Future<void> loadUsers() async {
      try {
        final token = context.read<AuthProvider>().token;
        final response = await Dio().get(
          '${AppConfig.apiUrl}/users',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        registeredUsers = List<Map<String, dynamic>>.from(response.data);
      } catch (e) {
        debugPrint('Error loading users: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          if (isLoading) {
            loadUsers().then((_) {
              setState(() => isLoading = false);
            });
          }

          return AlertDialog(
            title: const Text('Поділитися пристроєм'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Виберіть користувача або введіть email',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (isLoading)
                  const CircularProgressIndicator()
                else if (registeredUsers.isNotEmpty) ...[
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: registeredUsers.length,
                      itemBuilder: (context, index) {
                        final user = registeredUsers[index];
                        return ListTile(
                          title: Text(user['name'] ?? user['email']),
                          subtitle: Text(user['email']),
                          onTap: () {
                            emailController.text = user['email'];
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email користувача',
                    hintText: 'user@example.com',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Користувач повинен бути зареєстрований в системі',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Скасувати'),
              ),
              TextButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isNotEmpty) {
                    Navigator.pop(context);

                    final success =
                        await context.read<DeviceProvider>().shareDevice(
                              widget.device.deviceId,
                              email,
                            );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Доступ надано'
                                : 'Помилка: користувач не знайдений або вже має доступ',
                          ),
                          backgroundColor: success ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Поділитися'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatUptime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '$hoursг $minutesхв';
    }
    return '$minutesхв';
  }

  String _formatMemory(int bytes) {
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
