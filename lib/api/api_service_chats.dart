part of 'api_service.dart';

extension ApiServiceChats on ApiService {
  void createGroup(String name, List<int> participantIds) {
    final payload = {"name": name, "participantIds": participantIds};
    _sendMessage(48, payload);
    print('Создаем группу: $name с участниками: $participantIds');
  }

  void updateGroup(int chatId, {String? name, List<int>? participantIds}) {
    final payload = {
      "chatId": chatId,
      if (name != null) "name": name,
      if (participantIds != null) "participantIds": participantIds,
    };
    _sendMessage(272, payload);
    print('Обновляем группу $chatId: $payload');
  }

  void createGroupWithMessage(String name, List<int> participantIds) {
    final cid = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      "message": {
        "cid": cid,
        "attaches": [
          {
            "_type": "CONTROL",
            "event": "new",
            "chatType": "CHAT",
            "title": name,
            "userIds": participantIds,
          },
        ],
      },
      "notify": true,
    };
    _sendMessage(64, payload);
    print('Создаем группу: $name с участниками: $participantIds');
  }

  void renameGroup(int chatId, String newName) {
    final payload = {"chatId": chatId, "theme": newName};
    _sendMessage(55, payload);
    print('Переименовываем группу $chatId в: $newName');
  }

  void addGroupMember(
    int chatId,
    List<int> userIds, {
    bool showHistory = true,
  }) {
    final payload = {
      "chatId": chatId,
      "userIds": userIds,
      "showHistory": showHistory,
      "operation": "add",
    };
    _sendMessage(77, payload);
    print('Добавляем участников $userIds в группу $chatId');
  }

  void removeGroupMember(
    int chatId,
    List<int> userIds, {
    int cleanMsgPeriod = 0,
  }) {
    final payload = {
      "chatId": chatId,
      "userIds": userIds,
      "operation": "remove",
      "cleanMsgPeriod": cleanMsgPeriod,
    };
    _sendMessage(77, payload);
    print('Удаляем участников $userIds из группы $chatId');
  }

  void leaveGroup(int chatId) {
    final payload = {"chatId": chatId};
    _sendMessage(58, payload);
    print('Выходим из группы $chatId');
  }

  void getGroupMembers(int chatId, {int marker = 0, int count = 50}) {
    final payload = {
      "type": "MEMBER",
      "marker": marker,
      "chatId": chatId,
      "count": count,
    };
    _sendMessage(59, payload);
    print(
      'Запрашиваем участников группы $chatId (marker: $marker, count: $count)',
    );
  }

  Future<Map<String, dynamic>> getChatsOnly({bool force = false}) async {
    if (authToken == null) {
      await _loadTokenFromAccountManager();
    }
    if (authToken == null) throw Exception("Auth token not found");

    if (!force && _lastChatsPayload != null && _lastChatsAt != null) {
      if (DateTime.now().difference(_lastChatsAt!) < _chatsCacheTtl) {
        return _lastChatsPayload!;
      }
    }

    try {
      final payload = {"chatsCount": 100};

      final int chatSeq = _sendMessage(48, payload);
      final chatResponse = await messages.firstWhere(
        (msg) => msg['seq'] == chatSeq,
      );

      final List<dynamic> chatListJson =
          chatResponse['payload']?['chats'] ?? [];

      if (chatListJson.isEmpty) {
        final result = {'chats': [], 'contacts': [], 'profile': null};
        _lastChatsPayload = result;
        _lastChatsAt = DateTime.now();
        return result;
      }

      final contactIds = <int>{};
      for (var chatJson in chatListJson) {
        final participants =
            chatJson['participants'] as Map<String, dynamic>? ?? {};
        contactIds.addAll(participants.keys.map((id) => int.parse(id)));
      }

      final int contactSeq = _sendMessage(32, {
        "contactIds": contactIds.toList(),
      });
      final contactResponse = await messages.firstWhere(
        (msg) => msg['seq'] == contactSeq,
      );

      final List<dynamic> contactListJson =
          contactResponse['payload']?['contacts'] ?? [];

      final result = {
        'chats': chatListJson,
        'contacts': contactListJson,
        'profile': null,
        'presence': null,
      };
      _lastChatsPayload = result;

      final contacts =
          contactListJson.map((json) => Contact.fromJson(json)).toList();
      updateContactCache(contacts);
      _lastChatsAt = DateTime.now();
      return result;
    } catch (e) {
      print('Ошибка получения чатов: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getChatsAndContacts({bool force = false}) async {
    await waitUntilOnline();

    if (authToken == null) {
      print("Токен авторизации не найден, требуется повторная авторизация");
      throw Exception("Auth token not found - please re-authenticate");
    }

    if (!force && _lastChatsPayload != null && _lastChatsAt != null) {
      if (DateTime.now().difference(_lastChatsAt!) < _chatsCacheTtl) {
        return _lastChatsPayload!;
      }
    }

    if (_chatsFetchedInThisSession && _lastChatsPayload != null && !force) {
      return _lastChatsPayload!;
    }

    if (_inflightChatsCompleter != null) {
      return _inflightChatsCompleter!.future;
    }
    _inflightChatsCompleter = Completer<Map<String, dynamic>>();

    if (_isSessionOnline &&
        _isSessionReady &&
        _lastChatsPayload != null &&
        !force) {
      _inflightChatsCompleter!.complete(_lastChatsPayload!);
      _inflightChatsCompleter = null;
      return _lastChatsPayload!;
    }

    try {
      Map<String, dynamic> chatResponse;

      final int opcode;
      final Map<String, dynamic> payload;

      final prefs = await SharedPreferences.getInstance();
      final deviceId =
          prefs.getString('spoof_deviceid') ?? generateRandomDeviceId();

      if (prefs.getString('spoof_deviceid') == null) {
        await prefs.setString('spoof_deviceid', deviceId);
      }

      if (!_chatsFetchedInThisSession) {
        opcode = 19;
        payload = {
          "chatsCount": 100,
          "chatsSync": 0,
          "contactsSync": 0,
          "draftsSync": 0,
          "interactive": true,
          "presenceSync": 0,
          "token": authToken,
        };

        if (userId != null) {
          payload["userId"] = userId;
        }
      } else {
        return await getChatsOnly(force: force);
      }

      final int chatSeq = _sendMessage(opcode, payload);
      chatResponse = await messages.firstWhere((msg) => msg['seq'] == chatSeq);

      if (opcode == 19 && chatResponse['cmd'] == 1) {
        print("✅ Авторизация (opcode 19) успешна. Сессия ГОТОВА.");
        _isSessionReady = true;

        _connectionStatusController.add("ready");

        final profile = chatResponse['payload']?['profile'];
        final contactProfile = profile?['contact'];

        if (contactProfile != null && contactProfile['id'] != null) {
          print(
            "[getChatsAndContacts] ✅ Профиль и ID пользователя найдены. ID: ${contactProfile['id']}. ЗАПУСКАЕМ АНАЛИТИКУ.",
          );
          _userId = contactProfile['id'];
          _sessionId = DateTime.now().millisecondsSinceEpoch;
          _lastActionTime = _sessionId;

          sendNavEvent('COLD_START');

          _sendInitialSetupRequests();
        } else {
          print(
            "[getChatsAndContacts] ❌ ВНИМАНИЕ: Профиль или ID в ответе пустой, аналитика не будет отправлена.",
          );
        }

        if (_onlineCompleter != null && !_onlineCompleter!.isCompleted) {
          _onlineCompleter!.complete();
        }

        _startPinging();
        _processMessageQueue();
      }

      final profile = chatResponse['payload']?['profile'];
      final presence = chatResponse['payload']?['presence'];
      final config = chatResponse['payload']?['config'];
      final List<dynamic> chatListJson =
          chatResponse['payload']?['chats'] ?? [];

      if (profile != null && authToken != null) {
        try {
          final accountManager = AccountManager();
          await accountManager.initialize();
          final currentAccount = accountManager.currentAccount;
          if (currentAccount != null && currentAccount.token == authToken) {
            final profileObj = Profile.fromJson(profile);
            await accountManager.updateAccountProfile(
              currentAccount.id,
              profileObj,
            );
          }
        } catch (e) {
          print('Ошибка сохранения профиля в AccountManager: $e');
        }
      }

      if (chatListJson.isEmpty) {
        if (config != null) {
          _processServerPrivacyConfig(config);
        }

        final result = {
          'chats': [],
          'contacts': [],
          'profile': profile,
          'config': config,
        };
        _lastChatsPayload = result;
        _lastChatsAt = DateTime.now();
        _chatsFetchedInThisSession = true;
        _inflightChatsCompleter!.complete(_lastChatsPayload!);
        _inflightChatsCompleter = null;
        return result;
      }

      final contactIds = <int>{};
      for (var chatJson in chatListJson) {
        final participants = chatJson['participants'] as Map<String, dynamic>;
        contactIds.addAll(participants.keys.map((id) => int.parse(id)));
      }

      final int contactSeq = _sendMessage(32, {
        "contactIds": contactIds.toList(),
      });
      final contactResponse = await messages.firstWhere(
        (msg) => msg['seq'] == contactSeq,
      );

      final List<dynamic> contactListJson =
          contactResponse['payload']?['contacts'] ?? [];

      if (presence != null) {
        updatePresenceData(presence);
      }

      if (config != null) {
        _processServerPrivacyConfig(config);
      }

      final result = {
        'chats': chatListJson,
        'contacts': contactListJson,
        'profile': profile,
        'presence': presence,
        'config': config,
      };
      _lastChatsPayload = result;

      final contacts =
          contactListJson.map((json) => Contact.fromJson(json)).toList();
      updateContactCache(contacts);
      _lastChatsAt = DateTime.now();
      _chatsFetchedInThisSession = true;
      _inflightChatsCompleter!.complete(result);
      _inflightChatsCompleter = null;
      return result;
    } catch (e) {
      final error = e;
      _inflightChatsCompleter?.completeError(error);
      _inflightChatsCompleter = null;
      rethrow;
    }
  }

  Future<void> _sendInitialSetupRequests() async {
    print("Запускаем отправку единичных запросов при старте...");

    if (!_isSessionOnline || !_isSessionReady) {
      print("Сессия еще не готова, ждем...");
      await waitUntilOnline();
    }

    await Future.delayed(const Duration(seconds: 2));

    if (!_isSessionOnline || !_isSessionReady) {
      print("Сессия не готова для отправки запросов, пропускаем");
      return;
    }

    _sendMessage(272, {"folderSync": 0});
    await Future.delayed(const Duration(milliseconds: 500));
    _sendMessage(27, {"sync": 0, "type": "STICKER"});
    await Future.delayed(const Duration(milliseconds: 500));
    _sendMessage(27, {"sync": 0, "type": "FAVORITE_STICKER"});
    await Future.delayed(const Duration(milliseconds: 500));
    _sendMessage(79, {"forward": false, "count": 100});

    await Future.delayed(const Duration(seconds: 5));
    _sendMessage(26, {
      "sectionId": "NEW_STICKER_SETS",
      "from": 5,
      "count": 100,
    });

    print("Единичные запросы отправлены.");
  }

  Future<List<Message>> getMessageHistory(
    int chatId, {
    bool force = false,
  }) async {
    if (!force && _messageCache.containsKey(chatId)) {
      print("Загружаем сообщения для чата $chatId из кэша.");
      return _messageCache[chatId]!;
    }

    print("Запрашиваем историю для чата $chatId с сервера.");
    final payload = {
      "chatId": chatId,
      "from": DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
      "forward": 0,
      "backward": 1000,
      "getMessages": true,
    };

    try {
      final int seq = _sendMessage(49, payload);
      final response = await messages
          .firstWhere((msg) => msg['seq'] == seq)
          .timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        final error = response['payload'];
        print('Ошибка получения истории сообщений: $error');

        if (error['error'] == 'proto.state') {
          print(
            'Ошибка состояния сессии при получении истории, переподключаемся...',
          );
          await reconnect();
          await waitUntilOnline();

          return getMessageHistory(chatId, force: true);
        }
        throw Exception('Ошибка получения истории: ${error['message']}');
      }

      final List<dynamic> messagesJson = response['payload']?['messages'] ?? [];
      final messagesList =
          messagesJson.map((json) => Message.fromJson(json)).toList()
            ..sort((a, b) => a.time.compareTo(b.time));

      _messageCache[chatId] = messagesList;

      return messagesList;
    } catch (e) {
      print('Ошибка при получении истории сообщений: $e');

      return [];
    }
  }

  Future<Map<String, dynamic>?> loadOldMessages(
    int chatId,
    String fromMessageId,
    int count,
  ) async {
    print(
      "Запрашиваем старые сообщения для чата $chatId начиная с $fromMessageId",
    );

    final payload = {
      "chatId": chatId,
      "from": int.parse(fromMessageId),
      "forward": 0,
      "backward": count,
      "getMessages": true,
    };

    try {
      final int seq = _sendMessage(49, payload);
      final response = await messages
          .firstWhere((msg) => msg['seq'] == seq)
          .timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        final error = response['payload'];
        print('Ошибка получения старых сообщений: $error');
        return null;
      }

      return response['payload'];
    } catch (e) {
      print('Ошибка при получении старых сообщений: $e');
      return null;
    }
  }

  void sendNavEvent(String event, {int? screenTo, int? screenFrom}) {
    if (_userId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> params = {
      'session_id': _sessionId,
      'action_id': _actionId++,
    };

    switch (event) {
      case 'COLD_START':
        if (_isColdStartSent) return;
        params['screen_to'] = 150;
        params['source_id'] = 1;
        _isColdStartSent = true;
        break;
      case 'WARM_START':
        params['screen_to'] = 150;
        params['screen_from'] = 1;
        params['prev_time'] = _lastActionTime;
        break;
      case 'GO':
        params['screen_to'] = screenTo;
        params['screen_from'] = screenFrom;
        params['prev_time'] = _lastActionTime;
        break;
    }

    _lastActionTime = now;
    _sendMessage(5, {
      "events": [
        {
          "type": "NAV",
          "event": event,
          "userId": _userId,
          "time": now,
          "params": params,
        },
      ],
    });
  }

  void createFolder(
    String title, {
    List<int>? include,
    List<dynamic>? filters,
  }) {
    final folderId = const Uuid().v4();
    final payload = {
      "id": folderId,
      "title": title,
      "include": include ?? [],
      "filters": filters ?? [],
    };
    _sendMessage(274, payload);
    print('Создаем папку: $title (ID: $folderId)');
  }

  void updateFolder(
    String folderId, {
    String? title,
    List<int>? include,
    List<dynamic>? filters,
  }) {
    final payload = {
      "id": folderId,
      if (title != null) "title": title,
      if (include != null) "include": include,
      if (filters != null) "filters": filters,
    };
    _sendMessage(274, payload);
    print('Обновляем папку: $folderId');
  }

  void deleteFolder(String folderId) {
    final payload = {
      "folderIds": [folderId],
    };
    _sendMessage(276, payload);
    print('Удаляем папку: $folderId');
  }

  void requestFolderSync() {
    _sendMessage(272, {"folderSync": 0});
    print('Запрос на обновление папок отправлен');
  }

  void clearCacheForChat(int chatId) {
    _messageCache.remove(chatId);
    print("Кэш для чата $chatId очищен.");
  }

  void clearChatsCache() {
    _lastChatsPayload = null;
    _lastChatsAt = null;
    print("Кэш чатов очищен.");
  }

  Contact? getCachedContact(int contactId) {
    if (_contactCache.containsKey(contactId)) {
      final contact = _contactCache[contactId]!;
      print('Контакт $contactId получен из кэша: ${contact.name}');
      return contact;
    }
    return null;
  }

  Future<Map<String, dynamic>> getNetworkStatistics() async {
    final prefs = await SharedPreferences.getInstance();

    final totalTraffic =
        prefs.getDouble('network_total_traffic') ??
        (150.0 * 1024 * 1024);
    final messagesTraffic =
        prefs.getDouble('network_messages_traffic') ?? (totalTraffic * 0.15);
    final mediaTraffic =
        prefs.getDouble('network_media_traffic') ?? (totalTraffic * 0.6);
    final syncTraffic =
        prefs.getDouble('network_sync_traffic') ?? (totalTraffic * 0.1);

    final currentSpeed =
        _isSessionOnline ? 512.0 * 1024 : 0.0;

    final ping = 25;

    return {
      'totalTraffic': totalTraffic,
      'messagesTraffic': messagesTraffic,
      'mediaTraffic': mediaTraffic,
      'syncTraffic': syncTraffic,
      'otherTraffic': totalTraffic * 0.15,
      'currentSpeed': currentSpeed,
      'isConnected': _isSessionOnline,
      'connectionType': 'Wi-Fi',
      'signalStrength': 85,
      'ping': ping,
      'jitter': 2.5,
      'packetLoss': 0.01,
      'hourlyStats': [],
    };
  }

  bool isContactCacheValid() {
    if (_lastContactsUpdate == null) return false;
    return DateTime.now().difference(_lastContactsUpdate!) <
        ApiService._contactCacheExpiry;
  }

  void updateContactCache(List<Contact> contacts) {
    _contactCache.clear();
    for (final contact in contacts) {
      _contactCache[contact.id] = contact;
    }
    _lastContactsUpdate = DateTime.now();
    print('Кэш контактов обновлен: ${contacts.length} контактов');
  }

  void updateCachedContact(Contact contact) {
    _contactCache[contact.id] = contact;
    print('Контакт ${contact.id} обновлен в кэше: ${contact.name}');
  }

  void clearContactCache() {
    _contactCache.clear();
    _lastContactsUpdate = null;
    print("Кэш контактов очищен.");
  }

  void clearAllCaches() {
    clearContactCache();
    clearChatsCache();
    _messageCache.clear();
    clearPasswordAuthData();
    print("Все кэши очищены из-за ошибки подключения.");
  }

  void sendMessage(
    int chatId,
    String text, {
    String? replyToMessageId,
    int? cid,
  }) {
    final int clientMessageId = cid ?? DateTime.now().millisecondsSinceEpoch;
    final payload = {
      "chatId": chatId,
      "message": {
        "text": text,
        "cid": clientMessageId,
        "elements": [],
        "attaches": [],
        if (replyToMessageId != null)
          "link": {"type": "REPLY", "messageId": replyToMessageId},
      },
      "notify": true,
    };

    clearChatsCache();

    if (_isSessionOnline) {
      _sendMessage(64, payload);
    } else {
      print("Сессия не онлайн. Сообщение добавлено в очередь.");
      _messageQueue.add({'opcode': 64, 'payload': payload});
    }
  }

  void forwardMessage(int targetChatId, String messageId, int sourceChatId) {
    final int clientMessageId = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      "chatId": targetChatId,
      "message": {
        "cid": clientMessageId,
        "link": {
          "type": "FORWARD",
          "messageId": messageId,
          "chatId": sourceChatId,
        },
        "attaches": [],
      },
      "notify": true,
    };

    if (_isSessionOnline) {
      _sendMessage(64, payload);
    } else {
      _messageQueue.add({'opcode': 64, 'payload': payload});
    }
  }

  Future<void> editMessage(int chatId, String messageId, String newText) async {
    final payload = {
      "chatId": chatId,
      "messageId": messageId,
      "text": newText,
      "elements": [],
      "attachments": [],
    };

    clearChatsCache();

    await waitUntilOnline();

    if (!_isSessionOnline) {
      print('Сессия не онлайн, пытаемся переподключиться...');
      await reconnect();
      await waitUntilOnline();
    }

    Future<bool> sendOnce() async {
      try {
        final int seq = _sendMessage(67, payload);
        final response = await messages
            .firstWhere((msg) => msg['seq'] == seq)
            .timeout(const Duration(seconds: 10));

        if (response['cmd'] == 3) {
          final error = response['payload'];
          print('Ошибка редактирования сообщения: $error');

          if (error['error'] == 'proto.state') {
            print('Ошибка состояния сессии, переподключаемся...');
            await reconnect();
            await waitUntilOnline();
            return false;
          }

          if (error['error'] == 'error.edit.invalid.message') {
            print(
              'Сообщение не может быть отредактировано: ${error['localizedMessage']}',
            );
            throw Exception(
              'Сообщение не может быть отредактировано: ${error['localizedMessage']}',
            );
          }

          return false;
        }

        return response['cmd'] == 1;
      } catch (e) {
        print('Ошибка при редактировании сообщения: $e');
        return false;
      }
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      print(
        'Попытка редактирования сообщения $messageId (попытка ${attempt + 1}/3)',
      );
      bool ok = await sendOnce();
      if (ok) {
        print('Сообщение $messageId успешно отредактировано');
        return;
      }

      if (attempt < 2) {
        print(
          'Повторяем запрос редактирования для сообщения $messageId через 2 секунды...',
        );
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    print('Не удалось отредактировать сообщение $messageId после 3 попыток');
  }

  Future<void> deleteMessage(
    int chatId,
    String messageId, {
    bool forMe = false,
  }) async {
    final payload = {
      "chatId": chatId,
      "messageIds": [messageId],
      "forMe": forMe,
    };

    clearChatsCache();

    await waitUntilOnline();

    if (!_isSessionOnline) {
      print('Сессия не онлайн, пытаемся переподключиться...');
      await reconnect();
      await waitUntilOnline();
    }

    Future<bool> sendOnce() async {
      try {
        final int seq = _sendMessage(66, payload);
        final response = await messages
            .firstWhere((msg) => msg['seq'] == seq)
            .timeout(const Duration(seconds: 10));

        if (response['cmd'] == 3) {
          final error = response['payload'];
          print('Ошибка удаления сообщения: $error');

          if (error['error'] == 'proto.state') {
            print('Ошибка состояния сессии, переподключаемся...');
            await reconnect();
            await waitUntilOnline();
            return false;
          }
          return false;
        }

        return response['cmd'] == 1;
      } catch (e) {
        print('Ошибка при удалении сообщения: $e');
        return false;
      }
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      print('Попытка удаления сообщения $messageId (попытка ${attempt + 1}/3)');
      bool ok = await sendOnce();
      if (ok) {
        print('Сообщение $messageId успешно удалено');
        return;
      }

      if (attempt < 2) {
        print(
          'Повторяем запрос удаления для сообщения $messageId через 2 секунды...',
        );
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    print('Не удалось удалить сообщение $messageId после 3 попыток');
  }

  void sendTyping(int chatId, {String type = "TEXT"}) {
    final payload = {"chatId": chatId, "type": type};
    if (_isSessionOnline) {
      _sendMessage(65, payload);
    }
  }
}

