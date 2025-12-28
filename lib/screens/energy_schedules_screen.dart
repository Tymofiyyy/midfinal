// lib/screens/energy_schedules_screen.dart
// ОНОВЛЕНО: Підтримка відображення TIME та RANGE розкладів

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/device.dart';
import '../models/energy_schedule.dart';
import '../providers/energy_provider.dart';
import 'add_schedule_screen.dart';

class EnergySchedulesScreen extends StatefulWidget {
  final Device device;

  const EnergySchedulesScreen({super.key, required this.device});

  @override
  State<EnergySchedulesScreen> createState() => _EnergySchedulesScreenState();
}

class _EnergySchedulesScreenState extends State<EnergySchedulesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final energyProvider = context.read<EnergyProvider>();
    await energyProvider.loadSchedules(widget.device.deviceId);
    await energyProvider.loadEnergyMode(widget.device.deviceId);
    await energyProvider.loadEnergyModeHistory(widget.device.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Розклади - ${widget.device.name}'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _showHistory(),
            tooltip: 'Історія перемикань',
          ),
        ],
      ),
      body: Consumer<EnergyProvider>(
        builder: (context, energyProvider, _) {
          final schedules = energyProvider.getSchedules(widget.device.deviceId);
          final currentMode =
              energyProvider.getEnergyMode(widget.device.deviceId);

          return RefreshIndicator(
            onRefresh: _loadData,
            child: CustomScrollView(
              slivers: [
                // Поточний режим
                SliverToBoxAdapter(
                  child: _buildCurrentModeCard(currentMode),
                ),

                // Заголовок розкладів
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Автоматичні розклади',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${schedules.where((s) => s.isEnabled).length} активних',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[600]),
                            ),
                            Text(
                              _getScheduleTypesCount(schedules),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Список розкладів
                if (schedules.isEmpty)
                  SliverFillRemaining(
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final schedule = schedules[index];
                          return _ScheduleCard(
                            schedule: schedule,
                            device: widget.device,
                            onToggle: () => _toggleSchedule(schedule),
                            onEdit: () => _editSchedule(schedule),
                            onDelete: () => _deleteSchedule(schedule),
                          );
                        },
                        childCount: schedules.length,
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 80),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSchedule,
        icon: const Icon(Icons.add),
        label: const Text('Новий розклад'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
      ),
    );
  }

  String _getScheduleTypesCount(List<EnergySchedule> schedules) {
    final timeCount = schedules.where((s) => s.isTimeSchedule).length;
    final rangeCount = schedules.where((s) => s.isRangeSchedule).length;

    final parts = <String>[];
    if (timeCount > 0) parts.add('$timeCount час');
    if (rangeCount > 0) parts.add('$rangeCount діап');

    return parts.isEmpty ? '' : parts.join(', ');
  }

  Widget _buildCurrentModeCard(currentMode) {
    if (currentMode == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final isSolar = currentMode.isSolar;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSolar ? Colors.orange.shade200 : Colors.blue.shade200,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSolar
                          ? Colors.orange.shade100
                          : Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSolar ? Icons.wb_sunny : Icons.location_city,
                      size: 40,
                      color: isSolar ? Colors.orange : Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Поточний режим',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSolar ? 'Сонячна енергія' : 'Міська енергія',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getChangedByText(currentMode.changedBy),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Змінено: ${DateFormat('dd.MM.yyyy HH:mm').format(currentMode.lastChanged)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Немає розкладів',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Створіть автоматичний розклад перемикання енергії.\n'
              'Можна вибрати конкретний час або діапазон годин.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _addSchedule,
              icon: const Icon(Icons.add),
              label: const Text('Створити розклад'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSchedule() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleScreen(device: widget.device),
      ),
    );

    if (result == true && mounted) {
      await _loadData();
    }
  }

  void _editSchedule(EnergySchedule schedule) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleScreen(
          device: widget.device,
          schedule: schedule,
        ),
      ),
    );

    if (result == true && mounted) {
      await _loadData();
    }
  }

  Future<void> _toggleSchedule(EnergySchedule schedule) async {
    final energyProvider = context.read<EnergyProvider>();
    final success = await energyProvider.toggleSchedule(
      widget.device.deviceId,
      schedule.id!,
      !schedule.isEnabled,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                schedule.isEnabled ? 'Розклад вимкнено' : 'Розклад увімкнено'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Помилка зміни статусу розкладу'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSchedule(EnergySchedule schedule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити розклад?'),
        content:
            Text('Ви впевнені, що хочете видалити розклад "${schedule.name}"?'),
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

    if (confirm == true && mounted) {
      final energyProvider = context.read<EnergyProvider>();
      final success = await energyProvider.deleteSchedule(
        widget.device.deviceId,
        schedule.id!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                success ? 'Розклад видалено' : 'Помилка видалення розкладу'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _HistoryBottomSheet(device: widget.device),
    );
  }

  String _getChangedByText(String changedBy) {
    switch (changedBy) {
      case 'manual':
        return '⚙️ Змінено вручну';
      case 'schedule':
        return '⏰ Змінено за розкладом (час)';
      case 'schedule_range':
        return '📅 Змінено за розкладом (діапазон)';
      case 'default':
        return '🔧 Дефолтне значення';
      default:
        return changedBy;
    }
  }
}

// Карточка розкладу - ОНОВЛЕНО для підтримки TIME та RANGE
class _ScheduleCard extends StatelessWidget {
  final EnergySchedule schedule;
  final Device device;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ScheduleCard({
    required this.schedule,
    required this.device,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isSolar = schedule.isSolar;
    final isRange = schedule.isRangeSchedule;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: schedule.isEnabled
              ? (isRange
                  ? Colors.purple.shade200
                  : (isSolar ? Colors.orange.shade200 : Colors.blue.shade200))
              : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Іконка типу розкладу
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: schedule.isEnabled
                        ? (isRange
                            ? Colors.purple.shade100
                            : (isSolar
                                ? Colors.orange.shade100
                                : Colors.blue.shade100))
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isRange ? Icons.date_range : Icons.access_time,
                    size: 20,
                    color: schedule.isEnabled
                        ? (isRange
                            ? Colors.purple
                            : (isSolar ? Colors.orange : Colors.blue))
                        : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),

                // Інформація про розклад
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              schedule.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: schedule.isEnabled
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          // Бейдж типу
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isRange
                                  ? Colors.purple.shade50
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isRange ? 'ДІАПАЗОН' : 'ЧАС',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isRange ? Colors.purple : Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Час або діапазон
                      if (isRange) ...[
                        _buildRangeInfo(context),
                      ] else ...[
                        _buildTimeInfo(context),
                      ],
                    ],
                  ),
                ),

                // Switch
                Switch(
                  value: schedule.isEnabled,
                  onChanged: (_) => onToggle(),
                  activeColor: isRange
                      ? Colors.purple
                      : (isSolar ? Colors.orange : Colors.blue),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Тип повторення
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.repeat, size: 16, color: Colors.grey[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schedule.repeatTypeDisplay +
                          (schedule.repeatType == 'weekly' &&
                                  schedule.weekDaysDisplay.isNotEmpty
                              ? ': ${schedule.weekDaysDisplay}'
                              : ''),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),

            // Наступне виконання (тільки для TIME)
            if (schedule.isTimeSchedule &&
                schedule.nextExecution != null &&
                schedule.isEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Наступне виконання: ${DateFormat('dd.MM.yyyy HH:mm').format(schedule.nextExecution!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            // Для RANGE - показуємо що працює постійно
            if (schedule.isRangeSchedule && schedule.isEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.autorenew, size: 14, color: Colors.purple[400]),
                    const SizedBox(width: 4),
                    Text(
                      'Автоматичне перемикання на межах діапазону',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 24),

            // Кнопки дій
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Редагувати'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Видалити'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInfo(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          schedule.timeString,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: schedule.isEnabled ? Colors.black87 : Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Text('→', style: TextStyle(color: Colors.grey[400])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: schedule.isSolar
                ? Colors.orange.shade100
                : Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                schedule.isSolar ? Icons.wb_sunny : Icons.location_city,
                size: 14,
                color: schedule.isSolar ? Colors.orange : Colors.blue,
              ),
              const SizedBox(width: 4),
              Text(
                schedule.targetModeDisplay,
                style: TextStyle(
                  fontSize: 12,
                  color: schedule.isSolar ? Colors.orange : Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRangeInfo(BuildContext context) {
    final secondaryMode = schedule.secondaryMode ??
        (schedule.targetMode == 'solar' ? 'grid' : 'solar');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Діапазон
        Row(
          children: [
            Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              schedule.rangeString,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: schedule.isEnabled ? Colors.black87 : Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Режими
        Row(
          children: [
            // В діапазоні
            _buildModeChip(
              label: 'В діапазоні',
              mode: schedule.targetMode,
            ),
            const SizedBox(width: 8),
            Icon(Icons.swap_horiz, size: 16, color: Colors.grey[400]),
            const SizedBox(width: 8),
            // Поза діапазоном
            _buildModeChip(
              label: 'Інший час',
              mode: secondaryMode,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required String label,
    required String mode,
  }) {
    final isSolar = mode == 'solar';
    final color = isSolar ? Colors.orange : Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSolar ? Icons.wb_sunny : Icons.location_city,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isSolar ? 'Сонце' : 'Місто',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom sheet для історії
class _HistoryBottomSheet extends StatelessWidget {
  final Device device;

  const _HistoryBottomSheet({required this.device});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 12),
                  const Text(
                    'Історія перемикань',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<EnergyProvider>(
                builder: (context, energyProvider, _) {
                  final history = energyProvider.getHistory(device.deviceId);

                  if (history.isEmpty) {
                    return const Center(
                      child: Text('Історія порожня'),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final record = history[index];
                      final isRangeChange =
                          record.changedBy == 'schedule_range';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: record.toMode == 'solar'
                              ? Colors.orange.shade100
                              : Colors.blue.shade100,
                          child: Icon(
                            record.toMode == 'solar'
                                ? Icons.wb_sunny
                                : Icons.location_city,
                            color: record.toMode == 'solar'
                                ? Colors.orange
                                : Colors.blue,
                          ),
                        ),
                        title: Text(record.displayText),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('dd.MM.yyyy HH:mm')
                                  .format(record.timestamp),
                            ),
                            if (isRangeChange)
                              Text(
                                '📅 Діапазонний розклад',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.purple[400],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
