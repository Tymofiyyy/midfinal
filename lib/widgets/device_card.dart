// lib/widgets/device_card.dart
import 'package:flutter/material.dart';
import '../models/device.dart';

class DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = device.status?.online ?? false;
    final relayState = device.status?.relayState ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              isOnline ? Icons.wifi : Icons.wifi_off,
                              size: 16,
                              color: isOnline ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOnline ? 'Онлайн' : 'Офлайн',
                              style: TextStyle(
                                fontSize: 12,
                                color: isOnline ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: relayState,
                    onChanged: isOnline ? (_) => onToggle() : null,
                    activeColor: const Color(0xFFFBBF24),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    device.deviceId,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  if (device.isOwner)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDEAFE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Власник',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF3B82F6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    iconSize: 20,
                    color: Colors.grey[600],
                  ),
                ],
              ),
              if (isOnline && device.status != null) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    _MetricItem(
                      icon: Icons.network_wifi,
                      value: '${device.status!.wifiRSSI ?? 0} dBm',
                    ),
                    const SizedBox(width: 16),
                    _MetricItem(
                      icon: Icons.access_time,
                      value: '${(device.status!.uptime ?? 0) ~/ 3600}h',
                    ),
                    if (device.status!.powerKw != null) ...[
                      const SizedBox(width: 16),
                      _MetricItem(
                        icon: Icons.flash_on,
                        value:
                            '${device.status!.powerKw!.toStringAsFixed(1)} kW',
                        color: Colors.orange,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;

  const _MetricItem({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 12, color: color ?? Colors.grey[600]),
        ),
      ],
    );
  }
}
