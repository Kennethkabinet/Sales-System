const pool = require('../db');
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../middleware/auth');

/**
 * WebSocket Collaboration Handler V2
 * Manages real-time collaboration features:
 * - File editing sessions (backward-compat)
 * - Sheet-level presence with role/department info
 * - Cell-level presence indicators
 * - Row locking
 * - Live updates
 * - Admin approval workflow for locked-cell edits
 */
class CollaborationHandler {
  constructor(io) {
    this.io = io;
    this.activeUsers  = new Map(); // socketId -> user info
    this.fileRooms    = new Map(); // fileId  -> Set of socketIds
    this.userLocks    = new Map(); // `${fileId}-${rowId}` -> userId

    // Sheet-level presence (V2)
    this.sheetRooms   = new Map(); // sheetId -> Set of socketIds
    this.sheetPresence = new Map(); // sheetId -> Map<socketId, presenceRecord>

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
        
        // Get user info (including department name for presence)
        const result = await pool.query(`
          SELECT u.id, u.username, u.full_name, u.department_id, r.name as role,
                 d.name as department_name
          FROM users u
          LEFT JOIN roles r ON u.role_id = r.id
          LEFT JOIN departments d ON u.department_id = d.id
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
        role: socket.user.role,
        departmentName: socket.user.department_name || null,
        currentFile: null,
        currentRow: null,
        currentSheet: null,
        currentCell: null
      });

      // Auto-join admins to a persistent room so they receive
      // edit_request_notification regardless of which sheet they have open.
      if (socket.user.role === 'admin') {
        socket.join('admins');
      }

      // ── Legacy file-room events (keep for backward compat) ──
      socket.on('join_file',       async (d) => this.handleJoinFile(socket, d));
      socket.on('leave_file',      async (d) => this.handleLeaveFile(socket, d));
      socket.on('lock_row',        async (d) => this.handleLockRow(socket, d));
      socket.on('unlock_row',      async (d) => this.handleUnlockRow(socket, d));
      socket.on('update_row',      async (d) => this.handleUpdateRow(socket, d));
      socket.on('cursor_position',       (d) => this.handleCursorPosition(socket, d));

      // ── V2 sheet-presence events ──
      socket.on('join_sheet',      async (d) => this.handleJoinSheet(socket, d));
      socket.on('leave_sheet',     async (d) => this.handleLeaveSheet(socket, d));
      socket.on('cell_focus',            (d) => this.handleCellFocus(socket, d));
      socket.on('cell_blur',             (d) => this.handleCellBlur(socket, d));

      // ── V2 real-time cell sync ──
      socket.on('cell_update',     async (d) => this.handleCellUpdate(socket, d));

      // ── V2 get_presence: client explicitly requests current presence list ──
      socket.on('get_presence', (d) => {
        const sid = (d && d.sheet_id) ? d.sheet_id : null;
        if (!sid) return;
        socket.emit('presence_update', this._buildPresencePayload(sid));
      });

      // ── V2 edit-request events ──
      socket.on('request_edit',    async (d) => this.handleRequestEdit(socket, d));
      socket.on('resolve_edit_request', async (d) => this.handleResolveEditRequest(socket, d));

      // Handle disconnection
      socket.on('disconnect', () => this.handleDisconnect(socket));
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

  // ═══════════════════════════════════════════════════════
  //  V2: Sheet-level presence
  // ═══════════════════════════════════════════════════════

  /**
   * User joins a sheet view (V2 sheet-level tracking with role/dept).
   * Emits 'presence_update' to all members with updated user list.
   */
  async handleJoinSheet(socket, { sheet_id }) {
    try {
      const roomName = `sheet-${sheet_id}`;

      // Leave previous sheet if any
      const user = this.activeUsers.get(socket.id);
      if (user?.currentSheet && user.currentSheet !== sheet_id) {
        await this.handleLeaveSheet(socket, { sheet_id: user.currentSheet });
      }

      socket.join(roomName);

      if (!this.sheetRooms.has(sheet_id)) {
        this.sheetRooms.set(sheet_id, new Set());
      }
      this.sheetRooms.get(sheet_id).add(socket.id);

      if (!this.sheetPresence.has(sheet_id)) {
        this.sheetPresence.set(sheet_id, new Map());
      }

      const presenceMap = this.sheetPresence.get(sheet_id);

      // ── Evict any stale socket entries for the same userId ─────────────────
      // This handles reconnects / multiple tabs: the old socketId entry would
      // linger as a "ghost" until disconnect fires. Removing it first ensures
      // the presence list is always accurate without waiting for the stale
      // disconnect event.
      for (const [sid, p] of presenceMap.entries()) {
        if (p.userId === socket.user.id && sid !== socket.id) {
          presenceMap.delete(sid);
          // Also clean up the sheetRooms set
          const roomSet = this.sheetRooms.get(sheet_id);
          if (roomSet) roomSet.delete(sid);
        }
      }

      presenceMap.set(socket.id, {
        userId:         socket.user.id,
        username:       socket.user.username,
        fullName:       socket.user.full_name || socket.user.username,
        role:           socket.user.role,
        departmentName: socket.user.department_name || null,
        currentCell:    null,
        joinedAt:       Date.now()
      });

      if (user) {
        user.currentSheet = sheet_id;
        user.currentCell  = null;
      }

      // Broadcast updated presence list to ALL users in the sheet (including
      // already-present users so they see the newly joined user).
      this._broadcastSheetPresence(sheet_id);

      // Also emit directly to the joining socket so it gets the full list
      // immediately even before the room broadcast propagates.
      socket.emit('presence_update', this._buildPresencePayload(sheet_id));

      console.log(`${socket.user.username} joined sheet ${sheet_id} (${presenceMap.size} users now present)`);
    } catch (err) {
      console.error('Join sheet error:', err);
      socket.emit('error', { code: 'JOIN_SHEET_ERROR', message: 'Failed to join sheet' });
    }
  }

  /**
   * User leaves a sheet view.
   */
  async handleLeaveSheet(socket, { sheet_id }) {
    try {
      const roomName = `sheet-${sheet_id}`;
      socket.leave(roomName);

      const sheetMembers = this.sheetRooms.get(sheet_id);
      if (sheetMembers) {
        sheetMembers.delete(socket.id);
        if (sheetMembers.size === 0) this.sheetRooms.delete(sheet_id);
      }

      const presence = this.sheetPresence.get(sheet_id);
      if (presence) {
        presence.delete(socket.id);
        if (presence.size === 0) this.sheetPresence.delete(sheet_id);
      }

      const user = this.activeUsers.get(socket.id);
      if (user) {
        user.currentSheet = null;
        user.currentCell  = null;
      }

      this._broadcastSheetPresence(sheet_id);
    } catch (err) {
      console.error('Leave sheet error:', err);
    }
  }

  /**
   * User focuses on a specific cell.
   * Broadcasts cell_focused to all others in the sheet.
   */
  handleCellFocus(socket, { sheet_id, cell_ref }) {
    const presence = this.sheetPresence.get(sheet_id);
    if (!presence) return;

    const record = presence.get(socket.id);
    if (record) record.currentCell = cell_ref;

    const user = this.activeUsers.get(socket.id);
    if (user) user.currentCell = cell_ref;

    // Broadcast to others (not sender)
    socket.to(`sheet-${sheet_id}`).emit('cell_focused', {
      user_id:         socket.user.id,
      username:        socket.user.username,
      role:            socket.user.role,
      department_name: socket.user.department_name,
      cell_ref,
      sheet_id
    });
  }

  /**
   * User blurs away from a cell.
   */
  handleCellBlur(socket, { sheet_id, cell_ref }) {
    const presence = this.sheetPresence.get(sheet_id);
    if (!presence) return;

    const record = presence.get(socket.id);
    if (record) record.currentCell = null;

    const user = this.activeUsers.get(socket.id);
    if (user) user.currentCell = null;

    socket.to(`sheet-${sheet_id}`).emit('cell_blurred', {
      user_id:  socket.user.id,
      cell_ref,
      sheet_id
    });
  }

  /**
   * Broadcast a single cell change to all OTHER users in the same sheet room
   * AND persist the change to PostgreSQL immediately.
   *
   * Payload sent by client: { sheet_id, row_index, column_name, value }
   * Payload received by others: { user_id, username, sheet_id, row_index, column_name, value }
   *
   * row_index is 0-based (Flutter _data array index).
   * DB row_number is 1-based → rowNumber = row_index + 1.
   */
  async handleCellUpdate(socket, { sheet_id, row_index, column_name, value }) {
    if (!sheet_id || row_index === undefined || !column_name) return;

    const payload = {
      user_id:     socket.user.id,
      username:    socket.user.username,
      sheet_id,
      row_index,   // 0-based row index matching Flutter _data array
      column_name,
      value: value ?? ''
    };

    // ── Broadcast FIRST so other users see the change instantly ──────────────
    // DB write happens after; a slow query must not block the real-time update.
    socket.to(`sheet-${sheet_id}`).emit('cell_updated', payload);

    // ── Persist cell value to PostgreSQL (non-blocking) ──────────────────────
    const rowNumber = row_index + 1; // convert 0-based → 1-based for DB
    pool.query(`
      INSERT INTO sheet_data (sheet_id, row_number, data)
      VALUES ($1, $2, jsonb_build_object($3::text, $4::text))
      ON CONFLICT (sheet_id, row_number)
      DO UPDATE SET
        data       = sheet_data.data || jsonb_build_object($3::text, $4::text),
        updated_at = CURRENT_TIMESTAMP
    `, [sheet_id, rowNumber, column_name, value ?? ''])
    .then(() =>
      pool.query(
        'UPDATE sheets SET last_edited_by = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [socket.user.id, sheet_id]
      )
    )
    .catch(dbErr =>
      console.error('[handleCellUpdate] DB persist error:', dbErr.message)
    );
  }

  /**
   * Build a presence payload object for a sheet.
   */
  _buildPresencePayload(sheet_id) {
    const presence = this.sheetPresence.get(sheet_id);
    const users = presence
      ? (() => {
          // Deduplicate by userId (safety net — join handler already evicts
          // stale entries, but guard here too for resilience).
          const seen = new Set();
          const out  = [];
          for (const p of presence.values()) {
            if (!seen.has(p.userId)) {
              seen.add(p.userId);
              out.push({
                user_id:         p.userId,
                username:        p.username,
                full_name:       p.fullName || p.username,
                role:            p.role,
                department_name: p.departmentName,
                current_cell:    p.currentCell
              });
            }
          }
          return out;
        })()
      : [];
    return { sheet_id, users };
  }

  /**
   * Broadcast full presence snapshot to all users in a sheet.
   * Payload: { sheet_id, users: [...] }
   */
  _broadcastSheetPresence(sheet_id) {
    this.io.to(`sheet-${sheet_id}`).emit('presence_update', this._buildPresencePayload(sheet_id));
  }

  // ═══════════════════════════════════════════════════════
  //  V2: Admin approval workflow for locked-cell edits
  // ═══════════════════════════════════════════════════════

  /**
   * Editor submits a request to edit a historically-locked cell.
   * Creates a DB record and notifies all admins in the sheet room.
   */
  async handleRequestEdit(socket, { sheet_id, row_number, column_name, cell_ref, current_value, proposed_value }) {
    try {
      if (!['editor', 'user'].includes(socket.user.role)) {
        // Admin doesn't need to request
        socket.emit('error', { code: 'PERMISSION_DENIED', message: 'Only editors can request edit access' });
        return;
      }

      // Upsert: cancel if a pending request already exists for this cell+user
      await pool.query(`
        DELETE FROM edit_requests
        WHERE sheet_id = $1 AND row_number = $2 AND column_name = $3
          AND requested_by = $4 AND status = 'pending'
      `, [sheet_id, row_number, column_name, socket.user.id]);

      const result = await pool.query(`
        INSERT INTO edit_requests
          (sheet_id, row_number, column_name, cell_reference, current_value,
           proposed_value, requested_by, requester_role, requester_dept, status)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending')
        RETURNING *
      `, [
        sheet_id, row_number, column_name, cell_ref || null,
        current_value || null, proposed_value || null,
        socket.user.id, socket.user.role, socket.user.department_name || null
      ]);

      const request = result.rows[0];

      // Confirm to requester
      socket.emit('edit_request_submitted', {
        request_id:  request.id,
        sheet_id,
        cell_ref,
        message:     'Edit request submitted. Waiting for admin approval.'
      });

      // Notify anyone in the sheet room AND all online admins
      // (the admin may be on a different tab and not in the sheet room).
      this.io.to(`sheet-${sheet_id}`).to('admins').emit('edit_request_notification', {
        request_id:      request.id,
        sheet_id,
        row_number,
        column_name,
        cell_ref,
        current_value,
        proposed_value,
        requested_by:    socket.user.username,
        requester_role:  socket.user.role,
        requester_dept:  socket.user.department_name,
        requested_at:    request.requested_at
      });

      console.log(`Edit request ${request.id} by ${socket.user.username} for ${cell_ref} in sheet ${sheet_id}`);
    } catch (err) {
      console.error('Request edit error:', err);
      socket.emit('error', { code: 'REQUEST_EDIT_ERROR', message: 'Failed to submit edit request' });
    }
  }

  /**
   * Admin approves or rejects an edit request.
   * On approval emits 'grant_temp_access' to the requester.
   */
  async handleResolveEditRequest(socket, { request_id, approved, reject_reason }) {
    try {
      if (socket.user.role !== 'admin') {
        socket.emit('error', { code: 'PERMISSION_DENIED', message: 'Only admins can resolve edit requests' });
        return;
      }

      const status = approved ? 'approved' : 'rejected';
      const expiresAt = approved
        ? new Date(Date.now() + 10 * 60 * 1000) // 10-minute window
        : null;

      const result = await pool.query(`
        UPDATE edit_requests
        SET status       = $2,
            reviewed_by  = $3,
            reviewed_at  = CURRENT_TIMESTAMP,
            reject_reason = $4,
            expires_at   = $5
        WHERE id = $1 AND status = 'pending'
        RETURNING *
      `, [request_id, status, socket.user.id, reject_reason || null, expiresAt]);

      if (result.rows.length === 0) {
        socket.emit('error', { code: 'NOT_FOUND', message: 'Request not found or already resolved' });
        return;
      }

      const req = result.rows[0];

      // If approved and a proposed value was provided, apply it immediately.
      // This writes the value to the DB and broadcasts cell_updated so the
      // editor and all other viewers see the change right away — no manual
      // re-edit required after approval.
      if (approved && req.proposed_value !== null && req.proposed_value !== undefined) {
        try {
          await pool.query(`
            INSERT INTO sheet_data (sheet_id, row_number, data)
            VALUES ($1, $2, jsonb_build_object($3::text, $4::text))
            ON CONFLICT (sheet_id, row_number)
            DO UPDATE SET data = sheet_data.data ||
              jsonb_build_object($3::text, $4::text),
              updated_at = CURRENT_TIMESTAMP
          `, [req.sheet_id, req.row_number, req.column_name, req.proposed_value]);

          // Broadcast the applied value to everyone in the sheet (row_index is 0-based)
          this.io.to(`sheet-${req.sheet_id}`).emit('cell_updated', {
            sheet_id:    req.sheet_id,
            row_index:   req.row_number - 1,
            column_name: req.column_name,
            value:       req.proposed_value,
            updated_by:  'admin-approved',
          });
        } catch (applyErr) {
          console.error('Auto-apply proposed value error:', applyErr);
          // Non-fatal: grant still resolves; editor can edit manually
        }
      }

      // Broadcast resolution to everyone in the sheet
      this.io.to(`sheet-${req.sheet_id}`).emit('edit_request_resolved', {
        request_id,
        sheet_id:    req.sheet_id,
        row_number:  req.row_number,
        column_name: req.column_name,
        cell_ref:    req.cell_reference,
        approved,
        reject_reason,
        resolved_by: socket.user.username,
        expires_at:  expiresAt
      });

      // If approved, also send the specific grant to the requester's socket
      if (approved) {
        // Find the requester's socket(s) in the sheet room
        const sheetMembers = this.sheetPresence.get(req.sheet_id);
        if (sheetMembers) {
          for (const [sockId, presence] of sheetMembers.entries()) {
            if (presence.userId === req.requested_by) {
              this.io.to(sockId).emit('grant_temp_access', {
                request_id,
                sheet_id:    req.sheet_id,
                row_number:  req.row_number,
                column_name: req.column_name,
                cell_ref:    req.cell_reference,
                expires_at:  expiresAt
              });
            }
          }
        }
      }

      console.log(`Edit request ${request_id} ${status} by admin ${socket.user.username}`);
    } catch (err) {
      console.error('Resolve edit request error:', err);
      socket.emit('error', { code: 'RESOLVE_ERROR', message: 'Failed to resolve edit request' });
    }
  }

  /**
   * Called by HTTP PUT /sheets/:id/edit-requests/:reqId so the REST fallback
   * also delivers real-time events to connected clients.
   */
  async emitResolveEvents(reqRow, approved, rejectReason, resolvedByUsername) {
    const sheetId   = reqRow.sheet_id;
    const expiresAt = reqRow.expires_at;

    // If approved and a proposed value was provided, persist it and broadcast cell_updated
    if (approved && reqRow.proposed_value !== null && reqRow.proposed_value !== undefined) {
      try {
        await pool.query(`
          INSERT INTO sheet_data (sheet_id, row_number, data)
          VALUES ($1, $2, jsonb_build_object($3::text, $4::text))
          ON CONFLICT (sheet_id, row_number)
          DO UPDATE SET data = sheet_data.data ||
            jsonb_build_object($3::text, $4::text),
            updated_at = CURRENT_TIMESTAMP
        `, [sheetId, reqRow.row_number, reqRow.column_name, reqRow.proposed_value]);

        this.io.to(`sheet-${sheetId}`).emit('cell_updated', {
          sheet_id:    sheetId,
          row_index:   reqRow.row_number - 1,
          column_name: reqRow.column_name,
          value:       reqRow.proposed_value,
          updated_by:  'admin-approved',
        });
      } catch (applyErr) {
        console.error('emitResolveEvents auto-apply error:', applyErr);
      }
    }

    // Broadcast resolution to everyone in the sheet room
    this.io.to(`sheet-${sheetId}`).emit('edit_request_resolved', {
      request_id:  reqRow.id,
      sheet_id:    sheetId,
      row_number:  reqRow.row_number,
      column_name: reqRow.column_name,
      cell_ref:    reqRow.cell_reference,
      approved,
      reject_reason: rejectReason || null,
      resolved_by:   resolvedByUsername,
      expires_at:    expiresAt
    });

    // If approved, send grant_temp_access directly to the requester's socket(s)
    if (approved) {
      const sheetMembers = this.sheetPresence.get(sheetId);
      if (sheetMembers) {
        for (const [sockId, presence] of sheetMembers.entries()) {
          if (presence.userId === reqRow.requested_by) {
            this.io.to(sockId).emit('grant_temp_access', {
              request_id:  reqRow.id,
              sheet_id:    sheetId,
              row_number:  reqRow.row_number,
              column_name: reqRow.column_name,
              cell_ref:    reqRow.cell_reference,
              expires_at:  expiresAt
            });
          }
        }
      }
    }
  }

  /**
   * Handle user disconnection
   */
  async handleDisconnect(socket) {
    console.log(`User disconnected: ${socket.user?.username} (${socket.id})`);
    
    const user = this.activeUsers.get(socket.id);
    
    if (user?.currentFile) {
      await this.handleLeaveFile(socket, { file_id: user.currentFile });
    }

    // V2: clean up sheet presence
    if (user?.currentSheet) {
      await this.handleLeaveSheet(socket, { sheet_id: user.currentSheet });
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
          user_id:         userInfo.userId,
          username:        userInfo.username,
          role:            userInfo.role,
          department_name: userInfo.departmentName,
          current_row:     userInfo.currentRow
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
