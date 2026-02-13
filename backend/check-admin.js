const pool = require('./db');
const bcrypt = require('bcrypt');

async function checkAdmin() {
  try {
    // Check if admin exists
    const result = await pool.query("SELECT id, username, password_hash FROM users WHERE username = 'admin'");
    
    if (result.rows.length === 0) {
      console.log('Admin user NOT found in database!');
      
      // Create admin user
      const hash = await bcrypt.hash('admin123', 10);
      console.log('Generated hash:', hash);
      
      await pool.query(`
        INSERT INTO users (username, email, password_hash, full_name, role_id, department_id, is_active)
        VALUES ('admin', 'admin@company.com', $1, 'System Administrator', 1, 1, TRUE)
      `, [hash]);
      
      console.log('Admin user created successfully!');
    } else {
      console.log('Admin user found:', result.rows[0]);
      
      // Verify password
      const validPassword = await bcrypt.compare('admin123', result.rows[0].password_hash);
      console.log('Password "admin123" valid:', validPassword);
      
      if (!validPassword) {
        // Update password
        const newHash = await bcrypt.hash('admin123', 10);
        await pool.query("UPDATE users SET password_hash = $1 WHERE username = 'admin'", [newHash]);
        console.log('Password hash updated!');
      }
    }
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    pool.end();
  }
}

checkAdmin();
