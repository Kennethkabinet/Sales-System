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

function envBool(name, fallback = false) {
  const raw = envTrim(name, fallback ? 'true' : 'false').toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(raw)) return false;
  return fallback;
}

const useSsl = envBool('DB_SSL', false);
const rejectUnauthorized = envBool('DB_SSL_REJECT_UNAUTHORIZED', false);

const pool = new Pool({
  host: envTrim('DB_HOST', 'localhost'),
  port: envInt('DB_PORT', 5432),
  user: envTrim('DB_USER', 'postgres'),
  password: envTrim('DB_PASSWORD', ''),
  database: envTrim('DB_NAME', 'sales_system'),
  ...(useSsl ? { ssl: { rejectUnauthorized } } : {}),
});

module.exports = pool;
