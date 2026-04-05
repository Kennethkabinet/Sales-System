const { Pool } = require('pg');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

function envTrim(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value === null) return fallback;
  const trimmed = String(value).trim();
  return trimmed === '' ? fallback : trimmed;
}

function envInt(name, fallback) {
  const raw = envTrim(name, String(fallback));
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

const pool = new Pool({
  host: envTrim('DB_HOST', 'localhost'),
  port: envInt('DB_PORT', 5432),
  user: envTrim('DB_USER', 'postgres'),
  password: envTrim('DB_PASSWORD', ''),
  database: envTrim('DB_NAME', 'sales_system'),
});

module.exports = pool;
