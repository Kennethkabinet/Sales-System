import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

/// Socket service for real-time collaboration
class SocketService {
  static SocketService? _instance;
  io.Socket? _socket;

  // Callbacks
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

    _socket?.on('user_joined', (data) {
      onUserJoined?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('user_left', (data) {
      onUserLeft?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('row_locked', (data) {
      onRowLocked?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('row_unlocked', (data) {
      onRowUnlocked?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('row_updated', (data) {
      onRowUpdated?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('active_users', (data) {
      onActiveUsers?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('cursor_moved', (data) {
      onCursorMoved?.call(Map<String, dynamic>.from(data));
    });

    _socket?.on('row_locks', (data) {
      // Initial locks when joining a file
    });

    _socket?.on('error', (data) {
      onError?.call(Map<String, dynamic>.from(data));
    });
  }

  /// Join a file editing session
  void joinFile(int fileId) {
    _socket?.emit('join_file', {'file_id': fileId});
  }

  /// Leave a file editing session
  void leaveFile(int fileId) {
    _socket?.emit('leave_file', {'file_id': fileId});
  }

  /// Request lock on a row
  void lockRow(int fileId, int rowId) {
    _socket?.emit('lock_row', {'file_id': fileId, 'row_id': rowId});
  }

  /// Release lock on a row
  void unlockRow(int fileId, int rowId) {
    _socket?.emit('unlock_row', {'file_id': fileId, 'row_id': rowId});
  }

  /// Broadcast row update to other users
  void updateRow(int fileId, int rowId, Map<String, dynamic> values) {
    _socket?.emit('update_row', {
      'file_id': fileId,
      'row_id': rowId,
      'values': values,
    });
  }

  /// Update cursor position
  void updateCursorPosition(int fileId, int rowId, String column) {
    _socket?.emit('cursor_position', {
      'file_id': fileId,
      'row_id': rowId,
      'column': column,
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
  }
}

/// Active user in a file
class ActiveUser {
  final int userId;
  final String username;
  final int? currentRow;

  ActiveUser({
    required this.userId,
    required this.username,
    this.currentRow,
  });

  factory ActiveUser.fromJson(Map<String, dynamic> json) {
    return ActiveUser(
      userId: json['user_id'],
      username: json['username'] ?? '',
      currentRow: json['current_row'],
    );
  }
}
