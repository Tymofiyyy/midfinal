// lib/widgets/energy_mode_toggle.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../models/energy_mode.dart';
import '../providers/energy_provider.dart';

class EnergyModeToggle extends StatefulWidget {
  final Device device;
  final VoidCallback? onTap; // Для переходу до налаштувань розкладів

  const EnergyModeToggle({
    super.key,
    required this.device,
    this.onTap,
  });

  @override
  State<EnergyModeToggle> createState() => _EnergyModeToggleState();
}

class _EnergyModeToggleState extends State<EnergyModeToggle>
    with SingleTickerProviderStateMixin {
  bool _isChanging = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Завантажуємо поточний режим при ініціалізації
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnergyProvider>().loadEnergyMode(widget.device.deviceId);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleMode(EnergyMode currentMode) async {
    if (_isChanging) return;

    setState(() => _isChanging = true);

    _animationController.forward().then((_) {
      _animationController.reverse();
    });

    final energyProvider = context.read<EnergyProvider>();
    final newMode = currentMode.isSolar ? 'grid' : 'solar';

    final success =
        await energyProvider.setEnergyMode(widget.device.deviceId, newMode);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newMode == 'solar' ? Icons.wb_sunny : Icons.location_city,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  newMode == 'solar'
                      ? 'Перемкнуто на сонячну енергію'
                      : 'Перемкнуто на міську енергію',
                ),
              ],
            ),
            backgroundColor: newMode == 'solar' ? Colors.orange : Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Помилка перемикання режиму'),
            backgroundColor: Colors.red,
          ),
        );
      }

      setState(() => _isChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnergyProvider>(
      builder: (context, energyProvider, _) {
        final energyMode = energyProvider.getEnergyMode(widget.device.deviceId);

        // Якщо режим ще не завантажений
        if (energyMode == null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Text('Завантаження режиму...'),
                  const Spacer(),
                  if (widget.onTap != null)
                    IconButton(
                      icon: const Icon(Icons.schedule),
                      onPressed: widget.onTap,
                      tooltip: 'Розклади',
                    ),
                ],
              ),
            ),
          );
        }

        final isSolar = energyMode.isSolar;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSolar ? Colors.orange.shade200 : Colors.blue.shade200,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: _isChanging ? null : () => _toggleMode(energyMode),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Іконка режиму
                      AnimatedBuilder(
                        animation: _scaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSolar
                                    ? Colors.orange.shade100
                                    : Colors.blue.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSolar ? Icons.wb_sunny : Icons.location_city,
                                size: 32,
                                color: isSolar ? Colors.orange : Colors.blue,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 16),

                      // Інформація
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Джерело енергії',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isSolar ? 'Сонячна енергія' : 'Міська енергія',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getChangedByText(energyMode.changedBy),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Індикатор завантаження або кнопка розкладів
                      if (_isChanging)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (widget.onTap != null)
                        IconButton(
                          icon: const Icon(Icons.schedule),
                          onPressed: widget.onTap,
                          tooltip: 'Налаштувати розклади',
                          color: Colors.grey[700],
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Кнопка перемикання
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isChanging ? null : () => _toggleMode(energyMode),
                      icon: Icon(
                        isSolar ? Icons.location_city : Icons.wb_sunny,
                        size: 20,
                      ),
                      label: Text(
                        isSolar
                            ? 'Перемкнути на міську'
                            : 'Перемкнути на сонячну',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSolar ? Colors.blue : Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
        );
      },
    );
  }

  String _getChangedByText(String changedBy) {
    switch (changedBy) {
      case 'manual':
        return '⚙️ Змінено вручну';
      case 'schedule':
        return '⏰ Змінено за розкладом';
      case 'default':
        return '🔧 Дефолтне значення';
      default:
        return changedBy;
    }
  }
}
