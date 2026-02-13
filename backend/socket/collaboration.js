const pool = require('../db');
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../middleware/auth');

/**
 * WebSocket Collaboration Handler
 * Manages real-time collaboration features:
 * - File editing sessions
 * - Row locking
 * - Live updates
 * - User presence
 */
class CollaborationHandler {
  constructor(io) {
    this.io = io;
    this.activeUsers = new Map(); // socketId -> user info
    this.fileRooms = new Map();   // fileId -> Set of socketIds
    this.userLocks = new Map();   // `${fileId}-${rowId}` -> userId
    
    this.setupMiddleware();
    this.setupEventHandlers();
    this.startLockCleanup();
  }

  /**
   * Setup authentication middleware for socket connections
   */
  setupMiddleware() {
    this.io.use(async (socket, next) => {
      try {
        const token = socket.handshake.auth.token?.replace('Bearer ', '');
        
        if (!token) {
          return next(new Error('Authentication required'));
        }
        
        const decoded = jwt.verify(token, JWT_SECRET);
        
        // Get user info
        const result = await pool.query(`
          SELECT u.id, u.username, u.department_id, r.name as role
          FROM users u
          LEFT JOIN roles r ON u.role_id = r.id
          WHERE u.id = $1 AND u.is_active = TRUE
        `, [decoded.userId]);
        
        if (result.rows.length === 0) {
          return next(new Error('User not found'));
        }
        
        socket.user = result.rows[0];
        next();
      } catch (error) {
        next(new Error('Invalid token'));
      }
    });
  }

  /**
   * Setup socket event handlers
   */
  setupEventHandlers() {
    this.io.on('connection', (socket) => {
      console.log(`User connected: ${socket.user.username} (${socket.id})`);
      
      // Store user info
      this.activeUsers.set(socket.id, {
        userId: socket.user.id,
        username: socket.user.username,
        currentFile: null,
        currentRow: null
      });

      // Handle joining a file editing session
      socket.on('join_file', async (data) => {
        await this.handleJoinFile(socket, data);
      });

      // Handle leaving a file editing session
      socket.on('leave_file', async (data) => {
        await this.handleLeaveFile(socket, data);
      });

      // Handle row lock request
      socket.on('lock_row', async (data) => {
        await this.handleLockRow(socket, data);
      });

      // Handle row unlock
      socket.on('unlock_row', async (data) => {
        await this.handleUnlockRow(socket, data);
      });

      // Handle row update (broadcasts to others)
      socket.on('update_row', async (data) => {
        await this.handleUpdateRow(socket, data);
      });

      // Handle cursor position update
      socket.on('cursor_position', (data) => {
        this.handleCursorPosition(socket, data);
      });

      // Handle disconnection
      socket.on('disconnect', () => {
        this.handleDisconnect(socket);
      });
    });
  }

  /**
   * Handle user joining a file editing session
   */
  async handleJoinFile(socket, { file_id }) {
    try {
      const roomName = `file-${file_id}`;
      
      // Leave any previous file room
      const user = this.activeUsers.get(socket.id);
      if (user?.currentFile) {
        await this.handleLeaveFile(socket, { file_id: user.currentFile });
      }
      
      // Join new room
      socket.join(roomName);
      
      // Track in our map
      if (!this.fileRooms.has(file_id)) {
        this.fileRooms.set(file_id, new Set());
      }
      this.fileRooms.get(file_id).add(socket.id);
      
      // Update user's current file
      if (user) {
        user.currentFile = file_id;
      }
      
      // Notify others in the room
      socket.to(roomName).emit('user_joined', {
        user_id: socket.user.id,
        username: socket.user.username,
        file_id
      });
      
      // Send list of active users in this file
      const activeInFile = await this.getActiveUsersInFile(file_id);
      socket.emit('active_users', {
        file_id,
        users: activeInFile
      });
      
      // Send current row locks
      const locks = await this.getFileRowLocks(file_id);
      socket.emit('row_locks', { file_id, locks });
      
      console.log(`${socket.user.username} joined file ${file_id}`);
      
    } catch (error) {
      console.error('Join file error:', error);
      socket.emit('error', { code: 'JOIN_ERROR', message: 'Failed to join file' });
    }
  }

  /**
   * Handle user leaving a file editing session
   */
  async handleLeaveFile(socket, { file_id }) {
    try {
      const roomName = `file-${file_id}`;
      
      // Release any locks held by this user in this file
      await this.releaseUserLocks(socket.user.id, file_id);
      
      // Leave the room
      socket.leave(roomName);
      
      // Remove from tracking
      const fileUsers = this.fileRooms.get(file_id);
      if (fileUsers) {
        fileUsers.delete(socket.id);
        if (fileUsers.size === 0) {
          this.fileRooms.delete(file_id);
        }
      }
      
      // Update user's current file
      const user = this.activeUsers.get(socket.id);
      if (user) {
        user.currentFile = null;
        user.currentRow = null;
      }
      
      // Notify others
      socket.to(roomName).emit('user_left', {
        user_id: socket.user.id,
        username: socket.user.username,
        file_id
      });
      
      console.log(`${socket.user.username} left file ${file_id}`);
      
    } catch (error) {
      console.error('Leave file error:', error);
    }
  }

  /**
   * Handle row lock request (Edit permissions required)
   */
  async handleLockRow(socket, { file_id, row_id }) {
    try {
      // Check if user has edit permissions
      if (!['admin', 'editor', 'user'].includes(socket.user.role)) {
        socket.emit('error', {
          code: 'PERMISSION_DENIED',
          message: 'Viewer role cannot lock rows for editing'
        });
        return;
      }

      const lockKey = `${file_id}-${row_id}`;
      
      // Check if row is already locked by another user
      const existingLock = await pool.query(`
        SELECT rl.locked_by, u.username
        FROM row_locks rl
        LEFT JOIN users u ON rl.locked_by = u.id
        WHERE rl.file_id = $1 AND rl.row_id = $2 AND rl.expires_at > CURRENT_TIMESTAMP
      `, [file_id, row_id]);
      
      if (existingLock.rows.length > 0 && existingLock.rows[0].locked_by !== socket.user.id) {
        socket.emit('error', {
          code: 'ROW_LOCKED',
          message: `Row is being edited by ${existingLock.rows[0].username}`
        });
        return;
      }
      
      // Create or update lock
      await pool.query(`
        INSERT INTO row_locks (file_id, row_id, locked_by, expires_at)
        VALUES ($1, $2, $3, CURRENT_TIMESTAMP + INTERVAL '5 minutes')
        ON CONFLICT (file_id, row_id) DO UPDATE SET
          locked_by = $3,
          locked_at = CURRENT_TIMESTAMP,
          expires_at = CURRENT_TIMESTAMP + INTERVAL '5 minutes'
      `, [file_id, row_id, socket.user.id]);
      
      // Track lock
      this.userLocks.set(lockKey, socket.user.id);
      
      // Update user's current row
      const user = this.activeUsers.get(socket.id);
      if (user) {
        user.currentRow = row_id;
      }
      
      // Broadcast to room - ALL users can see who's editing
      this.io.to(`file-${file_id}`).emit('row_locked', {
        file_id,
        row_id,
        locked_by: socket.user.username,
        user_id: socket.user.id
      });
      
    } catch (error) {
      console.error('Lock row error:', error);
      socket.emit('error', { code: 'LOCK_ERROR', message: 'Failed to lock row' });
    }
  }

  /**
   * Handle row unlock (Edit permissions required)
   */
  async handleUnlockRow(socket, { file_id, row_id }) {
    try {
      // Check if user has edit permissions
      if (!['admin', 'editor', 'user'].includes(socket.user.role)) {
        socket.emit('error', {
          code: 'PERMISSION_DENIED',
          message: 'Viewer role cannot unlock rows'
        });
        return;
      }

      // Only the owner can unlock
      await pool.query(`
        DELETE FROM row_locks
        WHERE file_id = $1 AND row_id = $2 AND locked_by = $3
      `, [file_id, row_id, socket.user.id]);
      
      // Remove from tracking
      const lockKey = `${file_id}-${row_id}`;
      this.userLocks.delete(lockKey);
      
      // Update user's current row
      const user = this.activeUsers.get(socket.id);
      if (user) {
        user.currentRow = null;
      }
      
      // Broadcast to room - ALL users can see when editing stops
      this.io.to(`file-${file_id}`).emit('row_unlocked', {
        file_id,
        row_id
      });
      
    } catch (error) {
      console.error('Unlock row error:', error);
    }
  }

  /**
   * Handle row update broadcast (Edit permissions required for sender, all users receive)
   */
  async handleUpdateRow(socket, { file_id, row_id, values }) {
    try {
      // Check if user has edit permissions to make updates
      if (!['admin', 'editor', 'user'].includes(socket.user.role)) {
        socket.emit('error', {
          code: 'PERMISSION_DENIED',
          message: 'Viewer role cannot make changes to sheets'
        });
        return;
      }

      // Broadcast update to ALL other users in the file (including viewers)
      // This ensures viewers see real-time changes made by editors
      socket.to(`file-${file_id}`).emit('row_updated', {
        file_id,
        row_id,
        values,
        updated_by: socket.user.username,
        editor_role: socket.user.role
      });
      
    } catch (error) {
      console.error('Update row error:', error);
    }
  }

  /**
   * Handle cursor position update
   */
  handleCursorPosition(socket, { file_id, row_id, column }) {
    // Broadcast cursor position to others in the file
    socket.to(`file-${file_id}`).emit('cursor_moved', {
      user_id: socket.user.id,
      username: socket.user.username,
      row_id,
      column
    });
  }

  /**
   * Handle user disconnection
   */
  async handleDisconnect(socket) {
    console.log(`User disconnected: ${socket.user?.username} (${socket.id})`);
    
    const user = this.activeUsers.get(socket.id);
    
    if (user?.currentFile) {
      // Release locks and leave file
      await this.handleLeaveFile(socket, { file_id: user.currentFile });
    }
    
    // Remove from active users
    this.activeUsers.delete(socket.id);
  }

  /**
   * Release all locks held by a user in a file
   */
  async releaseUserLocks(userId, fileId) {
    await pool.query(`
      DELETE FROM row_locks
      WHERE locked_by = $1 ${fileId ? 'AND file_id = $2' : ''}
    `, fileId ? [userId, fileId] : [userId]);
    
    // Clean up our tracking
    for (const [key, lockedBy] of this.userLocks.entries()) {
      if (lockedBy === userId) {
        const [lockFileId] = key.split('-');
        if (!fileId || lockFileId === String(fileId)) {
          this.userLocks.delete(key);
        }
      }
    }
  }

  /**
   * Get active users in a file
   */
  async getActiveUsersInFile(fileId) {
    const socketIds = this.fileRooms.get(fileId) || new Set();
    const users = [];
    
    for (const socketId of socketIds) {
      const userInfo = this.activeUsers.get(socketId);
      if (userInfo) {
        users.push({
          user_id: userInfo.userId,
          username: userInfo.username,
          current_row: userInfo.currentRow
        });
      }
    }
    
    return users;
  }

  /**
   * Get current row locks for a file
   */
  async getFileRowLocks(fileId) {
    const result = await pool.query(`
      SELECT rl.row_id, u.username as locked_by, rl.locked_at
      FROM row_locks rl
      LEFT JOIN users u ON rl.locked_by = u.id
      WHERE rl.file_id = $1 AND rl.expires_at > CURRENT_TIMESTAMP
    `, [fileId]);
    
    return result.rows;
  }

  /**
   * Periodically clean up expired locks
   */
  startLockCleanup() {
    setInterval(async () => {
      try {
        await pool.query('SELECT cleanup_expired_locks()');
      } catch (error) {
        // Function might not exist, use direct delete
        await pool.query('DELETE FROM row_locks WHERE expires_at < CURRENT_TIMESTAMP');
      }
    }, 60000); // Every minute
  }
}

module.exports = CollaborationHandler;
