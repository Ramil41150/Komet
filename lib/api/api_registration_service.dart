import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:es_compression/lz4.dart';
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
  Lz4Codec? _lz4Codec;
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
      final payload = msgpack.deserialize(data);
      print('✅ Msgpack десериализация успешна');

      // Проверяем, что получили валидный результат (не просто число)
      if (payload is int && payload < 0) {
        print(
          '⚠️  Получено отрицательное число вместо Map - возможно данные все еще сжаты',
        );
        return null;
      }
      return payload;
    } catch (e) {
      print('❌ Ошибка десериализации msgpack: $e');
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
      // Сначала пробуем LZ4 декомпрессию как в register.py
      Uint8List decompressedBytes = payloadBytes;

      // Если данные сжаты (compFlag != 0), пробуем LZ4 block декомпрессию
      if (isCompressed && payloadBytes.length > 4) {
        print('📦 Данные помечены как сжатые (compFlag != 0)');

        // Пробуем LZ4 block декомпрессию через FFI (как в register.py)
        try {
          if (_lz4BlockDecompress != null) {
            print('📦 Попытка LZ4 block декомпрессии через FFI...');

            // В register.py используется фиксированный uncompressed_size=99999
            // И данные используются полностью (без пропуска первых 4 байт)
            // Но в packet_framer.dart при compFlag пропускаются первые 4 байта
            // Попробуем оба варианта

            // Вариант 1: как в register.py - используем все данные с фиксированным размером
            // Увеличиваем размер для больших ответов (как в register.py используется 99999, но может быть недостаточно)
            int uncompressedSize =
                500000; // Увеличенный размер для больших ответов
            Uint8List compressedData = payloadBytes;

            print(
              '📦 Попытка 1: Используем все данные с uncompressed_size=99999 (как в register.py)',
            );
            try {
              if (uncompressedSize > 0 && uncompressedSize < 10 * 1024 * 1024) {
                final srcSize = compressedData.length;
                final srcPtr = malloc.allocate<Uint8>(srcSize);
                final dstPtr = malloc.allocate<Uint8>(uncompressedSize);

                try {
                  final srcList = srcPtr.asTypedList(srcSize);
                  srcList.setAll(0, compressedData);

                  final result = _lz4BlockDecompress!(
                    srcPtr,
                    dstPtr,
                    srcSize,
                    uncompressedSize,
                  );

                  if (result > 0) {
                    final actualSize = result;
                    final dstList = dstPtr.asTypedList(actualSize);
                    decompressedBytes = Uint8List.fromList(dstList);
                    print(
                      '✅ LZ4 block декомпрессия успешна: $srcSize → ${decompressedBytes.length} байт',
                    );
                    print(
                      '📦 Декомпрессированные данные (hex, первые 64 байта):',
                    );
                    final preview = decompressedBytes.length > 64
                        ? decompressedBytes.sublist(0, 64)
                        : decompressedBytes;
                    print(_bytesToHex(preview));
                    // Успешная декомпрессия - возвращаем результат
                    return _deserializeMsgpack(decompressedBytes);
                  } else {
                    throw Exception('LZ4 декомпрессия вернула ошибку: $result');
                  }
                } finally {
                  malloc.free(srcPtr);
                  malloc.free(dstPtr);
                }
              }
            } catch (e1) {
              print('⚠️  Вариант 1 не сработал: $e1');

              // Вариант 2: пропускаем первые 4 байта (как в packet_framer.dart)
              if (payloadBytes.length > 4) {
                print('📦 Попытка 2: Пропускаем первые 4 байта...');
                compressedData = payloadBytes.sublist(4);
                print('📦 Сжатые данные (hex, первые 32 байта):');
                final firstBytes = compressedData.length > 32
                    ? compressedData.sublist(0, 32)
                    : compressedData;
                print(_bytesToHex(firstBytes));

                try {
                  final srcSize = compressedData.length;
                  final srcPtr = malloc.allocate<Uint8>(srcSize);
                  final dstPtr = malloc.allocate<Uint8>(uncompressedSize);

                  try {
                    final srcList = srcPtr.asTypedList(srcSize);
                    srcList.setAll(0, compressedData);

                    final result = _lz4BlockDecompress!(
                      srcPtr,
                      dstPtr,
                      srcSize,
                      uncompressedSize,
                    );

                    if (result > 0) {
                      final actualSize = result;
                      final dstList = dstPtr.asTypedList(actualSize);
                      decompressedBytes = Uint8List.fromList(dstList);
                      print(
                        '✅ LZ4 block декомпрессия успешна (вариант 2): $srcSize → ${decompressedBytes.length} байт',
                      );
                      print(
                        '📦 Декомпрессированные данные (hex, первые 64 байта):',
                      );
                      final preview = decompressedBytes.length > 64
                          ? decompressedBytes.sublist(0, 64)
                          : decompressedBytes;
                      print(_bytesToHex(preview));
                      // Успешная декомпрессия - возвращаем результат
                      return _deserializeMsgpack(decompressedBytes);
                    } else {
                      throw Exception(
                        'LZ4 декомпрессия вернула ошибку: $result',
                      );
                    }
                  } finally {
                    malloc.free(srcPtr);
                    malloc.free(dstPtr);
                  }
                } catch (e2) {
                  print('⚠️  Вариант 2 не сработал: $e2');
                  throw e2; // Пробрасываем ошибку дальше
                }
              } else {
                throw e1;
              }
            }
          } else {
            // Пробуем через es_compression (frame format)
            final compressedData = payloadBytes.sublist(4);
            if (_lz4Codec == null) {
              print('📦 Инициализация Lz4Codec (frame format)...');
              _lz4Codec = Lz4Codec();
              print('✅ Lz4Codec инициализирован успешно');
            }

            print('📦 Попытка декомпрессии через es_compression...');
            final decoded = _lz4Codec!.decode(compressedData);
            decompressedBytes = decoded is Uint8List
                ? decoded
                : Uint8List.fromList(decoded);
            print(
              '✅ LZ4 декомпрессия успешна: ${compressedData.length} → ${decompressedBytes.length} байт',
            );
          }
        } catch (lz4Error) {
          print('⚠️  LZ4 декомпрессия не применена: $lz4Error');
          print('📦 Тип ошибки: ${lz4Error.runtimeType}');
          print('📦 Используем сырые данные...');
          decompressedBytes = payloadBytes;
        }
      } else {
        // Данные не сжаты или нет флага - пробуем LZ4 на всякий случай (как в register.py)
        print(
          '📦 Данные не помечены как сжатые, но пробуем LZ4 (как в register.py)...',
        );
        final firstBytes = payloadBytes.length > 32
            ? payloadBytes.sublist(0, 32)
            : payloadBytes;
        print(
          '📦 Первые ${firstBytes.length} байта payload (hex): ${_bytesToHex(firstBytes)}',
        );

        try {
          if (_lz4Codec == null) {
            print('📦 Инициализация Lz4Codec...');
            _lz4Codec = Lz4Codec();
            print('✅ Lz4Codec инициализирован успешно');
          }

          print('📦 Попытка декомпрессии ${payloadBytes.length} байт...');
          final decoded = _lz4Codec!.decode(payloadBytes);
          decompressedBytes = decoded is Uint8List
              ? decoded
              : Uint8List.fromList(decoded);
          print(
            '✅ LZ4 декомпрессия успешна: ${payloadBytes.length} → ${decompressedBytes.length} байт',
          );
        } catch (lz4Error) {
          // Если LZ4 не удалась (данные не сжаты), используем сырые данные
          print(
            '⚠️  LZ4 декомпрессия не применена (данные не сжаты): $lz4Error',
          );
          decompressedBytes = payloadBytes;
        }
      }

      return _deserializeMsgpack(decompressedBytes);
    } catch (e) {
      print('❌ Ошибка десериализации payload: $e');
      print('Stack trace: ${StackTrace.current}');
      return null;
    }
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
