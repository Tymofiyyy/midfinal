import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _confirmationCodeController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _deviceIdController.dispose();
    _confirmationCodeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await context.read<DeviceProvider>().addDevice(
          _deviceIdController.text,
          _confirmationCodeController.text,
          _nameController.text.isEmpty ? null : _nameController.text,
        );

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        // Показуємо діалог про успішне додавання
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 64,
            ),
            title: const Text('Пристрій додано!'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Пристрій успішно додано до вашого облікового запису.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                LinearProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Точка доступу ESP32 буде вимкнена через кілька секунд...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Закриваємо діалог
                  Navigator.pop(context); // Повертаємось на головну
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Пристрій додано успішно!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Помилка додавання пристрою. Перевірте код підтвердження.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Додати пристрій'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                color: Color(0xFFF0F9FF),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Color(0xFF3B82F6),
                        size: 24,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Для додавання пристрою вам потрібні ID та код підтвердження, які відображаються на пристрої або в Serial Monitor',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF1E40AF),
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '⚠️ Після додавання точка доступу ESP32 автоматично вимкнеться',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: 'ID пристрою',
                  hintText: 'ESP32_XXXXXX',
                  prefixIcon: Icon(Icons.devices),
                  border: OutlineInputBorder(),
                  helperText: 'Наприклад: ESP32_c0c3ea20691c',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введіть ID пристрою';
                  }
                  if (!value.startsWith('ESP32_')) {
                    return 'ID має починатися з ESP32_';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmationCodeController,
                decoration: const InputDecoration(
                  labelText: 'Код підтвердження',
                  hintText: '123456',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                  helperText: '6-значний код з Serial Monitor',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Введіть код підтвердження';
                  }
                  if (value.length != 6) {
                    return 'Код має містити 6 цифр';
                  }
                  if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                    return 'Код може містити тільки цифри';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Назва (опціонально)',
                  hintText: 'Сонячна панель гараж',
                  prefixIcon: Icon(Icons.edit),
                  border: OutlineInputBorder(),
                  helperText: 'Дайте зрозумілу назву вашому пристрою',
                ),
                maxLength: 50,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _addDevice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
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
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Додавання...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Додати пристрій',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              // Підказка для тестування
              if (const bool.fromEnvironment('dart.vm.product') == false)
                Card(
                  color: Colors.yellow[50],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🧪 Режим розробки',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Для тестування можна використати:\nКод: 123456 або 147091',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
