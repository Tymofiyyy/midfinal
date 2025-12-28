// backend/migrate-energy-modes.js - ФІНАЛЬНА ВЕРСІЯ
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER || 'DB_USER',
  host: process.env.DB_HOST || 'DB_HOST',
  database: process.env.DB_NAME || 'DB_NAME',
  password: process.env.DB_PASSWORD || 'your-secret-key-change-this',
  port: process.env.DB_PORT || 1234,
});

async function migrateEnergyModes() {
  const client = await pool.connect();
  
  try {
    console.log('🚀 Starting energy modes migration...');
    console.log('=====================================\n');
    
    await client.query('BEGIN');
    
    // ПОВНІСТЮ ОЧИЩУЄМО ВСЕ ПОВ'ЯЗАНЕ З ENERGY MODES
    console.log('🗑️ Dropping all energy-related objects...');
    
    // Видаляємо тригери
    await client.query('DROP TRIGGER IF EXISTS trigger_update_next_execution ON energy_schedules CASCADE');
    
    // Видаляємо функції
    await client.query('DROP FUNCTION IF EXISTS update_next_execution() CASCADE');
    await client.query('DROP FUNCTION IF EXISTS calculate_next_execution(INTEGER, INTEGER, VARCHAR, INTEGER[], TIMESTAMP) CASCADE');
    
    // Видаляємо індекси (якщо залишились)
    await client.query('DROP INDEX IF EXISTS idx_energy_modes_device_id CASCADE');
    await client.query('DROP INDEX IF EXISTS idx_schedules_device_id CASCADE');
    await client.query('DROP INDEX IF EXISTS idx_schedules_user_id CASCADE');
    await client.query('DROP INDEX IF EXISTS idx_schedules_enabled CASCADE');
    await client.query('DROP INDEX IF EXISTS idx_schedules_next_execution CASCADE');
    await client.query('DROP INDEX IF EXISTS idx_history_device_id CASCADE');
    await client.query('DROP INDEX IF EXISTS idx_history_timestamp CASCADE');
    
    // Видаляємо таблиці
    await client.query('DROP TABLE IF EXISTS energy_mode_history CASCADE');
    await client.query('DROP TABLE IF EXISTS energy_schedules CASCADE');
    await client.query('DROP TABLE IF EXISTS device_energy_modes CASCADE');
    
    console.log('✅ All old objects dropped');
    
    // 1. Таблиця для збереження поточного режиму енергії
    console.log('\n📊 Creating device_energy_modes table...');
    
    await client.query(`
      CREATE TABLE device_energy_modes (
        id SERIAL PRIMARY KEY,
        device_id VARCHAR(255) UNIQUE NOT NULL,
        current_mode VARCHAR(50) NOT NULL DEFAULT 'solar',
        last_changed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        changed_by VARCHAR(50) DEFAULT 'manual',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        
        CONSTRAINT valid_energy_mode CHECK (current_mode IN ('solar', 'grid'))
      )
    `);
    
    console.log('✅ device_energy_modes table created');
    
    // 2. Таблиця для розкладів
    console.log('📊 Creating energy_schedules table...');
    
    await client.query(`
      CREATE TABLE energy_schedules (
        id SERIAL PRIMARY KEY,
        device_id VARCHAR(255) NOT NULL,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        name VARCHAR(255) NOT NULL,
        target_mode VARCHAR(50) NOT NULL,
        
        hour INTEGER NOT NULL CHECK (hour >= 0 AND hour <= 23),
        minute INTEGER NOT NULL CHECK (minute >= 0 AND minute <= 59),
        
        repeat_type VARCHAR(50) NOT NULL DEFAULT 'once',
        repeat_days INTEGER[],
        
        is_enabled BOOLEAN DEFAULT true,
        last_executed TIMESTAMP,
        next_execution TIMESTAMP,
        
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        
        CONSTRAINT valid_target_mode CHECK (target_mode IN ('solar', 'grid')),
        CONSTRAINT valid_repeat_type CHECK (repeat_type IN ('once', 'daily', 'weekly', 'weekdays', 'weekends'))
      )
    `);
    
    console.log('✅ energy_schedules table created');
    
    // 3. Таблиця для історії
    console.log('📊 Creating energy_mode_history table...');
    
    await client.query(`
      CREATE TABLE energy_mode_history (
        id SERIAL PRIMARY KEY,
        device_id VARCHAR(255) NOT NULL,
        from_mode VARCHAR(50),
        to_mode VARCHAR(50) NOT NULL,
        changed_by VARCHAR(50) NOT NULL,
        schedule_id INTEGER REFERENCES energy_schedules(id) ON DELETE SET NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        
        CONSTRAINT valid_from_mode CHECK (from_mode IN ('solar', 'grid') OR from_mode IS NULL),
        CONSTRAINT valid_to_mode CHECK (to_mode IN ('solar', 'grid'))
      )
    `);
    
    console.log('✅ energy_mode_history table created');
    
    // 4. Створюємо індекси
    console.log('\n📇 Creating indexes...');
    
    await client.query('CREATE INDEX idx_energy_modes_device_id ON device_energy_modes(device_id)');
    await client.query('CREATE INDEX idx_schedules_device_id ON energy_schedules(device_id)');
    await client.query('CREATE INDEX idx_schedules_user_id ON energy_schedules(user_id)');
    await client.query('CREATE INDEX idx_schedules_enabled ON energy_schedules(is_enabled) WHERE is_enabled = true');
    await client.query('CREATE INDEX idx_schedules_next_execution ON energy_schedules(next_execution) WHERE next_execution IS NOT NULL');
    await client.query('CREATE INDEX idx_history_device_id ON energy_mode_history(device_id)');
    await client.query('CREATE INDEX idx_history_timestamp ON energy_mode_history(timestamp DESC)');
    
    console.log('✅ Indexes created');
    
    // 5. Функція для розрахунку наступного виконання
    console.log('\n🔧 Creating calculate_next_execution function...');
    
    await client.query(`
      CREATE OR REPLACE FUNCTION calculate_next_execution(
        p_hour INTEGER,
        p_minute INTEGER,
        p_repeat_type VARCHAR,
        p_repeat_days INTEGER[],
        p_from_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) RETURNS TIMESTAMP AS $$
      DECLARE
        v_next_time TIMESTAMP;
        v_current_dow INTEGER;
        v_target_dow INTEGER;
        v_days_ahead INTEGER;
      BEGIN
        v_next_time := DATE_TRUNC('day', p_from_time) + 
                       MAKE_INTERVAL(hours => p_hour, mins => p_minute);
        
        IF v_next_time <= p_from_time THEN
          v_next_time := v_next_time + INTERVAL '1 day';
        END IF;
        
        IF p_repeat_type = 'once' THEN
          RETURN v_next_time;
        END IF;
        
        IF p_repeat_type = 'daily' THEN
          RETURN v_next_time;
        END IF;
        
        IF p_repeat_type = 'weekdays' THEN
          WHILE EXTRACT(DOW FROM v_next_time) IN (0, 6) LOOP
            v_next_time := v_next_time + INTERVAL '1 day';
          END LOOP;
          RETURN v_next_time;
        END IF;
        
        IF p_repeat_type = 'weekends' THEN
          WHILE EXTRACT(DOW FROM v_next_time) NOT IN (0, 6) LOOP
            v_next_time := v_next_time + INTERVAL '1 day';
          END LOOP;
          RETURN v_next_time;
        END IF;
        
        IF p_repeat_type = 'weekly' AND p_repeat_days IS NOT NULL AND array_length(p_repeat_days, 1) > 0 THEN
          v_current_dow := EXTRACT(DOW FROM v_next_time)::INTEGER;
          
          FOR v_target_dow IN SELECT UNNEST(p_repeat_days) ORDER BY 1 LOOP
            v_days_ahead := (v_target_dow - v_current_dow + 7) % 7;
            
            IF v_days_ahead = 0 AND v_next_time > p_from_time THEN
              RETURN v_next_time;
            ELSIF v_days_ahead > 0 THEN
              RETURN v_next_time + (v_days_ahead || ' days')::INTERVAL;
            END IF;
          END LOOP;
          
          v_target_dow := p_repeat_days[1];
          v_days_ahead := (v_target_dow - v_current_dow + 7) % 7;
          IF v_days_ahead = 0 THEN
            v_days_ahead := 7;
          END IF;
          RETURN v_next_time + (v_days_ahead || ' days')::INTERVAL;
        END IF;
        
        RETURN v_next_time;
      END;
      $$ LANGUAGE plpgsql;
    `);
    
    console.log('✅ calculate_next_execution function created');
    
    // 6. Тригер
    console.log('🔧 Creating trigger...');
    
    await client.query(`
      CREATE OR REPLACE FUNCTION update_next_execution()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.is_enabled = true THEN
          NEW.next_execution := calculate_next_execution(
            NEW.hour,
            NEW.minute,
            NEW.repeat_type,
            NEW.repeat_days,
            COALESCE(NEW.last_executed, CURRENT_TIMESTAMP)
          );
        ELSE
          NEW.next_execution := NULL;
        END IF;
        
        NEW.updated_at := CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    `);
    
    await client.query(`
      CREATE TRIGGER trigger_update_next_execution
      BEFORE INSERT OR UPDATE ON energy_schedules
      FOR EACH ROW
      EXECUTE FUNCTION update_next_execution();
    `);
    
    console.log('✅ Trigger created');
    
    await client.query('COMMIT');
    
    // Статистика
    console.log('\n✅ Energy modes migration completed successfully!');
    console.log('\n📊 Created tables:');
    console.log('  ✓ device_energy_modes');
    console.log('  ✓ energy_schedules');
    console.log('  ✓ energy_mode_history');
    console.log('\n📝 You can now:');
    console.log('  1. Use Flutter app to toggle energy modes');
    console.log('  2. Create automatic schedules');
    console.log('  3. View history of mode changes');
    console.log('  4. Schedules execute automatically via cron\n');
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('\n❌ Migration failed:', error.message);
    console.error('\n🔍 Full error:', error);
    process.exit(1);
  } finally {
    client.release();
    pool.end();
  }
}

console.log('🔄 Solar Controller - Energy Modes Migration');
console.log('============================================\n');

migrateEnergyModes().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);

});
