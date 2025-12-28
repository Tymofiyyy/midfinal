// fix-all-functions.js - Повне очищення та пересторення функцій
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER || 'iot_user',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'iot_devices',
  password: process.env.DB_PASSWORD || 'Tomwoker159357',
  port: process.env.DB_PORT || 5432,
});

async function fixFunctions() {
  const client = await pool.connect();
  
  try {
    console.log('🔧 Fixing all schedule functions...\n');
    
    // 1. Знаходимо всі версії функції
    console.log('🔍 Finding all versions of calculate_next_execution...');
    
    const functions = await client.query(`
      SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' 
        AND p.proname = 'calculate_next_execution'
    `);
    
    console.log(`   Found ${functions.rows.length} version(s)`);
    functions.rows.forEach(f => {
      console.log(`   - calculate_next_execution(${f.args})`);
    });
    
    // 2. Видаляємо тригер спочатку
    console.log('\n🗑️  Dropping trigger...');
    await client.query('DROP TRIGGER IF EXISTS trigger_update_next_execution ON energy_schedules CASCADE');
    
    // 3. Видаляємо функцію тригера
    console.log('🗑️  Dropping trigger function...');
    await client.query('DROP FUNCTION IF EXISTS update_next_execution() CASCADE');
    
    // 4. Видаляємо ВСІ версії calculate_next_execution
    console.log('🗑️  Dropping all calculate_next_execution versions...');
    
    for (const func of functions.rows) {
      try {
        await client.query(`DROP FUNCTION IF EXISTS calculate_next_execution(${func.args}) CASCADE`);
        console.log(`   ✓ Dropped: calculate_next_execution(${func.args})`);
      } catch (e) {
        console.log(`   ⚠ Could not drop: ${e.message}`);
      }
    }
    
    // Також спробуємо видалити без аргументів (на всяк випадок)
    try {
      await client.query('DROP FUNCTION IF EXISTS calculate_next_execution CASCADE');
    } catch (e) {
      // Ігноруємо
    }
    
    // 5. Перевіряємо що всі видалені
    const remaining = await client.query(`
      SELECT COUNT(*) as cnt FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'public' AND p.proname = 'calculate_next_execution'
    `);
    
    if (parseInt(remaining.rows[0].cnt) > 0) {
      console.log('\n⚠️  Some functions still exist, trying CASCADE drop...');
      await client.query(`
        DO $$ 
        DECLARE 
          r RECORD;
        BEGIN
          FOR r IN SELECT oid::regprocedure AS func_sig
                   FROM pg_proc 
                   WHERE proname = 'calculate_next_execution'
          LOOP
            EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
          END LOOP;
        END $$;
      `);
    }
    
    console.log('✅ All old functions removed');
    
    // 6. Створюємо ОДНУ нову функцію
    console.log('\n📝 Creating new calculate_next_execution function...');
    
    await client.query(`
      CREATE FUNCTION calculate_next_execution(
        p_hour INTEGER,
        p_minute INTEGER,
        p_repeat_type VARCHAR,
        p_repeat_days INTEGER[] DEFAULT NULL,
        p_from_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      ) RETURNS TIMESTAMP WITH TIME ZONE AS $$
      DECLARE
        v_next_time TIMESTAMP WITH TIME ZONE;
        v_current_dow INTEGER;
        v_target_dow INTEGER;
        v_days_ahead INTEGER;
      BEGIN
        -- Базовий час сьогодні
        v_next_time := DATE_TRUNC('day', p_from_time) + 
                       MAKE_INTERVAL(hours => p_hour, mins => p_minute);
        
        -- Якщо час вже минув сьогодні, беремо завтра
        IF v_next_time <= p_from_time THEN
          v_next_time := v_next_time + INTERVAL '1 day';
        END IF;
        
        -- Для once - просто повертаємо наступний час
        IF p_repeat_type = 'once' THEN
          RETURN v_next_time;
        END IF;
        
        -- Для daily - вже правильно
        IF p_repeat_type = 'daily' THEN
          RETURN v_next_time;
        END IF;
        
        -- Для weekdays (Пн-Пт)
        IF p_repeat_type = 'weekdays' THEN
          WHILE EXTRACT(DOW FROM v_next_time)::INTEGER IN (0, 6) LOOP
            v_next_time := v_next_time + INTERVAL '1 day';
          END LOOP;
          RETURN v_next_time;
        END IF;
        
        -- Для weekends (Сб-Нд)
        IF p_repeat_type = 'weekends' THEN
          WHILE EXTRACT(DOW FROM v_next_time)::INTEGER NOT IN (0, 6) LOOP
            v_next_time := v_next_time + INTERVAL '1 day';
          END LOOP;
          RETURN v_next_time;
        END IF;
        
        -- Для weekly з конкретними днями
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
    
    console.log('✅ calculate_next_execution created');
    
    // 7. Створюємо функцію тригера
    console.log('📝 Creating trigger function...');
    
    await client.query(`
      CREATE FUNCTION update_next_execution()
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
    
    console.log('✅ update_next_execution trigger function created');
    
    // 8. Створюємо тригер
    console.log('📝 Creating trigger...');
    
    await client.query(`
      CREATE TRIGGER trigger_update_next_execution
      BEFORE INSERT OR UPDATE ON energy_schedules
      FOR EACH ROW
      EXECUTE FUNCTION update_next_execution();
    `);
    
    console.log('✅ Trigger created');
    
    // 9. Тестуємо
    console.log('\n🧪 Testing function...');
    
    const test1 = await client.query(`
      SELECT calculate_next_execution(14, 30, 'daily', NULL) as next_time
    `);
    console.log('   Daily 14:30 →', test1.rows[0].next_time);
    
    const test2 = await client.query(`
      SELECT calculate_next_execution(9, 0, 'weekdays', NULL) as next_time
    `);
    console.log('   Weekdays 9:00 →', test2.rows[0].next_time);
    
    const test3 = await client.query(`
      SELECT calculate_next_execution(21, 56, 'daily', NULL, CURRENT_TIMESTAMP) as next_time
    `);
    console.log('   Daily 21:56 with explicit timestamp →', test3.rows[0].next_time);
    
    console.log('\n✅ All functions fixed successfully!');
    console.log('\n📝 Now restart your server: npm start');
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  } finally {
    client.release();
    pool.end();
  }
}

console.log('🔧 Complete function fix script');
console.log('================================\n');
fixFunctions();