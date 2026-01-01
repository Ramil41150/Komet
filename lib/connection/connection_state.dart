import 'dart:async';

enum ConnectionState {
  disconnected,

  connecting,

  connected,

  ready,

  reconnecting,

  error,

  disabled,
}

class ConnectionInfo {
  final ConnectionState state;
  final DateTime timestamp;
  final String? message;
  final Map<String, dynamic>? metadata;
  final int? attemptNumber;
  final Duration? reconnectDelay;
  final String? serverUrl;
  final int? latency;

  ConnectionInfo({
    required this.state,
    required this.timestamp,
    this.message,
    this.metadata,
    this.attemptNumber,
    this.reconnectDelay,
    this.serverUrl,
    this.latency,
  });

  ConnectionInfo copyWith({
    ConnectionState? state,
    DateTime? timestamp,
    String? message,
    Map<String, dynamic>? metadata,
    int? attemptNumber,
    Duration? reconnectDelay,
    String? serverUrl,
    int? latency,
  }) {
    return ConnectionInfo(
      state: state ?? this.state,
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
      metadata: metadata ?? this.metadata,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      serverUrl: serverUrl ?? this.serverUrl,
      latency: latency ?? this.latency,
    );
  }

  bool get isActive =>
      state == ConnectionState.ready || state == ConnectionState.connected;

  bool get canSendMessages => state == ConnectionState.ready;

  bool get isConnecting =>
      state == ConnectionState.connecting ||
      state == ConnectionState.reconnecting;

  bool get hasError => state == ConnectionState.error;

  bool get isDisconnected =>
      state == ConnectionState.disconnected ||
      state == ConnectionState.disabled;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('ConnectionInfo(state: $state');
    if (message != null) buffer.write(', message: $message');
    if (attemptNumber != null) buffer.write(', attempt: $attemptNumber');
    if (serverUrl != null) buffer.write(', server: $serverUrl');
    if (latency != null) buffer.write(', latency: ${latency}ms');
    buffer.write(')');
    return buffer.toString();
  }
}

class ConnectionStateManager {
  static final ConnectionStateManager _instance =
      ConnectionStateManager._internal();
  factory ConnectionStateManager() => _instance;
  ConnectionStateManager._internal();

  ConnectionInfo _currentInfo = ConnectionInfo(
    state: ConnectionState.disconnected,
    timestamp: DateTime.now(),
  );

  final StreamController<ConnectionInfo> _stateController =
      StreamController<ConnectionInfo>.broadcast();

  ConnectionInfo get currentInfo => _currentInfo;

  Stream<ConnectionInfo> get stateStream => _stateController.stream;

  final List<ConnectionInfo> _stateHistory = [];

  List<ConnectionInfo> get stateHistory => List.unmodifiable(_stateHistory);

  void setState(
    ConnectionState newState, {
    String? message,
    Map<String, dynamic>? metadata,
    int? attemptNumber,
    Duration? reconnectDelay,
    String? serverUrl,
    int? latency,
  }) {
    final oldState = _currentInfo.state;
    final newInfo = _currentInfo.copyWith(
      state: newState,
      timestamp: DateTime.now(),
      message: message,
      metadata: metadata,
      attemptNumber: attemptNumber,
      reconnectDelay: reconnectDelay,
      serverUrl: serverUrl,
      latency: latency,
    );

    _currentInfo = newInfo;
    _addToHistory(newInfo);
    _stateController.add(newInfo);

    _logStateChange(oldState, newState, message);
  }

  void updateMetadata(Map<String, dynamic> metadata) {
    final updatedInfo = _currentInfo.copyWith(
      metadata: {...?(_currentInfo.metadata), ...metadata},
    );
    _currentInfo = updatedInfo;
    _stateController.add(updatedInfo);
  }

  void updateReconnectDelay(Duration delay) {
    final updatedInfo = _currentInfo.copyWith(reconnectDelay: delay);
    _currentInfo = updatedInfo;
    _stateController.add(updatedInfo);
  }

  void updateLatency(int latencyMs) {
    final updatedInfo = _currentInfo.copyWith(latency: latencyMs);
    _currentInfo = updatedInfo;
    _stateController.add(updatedInfo);
  }

  Duration get timeInCurrentState {
    return DateTime.now().difference(_currentInfo.timestamp);
  }

  int get connectionAttempts {
    return _stateHistory
        .where((info) => info.state == ConnectionState.connecting)
        .length;
  }

  int get errorCount {
    return _stateHistory
        .where((info) => info.state == ConnectionState.error)
        .length;
  }

  double get averageLatency {
    final latencies = _stateHistory
        .where((info) => info.latency != null)
        .map((info) => info.latency!)
        .toList();

    if (latencies.isEmpty) return 0.0;
    return latencies.reduce((a, b) => a + b) / latencies.length;
  }

  Map<ConnectionState, int> get stateStatistics {
    final stats = <ConnectionState, int>{};
    for (final info in _stateHistory) {
      stats[info.state] = (stats[info.state] ?? 0) + 1;
    }
    return stats;
  }

  List<ConnectionInfo> getLastStates(int count) {
    final start = _stateHistory.length - count;
    return _stateHistory.sublist(start < 0 ? 0 : start);
  }

  void clearHistory() {
    _stateHistory.clear();
  }

  void reset() {
    setState(ConnectionState.disconnected, message: 'Состояние сброшено');
    clearHistory();
  }

  void _addToHistory(ConnectionInfo info) {
    _stateHistory.add(info);

    if (_stateHistory.length > 50) {
      _stateHistory.removeAt(0);
    }
  }

  void _logStateChange(
    ConnectionState from,
    ConnectionState to,
    String? message,
  ) {
    final fromStr = _getStateDisplayName(from);
    final toStr = _getStateDisplayName(to);
    final messageStr = message != null ? ' ($message)' : '';

    print('🔄 Состояние подключения: $fromStr → $toStr$messageStr');
  }

  String _getStateDisplayName(ConnectionState state) {
    switch (state) {
      case ConnectionState.disconnected:
        return 'Отключен';
      case ConnectionState.connecting:
        return 'Подключение';
      case ConnectionState.connected:
        return 'Подключен';
      case ConnectionState.ready:
        return 'Готов';
      case ConnectionState.reconnecting:
        return 'Переподключение';
      case ConnectionState.error:
        return 'Ошибка';
      case ConnectionState.disabled:
        return 'Отключен';
    }
  }

  void dispose() {
    _stateController.close();
  }
}
