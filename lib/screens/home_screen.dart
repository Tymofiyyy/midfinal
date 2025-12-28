// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../providers/mqtt_provider.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/energy_mode_toggle.dart';
import '../models/device.dart';
import '../config/connection_mode.dart';
import 'add_device_screen.dart';
import 'device_detail_screen.dart';
import 'energy_schedules_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Connect to MQTT
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MqttProvider>().connect();
    });

    // Автоматичне оновлення кожні 5 секунд
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
    final authProvider = context.watch<AuthProvider>();
    final deviceProvider = context.watch<DeviceProvider>();
    final mqttProvider = context.watch<MqttProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    offset: Offset(0, 1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.wb_sunny,
                    color: Color(0xFFFBBF24),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Solar Controller',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Перемикач режиму
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ConnectionMode.isRemoteMode ? 'Remote' : 'Local',
                        style: TextStyle(
                          fontSize: 10,
                          color: ConnectionMode.isRemoteMode
                              ? Colors.green
                              : Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: ConnectionMode.isRemoteMode,
                          onChanged: (value) async {
                            await ConnectionMode.setRemoteMode(value);

                            // Показуємо повідомлення
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? 'Перемкнуто на Remote (Internet)'
                                        : 'Перемкнуто на Local (Home)',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );

                              // Перезавантажуємо сторінку для оновлення
                              setState(() {});

                              // Перезавантажуємо дані
                              context.read<DeviceProvider>().fetchDevices();

                              // Перепідключаємо MQTT
                              final mqttProvider = context.read<MqttProvider>();
                              await mqttProvider.reconnect();
                            }
                          },
                          activeColor: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 8),

                  CircleAvatar(
                    radius: 16,
                    backgroundImage: authProvider.user?.picture != null
                        ? NetworkImage(authProvider.user!.picture!)
                        : null,
                    child: authProvider.user?.picture == null
                        ? Text(authProvider.user?.name[0] ?? '')
                        : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Вихід'),
                          content: const Text('Ви впевнені, що хочете вийти?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Скасувати'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Вийти'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await authProvider.logout();
                      }
                    },
                  ),
                ],
              ),
            ),

            // Connection Status Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ConnectionMode.isRemoteMode
                    ? Colors.green.withOpacity(0.1)
                    : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ConnectionMode.isRemoteMode
                      ? Colors.green.withOpacity(0.3)
                      : Colors.blue.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ConnectionMode.isRemoteMode ? Icons.public : Icons.home,
                    size: 16,
                    color: ConnectionMode.isRemoteMode
                        ? Colors.green
                        : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ConnectionMode.isRemoteMode
                          ? 'Підключено через Internet'
                          : 'Локальне підключення',
                      style: TextStyle(
                        fontSize: 12,
                        color: ConnectionMode.isRemoteMode
                            ? Colors.green[700]
                            : Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // MQTT Status
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: mqttProvider.isConnected
                          ? Colors.green.withOpacity(0.2)
                          : mqttProvider.isConnecting
                              ? Colors.orange.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sensors,
                          size: 12,
                          color: mqttProvider.isConnected
                              ? Colors.green
                              : mqttProvider.isConnecting
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mqttProvider.isConnected
                              ? 'MQTT OK'
                              : mqttProvider.isConnecting
                                  ? 'Connecting...'
                                  : 'MQTT Offline',
                          style: TextStyle(
                            fontSize: 10,
                            color: mqttProvider.isConnected
                                ? Colors.green
                                : mqttProvider.isConnecting
                                    ? Colors.orange
                                    : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Stats
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.power_settings_new,
                      color: const Color(0xFF3B82F6),
                      label: 'Активні',
                      value: deviceProvider.devices
                          .where((d) => d.status?.relayState ?? false)
                          .length
                          .toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.wifi,
                      color: const Color(0xFF10B981),
                      label: 'Онлайн',
                      value: deviceProvider.devices
                          .where((d) => d.status?.online ?? false)
                          .length
                          .toString(),
                    ),
                  ),
                ],
              ),
            ),

            // Energy Mode Toggles для кожного пристрою
            if (deviceProvider.devices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Джерела енергії',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...deviceProvider.devices.map((device) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (deviceProvider.devices.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  device.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            EnergyModeToggle(
                              device: device,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EnergySchedulesScreen(device: device),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Devices List
            Expanded(
              child: RefreshIndicator(
                onRefresh: deviceProvider.fetchDevices,
                child: deviceProvider.isLoading &&
                        deviceProvider.devices.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : deviceProvider.devices.isEmpty
                        ? EmptyState(
                            onAddDevice: () => _navigateToAddDevice(context),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: deviceProvider.devices.length,
                            itemBuilder: (context, index) {
                              final device = deviceProvider.devices[index];
                              return DeviceCard(
                                device: device,
                                onTap: () =>
                                    _navigateToDeviceDetail(context, device),
                                onToggle: () => deviceProvider.toggleRelay(
                                  device.deviceId,
                                  device.status?.relayState ?? false,
                                ),
                                onDelete: () => _deleteDevice(context, device),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: deviceProvider.devices.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _navigateToAddDevice(context),
              backgroundColor: const Color(0xFF3B82F6),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _navigateToAddDevice(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddDeviceScreen()),
    );
  }

  void _navigateToDeviceDetail(BuildContext context, Device device) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeviceDetailScreen(device: device)),
    );
  }

  Future<void> _deleteDevice(BuildContext context, Device device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити пристрій'),
        content: Text('Ви впевнені, що хочете видалити ${device.name}?'),
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

    if (confirm == true && context.mounted) {
      final success =
          await context.read<DeviceProvider>().deleteDevice(device.deviceId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Пристрій видалено' : 'Помилка видалення пристрою',
            ),
          ),
        );
      }
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
