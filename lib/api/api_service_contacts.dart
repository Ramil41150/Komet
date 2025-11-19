part of 'api_service.dart';

extension ApiServiceContacts on ApiService {
  Future<void> blockContact(int contactId) async {
    await waitUntilOnline();
    _sendMessage(34, {'contactId': contactId, 'action': 'BLOCK'});
  }

  Future<void> unblockContact(int contactId) async {
    await waitUntilOnline();
    _sendMessage(34, {'contactId': contactId, 'action': 'UNBLOCK'});
  }

  Future<void> addContact(int contactId) async {
    await waitUntilOnline();
    _sendMessage(34, {'contactId': contactId, 'action': 'ADD'});
  }

  Future<void> subscribeToChat(int chatId, bool subscribe) async {
    await waitUntilOnline();
    _sendMessage(75, {'chatId': chatId, 'subscribe': subscribe});
  }

  Future<void> navigateToChat(int currentChatId, int targetChatId) async {
    await waitUntilOnline();
    if (currentChatId != 0) {
      await subscribeToChat(currentChatId, false);
    }
    await subscribeToChat(targetChatId, true);
  }

  Future<void> clearChatHistory(int chatId, {bool forAll = false}) async {
    await waitUntilOnline();
    final payload = {
      'chatId': chatId,
      'forAll': forAll,
      'lastEventTime': DateTime.now().millisecondsSinceEpoch,
    };
    _sendMessage(54, payload);
  }

  Future<Map<String, dynamic>> getChatInfoByLink(String link) async {
    await waitUntilOnline();

    final payload = {'link': link};

    final int seq = _sendMessage(89, payload);
    print('Запрашиваем информацию о чате (seq: $seq) по ссылке: $link');

    try {
      final response = await messages
          .firstWhere((msg) => msg['seq'] == seq)
          .timeout(const Duration(seconds: 10));

      if (response['cmd'] == 3) {
        final errorPayload = response['payload'] ?? {};
        final errorMessage =
            errorPayload['localizedMessage'] ??
            errorPayload['message'] ??
            'Неизвестная ошибка';
        print('Ошибка получения информации о чате: $errorMessage');
        throw Exception(errorMessage);
      }

      if (response['cmd'] == 1 &&
          response['payload'] != null &&
          response['payload']['chat'] != null) {
        print(
          'Информация о чате получена: ${response['payload']['chat']['title']}',
        );
        return response['payload']['chat'] as Map<String, dynamic>;
      } else {
        print('Не удалось найти "chat" в ответе opcode 89: $response');
        throw Exception('Неверный ответ от сервера');
      }
    } on TimeoutException {
      print('Таймаут ожидания ответа на getChatInfoByLink (seq: $seq)');
      throw Exception('Сервер не ответил вовремя');
    } catch (e) {
      print('Ошибка в getChatInfoByLink: $e');
      rethrow;
    }
  }

  void markMessageAsRead(int chatId, String messageId) {
    waitUntilOnline().then((_) {
      final payload = {
        "type": "READ_MESSAGE",
        "chatId": chatId,
        "messageId": messageId,
        "mark": DateTime.now().millisecondsSinceEpoch,
      };
      _sendMessage(50, payload);
      print(
        'Отправляем отметку о прочтении для сообщения $messageId в чате $chatId',
      );
    });
  }

  void getBlockedContacts() async {
    if (_isLoadingBlockedContacts) {
      print(
        'ApiService: запрос заблокированных контактов уже выполняется, пропускаем',
      );
      return;
    }

    _isLoadingBlockedContacts = true;
    print('ApiService: запрашиваем заблокированные контакты');
    _sendMessage(36, {'status': 'BLOCKED', 'count': 100, 'from': 0});

    Future.delayed(const Duration(seconds: 2), () {
      _isLoadingBlockedContacts = false;
    });
  }

  void notifyContactUpdate(Contact contact) {
    print(
      'ApiService отправляет обновление контакта: ${contact.name} (ID: ${contact.id}), isBlocked: ${contact.isBlocked}, isBlockedByMe: ${contact.isBlockedByMe}',
    );
    _contactUpdatesController.add(contact);
  }

  DateTime? getLastSeen(int userId) {
    final userPresence = _presenceData[userId.toString()];
    if (userPresence != null && userPresence['seen'] != null) {
      final seenTimestamp = userPresence['seen'] as int;

      return DateTime.fromMillisecondsSinceEpoch(seenTimestamp * 1000);
    }
    return null;
  }

  void updatePresenceData(Map<String, dynamic> presenceData) {
    _presenceData.addAll(presenceData);
    print('ApiService обновил presence данные: $_presenceData');
  }

  void sendReaction(int chatId, String messageId, String emoji) {
    final payload = {
      "chatId": chatId,
      "messageId": messageId,
      "reaction": {"reactionType": "EMOJI", "id": emoji},
    };
    _sendMessage(178, payload);
    print('Отправляем реакцию: $emoji на сообщение $messageId в чате $chatId');
  }

  void removeReaction(int chatId, String messageId) {
    final payload = {"chatId": chatId, "messageId": messageId};
    _sendMessage(179, payload);
    print('Удаляем реакцию с сообщения $messageId в чате $chatId');
  }

  Future<Map<String, dynamic>> joinGroupByLink(String link) async {
    await waitUntilOnline();

    final payload = {'link': link};

    final int seq = _sendMessage(57, payload);
    print('Отправляем запрос на присоединение (seq: $seq) по ссылке: $link');

    try {
      final response = await messages
          .firstWhere((msg) => msg['seq'] == seq && msg['opcode'] == 57)
          .timeout(const Duration(seconds: 15));

      if (response['cmd'] == 3) {
        final errorPayload = response['payload'] ?? {};
        final errorMessage =
            errorPayload['localizedMessage'] ??
            errorPayload['message'] ??
            'Неизвестная ошибка';
        print('Ошибка присоединения к группе: $errorMessage');
        throw Exception(errorMessage);
      }

      if (response['cmd'] == 1 && response['payload'] != null) {
        print('Успешно присоединились: ${response['payload']}');
        return response['payload'] as Map<String, dynamic>;
      } else {
        print('Неожиданный ответ на joinGroupByLink: $response');
        throw Exception('Неверный ответ от сервера');
      }
    } on TimeoutException {
      print('Таймаут ожидания ответа на joinGroupByLink (seq: $seq)');
      throw Exception('Сервер не ответил вовремя');
    } catch (e) {
      print('Ошибка в joinGroupByLink: $e');
      rethrow;
    }
  }

  Future<void> searchContactByPhone(String phone) async {
    await waitUntilOnline();

    final payload = {'phone': phone};

    _sendMessage(46, payload);
    print('Запрос на поиск контакта отправлен с payload: $payload');
  }

  Future<void> searchChannels(String query) async {
    await waitUntilOnline();

    final payload = {'contactIds': []};

    _sendMessage(32, payload);
    print('Запрос на поиск каналов отправлен с payload: $payload');
  }

  Future<void> enterChannel(String link) async {
    await waitUntilOnline();

    final payload = {'link': link};

    _sendMessage(89, payload);
    print('Запрос на вход в канал отправлен с payload: $payload');
  }

  Future<void> subscribeToChannel(String link) async {
    await waitUntilOnline();

    final payload = {'link': link};

    _sendMessage(57, payload);
    print('Запрос на подписку на канал отправлен с payload: $payload');
  }

  Future<int?> getChatIdByUserId(int userId) async {
    await waitUntilOnline();

    final payload = {
      "chatIds": [userId],
    };
    final int seq = _sendMessage(48, payload);
    print('Запрашиваем информацию о чате для userId: $userId (seq: $seq)');

    try {
      final response = await messages
          .firstWhere((msg) => msg['seq'] == seq)
          .timeout(const Duration(seconds: 10));

      if (response['cmd'] == 3) {
        final errorPayload = response['payload'] ?? {};
        final errorMessage =
            errorPayload['localizedMessage'] ??
            errorPayload['message'] ??
            'Неизвестная ошибка';
        print('Ошибка получения информации о чате: $errorMessage');
        return null;
      }

      if (response['cmd'] == 1 && response['payload'] != null) {
        final chats = response['payload']['chats'] as List<dynamic>?;
        if (chats != null && chats.isNotEmpty) {
          final chat = chats[0] as Map<String, dynamic>;
          final chatId = chat['id'] as int?;
          final chatType = chat['type'] as String?;

          if (chatType == 'DIALOG' && chatId != null) {
            print('Получен chatId для диалога с userId $userId: $chatId');
            return chatId;
          }
        }
      }

      print('Не удалось найти chatId для userId: $userId');
      return null;
    } on TimeoutException {
      print('Таймаут ожидания ответа на getChatIdByUserId (seq: $seq)');
      return null;
    } catch (e) {
      print('Ошибка при получении chatId для userId $userId: $e');
      return null;
    }
  }

  Future<List<Contact>> fetchContactsByIds(List<int> contactIds) async {
    if (contactIds.isEmpty) {
      return [];
    }

    print('Запрашиваем данные для ${contactIds.length} контактов...');
    try {
      final int contactSeq = _sendMessage(32, {"contactIds": contactIds});

      final contactResponse = await messages
          .firstWhere((msg) => msg['seq'] == contactSeq)
          .timeout(const Duration(seconds: 10));

      if (contactResponse['cmd'] == 3) {
        print(
          "Ошибка при получении контактов по ID: ${contactResponse['payload']}",
        );
        return [];
      }

      final List<dynamic> contactListJson =
          contactResponse['payload']?['contacts'] ?? [];
      final contacts = contactListJson
          .map((json) => Contact.fromJson(json))
          .toList();

      for (final contact in contacts) {
        _contactCache[contact.id] = contact;
      }
      print("Получены и закэшированы данные для ${contacts.length} контактов.");
      return contacts;
    } catch (e) {
      print('Исключение при получении контактов по ID: $e');
      return [];
    }
  }
}

