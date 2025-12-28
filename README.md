# Solar Controller IoT System

Система керування сонячними панелями через ESP32 з Flutter мобільним додатком.

## Компоненти системи

1. **ESP32 Firmware** - Прошивка для ESP32 контролера
2. **Backend Server** - Node.js сервер з PostgreSQL та MQTT
3. **Flutter Mobile App** - Мобільний додаток для iOS/Android

## Швидкий старт

### 1. Налаштування Backend

```bash
cd backend
npm install
node reset-database.js
npm start
```

### 2. Налаштування ESP32

1. Відкрийте `firmware/solar_controller.ino` в Arduino IDE
2. Змініть IP адресу MQTT сервера на IP вашого ПК
3. Завантажте прошивку на ESP32

### 3. Запуск Flutter додатку

```bash
cd solar_controller
flutter pub get
flutter run
```

## Налаштування середовища

### PostgreSQL
- База даних: `solar_controller`
- Користувач: `postgres`
- Пароль: `postgres`

### Mosquitto MQTT
- Порт: 1883
- Без автентифікації (для локального використання)

### IP адреса
Знайдіть IP адресу вашого ПК:
- Windows: `ipconfig`
- Mac/Linux: `ifconfig` або `ip addr`

Оновіть IP адресу в:
- `.env` (Flutter)
- `backend/.env`
- `firmware/solar_controller.ino`

## Використання

1. Підключіться до WiFi точки доступу ESP32
2. Отримайте Device ID та код підтвердження
3. Увійдіть в мобільний додаток через Google
4. Додайте пристрій використовуючи ID та код
5. Керуйте реле в реальному часі

## Функціональність

- ✅ Google автентифікація
- ✅ Додавання/видалення пристроїв
- ✅ Керування реле в реальному часі
- ✅ Моніторинг статусу (WiFi, uptime, пам'ять)
- ✅ Можливість ділитися доступом
- ✅ Автоматичне підключення WiFi
- ✅ Captive Portal для налаштування

## Troubleshooting

### Проблема: Flutter додаток не підключається
- Перевірте IP адресу в `.env`
- Переконайтеся що телефон і ПК в одній мережі
- Вимкніть firewall або додайте виключення

### Проблема: MQTT не працює
- Перевірте чи запущений Mosquitto
- Перевірте IP адресу в прошивці ESP32

### Проблема: Google Sign In не працює
- Перевірте Client ID
- Для Android: додайте SHA-1 fingerprint

## Ліцензія

MIT