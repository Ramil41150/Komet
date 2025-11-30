import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pinput/pinput.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/screens/chats_screen.dart';
import 'package:gwid/screens/password_auth_screen.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;
  final String otpToken;

  const OTPScreen({
    super.key,
    required this.phoneNumber,
    required this.otpToken,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  StreamSubscription? _apiSubscription;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _apiSubscription = ApiService.instance.messages.listen((message) {

      if (message['type'] == 'password_required' && mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PasswordAuthScreen(),
              ),
            );
          }
        });
        return;
      }

      if (message['opcode'] == 18 && mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        });

        final payload = message['payload'];
        print('Полный payload при авторизации: $payload');
        if (payload != null &&
            payload['tokenAttrs']?['LOGIN']?['token'] != null) {
          final String finalToken = payload['tokenAttrs']['LOGIN']['token'];
          final userId = payload['tokenAttrs']?['LOGIN']?['userId'];
          print('Успешная авторизация! Токен: $finalToken, UserID: $userId');

          ApiService.instance
              .saveToken(finalToken, userId: userId?.toString())
              .then((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Код верный! Вход выполнен.'),
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(10),
                  ),
                );
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const ChatsScreen()),
                  (route) => false,
                );
              });
        } else {
          _handleIncorrectCode();
        }
      }
    });
  }

  void _verifyCode(String code) async {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _isLoading = true);
      }
    });

    try {
      await ApiService.instance.verifyCode(widget.otpToken, code);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка подключения: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }

  void _handleIncorrectCode() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Неверный код. Попробуйте снова.'),
        backgroundColor: Theme.of(context).colorScheme.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10),
      ),
    );
    _pinController.clear();
    _pinFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 60,
      textStyle: TextStyle(fontSize: 22, color: colors.onSurface),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение')),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Код отправлен на номер',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.phoneNumber,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Pinput(
                    length: 6,
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    autofocus: true,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: defaultPinTheme.copyWith(
                      decoration: defaultPinTheme.decoration!.copyWith(
                        border: Border.all(color: colors.primary, width: 2),
                      ),
                    ),
                    onCompleted: (pin) => _verifyCode(pin),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    _apiSubscription?.cancel();
    super.dispose();
  }
}
