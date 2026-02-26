import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

/// Socket service for real-time collaboration (V2)
class SocketService {
  static SocketService? _instance;
  io.Socket? _socket;

  // ── Legacy file-room callbacks ──
  Function(Map<String, dynamic>)? onUserJoined;
  Function(Map<String, dynamic>)? onUserLeft;
  Function(Map<String, dynamic>)? onRowLocked;
  Function(Map<String, dynamic>)? onRowUnlocked;
  Function(Map<String, dynamic>)? onRowUpdated;
  Function(Map<String, dynamic>)? onActiveUsers;
  Function(Map<String, dynamic>)? onCursorMoved;
  Function(Map<String, dynamic>)? onError;
  Function()? onConnect;
  Function()? onDisconnect;

  // ── V2 sheet-presence callbacks ──
  /// Called whenever the full presence list changes: { sheet_id, users: [...] }
  Function(Map<String, dynamic>)? onPresenceUpdate;

  /// Another user focused a cell: { user_id, username, role, dept, cell_ref, sheet_id }
  Function(Map<String, dynamic>)? onCellFocused;

  /// Another user blurred a cell: { user_id, cell_ref, sheet_id }
  Function(Map<String, dynamic>)? onCellBlurred;

  /// Another user saved a cell edit: { user_id, username, sheet_id, row_index, column_name, value }
  Function(Map<String, dynamic>)? onCellUpdated;

  /// A user performed a full HTTP save of the sheet:
  /// { sheet_id, saved_by, saved_by_id, columns, timestamp }
  /// Viewers should use this to reload the full sheet data from DB.
  Function(Map<String, dynamic>)? onSheetSaved;

  // ── V2 edit-request callbacks ──
  /// Admin receives a new edit request notification from an editor
  Function(Map<String, dynamic>)? onEditRequestNotification;

  /// Secondary persistent listener set by DashboardScreen so the badge
  /// updates even when the Sheets tab is not the active page.
  Function(Map<String, dynamic>)? onAdminEditNotification;

  /// Requester/everyone gets the resolution (approved/rejected)
  Function(Map<String, dynamic>)? onEditRequestResolved;

  /// Requester gets temporary cell access: { request_id, sheet_id, row_number, column_name, cell_ref, expires_at }
  Function(Map<String, dynamic>)? onGrantTempAccess;

  /// Confirmation that this user's request was submitted
  Function(Map<String, dynamic>)? onEditRequestSubmitted;

  SocketService._();

  static SocketService get instance {
    _instance ??= SocketService._();
    return _instance!;
  }

  bool get isConnected => _socket?.connected ?? false;

  /// Connect to WebSocket server with auth token
  void connect(String authToken) {
    _socket = io.io(
      AppConfig.wsBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': 'Bearer $authToken'})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(AppConfig.wsReconnectDelay.inMilliseconds)
          .build(),
    );

    _setupListeners();
  }

  /// socket_io_client v2 sometimes delivers payloads as List([Map]) instead
  /// of Map directly. This unwraps either format into a plain
  /// Map<String, dynamic>.
  static Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty && data[0] is Map) {
      return Map<String, dynamic>.from(data[0] as Map);
    }
    return {};
  }

  void _setupListeners() {
    _socket?.onConnect((_) {
      print('Socket connected');
      onConnect?.call();
    });

    _socket?.onDisconnect((_) {
      print('Socket disconnected');
      onDisconnect?.call();
    });

    _socket?.onConnectError((error) {
      print('Socket connection error: $error');
      onError?.call({'code': 'CONNECT_ERROR', 'message': error.toString()});
    });

    // ── Legacy events ──
    _socket?.on('user_joined', (d) => onUserJoined?.call(_unwrap(d)));
    _socket?.on('user_left', (d) => onUserLeft?.call(_unwrap(d)));
    _socket?.on('row_locked', (d) => onRowLocked?.call(_unwrap(d)));
    _socket?.on('row_unlocked', (d) => onRowUnlocked?.call(_unwrap(d)));
    _socket?.on('row_updated', (d) => onRowUpdated?.call(_unwrap(d)));
    _socket?.on('active_users', (d) => onActiveUsers?.call(_unwrap(d)));
    _socket?.on('cursor_moved', (d) => onCursorMoved?.call(_unwrap(d)));
    _socket?.on('row_locks', (_) {/* handled elsewhere */});
    _socket?.on('error', (d) => onError?.call(_unwrap(d)));

    // ── V2 presence events ──
    _socket?.on('presence_update', (d) {
      final m = _unwrap(d);
      print('[Socket] presence_update received: ${m["users"]}');
      onPresenceUpdate?.call(m);
    });
    _socket?.on('cell_focused', (d) => onCellFocused?.call(_unwrap(d)));
    _socket?.on('cell_blurred', (d) => onCellBlurred?.call(_unwrap(d)));
    // Real-time cell edits from other users
    _socket?.on('cell_updated', (d) => onCellUpdated?.call(_unwrap(d)));
    // Full-sheet HTTP save notification
    _socket?.on('sheet_saved', (d) => onSheetSaved?.call(_unwrap(d)));

    // ── V2 edit-request events ──
    _socket?.on('edit_request_notification', (data) {
      final m = _unwrap(data);
      onEditRequestNotification?.call(m);
      onAdminEditNotification?.call(m);
    });
    _socket?.on('edit_request_resolved',
        (data) => onEditRequestResolved?.call(_unwrap(data)));
    _socket?.on(
        'grant_temp_access', (data) => onGrantTempAccess?.call(_unwrap(data)));
    _socket?.on('edit_request_submitted',
        (data) => onEditRequestSubmitted?.call(_unwrap(data)));
  }

  // ── Legacy emitters ──

  void joinFile(int fileId) => _socket?.emit('join_file', {'file_id': fileId});

  void leaveFile(int fileId) =>
      _socket?.emit('leave_file', {'file_id': fileId});

  void lockRow(int fileId, int rowId) =>
      _socket?.emit('lock_row', {'file_id': fileId, 'row_id': rowId});

  void unlockRow(int fileId, int rowId) =>
      _socket?.emit('unlock_row', {'file_id': fileId, 'row_id': rowId});

  void updateRow(int fileId, int rowId, Map<String, dynamic> values) =>
      _socket?.emit(
          'update_row', {'file_id': fileId, 'row_id': rowId, 'values': values});

  void updateCursorPosition(int fileId, int rowId, String column) =>
      _socket?.emit('cursor_position',
          {'file_id': fileId, 'row_id': rowId, 'column': column});

  // ── V2 sheet-presence emitters ──

  /// Call when the user opens a sheet.
  void joinSheet(int sheetId) =>
      _socket?.emit('join_sheet', {'sheet_id': sheetId});

  /// Explicitly request the current presence list for a sheet.
  /// Use as a fallback a moment after joinSheet.
  void getPresence(int sheetId) =>
      _socket?.emit('get_presence', {'sheet_id': sheetId});

  /// Call when the user closes/leaves a sheet.
  void leaveSheet(int sheetId) =>
      _socket?.emit('leave_sheet', {'sheet_id': sheetId});

  /// Call when the user taps/focuses a cell.
  void cellFocus(int sheetId, String cellRef) =>
      _socket?.emit('cell_focus', {'sheet_id': sheetId, 'cell_ref': cellRef});

  /// Call when the user leaves a cell.
  void cellBlur(int sheetId, String cellRef) =>
      _socket?.emit('cell_blur', {'sheet_id': sheetId, 'cell_ref': cellRef});

  /// Call when the user saves a cell edit — instantly broadcasts to others.
  void cellUpdate(int sheetId, int rowIndex, String columnName, String value) =>
      _socket?.emit('cell_update', {
        'sheet_id': sheetId,
        'row_index': rowIndex,
        'column_name': columnName,
        'value': value,
      });

  // ── V2 edit-request emitters ──

  /// Editor requests permission to edit a locked cell.
  void requestEdit({
    required int sheetId,
    required int rowNumber,
    required String columnName,
    String? cellRef,
    String? currentValue,
    String? proposedValue,
  }) {
    _socket?.emit('request_edit', {
      'sheet_id': sheetId,
      'row_number': rowNumber,
      'column_name': columnName,
      'cell_ref': cellRef,
      'current_value': currentValue,
      'proposed_value': proposedValue,
    });
  }

  /// Admin approves or rejects an edit request.
  void resolveEditRequest({
    required int requestId,
    required bool approved,
    String? rejectReason,
  }) {
    _socket?.emit('resolve_edit_request', {
      'request_id': requestId,
      'approved': approved,
      'reject_reason': rejectReason,
    });
  }

  /// Disconnect from server
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  /// Clear all callbacks
  void clearCallbacks() {
    onUserJoined = null;
    onUserLeft = null;
    onRowLocked = null;
    onRowUnlocked = null;
    onRowUpdated = null;
    onActiveUsers = null;
    onCursorMoved = null;
    onError = null;
    onConnect = null;
    onDisconnect = null;
    onPresenceUpdate = null;
    onCellFocused = null;
    onCellBlurred = null;
    onCellUpdated = null;
    onSheetSaved = null;
    onEditRequestNotification = null;
    onAdminEditNotification = null;
    onEditRequestResolved = null;
    onGrantTempAccess = null;
    onEditRequestSubmitted = null;
  }
}
