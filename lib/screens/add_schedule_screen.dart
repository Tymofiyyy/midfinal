// lib/screens/add_schedule_screen.dart
// ОНОВЛЕНО: Підтримка TIME та RANGE розкладів

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../models/energy_schedule.dart';
import '../providers/energy_provider.dart';
import '../providers/auth_provider.dart';

class AddScheduleScreen extends StatefulWidget {
  final Device device;
  final EnergySchedule? schedule;

  const AddScheduleScreen({
    super.key,
    required this.device,
    this.schedule,
  });

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  // Тип розкладу
  ScheduleType _scheduleType = ScheduleType.time;

  // Для TIME розкладу
  TimeOfDay _selectedTime = TimeOfDay.now();

  // Для RANGE розкладу
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 20, minute: 0);
  String _secondaryMode = 'grid';

  // Загальні
  String _targetMode = 'solar';
  ScheduleRepeatType _repeatType = ScheduleRepeatType.daily;
  Set<int> _selectedWeekDays = {};
  bool _isEnabled = true;
  bool _isLoading = false;

  bool get _isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();

    if (_isEditing) {
      final schedule = widget.schedule!;
      _nameController.text = schedule.name;
      _targetMode = schedule.targetMode;
      _repeatType = ScheduleRepeatType.fromString(schedule.repeatType);
      _selectedWeekDays = schedule.repeatDays?.toSet() ?? {};
      _isEnabled = schedule.isEnabled;

      // Визначаємо тип розкладу
      _scheduleType = ScheduleType.fromString(schedule.scheduleType);

      if (schedule.isTimeSchedule) {
        _selectedTime = TimeOfDay(
          hour: schedule.hour ?? 0,
          minute: schedule.minute ?? 0,
        );
      } else if (schedule.isRangeSchedule) {
        _startTime = TimeOfDay(
          hour: schedule.startHour ?? 8,
          minute: schedule.startMinute ?? 0,
        );
        _endTime = TimeOfDay(
          hour: schedule.endHour ?? 20,
          minute: schedule.endMinute ?? 0,
        );
        _secondaryMode = schedule.secondaryMode ??
            (schedule.targetMode == 'solar' ? 'grid' : 'solar');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редагувати розклад' : 'Новий розклад'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Назва розкладу
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Назва розкладу',
                hintText: 'наприклад: Денний режим',
                prefixIcon: Icon(Icons.edit),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введіть назву розкладу';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Тип розкладу
            const Text(
              'Тип розкладу',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ScheduleTypeCard(
                    icon: Icons.access_time,
                    label: 'Конкретний час',
                    description: 'Перемикання о заданий час',
                    isSelected: _scheduleType == ScheduleType.time,
                    onTap: () =>
                        setState(() => _scheduleType = ScheduleType.time),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ScheduleTypeCard(
                    icon: Icons.date_range,
                    label: 'Діапазон',
                    description: 'Режим в проміжку часу',
                    isSelected: _scheduleType == ScheduleType.range,
                    onTap: () =>
                        setState(() => _scheduleType = ScheduleType.range),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Вибір режиму енергії (основний)
            Text(
              _scheduleType == ScheduleType.time
                  ? 'Режим енергії'
                  : 'Режим в діапазоні',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.wb_sunny,
                    label: 'Сонячна',
                    color: Colors.orange,
                    isSelected: _targetMode == 'solar',
                    onTap: () => setState(() {
                      _targetMode = 'solar';
                      if (_scheduleType == ScheduleType.range) {
                        _secondaryMode = 'grid';
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.location_city,
                    label: 'Міська',
                    color: Colors.blue,
                    isSelected: _targetMode == 'grid',
                    onTap: () => setState(() {
                      _targetMode = 'grid';
                      if (_scheduleType == ScheduleType.range) {
                        _secondaryMode = 'solar';
                      }
                    }),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Вибір часу - залежить від типу розкладу
            if (_scheduleType == ScheduleType.time) ...[
              // TIME: Один час
              const Text(
                'Час виконання',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _buildTimeSelector(
                time: _selectedTime,
                label: 'Час перемикання',
                onTap: () => _selectTime(isStart: true),
              ),
            ] else ...[
              // RANGE: Початок і кінець
              const Text(
                'Діапазон часу',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'В цьому діапазоні буде ${_targetMode == 'solar' ? 'сонячна' : 'міська'} енергія',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTimeSelector(
                      time: _startTime,
                      label: 'Початок',
                      icon: Icons.play_arrow,
                      onTap: () => _selectTime(isStart: true),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, color: Colors.grey[400]),
                  ),
                  Expanded(
                    child: _buildTimeSelector(
                      time: _endTime,
                      label: 'Кінець',
                      icon: Icons.stop,
                      onTap: () => _selectTime(isStart: false),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Режим поза діапазоном
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.swap_horiz, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Поза діапазоном:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallModeCard(
                            icon: Icons.wb_sunny,
                            label: 'Сонячна',
                            color: Colors.orange,
                            isSelected: _secondaryMode == 'solar',
                            onTap: () =>
                                setState(() => _secondaryMode = 'solar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SmallModeCard(
                            icon: Icons.location_city,
                            label: 'Міська',
                            color: Colors.blue,
                            isSelected: _secondaryMode == 'grid',
                            onTap: () =>
                                setState(() => _secondaryMode = 'grid'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Візуалізація діапазону
              _buildRangeVisualization(),
            ],

            const SizedBox(height: 24),

            // Тип повторення
            const Text(
              'Повторення',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...ScheduleRepeatType.values.map((type) {
              return RadioListTile<ScheduleRepeatType>(
                value: type,
                groupValue: _repeatType,
                onChanged: (value) {
                  setState(() {
                    _repeatType = value!;
                    if (_repeatType != ScheduleRepeatType.weekly) {
                      _selectedWeekDays.clear();
                    }
                  });
                },
                title: Text(type.displayName),
                activeColor: const Color(0xFF3B82F6),
              );
            }),

            // Вибір днів тижня (тільки для weekly)
            if (_repeatType == ScheduleRepeatType.weekly) ...[
              const SizedBox(height: 12),
              const Text(
                'Виберіть дні тижня:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _WeekDayChip(
                      label: 'Пн',
                      day: 1,
                      isSelected: _selectedWeekDays.contains(1),
                      onTap: () => _toggleWeekDay(1)),
                  _WeekDayChip(
                      label: 'Вт',
                      day: 2,
                      isSelected: _selectedWeekDays.contains(2),
                      onTap: () => _toggleWeekDay(2)),
                  _WeekDayChip(
                      label: 'Ср',
                      day: 3,
                      isSelected: _selectedWeekDays.contains(3),
                      onTap: () => _toggleWeekDay(3)),
                  _WeekDayChip(
                      label: 'Чт',
                      day: 4,
                      isSelected: _selectedWeekDays.contains(4),
                      onTap: () => _toggleWeekDay(4)),
                  _WeekDayChip(
                      label: 'Пт',
                      day: 5,
                      isSelected: _selectedWeekDays.contains(5),
                      onTap: () => _toggleWeekDay(5)),
                  _WeekDayChip(
                      label: 'Сб',
                      day: 6,
                      isSelected: _selectedWeekDays.contains(6),
                      onTap: () => _toggleWeekDay(6)),
                  _WeekDayChip(
                      label: 'Нд',
                      day: 0,
                      isSelected: _selectedWeekDays.contains(0),
                      onTap: () => _toggleWeekDay(0)),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Увімкнений/вимкнений
            SwitchListTile(
              value: _isEnabled,
              onChanged: (value) => setState(() => _isEnabled = value),
              title: const Text('Активний розклад'),
              subtitle: Text(
                _isEnabled
                    ? 'Розклад буде виконуватись автоматично'
                    : 'Розклад не буде виконуватись',
              ),
              activeColor: const Color(0xFF3B82F6),
            ),

            const SizedBox(height: 32),

            // Кнопка збереження
            ElevatedButton(
              onPressed: _isLoading ? null : _saveSchedule,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Збереження...',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    )
                  : Text(
                      _isEditing ? 'Оновити розклад' : 'Створити розклад',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),

            const SizedBox(height: 16),

            // Інформаційна картка
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector({
    required TimeOfDay time,
    required String label,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon ?? Icons.access_time, size: 28, color: Colors.grey[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time.format(context),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeVisualization() {
    // Розрахунок відсотків для візуалізації
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    final totalMinutes = 24 * 60;

    final bool isOvernight = endMinutes <= startMinutes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Візуалізація доби',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 24-годинна шкала
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 40,
              child: isOvernight
                  ? _buildOvernightVisualization(
                      startMinutes, endMinutes, totalMinutes)
                  : _buildNormalVisualization(
                      startMinutes, endMinutes, totalMinutes),
            ),
          ),

          const SizedBox(height: 8),

          // Легенда
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00:00',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('06:00',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('12:00',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('18:00',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('24:00',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),

          const SizedBox(height: 12),

          // Опис
          Row(
            children: [
              _buildLegendItem(
                color: _targetMode == 'solar' ? Colors.orange : Colors.blue,
                label: _targetMode == 'solar' ? 'Сонячна' : 'Міська',
              ),
              const SizedBox(width: 16),
              _buildLegendItem(
                color: _secondaryMode == 'solar' ? Colors.orange : Colors.blue,
                label: _secondaryMode == 'solar' ? 'Сонячна' : 'Міська',
              ),
            ],
          ),

          if (isOvernight) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Діапазон через північ',
                      style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNormalVisualization(
      int startMinutes, int endMinutes, int totalMinutes) {
    final startPercent = startMinutes / totalMinutes;
    final rangePercent = (endMinutes - startMinutes) / totalMinutes;

    return Row(
      children: [
        // До початку - secondary mode
        if (startPercent > 0)
          Expanded(
            flex: (startPercent * 100).round(),
            child: Container(
              color: _secondaryMode == 'solar'
                  ? Colors.orange[200]
                  : Colors.blue[200],
            ),
          ),
        // Діапазон - target mode
        Expanded(
          flex: (rangePercent * 100).round(),
          child: Container(
            color: _targetMode == 'solar' ? Colors.orange : Colors.blue,
          ),
        ),
        // Після кінця - secondary mode
        if (endMinutes < totalMinutes)
          Expanded(
            flex: ((totalMinutes - endMinutes) / totalMinutes * 100).round(),
            child: Container(
              color: _secondaryMode == 'solar'
                  ? Colors.orange[200]
                  : Colors.blue[200],
            ),
          ),
      ],
    );
  }

  Widget _buildOvernightVisualization(
      int startMinutes, int endMinutes, int totalMinutes) {
    // Діапазон через північ: target mode від start до 24:00 і від 00:00 до end
    final beforeMidnight = (totalMinutes - startMinutes) / totalMinutes;
    final afterMidnight = endMinutes / totalMinutes;
    final middleDay = (startMinutes - endMinutes) / totalMinutes;

    return Row(
      children: [
        // Від 00:00 до end - target mode
        if (afterMidnight > 0)
          Expanded(
            flex: (afterMidnight * 100).round(),
            child: Container(
              color: _targetMode == 'solar' ? Colors.orange : Colors.blue,
            ),
          ),
        // Від end до start - secondary mode
        Expanded(
          flex: (middleDay * 100).round(),
          child: Container(
            color: _secondaryMode == 'solar'
                ? Colors.orange[200]
                : Colors.blue[200],
          ),
        ),
        // Від start до 24:00 - target mode
        if (beforeMidnight > 0)
          Expanded(
            flex: (beforeMidnight * 100).round(),
            child: Container(
              color: _targetMode == 'solar' ? Colors.orange : Colors.blue,
            ),
          ),
      ],
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildInfoCard() {
    final String infoText;
    if (_scheduleType == ScheduleType.time) {
      infoText = '• Розклад спрацює о ${_selectedTime.format(context)}\n'
          '• Режим перемкнеться на ${_targetMode == 'solar' ? 'сонячну' : 'міську'} енергію\n'
          '• Працює навіть коли телефон виключений';
    } else {
      infoText =
          '• З ${_startTime.format(context)} до ${_endTime.format(context)} - ${_targetMode == 'solar' ? 'сонячна' : 'міська'}\n'
          '• В інший час - ${_secondaryMode == 'solar' ? 'сонячна' : 'міська'}\n'
          '• Автоматичне перемикання на межах діапазону';
    }

    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Як це працює?',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.blue[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              infoText,
              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectTime({required bool isStart}) async {
    final TimeOfDay initialTime;
    if (_scheduleType == ScheduleType.time) {
      initialTime = _selectedTime;
    } else {
      initialTime = isStart ? _startTime : _endTime;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF3B82F6)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (_scheduleType == ScheduleType.time) {
          _selectedTime = picked;
        } else {
          if (isStart) {
            _startTime = picked;
          } else {
            _endTime = picked;
          }
        }
      });
    }
  }

  void _toggleWeekDay(int day) {
    setState(() {
      if (_selectedWeekDays.contains(day)) {
        _selectedWeekDays.remove(day);
      } else {
        _selectedWeekDays.add(day);
      }
    });
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    if (_repeatType == ScheduleRepeatType.weekly && _selectedWeekDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Виберіть хоча б один день тижня'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final energyProvider = context.read<EnergyProvider>();

    List<int>? repeatDaysList;
    if (_repeatType == ScheduleRepeatType.weekly) {
      repeatDaysList = _selectedWeekDays.toList();
      repeatDaysList.sort();
    }

    int userId;
    if (authProvider.user!.id is int) {
      userId = authProvider.user!.id as int;
    } else if (authProvider.user!.id is String) {
      userId = int.parse(authProvider.user!.id as String);
    } else {
      userId = int.parse(authProvider.user!.id.toString());
    }

    final schedule = EnergySchedule(
      id: _isEditing ? widget.schedule!.id : null,
      deviceId: widget.device.deviceId,
      userId: userId,
      name: _nameController.text.trim(),
      targetMode: _targetMode,
      scheduleType: _scheduleType.value,
      // TIME fields
      hour: _scheduleType == ScheduleType.time ? _selectedTime.hour : null,
      minute: _scheduleType == ScheduleType.time ? _selectedTime.minute : null,
      // RANGE fields
      startHour: _scheduleType == ScheduleType.range ? _startTime.hour : null,
      startMinute:
          _scheduleType == ScheduleType.range ? _startTime.minute : null,
      endHour: _scheduleType == ScheduleType.range ? _endTime.hour : null,
      endMinute: _scheduleType == ScheduleType.range ? _endTime.minute : null,
      secondaryMode:
          _scheduleType == ScheduleType.range ? _secondaryMode : null,
      // Common fields
      repeatType: _repeatType.value,
      repeatDays: repeatDaysList,
      isEnabled: _isEnabled,
    );

    bool success;
    if (_isEditing) {
      success = await energyProvider.updateSchedule(
        widget.device.deviceId,
        widget.schedule!.id!,
        schedule,
      );
    } else {
      success = await energyProvider.createSchedule(
        widget.device.deviceId,
        schedule,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(_isEditing ? '✅ Розклад оновлено' : '✅ Розклад створено'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(energyProvider.error ?? 'Помилка збереження розкладу'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Карточка вибору типу розкладу
class _ScheduleTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScheduleTypeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3B82F6).withOpacity(0.1)
              : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? const Color(0xFF3B82F6) : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF3B82F6) : Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Карточка вибору режиму
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Маленька карточка режиму для secondary mode
class _SmallModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _SmallModeCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade400,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: isSelected ? color : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Чіп для вибору дня тижня
class _WeekDayChip extends StatelessWidget {
  final String label;
  final int day;
  final bool isSelected;
  final VoidCallback onTap;

  const _WeekDayChip({
    required this.label,
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF3B82F6),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      showCheckmark: false,
    );
  }
}
