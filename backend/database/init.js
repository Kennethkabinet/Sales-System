const pool = require('../db');
const fs = require('fs');
const path = require('path');

async function initializeDatabase() {
  console.log('Initializing database...');
  
  try {
    // Read the schema file
    const schemaPath = path.join(__dirname, 'schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf8');
    
    // Execute the schema
    await pool.query(schema);
    
    console.log('Database schema created successfully!');
    
    // Create default admin user with proper bcrypt hash
    const bcrypt = require('bcrypt');
    const adminPassword = await bcrypt.hash('admin123', 10);
    
    await pool.query(`
      UPDATE users 
      SET password_hash = $1 
      WHERE username = 'admin'
    `, [adminPassword]);
    
    // Or insert if not exists
    await pool.query(`
      INSERT INTO users (username, email, password_hash, full_name, role_id, department_id, is_active)
      VALUES ('admin', 'admin@company.com', $1, 'System Administrator', 1, 1, TRUE)
      ON CONFLICT (username) DO UPDATE SET password_hash = $1
    `, [adminPassword]);
    
    console.log('Default admin user created (username: admin, password: admin123)');
    
  } catch (error) {
    console.error('Error initializing database:', error);
    throw error;
  } finally {
    await pool.end();
  }
}

// Run if called directly
if (require.main === module) {
  initializeDatabase()
    .then(() => {
      console.log('Database initialization complete!');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Database initialization failed:', err);
      process.exit(1);
    });
}

module.exports = initializeDatabase;
