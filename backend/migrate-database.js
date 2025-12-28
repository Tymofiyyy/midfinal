// migrate-database.js - Скрипт для міграції існуючої БД без втрати даних
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER || 'iot_user',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'iot_devices',
  password: process.env.DB_PASSWORD || 'Tomwoker159357',
  port: process.env.DB_PORT || 5432,
});

async function migrateDatabase() {
  const client = await pool.connect();
  
  try {
    console.log('🚀 Starting database migration...');
    console.log('==================================\n');
    
    await client.query('BEGIN');
    
    // Перевіряємо чи існують нові таблиці
    const energyDataExists = await client.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'energy_data'
      );
    `);
    
    const dailyEnergyExists = await client.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'daily_energy'
      );
    `);
    
    // Створюємо таблицю energy_data якщо не існує
    if (!energyDataExists.rows[0].exists) {
      console.log('📊 Creating energy_data table...');
      
      await client.query(`
        CREATE TABLE energy_data (
          id SERIAL PRIMARY KEY,
          device_id VARCHAR(255) NOT NULL,
          power_kw DECIMAL(10,3) NOT NULL,
          energy_kwh DECIMAL(10,3) NOT NULL,
          timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          created_at DATE NOT NULL DEFAULT CURRENT_DATE,
          
          CONSTRAINT energy_data_device_date_idx UNIQUE (device_id, timestamp)
        )
      `);
      
      // Створюємо індекси
      await client.query('CREATE INDEX idx_energy_data_device_id ON energy_data(device_id)');
      await client.query('CREATE INDEX idx_energy_data_timestamp ON energy_data(timestamp DESC)');
      await client.query('CREATE INDEX idx_energy_data_created_at ON energy_data(created_at)');
      
      console.log('✅ energy_data table created');
    } else {
      console.log('ℹ️  energy_data table already exists');
    }
    
    // Створюємо таблицю daily_energy якщо не існує
    if (!dailyEnergyExists.rows[0].exists) {
      console.log('📊 Creating daily_energy table...');
      
      await client.query(`
        CREATE TABLE daily_energy (
          id SERIAL PRIMARY KEY,
          device_id VARCHAR(255) NOT NULL,
          date DATE NOT NULL,
          total_energy_kwh DECIMAL(10,3) NOT NULL,
          max_power_kw DECIMAL(10,3),
          avg_power_kw DECIMAL(10,3),
          operating_hours DECIMAL(5,2),
          data_points INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          
          CONSTRAINT daily_energy_unique UNIQUE (device_id, date)
        )
      `);
      
      // Створюємо індекси
      await client.query('CREATE INDEX idx_daily_energy_device_id ON daily_energy(device_id)');
      await client.query('CREATE INDEX idx_daily_energy_date ON daily_energy(date DESC)');
      await client.query('CREATE INDEX idx_daily_energy_device_date ON daily_energy(device_id, date DESC)');
      
      console.log('✅ daily_energy table created');
    } else {
      console.log('ℹ️  daily_energy table already exists');
    }
    
    // Створюємо або оновлюємо функцію очищення
    console.log('🔧 Creating cleanup function...');
    
    await client.query(`
      CREATE OR REPLACE FUNCTION delete_old_energy_data()
      RETURNS void AS $$
      BEGIN
        DELETE FROM energy_data 
        WHERE created_at < CURRENT_DATE;
      END;
      $$ LANGUAGE plpgsql;
    `);
    
    console.log('✅ Cleanup function created');
    
    // Мігруємо існуючі дані з device_history якщо є
    const historyExists = await client.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'device_history'
      );
    `);
    
    if (historyExists.rows[0].exists) {
      console.log('\n📦 Checking for existing data to migrate...');
      
      const historyCount = await client.query('SELECT COUNT(*) FROM device_history');
      const count = parseInt(historyCount.rows[0].count);
      
      if (count > 0) {
        console.log(`Found ${count} records in device_history`);
        
        // Запитуємо чи мігрувати дані
        console.log('\nWould you like to migrate existing device_history data?');
        console.log('This will create sample energy data based on relay states.');
        console.log('Note: This is for testing only, as real energy data was not tracked before.\n');
        
        // Для автоматичної міграції встановіть це в true
        // Для продакшн рекомендується false
        const shouldMigrate = false; // Змініть на true якщо хочете мігрувати
        
        if (shouldMigrate) {
          console.log('⚙️  Migrating historical data...');
          
          // Створюємо тестові енергетичні дані на основі історії реле
          const devices = await client.query(`
            SELECT DISTINCT device_id FROM device_history
          `);
          
          for (const device of devices.rows) {
            const deviceId = device.device_id;
            console.log(`  Processing device: ${deviceId}`);
            
            // Отримуємо історію для пристрою
            const history = await client.query(`
              SELECT device_id, relay_state, timestamp 
              FROM device_history 
              WHERE device_id = $1 
              ORDER BY timestamp ASC
            `, [deviceId]);
            
            let totalEnergy = 0;
            let lastTimestamp = null;
            
            for (const record of history.rows) {
              if (record.relay_state && lastTimestamp) {
                // Розраховуємо енергію на основі часу роботи
                const hours = (record.timestamp - lastTimestamp) / (1000 * 60 * 60);
                const power = 2.0 + Math.random(); // Симулюємо 2-3 kW
                totalEnergy += power * hours;
                
                // Додаємо запис в energy_data якщо це сьогоднішній день
                const recordDate = new Date(record.timestamp);
                const today = new Date();
                
                if (recordDate.toDateString() === today.toDateString()) {
                  await client.query(`
                    INSERT INTO energy_data (device_id, power_kw, energy_kwh, timestamp, created_at)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (device_id, timestamp) DO NOTHING
                  `, [deviceId, power, totalEnergy, record.timestamp, recordDate]);
                }
                
                // Додаємо в daily_energy
                const dateStr = recordDate.toISOString().split('T')[0];
                await client.query(`
                  INSERT INTO daily_energy (device_id, date, total_energy_kwh, max_power_kw, avg_power_kw, operating_hours, data_points)
                  VALUES ($1, $2, $3, $4, $5, $6, $7)
                  ON CONFLICT (device_id, date) 
                  DO UPDATE SET 
                    total_energy_kwh = GREATEST(daily_energy.total_energy_kwh, $3),
                    max_power_kw = GREATEST(daily_energy.max_power_kw, $4),
                    data_points = daily_energy.data_points + 1,
                    updated_at = CURRENT_TIMESTAMP
                `, [deviceId, dateStr, totalEnergy, power, power, hours, 1]);
              }
              
              lastTimestamp = record.timestamp;
            }
          }
          
          console.log('✅ Historical data migrated');
        } else {
          console.log('⏭️  Skipping historical data migration');
        }
      } else {
        console.log('ℹ️  No historical data found to migrate');
      }
    }
    
    await client.query('COMMIT');
    
    // Виводимо статистику
    console.log('\n📈 Migration Statistics:');
    console.log('========================');
    
    const tables = await client.query(`
      SELECT 
        table_name,
        (SELECT COUNT(*) FROM information_schema.columns 
         WHERE table_schema = 'public' AND table_name = t.table_name) as columns_count
      FROM information_schema.tables t
      WHERE table_schema = 'public'
      ORDER BY table_name
    `);
    
    console.log('\nTables structure:');
    for (const table of tables.rows) {
      const countResult = await client.query(
        `SELECT COUNT(*) FROM ${table.table_name}`
      );
      console.log(`  📋 ${table.table_name}: ${table.columns_count} columns, ${countResult.rows[0].count} rows`);
    }
    
    // Перевіряємо індекси
    const indexes = await client.query(`
      SELECT tablename, indexname 
      FROM pg_indexes 
      WHERE schemaname = 'public' 
        AND tablename IN ('energy_data', 'daily_energy')
      ORDER BY tablename, indexname
    `);
    
    console.log('\nIndexes for energy tables:');
    let currentTable = '';
    for (const index of indexes.rows) {
      if (currentTable !== index.tablename) {
        currentTable = index.tablename;
        console.log(`  ${currentTable}:`);
      }
      console.log(`    - ${index.indexname}`);
    }
    
    console.log('\n✅ Database migration completed successfully!');
    console.log('\n📝 Next steps:');
    console.log('  1. Update server.js with the new version');
    console.log('  2. Install node-cron: npm install node-cron');
    console.log('  3. Restart the server: npm start');
    console.log('  4. Update Flutter app files');
    console.log('\n💡 The system will now:');
    console.log('  - Store energy data throughout the day');
    console.log('  - Automatically clean old data at midnight');
    console.log('  - Keep daily statistics permanently');
    console.log('  - Show hourly energy consumption');
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migration failed:', error.message);
    console.error('\n🔍 Error details:', error);
    console.error('\n💡 Suggestions:');
    console.error('  1. Check database connection settings');
    console.error('  2. Ensure you have proper permissions');
    console.error('  3. Try running reset-database.js if this is a fresh install');
    process.exit(1);
  } finally {
    client.release();
    pool.end();
  }
}

// Головна функція
console.log('🔄 Solar Controller - Database Migration Tool');
console.log('=============================================');
console.log('This tool will add energy tracking tables to your existing database');
console.log('Your existing data will NOT be deleted\n');

migrateDatabase().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});