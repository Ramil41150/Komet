import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

// FFI типы для LZ4 block decompress
typedef Lz4DecompressFunction =
    Int32 Function(
      Pointer<Uint8> src,
      Pointer<Uint8> dst,
      Int32 compressedSize,
      Int32 dstCapacity,
    );
typedef Lz4Decompress =
    int Function(
      Pointer<Uint8> src,
      Pointer<Uint8> dst,
      int compressedSize,
      int dstCapacity,
    );

class RegistrationService {
  Socket? _socket;
  int _seq = 0;
  final Map<int, Completer<dynamic>> _pending = {};
  bool _isConnected = false;
  Timer? _pingTimer;
  StreamSubscription? _socketSubscription;
  // LZ4 через es_compression/FFI сейчас не работает на Windows из‑за отсутствия
  // eslz4-win64.dll, поэтому ниже реализован свой чистый декодер LZ4 block.
  // Поля для LZ4 через FFI оставлены на будущее, если появится корректная DLL.
  DynamicLibrary? _lz4Lib;
  Lz4Decompress? _lz4BlockDecompress;

  void _initLz4BlockDecompress() {
    if (_lz4BlockDecompress != null) return;

    try {
      if (Platform.isWindows) {
        // Пробуем загрузить eslz4-win64.dll
        final dllPath = 'eslz4-win64.dll';
        print('📦 Загрузка LZ4 DLL для block decompress: $dllPath');
        _lz4Lib = DynamicLibrary.open(dllPath);

        // Ищем функцию LZ4_decompress_safe (block format)
        try {
          _lz4BlockDecompress = _lz4Lib!
              .lookup<NativeFunction<Lz4DecompressFunction>>(
                'LZ4_decompress_safe',
              )
              .asFunction();
          print('✅ LZ4 block decompress функция загружена');
        } catch (e) {
          print(
            '⚠️  Функция LZ4_decompress_safe не найдена, пробуем альтернативные имена...',
          );
          // Пробуем другие возможные имена
          try {
            _lz4BlockDecompress = _lz4Lib!
                .lookup<NativeFunction<Lz4DecompressFunction>>(
                  'LZ4_decompress_fast',
                )
                .asFunction();
            print('✅ LZ4 block decompress функция загружена (fast)');
          } catch (e2) {
            print('❌ Не удалось найти LZ4 block decompress функцию: $e2');
          }
        }
      }
    } catch (e) {
      print('⚠️  Не удалось загрузить LZ4 DLL для block decompress: $e');
      print('📦 Будем использовать только frame format (es_compression)');
    }
  }

  Future<void> connect() async {
    if (_isConnected) return;

    // Инициализируем LZ4 block decompress
    _initLz4BlockDecompress();

    try {
      print('🌐 Подключаемся к api.oneme.ru:443...');

      // Создаем SSL контекст
      final securityContext = SecurityContext.defaultContext;

      print('🔒 Создаем TCP соединение...');
      final rawSocket = await Socket.connect('api.oneme.ru', 443);
      print('✅ TCP соединение установлено');

      print('🔒 Устанавливаем SSL соединение...');
      _socket = await SecureSocket.secure(
        rawSocket,
        context: securityContext,
        host: 'api.oneme.ru',
        onBadCertificate: (certificate) {
          print('⚠️  Сертификат не прошел проверку, принимаем...');
          return true;
        },
      );

      _isConnected = true;
      print('✅ SSL соединение установлено');

      // Запускаем ping loop
      _startPingLoop();

      // Слушаем ответы
      _socketSubscription = _socket!.listen(
        _handleData,
        onError: (error) {
          print('❌ Ошибка сокета: $error');
          _isConnected = false;
        },
        onDone: () {
          print('🔌 Соединение закрыто');
          _isConnected = false;
        },
      );
    } catch (e) {
      print('❌ Ошибка подключения: $e');
      rethrow;
    }
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isConnected) {
        timer.cancel();
        return;
      }
      try {
        await _sendMessage(1, {});
        print('🏓 Ping отправлен');
      } catch (e) {
        print('❌ Ping failed: $e');
      }
    });
  }

  void _handleData(Uint8List data) {
    // Обрабатываем данные по частям - сначала заголовок, потом payload
    _processIncomingData(data);
  }

  Uint8List? _buffer = Uint8List(0);

  void _processIncomingData(Uint8List newData) {
    // Добавляем новые данные в буфер
    _buffer = Uint8List.fromList([..._buffer!, ...newData]);

    while (_buffer!.length >= 10) {
      // Читаем заголовок
      final header = _buffer!.sublist(0, 10);
      final payloadLen =
          ByteData.view(header.buffer, 6, 4).getUint32(0, Endian.big) &
          0xFFFFFF;

      if (_buffer!.length < 10 + payloadLen) {
        // Недостаточно данных, ждем еще
        break;
      }

      // Полный пакет готов
      final fullPacket = _buffer!.sublist(0, 10 + payloadLen);
      _buffer = _buffer!.sublist(10 + payloadLen);

      _processPacket(fullPacket);
    }
  }

  void _processPacket(Uint8List packet) {
    try {
      // Разбираем заголовок
      final ver = packet[0];
      final cmd = ByteData.view(packet.buffer).getUint16(1, Endian.big);
      final seq = packet[3];
      final opcode = ByteData.view(packet.buffer).getUint16(4, Endian.big);
      final packedLen = ByteData.view(
        packet.buffer,
        6,
        4,
      ).getUint32(0, Endian.big);

      // Проверяем флаг сжатия (как в packet_framer.dart)
      final compFlag = packedLen >> 24;
      final payloadLen = packedLen & 0x00FFFFFF;

      print('═══════════════════════════════════════════════════════════');
      print('📥 ПОЛУЧЕН ПАКЕТ ОТ СЕРВЕРА');
      print('═══════════════════════════════════════════════════════════');
      print(
        '📋 Заголовок: ver=$ver, cmd=$cmd, seq=$seq, opcode=$opcode, packedLen=$packedLen, compFlag=$compFlag, payloadLen=$payloadLen',
      );
      print('📦 Полный пакет (hex, ${packet.length} байт):');
      print(_bytesToHex(packet));
      print('');

      final payloadBytes = packet.sublist(10, 10 + payloadLen);
      print('📦 Сырые payload байты (hex, ${payloadBytes.length} байт):');
      print(_bytesToHex(payloadBytes));
      print('');

      final payload = _unpackPacketPayload(payloadBytes, compFlag != 0);

      print('📦 Разобранный payload (после LZ4 и msgpack):');
      print(_formatPayload(payload));
      print('═══════════════════════════════════════════════════════════');
      print('');

      // Находим completer по seq
      final completer = _pending[seq];
      if (completer != null && !completer.isCompleted) {
        completer.complete(payload);
        print('✅ Completer завершен для seq=$seq');
      } else {
        print('⚠️  Completer не найден для seq=$seq');
      }
    } catch (e) {
      print('❌ Ошибка разбора пакета: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  Uint8List _packPacket(
    int ver,
    int cmd,
    int seq,
    int opcode,
    Map<String, dynamic> payload,
  ) {
    final verB = Uint8List(1)..[0] = ver;
    final cmdB = Uint8List(2)
      ..buffer.asByteData().setUint16(0, cmd, Endian.big);
    final seqB = Uint8List(1)..[0] = seq;
    final opcodeB = Uint8List(2)
      ..buffer.asByteData().setUint16(0, opcode, Endian.big);

    final payloadBytes = msgpack.serialize(payload);
    final payloadLen = payloadBytes.length & 0xFFFFFF;
    final payloadLenB = Uint8List(4)
      ..buffer.asByteData().setUint32(0, payloadLen, Endian.big);

    final packet = Uint8List.fromList(
      verB + cmdB + seqB + opcodeB + payloadLenB + payloadBytes,
    );

    print('═══════════════════════════════════════════════════════════');
    print('📤 ОТПРАВЛЯЕМ ПАКЕТ НА СЕРВЕР');
    print('═══════════════════════════════════════════════════════════');
    print(
      '📋 Заголовок: ver=$ver, cmd=$cmd, seq=$seq, opcode=$opcode, payloadLen=$payloadLen',
    );
    print('📦 Payload (JSON):');
    print(_formatPayload(payload));
    print('📦 Payload (msgpack hex, ${payloadBytes.length} байт):');
    print(_bytesToHex(payloadBytes));
    print('📦 Полный пакет (hex, ${packet.length} байт):');
    print(_bytesToHex(packet));
    print('═══════════════════════════════════════════════════════════');
    print('');

    return packet;
  }

  String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      if (i > 0 && i % 16 == 0) buffer.writeln();
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      buffer.write(' ');
    }
    return buffer.toString();
  }

  String _formatPayload(dynamic payload) {
    if (payload == null) return 'null';
    if (payload is Map) {
      final buffer = StringBuffer();
      _formatMap(payload, buffer, 0);
      return buffer.toString();
    }
    return payload.toString();
  }

  void _formatMap(Map map, StringBuffer buffer, int indent) {
    final indentStr = '  ' * indent;
    buffer.writeln('{');
    map.forEach((key, value) {
      buffer.write('$indentStr  "$key": ');
      if (value is Map) {
        _formatMap(value, buffer, indent + 1);
      } else if (value is List) {
        buffer.writeln('[');
        for (var item in value) {
          buffer.write('$indentStr    ');
          if (item is Map) {
            _formatMap(item, buffer, indent + 2);
          } else {
            buffer.writeln('$item,');
          }
        }
        buffer.writeln('$indentStr  ],');
      } else {
        buffer.writeln('$value,');
      }
    });
    buffer.write('$indentStr}');
    if (indent > 0) buffer.writeln(',');
  }

  dynamic _deserializeMsgpack(Uint8List data) {
    print('📦 Десериализация msgpack...');
    try {
      dynamic payload = msgpack.deserialize(data);
      print('✅ Msgpack десериализация успешна');

      // Иногда сервер шлёт FFI‑токены в виде "отрицательное число + настоящий объект"
      // в одном msgpack‑буфере. msgpack_dart в таком случае возвращает только первое
      // значение (например, -16 или -13), а остальное игнорирует.
      //
      // Паттерны из логов:
      //  - F0 56 84 ... → -16 и дальше полноценная map
      //  - F3 A7 85 ... → -13 и дальше полноценная map
      //
      // Если мы увидели отрицательный fixint и в буфере есть ещё данные,
      // пробуем повторно распарсить "хвост" как настоящий payload.
      if (payload is int && data.length > 1 && payload <= -1 && payload >= -32) {
        final marker = data[0];

        // Для разных FFI‑токенов offset до реального msgpack может отличаться.
        // Вместо жёсткой привязки пробуем несколько вариантов подряд.
        final candidateOffsets = <int>[1, 2, 3, 4];

        // Сохраним сюда первый успешно распарсенный payload.
        dynamic recovered;

        for (final offset in candidateOffsets) {
          if (offset >= data.length) continue;

          try {
            print(
              '📦 Обнаружен FFI‑токен $payload (marker=0x${marker.toRadixString(16)}), '
              'пробуем msgpack c offset=$offset...',
            );
            final tail = data.sublist(offset);
            final realPayload = msgpack.deserialize(tail);
            print('✅ Удалось распарсить payload после FFI‑токена с offset=$offset');
            recovered = realPayload;
            break;
          } catch (e) {
            print(
              '⚠️  Попытка распарсить хвост msgpack (offset=$offset) не удалась: $e',
            );
          }
        }

        if (recovered != null) {
          payload = recovered;
        } else {
          print(
            '⚠️  Не удалось восстановить payload после FFI‑токена, '
            'оставляем исходное значение ($payload).',
          );
        }
      }

      // После базовой (и возможной повторной) десериализации дополнительно
      // разбираем "block"-объекты — структуры с lz4‑сжатыми данными.
      final decoded = _decodeBlockTokens(payload);
      return decoded;
    } catch (e) {
      print('❌ Ошибка десериализации msgpack: $e');
      return null;
    }
  }

  /// Рекурсивно обходит структуру ответа и декодирует блоки вида:
  /// {"type": "block", "data": <bytes>, "uncompressed_size": N}
  /// Такие блоки используются FFI для передачи lz4‑сжатых кусков данных.
  dynamic _decodeBlockTokens(dynamic value) {
    if (value is Map) {
      // Пытаемся декодировать саму map как block‑токен
      final maybeDecoded = _tryDecodeSingleBlock(value);
      if (maybeDecoded != null) {
        return maybeDecoded;
      }

      // Если это обычная map — обходим все поля рекурсивно
      final result = <dynamic, dynamic>{};
      value.forEach((k, v) {
        result[k] = _decodeBlockTokens(v);
      });
      return result;
    } else if (value is List) {
      return value.map(_decodeBlockTokens).toList();
    }

    return value;
  }

  /// Пробует интерпретировать map как блок вида "block".
  /// Если структура не похожа на блок, возвращает null.
  dynamic _tryDecodeSingleBlock(Map value) {
    try {
      if (value['type'] != 'block') {
        return null;
      }

      final rawData = value['data'];
      if (rawData is! List && rawData is! Uint8List) {
        return null;
      }

      // Пробуем вытащить ожидаемый размер распакованных данных.
      // Название поля может отличаться, поэтому проверяем несколько вариантов.
      final uncompressedSize = (value['uncompressed_size'] ??
              value['uncompressedSize'] ??
              value['size']) as int?;

      Uint8List compressedBytes = rawData is Uint8List
          ? rawData
          : Uint8List.fromList(List<int>.from(rawData as List));

      // Если FFI‑функция доступна — используем её (LZ4_decompress_safe).
      if (_lz4BlockDecompress != null && uncompressedSize != null) {
        print(
          '📦 Декодируем block‑токен через LZ4 FFI: '
          'compressed=${compressedBytes.length}, uncompressed=$uncompressedSize',
        );

        if (uncompressedSize <= 0 || uncompressedSize > 10 * 1024 * 1024) {
          print(
            '⚠️  Некорректный uncompressed_size=$uncompressedSize, '
            'пропускаем FFI‑декомпрессию для этого блока',
          );
          return null;
        }

        final srcSize = compressedBytes.length;
        final srcPtr = malloc.allocate<Uint8>(srcSize);
        final dstPtr = malloc.allocate<Uint8>(uncompressedSize);

        try {
          final srcList = srcPtr.asTypedList(srcSize);
          srcList.setAll(0, compressedBytes);

          final result = _lz4BlockDecompress!(
            srcPtr,
            dstPtr,
            srcSize,
            uncompressedSize,
          );

          if (result <= 0) {
            print('❌ LZ4_decompress_safe вернула код ошибки: $result');
            return null;
          }

          final actualSize = result;
          final dstList = dstPtr.asTypedList(actualSize);
          final decompressed = Uint8List.fromList(dstList);

          print(
            '✅ block‑токен успешно декомпрессирован: '
            '$srcSize → ${decompressed.length} байт',
          );

          // Пытаемся интерпретировать результат как msgpack — многие блоки
          // содержат внутри ещё один msgpack‑объект.
          final nested = _deserializeMsgpack(decompressed);
          if (nested != null) {
            return nested;
          }

          // Если это не msgpack — вернём просто байты, вызывающий код сам решит,
          // что с ними делать.
          return decompressed;
        } finally {
          malloc.free(srcPtr);
          malloc.free(dstPtr);
        }
      }

      // FFI недоступен — пробуем наш чистый Dart‑декодер LZ4 block.
      try {
        final decompressed =
            _lz4DecompressBlockPure(compressedBytes, 500000 /* max */);
        print(
          '✅ block‑токен декомпрессирован через чистый LZ4 block: '
          '${compressedBytes.length} → ${decompressed.length} байт',
        );

        final nested = _deserializeMsgpack(decompressed);
        return nested ?? decompressed;
      } catch (e) {
        print('⚠️  Не удалось декомпрессировать block‑токен через чистый LZ4: $e');
        return null;
      }
    } catch (e) {
      print('⚠️  Ошибка при разборе block‑токена: $e');
      return null;
    }
  }

  dynamic _unpackPacketPayload(
    Uint8List payloadBytes, [
    bool isCompressed = false,
  ]) {
    if (payloadBytes.isEmpty) {
      print('📦 Payload пустой');
      return null;
    }

    try {
      // Сначала пробуем LZ4 block‑декомпрессию так же, как делает register.py
      // (lz4.block.decompress(payload_bytes, uncompressed_size=99999)).
      Uint8List decompressedBytes = payloadBytes;

      try {
        print('📦 Пробуем LZ4 block‑декомпрессию (чистый Dart)...');
        decompressedBytes = _lz4DecompressBlockPure(payloadBytes, 500000);
        print(
          '✅ LZ4 block‑декомпрессия успешна: '
          '${payloadBytes.length} → ${decompressedBytes.length} байт',
        );
      } catch (lz4Error) {
        // Как и в Python‑скрипте: если lz4 не сработал, просто используем сырые байты.
        print('⚠️  LZ4 block‑декомпрессия не применена: $lz4Error');
        print('📦 Используем сырые данные без распаковки...');
        decompressedBytes = payloadBytes;
      }

      return _deserializeMsgpack(decompressedBytes);
    } catch (e) {
      print('❌ Ошибка десериализации payload: $e');
      print('Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Простейшая реализация LZ4 block‑декомпрессии на Dart.
  /// Поддерживает стандартный формат блоков без фрейм‑заголовка.
  /// Используется как аналог lz4.block.decompress из Python‑скрипта.
  Uint8List _lz4DecompressBlockPure(Uint8List src, int maxOutputSize) {
    // Алгоритм основан на официальной спецификации LZ4.
    final dst = BytesBuilder(copy: false);
    int srcPos = 0;

    while (srcPos < src.length) {
      if (srcPos >= src.length) break;
      final token = src[srcPos++];
      var literalLen = token >> 4;

      // Дополнительная длина литералов
      if (literalLen == 15) {
        while (srcPos < src.length) {
          final b = src[srcPos++];
          literalLen += b;
          if (b != 255) break;
        }
      }

      // Копируем литералы
      if (literalLen > 0) {
        if (srcPos + literalLen > src.length) {
          throw StateError('LZ4: literal length выходит за пределы входного буфера');
        }
        final literals = src.sublist(srcPos, srcPos + literalLen);
        srcPos += literalLen;
        dst.add(literals);
        if (dst.length > maxOutputSize) {
          throw StateError('LZ4: превышен максимально допустимый размер вывода');
        }
      }

      // Конец блока — нет места даже на offset
      if (srcPos >= src.length) {
        break;
      }

      // Читаем offset
      if (srcPos + 1 >= src.length) {
        throw StateError('LZ4: неполный offset в потоке');
      }
      final offset = src[srcPos] | (src[srcPos + 1] << 8);
      srcPos += 2;

      if (offset == 0) {
        throw StateError('LZ4: offset не может быть 0');
      }

      var matchLen = (token & 0x0F) + 4;

      // Дополнительная длина match‑а
      if ((token & 0x0F) == 0x0F) {
        while (srcPos < src.length) {
          final b = src[srcPos++];
          matchLen += b;
          if (b != 255) break;
        }
      }

      // Копируем match из уже записанных данных
      final dstBytes = dst.toBytes();
      final dstLen = dstBytes.length;
      final matchPos = dstLen - offset;
      if (matchPos < 0) {
        throw StateError('LZ4: match указывает за пределы уже декодированных данных');
      }

      final match = <int>[];
      for (int i = 0; i < matchLen; i++) {
        match.add(dstBytes[matchPos + (i % offset)]);
      }
      dst.add(Uint8List.fromList(match));

      if (dst.length > maxOutputSize) {
        throw StateError('LZ4: превышен максимально допустимый размер вывода');
      }
    }

    return Uint8List.fromList(dst.toBytes());
  }

  Future<dynamic> _sendMessage(int opcode, Map<String, dynamic> payload) async {
    if (!_isConnected || _socket == null) {
      throw Exception('Не подключено к серверу');
    }

    _seq = (_seq + 1) % 256;
    final seq = _seq;
    final packet = _packPacket(10, 0, seq, opcode, payload);

    print('📤 Отправляем сообщение opcode=$opcode, seq=$seq');

    final completer = Completer<dynamic>();
    _pending[seq] = completer;

    _socket!.add(packet);
    await _socket!.flush();

    return completer.future.timeout(const Duration(seconds: 30));
  }

  Future<String> startRegistration(String phoneNumber) async {
    await connect();

    // Отправляем handshake
    final handshakePayload = {
      "mt_instanceid": "63ae21a8-2417-484d-849b-0ae464a7b352",
      "userAgent": {
        "deviceType": "ANDROID",
        "appVersion": "25.14.2",
        "osVersion": "Android 14",
        "timezone": "Europe/Moscow",
        "screen": "440dpi 440dpi 1080x2072",
        "pushDeviceType": "GCM",
        "arch": "x86_64",
        "locale": "ru",
        "buildNumber": 6442,
        "deviceName": "unknown Android SDK built for x86_64",
        "deviceLocale": "en",
      },
      "clientSessionId": 8,
      "deviceId": "d53058ab998c3bdd",
    };

    print('🤝 Отправляем handshake (opcode=6)...');
    print('📦 Handshake payload:');
    print(_formatPayload(handshakePayload));
    final handshakeResponse = await _sendMessage(6, handshakePayload);
    print('📨 Ответ от handshake:');
    print(_formatPayload(handshakeResponse));

    // Проверяем ошибки
    if (handshakeResponse is Map) {
      final err = handshakeResponse['payload']?['error'];
      if (err != null) {
        print('❌ Ошибка handshake: $err');
      }
    }

    // Отправляем START_AUTH
    final authPayload = {"type": "START_AUTH", "phone": phoneNumber};
    print('🚀 Отправляем START_AUTH (opcode=17)...');
    print('📦 START_AUTH payload:');
    print(_formatPayload(authPayload));
    final response = await _sendMessage(17, authPayload);

    print('📨 Ответ от START_AUTH:');
    print(_formatPayload(response));

    // Проверяем ошибки
    if (response is Map) {
      // Проверяем ошибку в payload или в корне ответа
      final payload = response['payload'] ?? response;
      final err = payload['error'] ?? response['error'];

      if (err != null) {
        // Обрабатываем конкретную ошибку limit.violate
        if (err.toString().contains('limit.violate') ||
            err.toString().contains('error.limit.violate')) {
          throw Exception(
            'У вас кончились попытки на код, попробуйте позже...',
          );
        }

        // Для других ошибок используем сообщение от сервера или общее
        final message =
            payload['localizedMessage'] ??
            payload['message'] ??
            payload['description'] ??
            'Ошибка START_AUTH: $err';
        throw Exception(message);
      }
    }

    // Извлекаем токен из ответа (как в register.py)
    if (response is Map) {
      final payload = response['payload'] ?? response;
      final token = payload['token'] ?? response['token'];
      if (token != null) {
        return token as String;
      }
    }

    throw Exception('Не удалось получить токен из ответа сервера');
  }

  Future<String> verifyCode(String token, String code) async {
    final verifyPayload = {
      "verifyCode": code,
      "token": token,
      "authTokenType": "CHECK_CODE",
    };

    print('🔍 Проверяем код (opcode=18)...');
    print('📦 CHECK_CODE payload:');
    print(_formatPayload(verifyPayload));
    final response = await _sendMessage(18, verifyPayload);

    print('📨 Ответ от CHECK_CODE:');
    print(_formatPayload(response));

    // Проверяем ошибки
    if (response is Map) {
      // Проверяем ошибку в payload или в корне ответа
      final payload = response['payload'] ?? response;
      final err = payload['error'] ?? response['error'];

      if (err != null) {
        // Обрабатываем конкретную ошибку неправильного кода
        if (err.toString().contains('verify.code.wrong') ||
            err.toString().contains('wrong.code') ||
            err.toString().contains('code.wrong')) {
          throw Exception('Неверный код');
        }

        // Для других ошибок используем сообщение от сервера или общее
        final message =
            payload['localizedMessage'] ??
            payload['message'] ??
            payload['title'] ??
            'Ошибка CHECK_CODE: $err';
        throw Exception(message);
      }
    }

    // Извлекаем register токен (как в register.py)
    if (response is Map) {
      final tokenSrc = response['payload'] ?? response;
      final tokenAttrs = tokenSrc['tokenAttrs'];

      // Проверяем, есть ли LOGIN токен - значит аккаунт уже существует
      if (tokenAttrs is Map && tokenAttrs['LOGIN'] is Map) {
        throw Exception('ACCOUNT_EXISTS');
      }

      if (tokenAttrs is Map && tokenAttrs['REGISTER'] is Map) {
        final registerToken = tokenAttrs['REGISTER']['token'];
        if (registerToken != null) {
          return registerToken as String;
        }
      }
    }

    throw Exception('Не удалось получить токен регистрации из ответа сервера');
  }

  Future<void> completeRegistration(String registerToken) async {
    final registerPayload = {
      "lastName": "User",
      "token": registerToken,
      "firstName": "Komet",
      "tokenType": "REGISTER",
    };

    print('🎉 Завершаем регистрацию (opcode=23)...');
    print('📦 REGISTER payload:');
    print(_formatPayload(registerPayload));
    final response = await _sendMessage(23, registerPayload);

    print('📨 Ответ от REGISTER:');
    print(_formatPayload(response));

    // Проверяем ошибки
    if (response is Map) {
      final err = response['payload']?['error'];
      if (err != null) {
        throw Exception('Ошибка REGISTER: $err');
      }

      // Извлекаем финальный токен
      final payload = response['payload'] ?? response;
      final finalToken = payload['token'] ?? response['token'];
      if (finalToken != null) {
        print('✅ Регистрация успешна, финальный токен: $finalToken');
        return;
      }
    }

    throw Exception('Регистрация не удалась');
  }

  void disconnect() {
    try {
      _isConnected = false;
      _pingTimer?.cancel();
      _socketSubscription?.cancel();
      _socket?.close();
      print('🔌 Отключено от сервера');
    } catch (e) {
      print('❌ Ошибка отключения: $e');
    }
  }
}
