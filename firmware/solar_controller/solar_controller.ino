// firmware/solar_controller/solar_controller.ino - ОНОВЛЕНО: енергія кожні 15 секунд

#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <PubSubClient.h>
#include <EEPROM.h>
#include <ArduinoJson.h>

// Конфігурація
#define RELAY_PIN 32
#define LED_PIN 5  // GPIO5 (D5)
#define EEPROM_SIZE 512
#define AP_SSID "SolarController_"
#define CONFIRMATION_CODE_LENGTH 6
#define DNS_PORT 53

// MQTT налаштування - локальний Mosquitto
const char* mqtt_server = "192.168.68.122"; // Змініть на IP вашого ПК
const int mqtt_port = 1883;
const char* mqtt_user = ""; // Якщо є автентифікація
const char* mqtt_password = ""; // Якщо є автентифікація

// Глобальні змінні
WebServer server(80);
DNSServer dnsServer;
WiFiClient espClient;
PubSubClient client(espClient);

String deviceId;
String confirmationCode;
String savedSSID = "";
String savedPassword = "";
bool wifiConnected = false;
bool mqttConnected = false;
bool relayState = false;
bool apMode = true;
bool deviceAdded = false;

// ОНОВЛЕНІ змінні для симуляції енергії - тепер кожні 15 секунд
float currentPowerKw = 0.0;      // Поточна потужність в kW
float totalEnergyKwh = 0.0;      // Загальна енергія в kWh
unsigned long lastEnergyUpdate = 0;
unsigned long lastEnergyCalc = 0;
const unsigned long ENERGY_UPDATE_INTERVAL = 15000; // 15 секунд замість 5
const unsigned long ENERGY_CALC_INTERVAL = 15000;   // 15 секунд замість 1

// Структура для збереження даних в EEPROM
struct Config {
  char ssid[32];
  char password[64];
  char deviceId[32];
  bool deviceAdded;
  float totalEnergyKwh;
};

void setup() {
  Serial.begin(115200);
  EEPROM.begin(EEPROM_SIZE);
  
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  digitalWrite(LED_PIN, LOW);
  
  // Генеруємо унікальний ID пристрою
  deviceId = "ESP32_" + String(ESP.getEfuseMac(), HEX);
  
  // Генеруємо код підтвердження
  generateConfirmationCode();
  
  // Завантажуємо збережені налаштування
  loadConfig();
  
  // Спробуємо підключитися до збереженої мережі
  if (savedSSID.length() > 0) {
    connectToWiFi();
  }
  
  // Запускаємо точку доступу ТІЛЬКИ якщо пристрій не доданий або не підключений до WiFi
  if (!deviceAdded || !wifiConnected) {
    setupAP();
  }
  
  // Налаштовуємо веб-сервер
  setupWebServer();
  
  // Налаштовуємо MQTT
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(mqttCallback);
  
  // Ініціалізуємо генератор випадкових чисел
  randomSeed(analogRead(0));
  
  Serial.println("=== ESP32 Solar Controller Started ===");
  Serial.println("Energy data will be sent every 15 seconds");
  Serial.println("=======================================");
}

void loop() {
  // Обробляємо DNS запити для Captive Portal тільки в AP режимі
  if (apMode) {
    dnsServer.processNextRequest();
  }
  
  // Обробляємо веб-сервер
  server.handleClient();
  
  // Перевіряємо WiFi підключення
  if (!wifiConnected && WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("WiFi reconnected!");
    Serial.println("IP address: " + WiFi.localIP().toString());
    
    // Якщо пристрій доданий і WiFi підключений - вимикаємо AP
    if (apMode && deviceAdded) {
      disableAP();
    }
  } else if (wifiConnected && WiFi.status() != WL_CONNECTED) {
    wifiConnected = false;
    Serial.println("WiFi disconnected!");
  }
  
  if (wifiConnected && !client.connected()) {
    reconnectMQTT();
  }
  
  if (client.connected()) {
    client.loop();
    
    // ОНОВЛЕНО: Симулюємо та оновлюємо енергію кожні 15 секунд
    simulateEnergy();
    
    // Відправляємо статус кожні 30 секунд (рідше)
    static unsigned long lastStatusUpdate = 0;
    if (millis() - lastStatusUpdate > 30000) {
      sendStatus();
      lastStatusUpdate = millis();
    }
    
    // ОНОВЛЕНО: Відправляємо дані про енергію кожні 15 секунд
    if (millis() - lastEnergyUpdate > ENERGY_UPDATE_INTERVAL) {
      sendEnergyData();
      lastEnergyUpdate = millis();
    }
  }
}

void disableAP() {
  if (apMode) {
    Serial.println("Disabling AP mode...");
    WiFi.softAPdisconnect(true);
    dnsServer.stop();
    apMode = false;
    WiFi.mode(WIFI_STA);
    Serial.println("AP mode disabled, running in STA mode only");
  }
}

// ОНОВЛЕНО: Симуляція енергії кожні 15 секунд
void simulateEnergy() {
  // Симулюємо енергію тільки коли реле увімкнене
  if (relayState) {
    // Генеруємо реалістичну потужність кожні 15 секунд
    if (millis() - lastEnergyCalc > ENERGY_CALC_INTERVAL) {
      float basePower = 2.5; // Базова потужність 2.5 kW
      
      // Додаємо плавні варіації (синусоїда для реалістичності)
      float timeInSeconds = millis() / 1000.0;
      float variation = 1.0 + 0.3 * sin(timeInSeconds * 0.05); // Повільніші зміни
      
      // Додаємо невеликі випадкові коливання
      float randomVariation = (random(95, 105) / 100.0);
      
      currentPowerKw = basePower * variation * randomVariation;
      
      // Обмежуємо діапазон потужності
      if (currentPowerKw < 0.5) currentPowerKw = 0.5;
      if (currentPowerKw > 3.5) currentPowerKw = 3.5;
      
      // ОНОВЛЕНО: Розраховуємо енергію за 15 секунд (kWh = kW * hours)
      float hours = (float)(millis() - lastEnergyCalc) / 3600000.0;
      totalEnergyKwh += currentPowerKw * hours;
      
      lastEnergyCalc = millis();
      
      Serial.printf("⚡ Energy calculated: %.2f kW, Total: %.3f kWh\n", 
                   currentPowerKw, totalEnergyKwh);
    }
  } else {
    currentPowerKw = 0.0;
    lastEnergyCalc = millis(); // Скидаємо таймер для правильних розрахунків
  }
}

void sendEnergyData() {
  if (!client.connected()) return;
  
  StaticJsonDocument<256> doc;
  doc["deviceId"] = deviceId;
  doc["type"] = "energy";
  doc["powerKw"] = round(currentPowerKw * 100) / 100.0;
  doc["energyKwh"] = round(totalEnergyKwh * 100) / 100.0;
  doc["timestamp"] = millis() / 1000;
  
  String energyTopic = "solar/" + deviceId + "/energy";
  String message;
  serializeJson(doc, message);
  
  if (client.publish(energyTopic.c_str(), message.c_str())) {
    Serial.println("📊 Energy data sent (15s interval): " + message);
  } else {
    Serial.println("❌ Failed to send energy data");
  }
  
  // Зберігаємо загальну енергію в EEPROM кожні 60 секунд (рідше)
  static unsigned long lastEepromSave = 0;
  if (millis() - lastEepromSave > 60000) {
    saveConfig();
    lastEepromSave = millis();
  }
}

void generateConfirmationCode() {
  confirmationCode = "";
  for (int i = 0; i < CONFIRMATION_CODE_LENGTH; i++) {
    confirmationCode += String(random(0, 10));
  }
  Serial.println("=================================");
  Serial.println("Device ID: " + deviceId);
  Serial.println("Confirmation code: " + confirmationCode);
  Serial.println("Energy interval: 15 seconds");
  Serial.println("=================================");
}

void setupAP() {
  String apName = AP_SSID + deviceId.substring(deviceId.length() - 4);
  WiFi.softAP(apName.c_str());
  
  // Запускаємо DNS сервер для Captive Portal
  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());
  apMode = true;
  
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);
  Serial.println("AP Name: " + apName);
}

void connectToWiFi() {
  Serial.println("Connecting to WiFi: " + savedSSID);
  
  // Використовуємо різні режими залежно від стану
  if (!deviceAdded) {
    WiFi.mode(WIFI_AP_STA); // AP+STA якщо пристрій не доданий
  } else {
    WiFi.mode(WIFI_STA); // Тільки STA якщо пристрій доданий
  }
  
  WiFi.begin(savedSSID.c_str(), savedPassword.c_str());
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("\nWiFi connected!");
    Serial.println("IP address: " + WiFi.localIP().toString());
  } else {
    Serial.println("\nFailed to connect to WiFi");
    wifiConnected = false;
    // Якщо не вдалося підключитися і пристрій не доданий, запускаємо AP
    if (!deviceAdded) {
      setupAP();
    }
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.println("MQTT message received: " + String(topic) + " - " + message);
  
  // Обробка команд
  String deviceTopic = "solar/" + deviceId + "/command";
  if (String(topic) == deviceTopic) {
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, message);
    
    if (!error) {
      String command = doc["command"];
      
      if (command == "relay") {
        bool state = doc["state"];
        digitalWrite(RELAY_PIN, state ? HIGH : LOW);
        digitalWrite(LED_PIN, state ? HIGH : LOW);
        relayState = state;
        Serial.println("Relay state changed to: " + String(state));
        
        // Якщо реле вмикається, скидаємо таймер енергії
        if (state) {
          lastEnergyCalc = millis();
        }
        
        sendStatus();
      } else if (command == "getStatus") {
        sendStatus();
      } else if (command == "restart") {
        ESP.restart();
      } else if (command == "deviceAdded") {
        // Позначаємо що пристрій доданий
        deviceAdded = true;
        saveConfig();
        Serial.println("Device marked as added!");
        
        // Відправляємо підтвердження
        StaticJsonDocument<200> response;
        response["command"] = "deviceAdded";
        response["success"] = true;
        response["deviceId"] = deviceId;
        
        String responseTopic = "solar/" + deviceId + "/response";
        String responseMessage;
        serializeJson(response, responseMessage);
        client.publish(responseTopic.c_str(), responseMessage.c_str());
        
        // Вимикаємо AP режим через 2 секунди
        Serial.println("Disabling AP mode in 2 seconds...");
        delay(2000);
        disableAP();
        
      } else if (command == "resetEnergy") {
        // Команда для скидання лічильника енергії
        totalEnergyKwh = 0.0;
        saveConfig();
        Serial.println("Energy counter reset!");
        sendEnergyData();
      }
    }
  }
}

void reconnectMQTT() {
  if (!wifiConnected) return;
  
  static unsigned long lastAttempt = 0;
  if (millis() - lastAttempt < 5000) return;
  lastAttempt = millis();
  
  Serial.print("Attempting MQTT connection...");
  
  String clientId = "ESP32Client-" + deviceId;
  bool connected = false;
  
  if (strlen(mqtt_user) > 0) {
    connected = client.connect(clientId.c_str(), mqtt_user, mqtt_password);
  } else {
    connected = client.connect(clientId.c_str());
  }
  
  if (connected) {
    Serial.println("connected");
    mqttConnected = true;
    
    // Підписуємося на топіки
    String commandTopic = "solar/" + deviceId + "/command";
    client.subscribe(commandTopic.c_str());
    Serial.println("Subscribed to: " + commandTopic);
    
    // Відправляємо повідомлення про підключення
    String onlineTopic = "solar/" + deviceId + "/online";
    client.publish(onlineTopic.c_str(), "true", true);
    
    // Відправляємо початковий статус
    sendStatus();
    
    // Відправляємо поточні дані про енергію
    sendEnergyData();
  } else {
    Serial.print("failed, rc=");
    Serial.print(client.state());
    Serial.println(" try again in 5 seconds");
    mqttConnected = false;
  }
}

void sendStatus() {
  if (!client.connected()) return;
  
  StaticJsonDocument<300> doc;
  doc["deviceId"] = deviceId;
  doc["relayState"] = relayState;
  doc["wifiRSSI"] = WiFi.RSSI();
  doc["uptime"] = millis() / 1000;
  doc["freeHeap"] = ESP.getFreeHeap();
  doc["confirmationCode"] = confirmationCode;
  doc["deviceAdded"] = deviceAdded;
  doc["powerKw"] = round(currentPowerKw * 100) / 100.0;
  doc["energyKwh"] = round(totalEnergyKwh * 100) / 100.0;
  doc["apMode"] = apMode;
  doc["energyInterval"] = ENERGY_UPDATE_INTERVAL / 1000; // в секундах
  
  String statusTopic = "solar/" + deviceId + "/status";
  String message;
  serializeJson(doc, message);
  
  if (client.publish(statusTopic.c_str(), message.c_str())) {
    Serial.println("Status sent: " + message);
  } else {
    Serial.println("Failed to send status");
  }
}

void saveConfig() {
  Config config;
  strcpy(config.ssid, savedSSID.c_str());
  strcpy(config.password, savedPassword.c_str());
  strcpy(config.deviceId, deviceId.c_str());
  config.deviceAdded = deviceAdded;
  config.totalEnergyKwh = totalEnergyKwh;
  
  EEPROM.put(0, config);
  EEPROM.commit();
  Serial.println("Config saved to EEPROM");
}

void loadConfig() {
  Config config;
  EEPROM.get(0, config);
  
  if (strlen(config.ssid) > 0 && strlen(config.ssid) < 32) {
    savedSSID = String(config.ssid);
    savedPassword = String(config.password);
    deviceAdded = config.deviceAdded;
    totalEnergyKwh = config.totalEnergyKwh;
    Serial.println("Loaded config - SSID: " + savedSSID);
    Serial.println("Device added: " + String(deviceAdded));
    Serial.println("Total energy: " + String(totalEnergyKwh) + " kWh");
  } else {
    Serial.println("No valid config found in EEPROM");
  }
}

void setupWebServer() {
  // Головна сторінка
  server.on("/", HTTP_GET, handleRoot);
  
  // Обробка підключення до WiFi
  server.on("/connect", HTTP_POST, handleConnect);
  
  // API endpoints
  server.on("/api/status", HTTP_GET, handleApiStatus);
  
  // Captive Portal endpoints
  server.onNotFound(handleCaptivePortal);
  
  server.begin();
  Serial.println("Web server started");
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head>";
  html += "<meta charset='UTF-8'>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
  html += "<title>Solar Controller Setup</title>";
  html += "<style>";
  html += "body { font-family: Arial, sans-serif; margin: 20px; background: #f0f0f0; }";
  html += ".container { max-width: 400px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }";
  html += "h1 { color: #333; text-align: center; }";
  html += ".code { font-size: 36px; font-weight: bold; text-align: center; color: #2196F3; padding: 20px; background: #f5f5f5; border-radius: 5px; margin: 20px 0; letter-spacing: 5px; }";
  html += ".device-id { font-size: 14px; text-align: center; color: #666; padding: 10px; background: #f5f5f5; border-radius: 5px; margin: 10px 0; word-break: break-all; }";
  html += "input, select { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 5px; box-sizing: border-box; }";
  html += "button { width: 100%; padding: 10px; background: #2196F3; color: white; border: none; border-radius: 5px; cursor: pointer; font-size: 16px; }";
  html += "button:hover { background: #1976D2; }";
  html += ".status { padding: 10px; margin: 10px 0; border-radius: 5px; text-align: center; }";
  html += ".connected { background: #4CAF50; color: white; }";
  html += ".disconnected { background: #f44336; color: white; }";
  html += ".info { background: #FFC107; color: #333; padding: 10px; border-radius: 5px; margin: 10px 0; text-align: center; }";
  html += ".relay-status { background: #2196F3; color: white; padding: 10px; border-radius: 5px; margin: 10px 0; text-align: center; }";
  html += ".energy-info { background: #4CAF50; color: white; padding: 10px; border-radius: 5px; margin: 10px 0; }";
  html += ".interval-info { background: #FF9800; color: white; padding: 8px; border-radius: 5px; margin: 5px 0; font-size: 12px; }";
  html += "</style></head><body>";
  html += "<div class='container'>";
  html += "<h1>☀️ Solar Controller</h1>";
  
  if (!deviceAdded) {
    html += "<div class='info'>⚡ Для додавання пристрою використовуйте:</div>";
    html += "<div class='device-id'>ID: " + deviceId + "</div>";
    html += "<div class='code'>" + confirmationCode + "</div>";
  } else {
    html += "<div class='status connected'>✅ Пристрій доданий</div>";
  }
  
  html += "<div class='status " + String(wifiConnected ? "connected" : "disconnected") + "'>";
  html += wifiConnected ? "✅ WiFi підключено" : "❌ WiFi не підключено";
  html += "</div>";
  
  if (mqttConnected) {
    html += "<div class='status connected'>✅ MQTT підключено</div>";
    html += "<div class='interval-info'>📊 Енергія: кожні 15 секунд</div>";
    html += "<div class='relay-status'>Реле: " + String(relayState ? "УВІМКНЕНО" : "ВИМКНЕНО") + "</div>";
    html += "<div class='energy-info'>";
    html += "<div>⚡ Потужність: " + String(currentPowerKw) + " kW</div>";
    html += "<div>📊 Загальна енергія: " + String(totalEnergyKwh) + " kWh</div>";
    html += "</div>";
  }
  
  if (!wifiConnected || !deviceAdded) {
    html += "<form action='/connect' method='POST'>";
    html += "<select name='ssid' id='ssid' required>";
    html += "<option value=''>Виберіть WiFi мережу...</option>";
    
    // Сканування WiFi мереж
    int n = WiFi.scanNetworks();
    for (int i = 0; i < n; i++) {
      String security = (WiFi.encryptionType(i) == WIFI_AUTH_OPEN) ? " 🔓" : " 🔒";
      html += "<option value='" + WiFi.SSID(i) + "'>" + WiFi.SSID(i) + security + " (" + String(WiFi.RSSI(i)) + " dBm)</option>";
    }
    
    html += "</select>";
    html += "<input type='password' name='password' placeholder='Пароль WiFi'>";
    html += "<button type='submit'>Підключити</button>";
    html += "</form>";
  }
  
  html += "<p style='text-align: center; color: #666; margin-top: 20px; font-size: 12px;'>Device ID: " + deviceId + "</p>";
  html += "</div></body></html>";
  
  server.send(200, "text/html", html);
}

void handleConnect() {
  String ssid = server.arg("ssid");
  String password = server.arg("password");
  
  if (ssid.length() > 0) {
    savedSSID = ssid;
    savedPassword = password;
    saveConfig();
    
    String html = "<!DOCTYPE html><html><head>";
    html += "<meta charset='UTF-8'>";
    html += "<meta http-equiv='refresh' content='10;url=/'>";
    html += "<style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;}</style>";
    html += "</head><body>";
    html += "<h2>Підключення до WiFi...</h2>";
    html += "<p>Будь ласка, зачекайте. Сторінка оновиться автоматично.</p>";
    html += "</body></html>";
    
    server.send(200, "text/html", html);
    
    delay(1000);
    connectToWiFi();
  } else {
    server.send(400, "text/plain", "Помилка: не вибрано мережу");
  }
}

void handleApiStatus() {
  StaticJsonDocument<300> doc;
  doc["deviceId"] = deviceId;
  doc["wifiConnected"] = wifiConnected;
  doc["mqttConnected"] = mqttConnected;
  doc["relayState"] = relayState;
  doc["confirmationCode"] = confirmationCode;
  doc["deviceAdded"] = deviceAdded;
  doc["powerKw"] = currentPowerKw;
  doc["energyKwh"] = totalEnergyKwh;
  doc["apMode"] = apMode;
  doc["energyInterval"] = ENERGY_UPDATE_INTERVAL / 1000;
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleCaptivePortal() {
  // Перенаправляємо всі запити на головну сторінку для Captive Portal
  if (!server.hostHeader().equals(WiFi.softAPIP().toString())) {
    server.sendHeader("Location", "http://" + WiFi.softAPIP().toString() + "/", true);
    server.send(302, "text/plain", "");
  } else {
    handleRoot();
  }
}