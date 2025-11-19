library api_service;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:gwid/models/contact.dart';
import 'package:gwid/models/message.dart';
import 'package:gwid/models/profile.dart';
import 'package:gwid/proxy_service.dart';
import 'package:gwid/services/account_manager.dart';
import 'package:gwid/spoofing_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;

part 'api_service_connection.dart';
part 'api_service_auth.dart';
part 'api_service_contacts.dart';
part 'api_service_chats.dart';
part 'api_service_media.dart';
part 'api_service_privacy.dart';

class ApiService {
  ApiService._privateConstructor();
  static final ApiService instance = ApiService._privateConstructor();

  int? _userId;
  late int _sessionId;
  int _actionId = 1;
  bool _isColdStartSent = false;
  late int _lastActionTime;

  bool _isAppInForeground = true;

  final List<String> _wsUrls = ['wss://ws-api.oneme.ru:443/websocket'];
  int _currentUrlIndex = 0;

  List<String> get wsUrls => _wsUrls;
  int get currentUrlIndex => _currentUrlIndex;
  IOWebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  Timer? _pingTimer;
  int _seq = 0;

  final StreamController<Contact> _contactUpdatesController =
      StreamController<Contact>.broadcast();
  Stream<Contact> get contactUpdates => _contactUpdatesController.stream;

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  final _reconnectionCompleteController = StreamController<void>.broadcast();
  Stream<void> get reconnectionComplete =>
      _reconnectionCompleteController.stream;

  final Map<String, dynamic> _presenceData = {};
  String? authToken;
  String? userId;

  String? get token => authToken;

  String? _currentPasswordTrackId;
  String? _currentPasswordHint;
  String? _currentPasswordEmail;

  bool _isSessionOnline = false;
  bool _handshakeSent = false;
  Completer<void>? _onlineCompleter;
  final List<Map<String, dynamic>> _messageQueue = [];

  final Map<int, List<Message>> _messageCache = {};

  final Map<int, Contact> _contactCache = {};
  DateTime? _lastContactsUpdate;
  static const Duration _contactCacheExpiry = Duration(
    minutes: 5,
  );

  bool _isLoadingBlockedContacts = false;

  bool _isSessionReady = false;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _connectionStatusController = StreamController<String>.broadcast();
  Stream<String> get connectionStatus => _connectionStatusController.stream;

  final _connectionLogController = StreamController<String>.broadcast();
  Stream<String> get connectionLog => _connectionLogController.stream;

  final List<String> _connectionLogCache = [];
  List<String> get connectionLogCache => _connectionLogCache;

  bool get isOnline => _isSessionOnline;

  Future<void> waitUntilOnline() async {
    if (_isSessionOnline && _isSessionReady) return;
    _onlineCompleter ??= Completer<void>();
    return _onlineCompleter!.future;
  }

  bool get isActuallyConnected {
    try {
      if (_channel == null || !_isSessionOnline) {
        return false;
      }

      return true;
    } catch (e) {
      print("🔴 Ошибка при проверке состояния канала: $e");
      return false;
    }
  }

  Completer<Map<String, dynamic>>? _inflightChatsCompleter;
  Map<String, dynamic>? _lastChatsPayload;
  DateTime? _lastChatsAt;
  final Duration _chatsCacheTtl = const Duration(seconds: 5);
  bool _chatsFetchedInThisSession = false;

  Map<String, dynamic>? get lastChatsPayload => _lastChatsPayload;

  int _reconnectDelaySeconds = 2;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;

  void _log(String message) {
    print(message);
    _connectionLogCache.add(message);
    if (!_connectionLogController.isClosed) {
      _connectionLogController.add(message);
    }
  }

  void _emitLocal(Map<String, dynamic> frame) {
    try {
      _messageController.add(frame);
    } catch (_) {}
  }

  String generateRandomDeviceId() {
    return const Uuid().v4();
  }

  Future<Map<String, dynamic>> _buildUserAgentPayload() async {
    final spoofedData = await SpoofingService.getSpoofedSessionData();

    if (spoofedData != null) {
      print(
        '--- [_buildUserAgentPayload] Используются подменённые данные сессии ---',
      );
      final String finalDeviceId;
      final String? idFromSpoofing = spoofedData['device_id'] as String?;

      if (idFromSpoofing != null && idFromSpoofing.isNotEmpty) {
        finalDeviceId = idFromSpoofing;
        print('Используется deviceId из сессии: $finalDeviceId');
      } else {
        finalDeviceId = generateRandomDeviceId();
        print('device_id не найден в кэше, сгенерирован новый: $finalDeviceId');
      }
      return {
        'deviceType': spoofedData['device_type'] as String? ?? 'IOS',
        'locale': spoofedData['locale'] as String? ?? 'ru',
        'deviceLocale': spoofedData['locale'] as String? ?? 'ru',
        'osVersion': spoofedData['os_version'] as String? ?? 'iOS 17.5.1',
        'deviceName': spoofedData['device_name'] as String? ?? 'iPhone',
        'headerUserAgent':
            spoofedData['user_agent'] as String? ??
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
        'appVersion': spoofedData['app_version'] as String? ?? '25.10.10',
        'screen': spoofedData['screen'] as String? ?? '1170x2532 3.0x',
        'timezone': spoofedData['timezone'] as String? ?? 'Europe/Moscow',
      };
    } else {
      print(
        '--- [_buildUserAgentPayload] Используются псевдо-случайные данные ---',
      );
      return {
        'deviceType': 'WEB',
        'locale': 'ru',
        'deviceLocale': 'ru',
        'osVersion': 'Windows',
        'deviceName': 'Chrome',
        'headerUserAgent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'appVersion': '25.10.10',
        'screen': '1920x1080 1.0x',
        'timezone': 'Europe/Moscow',
      };
    }
  }

  void setAppInForeground(bool isForeground) {
    _isAppInForeground = isForeground;
  }

  Future<String?> getClipboardData() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  void dispose() {
    _pingTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _reconnectionCompleteController.close();
    _messageController.close();
  }
}

