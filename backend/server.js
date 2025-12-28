// server.js - Повна версія з Energy Mode Management та Daily Data Reset
// ОНОВЛЕНО: Додано підтримку діапазонів часу (range schedules)
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const mqtt = require('mqtt');
const jwt = require('jsonwebtoken');
const { OAuth2Client } = require('google-auth-library');
const httpProxy = require('http-proxy');
const cron = require('node-cron');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 8080;

// Google OAuth2 Client
const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

// JWT Secret
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-this';

// Middleware
app.use(cors({
  origin: '*',
  credentials: true
}));
app.use(express.json());

// PostgreSQL підключення
const pool = new Pool({
  user: process.env.DB_USER || 'iot_user',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'iot_devices',
  password: process.env.DB_PASSWORD || 'Tomwoker159357',
  port: process.env.DB_PORT || 5432,
});

// MQTT підключення
const mqttOptions = {
  host: process.env.MQTT_HOST || 'localhost',
  port: process.env.MQTT_PORT || 1883,
  protocol: process.env.MQTT_PROTOCOL || 'mqtt',
  reconnectPeriod: 1000,
  clientId: 'NodeJS_Backend_' + Date.now(),
};

if (process.env.MQTT_USERNAME) {
  mqttOptions.username = process.env.MQTT_USERNAME;
  mqttOptions.password = process.env.MQTT_PASSWORD;
}

const mqttClient = mqtt.connect(mqttOptions);

// Зберігаємо статуси пристроїв в пам'яті
const deviceStatuses = new Map();
const deviceConfirmationCodes = new Map();

// ============ ЩОДЕННЕ ОЧИЩЕННЯ О 00:00 ============
cron.schedule('0 0 * * *', async () => {
  console.log('\n🕛 MIDNIGHT DATA CLEANUP - Starting daily energy data reset...');
  console.log('========================================================');
  
  const startTime = Date.now();
  
  try {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');
      
      const countResult = await client.query('SELECT COUNT(*) FROM energy_data');
      const totalRecords = parseInt(countResult.rows[0].count);
      
      const devicesResult = await client.query(
        'SELECT COUNT(DISTINCT device_id) FROM energy_data'
      );
      const devicesCount = parseInt(devicesResult.rows[0].count);
      
      console.log(`📊 Current data: ${totalRecords} records for ${devicesCount} devices`);
      
      if (totalRecords > 0) {
        const deleteResult = await client.query(
          'DELETE FROM energy_data WHERE created_at < CURRENT_DATE'
        );
        
        const deletedCount = deleteResult.rowCount;
        
        let resetCommandsSent = 0;
        deviceStatuses.forEach((status, deviceId) => {
          if (status.online) {
            const commandTopic = `solar/${deviceId}/command`;
            const commandPayload = JSON.stringify({
              command: 'resetEnergy',
              state: true,
              timestamp: Date.now(),
              reason: 'daily_reset'
            });
            
            mqttClient.publish(commandTopic, commandPayload, { qos: 1 }, (error) => {
              if (!error) {
                console.log(`🔄 Reset command sent to ${deviceId}`);
              }
            });
            resetCommandsSent++;
          }
        });
        
        await client.query('COMMIT');
        
        const duration = Date.now() - startTime;
        
        console.log(`✅ Daily cleanup completed in ${duration}ms:`);
        console.log(`   📭 Deleted: ${deletedCount} energy records`);
        console.log(`   🔄 Reset commands sent to: ${resetCommandsSent} devices`);
        console.log(`   🆕 New day started - fresh data collection begins`);
        
        await client.query(`
          INSERT INTO device_history (device_id, relay_state, wifi_rssi, uptime, free_heap, timestamp)
          VALUES ('SYSTEM_CLEANUP', false, 0, 0, 0, CURRENT_TIMESTAMP)
        `);
        
      } else {
        console.log('ℹ️  No data to clean - database already empty');
      }
      
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    
  } catch (error) {
    console.error('❌ Error during midnight cleanup:', error);
    console.log('⚠️  Data cleanup failed - manual intervention may be required');
  }
  
  console.log('========================================================');
  console.log('🌅 Ready for new day data collection\n');
}, {
  scheduled: true,
  timezone: "Europe/Kiev"
});

// ============ ENERGY SCHEDULES CRON JOB - КОЖНУ ХВИЛИНУ ============
// ОНОВЛЕНО: Додано підтримку range розкладів
cron.schedule('* * * * *', async () => {
  try {
    const now = new Date();
    const currentHour = now.getHours();
    const currentMinute = now.getMinutes();
    const currentDayOfWeek = now.getDay();
    
    // ========== ОБРОБКА TIME РОЗКЛАДІВ (як раніше) ==========
    const timeSchedulesToExecute = await pool.query(
      `SELECT s.*, d.device_id as device_device_id
       FROM energy_schedules s
       JOIN devices d ON d.device_id = s.device_id
       WHERE s.is_enabled = true 
         AND s.schedule_type = 'time'
         AND s.next_execution IS NOT NULL
         AND s.next_execution <= $1`,
      [now]
    );
    
    if (timeSchedulesToExecute.rows.length > 0) {
      console.log(`\n⏰ Found ${timeSchedulesToExecute.rows.length} TIME schedule(s) to execute`);
    }
    
    for (const schedule of timeSchedulesToExecute.rows) {
      await executeTimeSchedule(schedule);
    }
    
    // ========== ОБРОБКА RANGE РОЗКЛАДІВ (НОВЕ) ==========
    const rangeSchedules = await pool.query(
      `SELECT s.*, d.device_id as device_device_id
       FROM energy_schedules s
       JOIN devices d ON d.device_id = s.device_id
       WHERE s.is_enabled = true 
         AND s.schedule_type = 'range'`
    );
    
    for (const schedule of rangeSchedules.rows) {
      await checkAndExecuteRangeSchedule(schedule, currentHour, currentMinute, currentDayOfWeek);
    }
    
  } catch (error) {
    console.error('❌ Error in schedule cron job:', error);
  }
}, {
  scheduled: true,
  timezone: "Europe/Kiev"
});

// ============ ФУНКЦІЯ ВИКОНАННЯ TIME РОЗКЛАДУ (як раніше) ============
async function executeTimeSchedule(schedule) {
  try {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');
      
      const deviceId = schedule.device_id;
      const targetMode = schedule.target_mode;
      
      console.log(`📅 Executing TIME schedule: ${schedule.name} (${deviceId} → ${targetMode})`);
      
      const currentModeResult = await client.query(
        'SELECT current_mode FROM device_energy_modes WHERE device_id = $1',
        [deviceId]
      );
      
      const oldMode = currentModeResult.rows.length > 0 
        ? currentModeResult.rows[0].current_mode 
        : null;
      
      await client.query(
        `INSERT INTO device_energy_modes (device_id, current_mode, changed_by, last_changed)
         VALUES ($1, $2, 'schedule', CURRENT_TIMESTAMP)
         ON CONFLICT (device_id) 
         DO UPDATE SET 
           current_mode = $2,
           changed_by = 'schedule',
           last_changed = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP`,
        [deviceId, targetMode]
      );
      
      await client.query(
        `INSERT INTO energy_mode_history (device_id, from_mode, to_mode, changed_by, schedule_id)
         VALUES ($1, $2, $3, 'schedule', $4)`,
        [deviceId, oldMode, targetMode, schedule.id]
      );
      
      if (schedule.repeat_type === 'once') {
        await client.query(
          `UPDATE energy_schedules 
           SET last_executed = CURRENT_TIMESTAMP,
               next_execution = NULL,
               is_enabled = false
           WHERE id = $1`,
          [schedule.id]
        );
        console.log(`  ✓ One-time schedule disabled`);
      } else {
        await client.query(
          `UPDATE energy_schedules 
           SET last_executed = CURRENT_TIMESTAMP,
               next_execution = calculate_next_execution(
                 hour, minute, repeat_type, repeat_days, CURRENT_TIMESTAMP
               )
           WHERE id = $1`,
          [schedule.id]
        );
        console.log(`  ✓ Next execution scheduled`);
      }
      
      await client.query('COMMIT');
      
      const commandTopic = `solar/${deviceId}/command`;
      const commandPayload = JSON.stringify({
        command: 'setEnergyMode',
        mode: targetMode,
        timestamp: Date.now(),
        source: 'schedule',
        scheduleName: schedule.name
      });
      
      mqttClient.publish(commandTopic, commandPayload, { qos: 1 }, (error) => {
        if (error) {
          console.error(`  ❌ Failed to send MQTT command:`, error);
        } else {
          console.log(`  ✅ MQTT command sent: ${deviceId} → ${targetMode}`);
        }
      });
      
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    
  } catch (error) {
    console.error(`❌ Error executing TIME schedule ${schedule.id}:`, error);
  }
}

// ============ ФУНКЦІЯ ПЕРЕВІРКИ ТА ВИКОНАННЯ RANGE РОЗКЛАДУ (НОВЕ) ============
async function checkAndExecuteRangeSchedule(schedule, currentHour, currentMinute, currentDayOfWeek) {
  try {
    const {
      id,
      device_id: deviceId,
      name,
      target_mode: targetMode,
      secondary_mode: secondaryMode,
      start_hour: startHour,
      start_minute: startMinute,
      end_hour: endHour,
      end_minute: endMinute,
      repeat_type: repeatType,
      repeat_days: repeatDays
    } = schedule;
    
    // Перевіряємо чи сьогодні потрібно виконувати
    if (!shouldRunToday(repeatType, repeatDays, currentDayOfWeek)) {
      return;
    }
    
    // Розраховуємо час в хвилинах для порівняння
    const currentTimeMinutes = currentHour * 60 + currentMinute;
    const startTimeMinutes = startHour * 60 + startMinute;
    const endTimeMinutes = endHour * 60 + endMinute;
    
    // Визначаємо чи зараз ми в діапазоні
    let isInRange;
    if (endTimeMinutes <= startTimeMinutes) {
      // Діапазон через північ (наприклад, 22:00 - 06:00)
      isInRange = currentTimeMinutes >= startTimeMinutes || currentTimeMinutes < endTimeMinutes;
    } else {
      // Звичайний діапазон (наприклад, 08:00 - 20:00)
      isInRange = currentTimeMinutes >= startTimeMinutes && currentTimeMinutes < endTimeMinutes;
    }
    
    // Визначаємо який режим має бути зараз
    const effectiveSecondaryMode = secondaryMode || (targetMode === 'solar' ? 'grid' : 'solar');
    const expectedMode = isInRange ? targetMode : effectiveSecondaryMode;
    
    // Отримуємо поточний режим
    const currentModeResult = await pool.query(
      'SELECT current_mode FROM device_energy_modes WHERE device_id = $1',
      [deviceId]
    );
    const currentMode = currentModeResult.rows.length > 0 
      ? currentModeResult.rows[0].current_mode 
      : null;
    
    // Перевіряємо чи зараз точка переходу (початок або кінець діапазону)
    const isStartTransition = currentHour === startHour && currentMinute === startMinute;
    const isEndTransition = currentHour === endHour && currentMinute === endMinute;
    
    // Перемикаємо тільки якщо:
    // 1. Зараз точка переходу (початок або кінець діапазону)
    // 2. Поточний режим відрізняється від очікуваного
    if ((isStartTransition || isEndTransition) && currentMode !== expectedMode) {
      console.log(`\n📅 RANGE schedule transition: ${name}`);
      console.log(`   Device: ${deviceId}`);
      console.log(`   Range: ${String(startHour).padStart(2, '0')}:${String(startMinute).padStart(2, '0')} - ${String(endHour).padStart(2, '0')}:${String(endMinute).padStart(2, '0')}`);
      console.log(`   Transition: ${isStartTransition ? 'START' : 'END'} of range`);
      console.log(`   Mode change: ${currentMode} → ${expectedMode}`);
      
      await executeRangeModeChange(deviceId, currentMode, expectedMode, schedule);
    }
    
  } catch (error) {
    console.error(`❌ Error checking RANGE schedule ${schedule.id}:`, error);
  }
}

// ============ ФУНКЦІЯ ПЕРЕВІРКИ ЧИ СЬОГОДНІ ПОТРІБНО ВИКОНУВАТИ (НОВЕ) ============
function shouldRunToday(repeatType, repeatDays, currentDayOfWeek) {
  switch (repeatType) {
    case 'once':
    case 'daily':
      return true;
    case 'weekdays':
      // Пн-Пт (1-5)
      return currentDayOfWeek >= 1 && currentDayOfWeek <= 5;
    case 'weekends':
      // Сб-Нд (0, 6)
      return currentDayOfWeek === 0 || currentDayOfWeek === 6;
    case 'weekly':
      // Перевіряємо чи поточний день є у списку
      return repeatDays && repeatDays.includes(currentDayOfWeek);
    default:
      return true;
  }
}

// ============ ФУНКЦІЯ ВИКОНАННЯ ЗМІНИ РЕЖИМУ ДЛЯ RANGE (НОВЕ) ============
async function executeRangeModeChange(deviceId, oldMode, newMode, schedule) {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    // Оновлюємо режим
    await client.query(
      `INSERT INTO device_energy_modes (device_id, current_mode, changed_by, last_changed)
       VALUES ($1, $2, 'schedule_range', CURRENT_TIMESTAMP)
       ON CONFLICT (device_id) 
       DO UPDATE SET 
         current_mode = $2,
         changed_by = 'schedule_range',
         last_changed = CURRENT_TIMESTAMP,
         updated_at = CURRENT_TIMESTAMP`,
      [deviceId, newMode]
    );
    
    // Записуємо в історію
    await client.query(
      `INSERT INTO energy_mode_history (device_id, from_mode, to_mode, changed_by, schedule_id)
       VALUES ($1, $2, $3, 'schedule_range', $4)`,
      [deviceId, oldMode, newMode, schedule.id]
    );
    
    // Оновлюємо last_executed
    await client.query(
      `UPDATE energy_schedules SET last_executed = CURRENT_TIMESTAMP WHERE id = $1`,
      [schedule.id]
    );
    
    await client.query('COMMIT');
    
    // Відправляємо MQTT команду
    const commandTopic = `solar/${deviceId}/command`;
    const commandPayload = JSON.stringify({
      command: 'setEnergyMode',
      mode: newMode,
      timestamp: Date.now(),
      source: 'schedule_range',
      scheduleName: schedule.name
    });
    
    mqttClient.publish(commandTopic, commandPayload, { qos: 1 }, (error) => {
      if (error) {
        console.error(`  ❌ Failed to send MQTT command:`, error);
      } else {
        console.log(`  ✅ MQTT command sent: ${deviceId} → ${newMode}`);
      }
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error(`❌ Error executing RANGE mode change:`, error);
  } finally {
    client.release();
  }
}

console.log('⏰ Schedule checker started (every minute) - supports TIME and RANGE schedules');

// MQTT обробники
mqttClient.on('connect', () => {
  console.log('✅ Connected to MQTT broker');
  
  mqttClient.subscribe('solar/+/status', (err) => {
    if (!err) console.log('📡 Subscribed to solar/+/status');
  });
  
  mqttClient.subscribe('solar/+/online', (err) => {
    if (!err) console.log('📡 Subscribed to solar/+/online');
  });
  
  mqttClient.subscribe('solar/+/confirmation', (err) => {
    if (!err) console.log('📡 Subscribed to solar/+/confirmation');
  });
  
  mqttClient.subscribe('solar/+/response', (err) => {
    if (!err) console.log('📡 Subscribed to solar/+/response');
  });
  
  mqttClient.subscribe('solar/+/energy', (err) => {
    if (!err) console.log('📡 Subscribed to solar/+/energy');
  });
});

mqttClient.on('error', (error) => {
  console.error('❌ MQTT connection error:', error);
});

mqttClient.on('reconnect', () => {
  console.log('🔄 MQTT reconnecting...');
});

mqttClient.on('message', async (topic, message) => {
  const topicParts = topic.split('/');
  if (topicParts.length < 3) return;
  
  const deviceId = topicParts[1];
  const messageType = topicParts[2];
  
  console.log(`📨 MQTT Message - Device: ${deviceId}, Type: ${messageType}`);
  
  try {
    if (messageType === 'status') {
      const status = JSON.parse(message.toString());
      console.log(`📊 Status from ${deviceId}:`, status);
      
      if (status.confirmationCode) {
        deviceConfirmationCodes.set(deviceId, status.confirmationCode);
        console.log(`✅ Stored confirmation code for ${deviceId}: ${status.confirmationCode}`);
      }
      
      deviceStatuses.set(deviceId, {
        ...status,
        lastSeen: new Date(),
        online: true
      });
      
      if (status.powerKw !== undefined && status.energyKwh !== undefined) {
        await saveEnergyData(deviceId, status.powerKw, status.energyKwh);
      }
      
      const deviceExists = await pool.query(
        'SELECT id FROM devices WHERE device_id = $1',
        [deviceId]
      );
      
      if (deviceExists.rows.length > 0) {
        await saveDeviceStatus(deviceId, status);
      }
      
    } else if (messageType === 'online') {
      const isOnline = message.toString().toLowerCase() === 'true' || message.toString() === '1';
      console.log(`${isOnline ? '🟢' : '🔴'} Device ${deviceId} is ${isOnline ? 'online' : 'offline'}`);
      
      const currentStatus = deviceStatuses.get(deviceId) || {};
      deviceStatuses.set(deviceId, {
        ...currentStatus,
        online: isOnline,
        lastSeen: new Date()
      });
      
    } else if (messageType === 'confirmation') {
      const code = message.toString();
      deviceConfirmationCodes.set(deviceId, code);
      console.log(`✅ Received separate confirmation code for ${deviceId}: ${code}`);
      
    } else if (messageType === 'response') {
      console.log(`📬 Response from ${deviceId}: ${message.toString()}`);
      
    } else if (messageType === 'energy') {
      const energyData = JSON.parse(message.toString());
      console.log(`⚡ Energy data (15s) from ${deviceId}: ${energyData.powerKw} kW, ${energyData.energyKwh} kWh`);
      
      await saveEnergyData(deviceId, energyData.powerKw, energyData.energyKwh);
      
      const currentStatus = deviceStatuses.get(deviceId) || {};
      deviceStatuses.set(deviceId, {
        ...currentStatus,
        powerKw: energyData.powerKw,
        energyKwh: energyData.energyKwh,
        lastEnergyUpdate: new Date()
      });
    }
  } catch (error) {
    console.error(`❌ Error processing MQTT message from ${deviceId}:`, error);
  }
});

// ФУНКЦІЯ: Збереження енергетичних даних в БД
async function saveEnergyData(deviceId, powerKw, energyKwh, timestamp = null) {
  try {
    const timestampValue = timestamp ? new Date(timestamp) : new Date();
    
    const result = await pool.query(
      `INSERT INTO energy_data (device_id, power_kw, energy_kwh, timestamp) 
       VALUES ($1, $2, $3, $4) 
       RETURNING id`,
      [deviceId, parseFloat(powerKw), parseFloat(energyKwh), timestampValue]
    );
    
    console.log(`💾 Saved energy data to DB: ${deviceId} - ${powerKw} kW, ${energyKwh} kWh at ${timestampValue.toLocaleTimeString()}`);
    return result.rows[0].id;
  } catch (error) {
    console.error(`❌ Error saving energy data for ${deviceId}:`, error);
    throw error;
  }
}

// Middleware для автентифікації
const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }
  
  if (token === 'test-token-12345') {
    try {
      const testUser = await getOrCreateTestUser('test@solar.com', 'test-google-id');
      req.user = {
        id: testUser.id,
        email: testUser.email,
        googleId: testUser.google_id
      };
      return next();
    } catch (error) {
      console.error('Error creating test user:', error);
      return res.status(500).json({ error: 'Failed to create test user' });
    }
  }
  
  if (token.startsWith('web-temp-token-')) {
    try {
      const googleId = token.replace('web-temp-token-', '');
      const webUser = await getOrCreateTestUser('webuser@solar.com', googleId);
      req.user = {
        id: webUser.id,
        email: webUser.email,
        googleId: googleId
      };
      return next();
    } catch (error) {
      console.error('Error creating web user:', error);
      return res.status(500).json({ error: 'Failed to create web user' });
    }
  }
  
  jwt.verify(token, JWT_SECRET, async (err, user) => {
    if (err) {
      console.log('❌ Invalid JWT token');
      return res.status(403).json({ error: 'Invalid token' });
    }
    req.user = user;
    next();
  });
};

// Функція для отримання або створення тестового користувача
async function getOrCreateTestUser(email, googleId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    let user = await client.query(
      'SELECT * FROM users WHERE email = $1',
      [email]
    );
    
    if (user.rows.length === 0) {
      user = await client.query(
        `INSERT INTO users (google_id, email, name, picture, created_at, last_login) 
         VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) 
         RETURNING *`,
        [googleId || 'test-' + Date.now(), email, 'Test User', null]
      );
      console.log(`✅ Created test user: ${email}`);
    } else {
      user = await client.query(
        `UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE email = $1 RETURNING *`,
        [email]
      );
      console.log(`✅ Updated test user: ${email}`);
    }
    
    await client.query('COMMIT');
    return user.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// ========== API ROUTES ==========

app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    mqtt: mqttClient.connected,
    timestamp: new Date(),
    mode: process.env.NODE_ENV || 'development',
    devices: deviceStatuses.size,
    codes: deviceConfirmationCodes.size,
    features: {
      dailyCleanup: 'enabled_00:00_Kiev',
      energySchedules: 'enabled_every_minute',
      rangeSchedules: 'enabled'
    }
  });
});

app.get('/', (req, res) => {
  res.json({
    message: 'Solar Controller API with Energy Mode Management',
    version: '2.3.0',
    features: {
      'energy_tracking': 'enabled',
      'daily_reset': '00:00 Kiev time',
      'energy_mode_switching': 'manual + automatic schedules',
      'schedule_types': 'time + range',
      'esp32_interval': '15 seconds',
      'app_sync': '5 seconds'
    },
    endpoints: {
      health: '/health',
      api: '/api/*',
      energy: '/api/devices/:deviceId/energy',
      energyMode: '/api/devices/:deviceId/energy-mode',
      schedules: '/api/devices/:deviceId/schedules'
    }
  });
});

// Test login
app.post('/api/auth/test', async (req, res) => {
  try {
    const user = await getOrCreateTestUser('test@solar.com', 'test-google-id');
    
    const token = jwt.sign(
      { 
        id: user.id,
        googleId: user.google_id,
        email: user.email
      },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        picture: user.picture
      }
    });
  } catch (error) {
    console.error('Error in test login:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Google OAuth2 login
app.post('/api/auth/google', async (req, res) => {
  const client = await pool.connect();
  try {
    const { credential } = req.body;
    
    const ticket = await googleClient.verifyIdToken({
      idToken: credential,
      audience: process.env.GOOGLE_CLIENT_ID
    });
    
    const payload = ticket.getPayload();
    const googleId = payload['sub'];
    const email = payload['email'];
    const name = payload['name'];
    const picture = payload['picture'];
    
    await client.query('BEGIN');
    
    let user = await client.query(
      'SELECT * FROM users WHERE google_id = $1',
      [googleId]
    );
    
    if (user.rows.length === 0) {
      user = await client.query(
        `INSERT INTO users (google_id, email, name, picture, created_at, last_login) 
         VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) 
         RETURNING *`,
        [googleId, email, name, picture]
      );
    } else {
      user = await client.query(
        `UPDATE users 
         SET email = $2, name = $3, picture = $4, last_login = CURRENT_TIMESTAMP
         WHERE google_id = $1
         RETURNING *`,
        [googleId, email, name, picture]
      );
    }
    
    await client.query('COMMIT');
    
    const token = jwt.sign(
      { 
        id: user.rows[0].id,
        googleId: user.rows[0].google_id,
        email: user.rows[0].email
      },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      token,
      user: {
        id: user.rows[0].id,
        email: user.rows[0].email,
        name: user.rows[0].name,
        picture: user.rows[0].picture
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error in Google auth:', error);
    res.status(500).json({ error: 'Authentication failed' });
  } finally {
    client.release();
  }
});

// Get current user
app.get('/api/auth/me', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, email, name, picture FROM users WHERE id = $1',
      [req.user.id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get all devices
app.get('/api/devices', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT DISTINCT d.*, ud.is_owner, ud.added_at
       FROM devices d
       JOIN user_devices ud ON d.id = ud.device_id
       WHERE ud.user_id = $1
       ORDER BY ud.added_at DESC`,
      [req.user.id]
    );
    
    const devices = result.rows.map(device => ({
      ...device,
      status: deviceStatuses.get(device.device_id) || { online: false }
    }));
    
    res.json(devices);
  } catch (error) {
    console.error('Error fetching devices:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============ ENERGY MODE MANAGEMENT ============

// Отримання поточного режиму енергії пристрою
app.get('/api/devices/:deviceId/energy-mode', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    
    console.log(`📊 Getting energy mode for ${deviceId}`);
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    let modeResult = await pool.query(
      'SELECT * FROM device_energy_modes WHERE device_id = $1',
      [deviceId]
    );
    
    if (modeResult.rows.length === 0) {
      modeResult = await pool.query(
        `INSERT INTO device_energy_modes (device_id, current_mode, changed_by)
         VALUES ($1, 'solar', 'default')
         RETURNING *`,
        [deviceId]
      );
      console.log(`✅ Created default energy mode for ${deviceId}: solar`);
    }
    
    const mode = modeResult.rows[0];
    
    res.json({
      deviceId: mode.device_id,
      currentMode: mode.current_mode,
      lastChanged: mode.last_changed,
      changedBy: mode.changed_by
    });
    
  } catch (error) {
    console.error('Error getting energy mode:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Ручна зміна режиму енергії
app.post('/api/devices/:deviceId/energy-mode', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const { deviceId } = req.params;
    const { mode } = req.body;
    
    console.log(`\n🔄 Manual energy mode change for ${deviceId} → ${mode}`);
    
    if (!mode || !['solar', 'grid'].includes(mode)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid mode. Must be "solar" or "grid"' });
    }
    
    const accessCheck = await client.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Access denied' });
    }
    
    const currentModeResult = await client.query(
      'SELECT current_mode FROM device_energy_modes WHERE device_id = $1',
      [deviceId]
    );
    
    const oldMode = currentModeResult.rows.length > 0 
      ? currentModeResult.rows[0].current_mode 
      : null;
    
    if (oldMode === mode) {
      await client.query('ROLLBACK');
      console.log(`ℹ️  Mode already set to ${mode}`);
      return res.json({ 
        success: true, 
        message: 'Mode already set to ' + mode,
        currentMode: mode 
      });
    }
    
    await client.query(
      `INSERT INTO device_energy_modes (device_id, current_mode, changed_by, last_changed)
       VALUES ($1, $2, 'manual', CURRENT_TIMESTAMP)
       ON CONFLICT (device_id) 
       DO UPDATE SET 
         current_mode = $2,
         changed_by = 'manual',
         last_changed = CURRENT_TIMESTAMP,
         updated_at = CURRENT_TIMESTAMP`,
      [deviceId, mode]
    );
    
    console.log(`✅ Database updated: ${oldMode || 'none'} → ${mode}`);
    
    await client.query(
      `INSERT INTO energy_mode_history (device_id, from_mode, to_mode, changed_by)
       VALUES ($1, $2, $3, 'manual')`,
      [deviceId, oldMode, mode]
    );
    
    console.log(`✅ History record added`);
    
    await client.query('COMMIT');
    
    console.log(`📤 Sending MQTT command to ESP32...`);
    
    const commandTopic = `solar/${deviceId}/command`;
    const commandPayload = JSON.stringify({
      command: 'setEnergyMode',
      mode: mode,
      timestamp: Date.now(),
      source: 'manual'
    });
    
    mqttClient.publish(commandTopic, commandPayload, { qos: 1 }, (error) => {
      if (error) {
        console.error(`❌ Failed to send MQTT command:`, error);
      } else {
        console.log(`✅ MQTT command sent: setEnergyMode → ${mode}`);
      }
    });
    
    res.json({
      success: true,
      deviceId,
      currentMode: mode,
      previousMode: oldMode,
      changedBy: 'manual',
      timestamp: new Date()
    });
    
    console.log(`✅ Manual mode change completed\n`);
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error changing energy mode:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// Отримання історії перемикань
app.get('/api/devices/:deviceId/energy-mode/history', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { limit = 50 } = req.query;
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    const history = await pool.query(
      `SELECT 
        h.*,
        s.name as schedule_name
       FROM energy_mode_history h
       LEFT JOIN energy_schedules s ON h.schedule_id = s.id
       WHERE h.device_id = $1
       ORDER BY h.timestamp DESC
       LIMIT $2`,
      [deviceId, parseInt(limit)]
    );
    
    res.json({
      deviceId,
      count: history.rows.length,
      history: history.rows
    });
    
  } catch (error) {
    console.error('Error getting energy mode history:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============ ENERGY SCHEDULES MANAGEMENT ============
// ОНОВЛЕНО: Додано підтримку range розкладів

// Отримання всіх розкладів для пристрою
app.get('/api/devices/:deviceId/schedules', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    
    console.log(`📅 Getting schedules for ${deviceId}`);
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    // ОНОВЛЕНО: Сортування враховує обидва типи розкладів
    const schedules = await pool.query(
      `SELECT * FROM energy_schedules 
       WHERE device_id = $1 AND user_id = $2
       ORDER BY 
         COALESCE(hour, start_hour),
         COALESCE(minute, start_minute)`,
      [deviceId, req.user.id]
    );
    
    res.json({
      deviceId,
      count: schedules.rows.length,
      schedules: schedules.rows
    });
    
  } catch (error) {
    console.error('Error getting schedules:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Створення нового розкладу
// ОНОВЛЕНО: Підтримка time та range типів
app.post('/api/devices/:deviceId/schedules', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const { deviceId } = req.params;
    const { 
      name, 
      targetMode,
      scheduleType = 'time',  // НОВЕ: 'time' або 'range'
      // Для time
      hour, 
      minute,
      // Для range (НОВЕ)
      startHour,
      startMinute,
      endHour,
      endMinute,
      secondaryMode,  // НОВЕ
      // Загальні
      repeatType = 'once', 
      repeatDays = null,
      isEnabled = true 
    } = req.body;
    
    console.log(`\n📅 Creating ${scheduleType.toUpperCase()} schedule for ${deviceId}`);
    console.log(`   Name: ${name}`);
    console.log(`   Mode: ${targetMode}`);
    
    if (scheduleType === 'time') {
      console.log(`   Time: ${hour}:${minute}`);
    } else {
      console.log(`   Range: ${startHour}:${startMinute} - ${endHour}:${endMinute}`);
      console.log(`   Secondary mode: ${secondaryMode || 'auto'}`);
    }
    console.log(`   Repeat: ${repeatType}`);
    
    // Валідація загальних полів
    if (!name || !targetMode) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Missing required fields: name, targetMode' });
    }
    
    if (!['solar', 'grid'].includes(targetMode)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid target mode' });
    }
    
    if (!['time', 'range'].includes(scheduleType)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid schedule type. Must be "time" or "range"' });
    }
    
    if (!['once', 'daily', 'weekly', 'weekdays', 'weekends'].includes(repeatType)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid repeat type' });
    }
    
    // Валідація для time
    if (scheduleType === 'time') {
      if (hour === undefined || minute === undefined) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Missing hour/minute for time schedule' });
      }
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid time values' });
      }
    }
    
    // Валідація для range
    if (scheduleType === 'range') {
      if (startHour === undefined || startMinute === undefined || 
          endHour === undefined || endMinute === undefined) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Missing start/end time for range schedule' });
      }
      if (startHour < 0 || startHour > 23 || startMinute < 0 || startMinute > 59 ||
          endHour < 0 || endHour > 23 || endMinute < 0 || endMinute > 59) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid time values' });
      }
      if (secondaryMode && !['solar', 'grid'].includes(secondaryMode)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid secondary mode' });
      }
    }
    
    // Перевірка доступу
    const accessCheck = await client.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Access denied' });
    }
    
    let schedule;
    
    if (scheduleType === 'time') {
      // Створення TIME розкладу (як раніше)
      const nextExecution = isEnabled ? calculateNextExecution(
        hour,
        minute,
        repeatType,
        repeatDays
      ) : null;

      schedule = await client.query(
        `INSERT INTO energy_schedules 
          (device_id, user_id, name, target_mode, schedule_type, hour, minute, repeat_type, repeat_days, is_enabled, next_execution)
        VALUES ($1, $2, $3, $4, 'time', $5, $6, $7, $8, $9, $10)
        RETURNING *`,
        [deviceId, req.user.id, name, targetMode, hour, minute, repeatType, repeatDays, isEnabled, nextExecution]
      );
    } else {
      // Створення RANGE розкладу (НОВЕ)
      const effectiveSecondaryMode = secondaryMode || (targetMode === 'solar' ? 'grid' : 'solar');
      
      schedule = await client.query(
        `INSERT INTO energy_schedules 
          (device_id, user_id, name, target_mode, schedule_type, start_hour, start_minute, end_hour, end_minute, secondary_mode, repeat_type, repeat_days, is_enabled)
        VALUES ($1, $2, $3, $4, 'range', $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING *`,
        [deviceId, req.user.id, name, targetMode, startHour, startMinute, endHour, endMinute, effectiveSecondaryMode, repeatType, repeatDays, isEnabled]
      );
    }
    
    await client.query('COMMIT');
    
    console.log(`✅ Schedule created with ID: ${schedule.rows[0].id}`);
    if (scheduleType === 'time') {
      console.log(`   Next execution: ${schedule.rows[0].next_execution}\n`);
    } else {
      console.log(`   Range schedule - checks every minute\n`);
    }
    
    res.json({
      success: true,
      schedule: schedule.rows[0]
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error creating schedule:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// Оновлення розкладу
// ОНОВЛЕНО: Підтримка зміни типу розкладу
app.put('/api/devices/:deviceId/schedules/:scheduleId', authenticateToken, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { deviceId, scheduleId } = req.params;
    const { 
      name, 
      targetMode,
      scheduleType,  // НОВЕ
      hour, 
      minute,
      startHour,     // НОВЕ
      startMinute,   // НОВЕ
      endHour,       // НОВЕ
      endMinute,     // НОВЕ
      secondaryMode, // НОВЕ
      repeatType, 
      repeatDays,
      isEnabled 
    } = req.body;

    console.log(`\n📅 Updating schedule ${scheduleId} for device ${deviceId}`);

    // Перевіряємо, що розклад належить цьому користувачу і цьому девайсу
    const current = await client.query(
      `SELECT * FROM energy_schedules 
       WHERE id = $1 AND device_id = $2 AND user_id = $3`,
      [scheduleId, deviceId, req.user.id]
    );

    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Access denied or schedule not found' });
    }

    const currentSchedule = current.rows[0];
    
    // Визначаємо фінальні значення
    const finalScheduleType = scheduleType ?? currentSchedule.schedule_type;
    const finalTargetMode = targetMode ?? currentSchedule.target_mode;
    const finalRepeatType = repeatType ?? currentSchedule.repeat_type;
    const finalRepeatDays = repeatDays ?? currentSchedule.repeat_days;
    const finalIsEnabled = isEnabled ?? currentSchedule.is_enabled;
    const finalName = name ?? currentSchedule.name;

    let schedule;

    if (finalScheduleType === 'time') {
      // Оновлення TIME розкладу
      const finalHour = hour ?? currentSchedule.hour;
      const finalMinute = minute ?? currentSchedule.minute;
      
      const nextExecution = finalIsEnabled
        ? calculateNextExecution(finalHour, finalMinute, finalRepeatType, finalRepeatDays)
        : null;

      schedule = await client.query(
        `UPDATE energy_schedules 
         SET name = $1, 
             target_mode = $2, 
             schedule_type = 'time',
             hour = $3, 
             minute = $4,
             start_hour = NULL,
             start_minute = NULL,
             end_hour = NULL,
             end_minute = NULL,
             secondary_mode = NULL,
             repeat_type = $5, 
             repeat_days = $6, 
             is_enabled = $7, 
             next_execution = $8,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $9
         RETURNING *`,
        [finalName, finalTargetMode, finalHour, finalMinute, finalRepeatType, finalRepeatDays, finalIsEnabled, nextExecution, scheduleId]
      );
    } else {
      // Оновлення RANGE розкладу
      const finalStartHour = startHour ?? currentSchedule.start_hour;
      const finalStartMinute = startMinute ?? currentSchedule.start_minute;
      const finalEndHour = endHour ?? currentSchedule.end_hour;
      const finalEndMinute = endMinute ?? currentSchedule.end_minute;
      const finalSecondaryMode = secondaryMode ?? currentSchedule.secondary_mode ?? 
        (finalTargetMode === 'solar' ? 'grid' : 'solar');

      schedule = await client.query(
        `UPDATE energy_schedules 
         SET name = $1, 
             target_mode = $2, 
             schedule_type = 'range',
             hour = NULL,
             minute = NULL,
             start_hour = $3,
             start_minute = $4,
             end_hour = $5,
             end_minute = $6,
             secondary_mode = $7,
             repeat_type = $8, 
             repeat_days = $9, 
             is_enabled = $10, 
             next_execution = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $11
         RETURNING *`,
        [finalName, finalTargetMode, finalStartHour, finalStartMinute, finalEndHour, finalEndMinute, finalSecondaryMode, finalRepeatType, finalRepeatDays, finalIsEnabled, scheduleId]
      );
    }

    await client.query('COMMIT');

    console.log('✅ Schedule updated\n');

    res.json({
      success: true,
      schedule: schedule.rows[0]
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error updating schedule:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});


// Видалення розкладу
app.delete('/api/devices/:deviceId/schedules/:scheduleId', authenticateToken, async (req, res) => {
  try {
    const { deviceId, scheduleId } = req.params;
    
    console.log(`\n🗑️ Deleting schedule ${scheduleId} for ${deviceId}`);
    
    const result = await pool.query(
      `DELETE FROM energy_schedules 
       WHERE id = $1 AND device_id = $2 AND user_id = $3
       RETURNING id`,
      [scheduleId, deviceId, req.user.id]
    );
    
    if (result.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied or schedule not found' });
    }
    
    console.log(`✅ Schedule deleted\n`);
    
    res.json({ success: true });
    
  } catch (error) {
    console.error('❌ Error deleting schedule:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============ ЕНЕРГЕТИЧНІ API ENDPOINTS ============

// Отримання енергетичних даних з БД
app.get('/api/devices/:deviceId/energy', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { period = '24h', limit = 1000 } = req.query;
    
    console.log(`📊 Energy data request: ${deviceId}, period: ${period}, limit: ${limit}`);
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    let timeCondition = '';
    
    switch (period) {
      case '1h':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '1 hour'`;
        break;
      case '6h':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '6 hours'`;
        break;
      case '24h':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '24 hours'`;
        break;
      case '7d':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '7 days'`;
        break;
      case '30d':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '30 days'`;
        break;
      case 'all':
        timeCondition = '';
        break;
      default:
        timeCondition = `AND timestamp >= NOW() - INTERVAL '24 hours'`;
    }
    
    const query = `
      SELECT id, device_id, power_kw, energy_kwh, timestamp, created_at
      FROM energy_data 
      WHERE device_id = $1 ${timeCondition}
      ORDER BY timestamp ASC
      LIMIT $2
    `;
    
    const result = await pool.query(query, [deviceId, parseInt(limit)]);
    
    const energyData = result.rows.map(row => ({
      id: row.id,
      deviceId: row.device_id,
      powerKw: parseFloat(row.power_kw),
      energyKwh: parseFloat(row.energy_kwh),
      timestamp: row.timestamp,
      createdAt: row.created_at
    }));
    
    console.log(`✅ Returned ${energyData.length} energy data points for ${deviceId}`);
    
    res.json({
      deviceId,
      period,
      count: energyData.length,
      data: energyData
    });
    
  } catch (error) {
    console.error('Error fetching energy data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Додавання енергетичних даних (backup метод)
app.post('/api/devices/:deviceId/energy', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { powerKw, energyKwh, timestamp } = req.body;
    
    console.log(`💾 Manual energy data save: ${deviceId} - ${powerKw} kW, ${energyKwh} kWh`);
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    const energyId = await saveEnergyData(deviceId, powerKw, energyKwh, timestamp);
    
    res.json({ 
      success: true, 
      id: energyId,
      message: 'Energy data saved successfully' 
    });
    
  } catch (error) {
    console.error('Error saving energy data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Очищення енергетичних даних
app.delete('/api/devices/:deviceId/energy', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    
    console.log(`🗑️ Clearing energy data for ${deviceId}`);
    
    const ownerCheck = await pool.query(
      `SELECT ud.is_owner FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (ownerCheck.rows.length === 0 || !ownerCheck.rows[0].is_owner) {
      return res.status(403).json({ error: 'Only device owner can clear energy data' });
    }
    
    const result = await pool.query(
      'DELETE FROM energy_data WHERE device_id = $1',
      [deviceId]
    );
    
    console.log(`✅ Cleared ${result.rowCount} energy data records for ${deviceId}`);
    
    res.json({ 
      success: true, 
      deletedCount: result.rowCount,
      message: 'Energy data cleared successfully' 
    });
    
  } catch (error) {
    console.error('Error clearing energy data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Статистика енергетичних даних
app.get('/api/devices/:deviceId/energy/stats', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { period = '24h' } = req.query;
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    let timeCondition = '';
    switch (period) {
      case '1h':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '1 hour'`;
        break;
      case '6h':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '6 hours'`;
        break;
      case '24h':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '24 hours'`;
        break;
      case '7d':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '7 days'`;
        break;
      case '30d':
        timeCondition = `AND timestamp >= NOW() - INTERVAL '30 days'`;
        break;
      default:
        timeCondition = `AND timestamp >= NOW() - INTERVAL '24 hours'`;
    }
    
    const statsQuery = `
      SELECT 
        COUNT(*) as total_records,
        MIN(power_kw) as min_power,
        MAX(power_kw) as max_power,
        AVG(power_kw) as avg_power,
        MIN(energy_kwh) as start_energy,
        MAX(energy_kwh) as end_energy,
        MAX(energy_kwh) - MIN(energy_kwh) as energy_generated,
        MIN(timestamp) as period_start,
        MAX(timestamp) as period_end
      FROM energy_data 
      WHERE device_id = $1 ${timeCondition}
    `;
    
    const result = await pool.query(statsQuery, [deviceId]);
    const stats = result.rows[0];
    
    res.json({
      deviceId,
      period,
      stats: {
        totalRecords: parseInt(stats.total_records),
        power: {
          min: parseFloat(stats.min_power) || 0,
          max: parseFloat(stats.max_power) || 0,
          avg: parseFloat(stats.avg_power) || 0
        },
        energy: {
          start: parseFloat(stats.start_energy) || 0,
          end: parseFloat(stats.end_energy) || 0,
          generated: parseFloat(stats.energy_generated) || 0
        },
        period: {
          start: stats.period_start,
          end: stats.period_end
        }
      }
    });
    
  } catch (error) {
    console.error('Error fetching energy stats:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Add device
app.post('/api/devices', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const { deviceId, confirmationCode, name } = req.body;
    
    console.log(`\n🔍 Adding device request:`);
    console.log(`   Device ID: ${deviceId}`);
    console.log(`   Provided code: ${confirmationCode}`);
    
    const storedCode = deviceConfirmationCodes.get(deviceId);
    console.log(`   Stored code: ${storedCode || 'NOT FOUND'}`);
    
    const deviceStatus = deviceStatuses.get(deviceId);
    const statusCode = deviceStatus?.confirmationCode;
    
    console.log(`   Status code: ${statusCode || 'NOT IN STATUS'}`);
    
    const isValidCode = 
      confirmationCode === storedCode || 
      confirmationCode === statusCode ||
      confirmationCode === '123456' ||
      confirmationCode === '147091';
    
    if (!isValidCode) {
      console.log(`❌ Invalid confirmation code for ${deviceId}`);
      console.log(`   Expected: ${storedCode || statusCode || '123456'}`);
      console.log(`   Received: ${confirmationCode}`);
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid confirmation code or device not found' });
    }
    
    console.log(`✅ Confirmation code valid`);
    
    let deviceResult = await client.query(
      'SELECT id FROM devices WHERE device_id = $1',
      [deviceId]
    );
    
    let deviceDbId;
    let isNewDevice = false;
    
    if (deviceResult.rows.length === 0) {
      deviceResult = await client.query(
        'INSERT INTO devices (device_id, name) VALUES ($1, $2) RETURNING id',
        [deviceId, name || `Solar Controller ${deviceId.slice(-4)}`]
      );
      deviceDbId = deviceResult.rows[0].id;
      isNewDevice = true;
      console.log(`✅ Created new device with ID: ${deviceDbId}`);
    } else {
      deviceDbId = deviceResult.rows[0].id;
      console.log(`📌 Device already exists with ID: ${deviceDbId}`);
      
      if (name) {
        await client.query(
          'UPDATE devices SET name = $1 WHERE id = $2',
          [name, deviceDbId]
        );
      }
    }
    
    const accessCheck = await client.query(
      'SELECT * FROM user_devices WHERE user_id = $1 AND device_id = $2',
      [req.user.id, deviceDbId]
    );
    
    if (accessCheck.rows.length > 0) {
      console.log(`⚠️ User already has access to device ${deviceId}`);
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'You already have access to this device' });
    }
    
    await client.query(
      'INSERT INTO user_devices (user_id, device_id, is_owner) VALUES ($1, $2, $3)',
      [req.user.id, deviceDbId, isNewDevice]
    );
    
    console.log(`✅ Added user access to device`);
    
    await client.query('COMMIT');
    
    console.log(`\n📤 Sending deviceAdded command to ESP32...`);
    
    const commandTopic = `solar/${deviceId}/command`;
    const commandPayload = JSON.stringify({
      command: 'deviceAdded',
      state: true,
      timestamp: Date.now()
    });
    
    mqttClient.publish(commandTopic, commandPayload, { qos: 1 }, (error) => {
      if (error) {
        console.error(`❌ Failed to send deviceAdded command:`, error);
      } else {
        console.log(`✅ deviceAdded command sent to ${deviceId}`);
      }
    });
    
    const fullDevice = await client.query(
      `SELECT d.*, ud.is_owner, ud.added_at
       FROM devices d
       JOIN user_devices ud ON d.id = ud.device_id
       WHERE d.id = $1 AND ud.user_id = $2`,
      [deviceDbId, req.user.id]
    );
    
    const device = {
      ...fullDevice.rows[0],
      status: deviceStatuses.get(deviceId) || { online: false }
    };
    
    console.log(`✅ Device ${deviceId} successfully added for user ${req.user.email}\n`);
    
    res.json(device);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error adding device:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// Control device
app.post('/api/devices/:deviceId/control', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { command, state } = req.body;
    
    console.log(`\n🎮 Control command for ${deviceId}: ${command} = ${state}`);
    
    const accessCheck = await pool.query(
      `SELECT 1 FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (accessCheck.rows.length === 0) {
      console.log(`❌ Access denied for user ${req.user.email} to device ${deviceId}`);
      return res.status(403).json({ error: 'Access denied' });
    }
    
    const topic = `solar/${deviceId}/command`;
    const payload = JSON.stringify({ 
      command, 
      state,
      timestamp: Date.now()
    });
    
    mqttClient.publish(topic, payload, { qos: 1 }, (error) => {
      if (error) {
        console.error(`❌ MQTT publish error:`, error);
        res.status(500).json({ error: 'Failed to send command' });
      } else {
        console.log(`✅ Command sent to ${deviceId} via MQTT`);
        
        const currentStatus = deviceStatuses.get(deviceId) || {};
        deviceStatuses.set(deviceId, {
          ...currentStatus,
          relayState: state,
          lastUpdated: new Date()
        });
        
        res.json({ success: true });
      }
    });
  } catch (error) {
    console.error('❌ Error controlling device:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete device
app.delete('/api/devices/:deviceId', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const { deviceId } = req.params;
    
    console.log(`\n🗑️ Deleting device ${deviceId} for user ${req.user.email}`);
    
    const deviceResult = await pool.query(
      'SELECT id FROM devices WHERE device_id = $1',
      [deviceId]
    );
    
    if (deviceResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Device not found' });
    }
    
    const deviceDbId = deviceResult.rows[0].id;
    
    await client.query(
      'DELETE FROM user_devices WHERE user_id = $1 AND device_id = $2',
      [req.user.id, deviceDbId]
    );
    const remainingUsers = await pool.query(
      'SELECT COUNT(*) FROM user_devices WHERE device_id = $1',
      [deviceDbId]
    );
    
    if (parseInt(remainingUsers.rows[0].count) === 0) {
      await client.query(
        'DELETE FROM energy_data WHERE device_id = $1',
        [deviceId]
      );
      
      await client.query(
        'DELETE FROM devices WHERE id = $1',
        [deviceDbId]
      );
      console.log(`✅ Device and energy data completely removed (no other users)`);
    } else {
      console.log(`✅ User access removed (${remainingUsers.rows[0].count} other users remain)`);
    }
    
    await client.query('COMMIT');
    res.json({ success: true });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error deleting device:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// Share device
app.post('/api/devices/:deviceId/share', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const { deviceId } = req.params;
    const { email } = req.body;
    
    console.log(`\n🤝 Sharing device ${deviceId} with ${email}`);
    
    const ownerResult = await client.query(
      `SELECT ud.is_owner 
       FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       WHERE ud.user_id = $1 AND d.device_id = $2`,
      [req.user.id, deviceId]
    );
    
    if (ownerResult.rows.length === 0 || !ownerResult.rows[0].is_owner) {
      await client.query('ROLLBACK');
      console.log(`❌ User ${req.user.email} is not owner of ${deviceId}`);
      return res.status(403).json({ error: 'Only owner can share device' });
    }
    
    const targetUser = await client.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );
    
    if (targetUser.rows.length === 0) {
      await client.query('ROLLBACK');
      console.log(`❌ User ${email} not found`);
      return res.status(404).json({ error: 'User not found. They need to register first.' });
    }
    
    const targetUserId = targetUser.rows[0].id;
    
    const deviceResult = await client.query(
      'SELECT id FROM devices WHERE device_id = $1',
      [deviceId]
    );
    
    const deviceDbId = deviceResult.rows[0].id;
    
    const existingAccess = await client.query(
      'SELECT * FROM user_devices WHERE user_id = $1 AND device_id = $2',
      [targetUserId, deviceDbId]
    );
    
    if (existingAccess.rows.length > 0) {
      await client.query('ROLLBACK');
      console.log(`⚠️ User ${email} already has access to ${deviceId}`);
      return res.status(400).json({ error: 'User already has access to this device' });
    }
    
    await client.query(
      'INSERT INTO user_devices (user_id, device_id, is_owner) VALUES ($1, $2, false)',
      [targetUserId, deviceDbId]
    );
    
    console.log(`✅ Device ${deviceId} shared with ${email}`);
    
    await client.query('COMMIT');
    res.json({ success: true });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error sharing device:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// Get all registered users (for sharing)
app.get('/api/users', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, email, name FROM users WHERE id != $1 ORDER BY name',
      [req.user.id]
    );
    
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Debug endpoint
app.get('/api/debug/codes', authenticateToken, async (req, res) => {
  const codes = [];
  deviceConfirmationCodes.forEach((code, deviceId) => {
    codes.push({ deviceId, code });
  });
  
  const statuses = [];
  deviceStatuses.forEach((status, deviceId) => {
    statuses.push({
      deviceId,
      online: status.online,
      relayState: status.relayState,
      confirmationCode: status.confirmationCode,
      powerKw: status.powerKw,
      energyKwh: status.energyKwh,
      lastSeen: status.lastSeen
    });
  });
  
  try {
    const dbStats = await pool.query(`
      SELECT 
        device_id,
        COUNT(*) as records_count,
        MIN(timestamp) as first_record,
        MAX(timestamp) as last_record,
        MAX(energy_kwh) as total_energy
      FROM energy_data 
      GROUP BY device_id 
      ORDER BY device_id
    `);
    
    const scheduleStats = await pool.query(`
      SELECT 
        COUNT(*) as total_schedules,
        COUNT(*) FILTER (WHERE is_enabled = true) as enabled_schedules,
        COUNT(*) FILTER (WHERE schedule_type = 'time') as time_schedules,
        COUNT(*) FILTER (WHERE schedule_type = 'range') as range_schedules,
        COUNT(DISTINCT device_id) as devices_with_schedules
      FROM energy_schedules
    `);
    
    res.json({
      confirmationCodes: codes,
      deviceStatuses: statuses,
      mqttConnected: mqttClient.connected,
      databaseStats: dbStats.rows,
      scheduleStats: scheduleStats.rows[0],
      features: {
        dailyCleanup: {
          enabled: true,
          time: '00:00',
          timezone: 'Europe/Kiev',
          nextRun: 'Every day at midnight'
        },
        energySchedules: {
          enabled: true,
          checkInterval: 'Every minute',
          timezone: 'Europe/Kiev',
          types: ['time', 'range']
        }
      }
    });
  } catch (error) {
    res.json({
      confirmationCodes: codes,
      deviceStatuses: statuses,
      mqttConnected: mqttClient.connected,
      databaseStats: { error: error.message },
      scheduleStats: { error: error.message },
      features: {
        dailyCleanup: { enabled: true, time: '00:00', timezone: 'Europe/Kiev' },
        energySchedules: { enabled: true, checkInterval: 'Every minute', types: ['time', 'range'] }
      }
    });
  }
});

// Helper functions
async function saveDeviceStatus(deviceId, status) {
  try {
    await pool.query(
      `INSERT INTO device_history (device_id, relay_state, wifi_rssi, uptime, free_heap)
       VALUES ($1, $2, $3, $4, $5)`,
      [deviceId, status.relayState, status.wifiRSSI, status.uptime, status.freeHeap]
    );
  } catch (error) {
    console.error('Error saving device status:', error);
  }
}
 
async function initDatabase() {
  try {
    console.log('🔍 Checking database connection...');
    
    const result = await pool.query('SELECT NOW()');
    console.log('✅ Database connected at:', result.rows[0].now);
    
    const tables = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public'
    `);
    if (tables.rows.length === 0) {
      console.log('⚠️  No tables found. Please run: node reset-database.js');
    } else {
      console.log('📊 Found tables:', tables.rows.map(t => t.table_name).join(', '));
      
      if (!tables.rows.some(t => t.table_name === 'energy_data')) {
        console.log('⚠️  Energy data table not found. Please run: node reset-database.js');
      } else {
        const energyStats = await pool.query(`
          SELECT COUNT(*) as total_records, COUNT(DISTINCT device_id) as devices_count
          FROM energy_data
        `);
        console.log(`💾 Energy data: ${energyStats.rows[0].total_records} records for ${energyStats.rows[0].devices_count} devices`);
      }
      
      if (tables.rows.some(t => t.table_name === 'energy_schedules')) {
        const scheduleStats = await pool.query(`
          SELECT 
            COUNT(*) as total_schedules,
            COUNT(*) FILTER (WHERE is_enabled = true) as enabled_schedules,
            COUNT(*) FILTER (WHERE schedule_type = 'time') as time_schedules,
            COUNT(*) FILTER (WHERE schedule_type = 'range') as range_schedules
          FROM energy_schedules
        `);
        console.log(`📅 Schedules: ${scheduleStats.rows[0].total_schedules} total (${scheduleStats.rows[0].enabled_schedules} enabled)`);
        console.log(`   Time: ${scheduleStats.rows[0].time_schedules}, Range: ${scheduleStats.rows[0].range_schedules}`);
      } else {
        console.log('⚠️  Energy schedules table not found. Please run: node reset-database.js');
      }
    }
  } catch (error) {
    console.error('❌ Database connection error:', error.message);
    console.log('💡 Make sure PostgreSQL is running and database exists');
    console.log('   Run: node reset-database.js to create tables');
    process.exit(1);
  }
}

// Періодична перевірка статусу пристроїв
setInterval(() => {
  const now = new Date();
  let offlineCount = 0;
  
  deviceStatuses.forEach((status, deviceId) => {
    const timeSinceLastSeen = now - status.lastSeen;
    if (timeSinceLastSeen > 30000 && status.online) {
      status.online = false;
      offlineCount++;
    }
  });
  
  if (offlineCount > 0) {
    console.log(`🔴 Marked ${offlineCount} device(s) as offline (no updates for 30s)`);
  }
}, 30000);

// Очищення старих кодів підтвердження (кожні 10 хвилин)
setInterval(() => {
  const now = new Date();
  let clearedCount = 0;
  
  deviceStatuses.forEach((status, deviceId) => {
    const timeSinceLastSeen = now - status.lastSeen;
    if (timeSinceLastSeen > 600000) {
      if (deviceConfirmationCodes.has(deviceId)) {
        deviceConfirmationCodes.delete(deviceId);
        clearedCount++;
      }
    }
  });
  
  if (clearedCount > 0) {
    console.log(`🧹 Cleared ${clearedCount} old confirmation code(s)`);
  }
}, 600000);

// ============ HELPER FUNCTION ДЛЯ РОЗРАХУНКУ НАСТУПНОГО ВИКОНАННЯ ============

function calculateNextExecution(hour, minute, repeatType, repeatDays, fromTime = null) {
  const now = fromTime ? new Date(fromTime) : new Date();
  
  // Створюємо час на сьогодні
  const nextTime = new Date(now);
  nextTime.setHours(hour, minute, 0, 0);
  
  // Якщо час вже минув сьогодні - беремо завтра
  if (nextTime <= now) {
    nextTime.setDate(nextTime.getDate() + 1);
  }
  
  switch (repeatType) {
    case 'once':
      return nextTime;
      
    case 'daily':
      return nextTime;
      
    case 'weekdays':
      // Пн-Пт (1-5)
      while (nextTime.getDay() === 0 || nextTime.getDay() === 6) {
        nextTime.setDate(nextTime.getDate() + 1);
      }
      return nextTime;
      
    case 'weekends':
      // Сб-Нд (0, 6)
      while (nextTime.getDay() !== 0 && nextTime.getDay() !== 6) {
        nextTime.setDate(nextTime.getDate() + 1);
      }
      return nextTime;
      
    case 'weekly':
      if (!repeatDays || repeatDays.length === 0) {
        return nextTime;
      }
      
      // Знаходимо найближчий день з repeatDays
      const currentDay = nextTime.getDay();
      let minDaysAhead = 7;
      
      for (const targetDay of repeatDays) {
        let daysAhead = (targetDay - currentDay + 7) % 7;
        
        // Якщо це сьогодні і час не минув - беремо сьогодні
        if (daysAhead === 0 && nextTime > now) {
          return nextTime;
        }
        
        // Якщо це сьогодні але час минув - беремо наступний тиждень
        if (daysAhead === 0) {
          daysAhead = 7;
        }
        
        if (daysAhead < minDaysAhead) {
          minDaysAhead = daysAhead;
        }
      }
      
      nextTime.setDate(nextTime.getDate() + minDaysAhead);
      return nextTime;
      
    default:
      return nextTime;
  }
}
  
// Start server with WebSocket proxy
const server = app.listen(PORT, async () => {
  console.log('\n🚀 Solar Controller Backend Server with Energy Mode Management');
  console.log('================================================================');
  console.log(`📡 Server running on port ${PORT}`);
  console.log(`🌐 API URL: http://localhost:${PORT}`);
  console.log(`📊 Database: ${process.env.DB_NAME || 'iot_devices'}`);
  console.log(`🔌 MQTT Broker: ${process.env.MQTT_HOST || 'localhost'}:${process.env.MQTT_PORT || 1883}`);
  console.log(`⏰ Daily cleanup: 00:00 Kiev time`);
  console.log(`⏰ Schedule checker: Every minute`);
  console.log(`📅 Schedule types: TIME + RANGE`);
  console.log('================================================================');
  console.log('\n📝 Energy Mode API endpoints:');
  console.log(`   GET /api/devices/:deviceId/energy-mode - Get current mode`);
  console.log(`   POST /api/devices/:deviceId/energy-mode - Set mode (manual)`);
  console.log(`   GET /api/devices/:deviceId/energy-mode/history - Get history`);
  console.log(`   GET /api/devices/:deviceId/schedules - Get schedules`);
  console.log(`   POST /api/devices/:deviceId/schedules - Create schedule (time/range)`);
  console.log(`   PUT /api/devices/:deviceId/schedules/:id - Update schedule`);
  console.log(`   DELETE /api/devices/:deviceId/schedules/:id - Delete schedule`);
  console.log('================================================================');
  console.log('\n🔄 System Flow:');
  console.log('   Manual: App → API → DB → MQTT → ESP32');
  console.log('   Time Schedule: Cron → next_execution check → MQTT → ESP32');
  console.log('   Range Schedule: Cron → start/end time check → MQTT → ESP32');
  console.log('   Offline: Schedule runs on server, syncs when app opens');
  console.log('================================================================\n');
  
  await initDatabase();
});

// WebSocket proxy для MQTT
const proxy = httpProxy.createProxyServer({
  target: 'ws://localhost:9001',
  ws: true,
  changeOrigin: true
});

server.on('upgrade', (request, socket, head) => {
  console.log('🔌 WebSocket upgrade request:', request.url);
  
  if (request.url === '/mqtt' || request.url === '/mqtt/' || request.url === '/ws' || request.url === '/ws/') {
    proxy.ws(request, socket, head, (error) => {
      if (error) {
        console.error('❌ WebSocket proxy error:', error);
        socket.destroy();
      }
    });
  } else {
    socket.destroy();
  }
});

proxy.on('error', (err, req, res) => {
  console.error('❌ Proxy error:', err);
  if (res && !res.headersSent) {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end('Proxy error');
  }
});

proxy.on('open', (proxySocket) => {
  console.log('✅ WebSocket connection opened');
});

proxy.on('close', (res, socket, head) => {
  console.log('🔌 WebSocket connection closed');
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('\n⚠️  SIGTERM signal received, shutting down gracefully...');
  
  server.close(() => {
    console.log('🛑 HTTP server closed');
    
    mqttClient.end(() => {
      console.log('🛑 MQTT client disconnected');
      
      pool.end(() => {
        console.log('🛑 Database pool closed');
        process.exit(0);
      });
    });
  });
  
  setTimeout(() => {
    console.error('❌ Forced shutdown after 10 seconds');
    process.exit(1);
  }, 10000);
});

process.on('SIGINT', () => {
  console.log('\n⚠️  SIGINT signal received, shutting down...');
  
  mqttClient.end();
  pool.end();
  process.exit(0);
});
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
});

console.log('✅ Server with Energy Mode Management + Range Schedules initialization complete');