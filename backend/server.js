const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const pool = require('./db');
const CollaborationHandler = require('./socket/collaboration');

// Create Express app
const app = express();
const server = http.createServer(app);

// Setup Socket.IO
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// Initialize collaboration handler
new CollaborationHandler(io);

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Create required directories
const uploadsDir = path.join(__dirname, 'uploads');
const exportsDir = path.join(__dirname, 'exports');
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
if (!fs.existsSync(exportsDir)) fs.mkdirSync(exportsDir, { recursive: true });

// Import routes
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const fileRoutes = require('./routes/files');
const formulaRoutes = require('./routes/formulas');
const auditRoutes = require('./routes/audit');
const dashboardRoutes = require('./routes/dashboard');
const sheetRoutes = require('./routes/sheets');
const inventoryRoutes = require('./routes/inventory');

const PORT = process.env.PORT || 3001;

// Health check routes
app.get('/', (req, res) => {
  res.send('Sales & Inventory Management System Backend v1.0');
});

app.get('/api/status', (req, res) => {
  res.json({
    status: 'Backend is running',
    port: PORT,
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

app.get('/api/db-test', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW()');
    res.json({
      status: 'Database connected',
      connected: true,
      host: process.env.DB_HOST,
      database: process.env.DB_NAME,
      timestamp: result.rows[0].now
    });
  } catch (error) {
    res.status(500).json({
      status: 'Database connection failed',
      connected: false,
      error: error.message
    });
  }
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/files', fileRoutes);
app.use('/api/formulas', formulaRoutes);
app.use('/api/audit', auditRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/sheets', sheetRoutes);
app.use('/api/inventory', inventoryRoutes);

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  
  if (err.name === 'MulterError') {
    return res.status(400).json({
      success: false,
      error: { code: 'FILE_ERROR', message: err.message }
    });
  }
  
  res.status(500).json({
    success: false,
    error: { code: 'SERVER_ERROR', message: 'Internal server error' }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: { code: 'NOT_FOUND', message: 'Endpoint not found' }
  });
});

// Start server
server.listen(PORT, () => {
  console.log(`\n========================================`);
  console.log(`  Sales & Inventory Management System`);
  console.log(`========================================`);
  console.log(`  Server running on port ${PORT}`);
  console.log(`  API: http://localhost:${PORT}/api`);
  console.log(`  WebSocket: ws://localhost:${PORT}`);
  console.log(`========================================\n`);
});

// Graceful shutdown
server.on('error', (err) => {
  console.error('Server error:', err);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    pool.end();
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully...');
  server.close(() => {
    pool.end();
    console.log('Server closed');
    process.exit(0);
  });
});

