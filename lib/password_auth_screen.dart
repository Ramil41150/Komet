import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/chats_screen.dart';

class PasswordAuthScreen extends StatefulWidget {
  const PasswordAuthScreen({super.key});

  @override
  State<PasswordAuthScreen> createState() => _PasswordAuthScreenState();
}

class _PasswordAuthScreenState extends State<PasswordAuthScreen> {
  final TextEditingController _passwordController = TextEditingController();
  StreamSubscription? _apiSubscription;
  bool _isLoading = false;
  String? _hint;
  String? _email;

  @override
  void initState() {
    super.initState();


    _apiSubscription = ApiService.instance.messages.listen((message) {
      if (message['type'] == 'password_required' && mounted) {
        setState(() {
          _hint = message['hint'];
          _email = message['email'];
        });
      }


      if (message['opcode'] == 115 && message['cmd'] == 1 && mounted) {
        final payload = message['payload'];
        if (payload != null &&
            payload['tokenAttrs']?['LOGIN']?['token'] != null) {
          final String finalToken = payload['tokenAttrs']['LOGIN']['token'];
          final userId = payload['tokenAttrs']?['LOGIN']?['userId'];

          print(
            'Успешная аутентификация паролем! Токен: $finalToken, UserID: $userId',
          );


          ApiService.instance
              .saveToken(finalToken, userId: userId?.toString())
              .then((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Пароль верный! Вход выполнен.'),
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(10),
                  ),
                );


                ApiService.instance.clearPasswordAuthData();

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const ChatsScreen()),
                  (route) => false,
                );
              });
        }
      }


      if (message['opcode'] == 115 && message['cmd'] == 3 && mounted) {
        setState(() {
          _isLoading = false;
        });

        final error = message['payload'];
        String errorMessage = 'Ошибка аутентификации';

        if (error != null) {
          if (error['localizedMessage'] != null) {
            errorMessage = error['localizedMessage'];
          } else if (error['message'] != null) {
            errorMessage = error['message'];
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    });


    final authData = ApiService.instance.getPasswordAuthData();
    _hint = authData['hint'];
    _email = authData['email'];
  }

  void _submitPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите пароль'),
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(10),
        ),
      );
      return;
    }

    final authData = ApiService.instance.getPasswordAuthData();
    final trackId = authData['trackId'];

    if (trackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ошибка: отсутствует идентификатор сессии'),
          backgroundColor: Theme.of(context).colorScheme.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(10),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.instance.sendPassword(trackId, password);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отправки пароля: ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ввод пароля'),
        backgroundColor: colors.surface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  if (_email != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Аккаунт защищен паролем',
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _email!,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                          if (_hint != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Подсказка: $_hint',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  const SizedBox(height: 30),


                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      hintText: 'Введите пароль от аккаунта',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock),
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                    ),
                    onSubmitted: (_) => _submitPassword(),
                  ),

                  const SizedBox(height: 24),


                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _submitPassword,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Войти'),
                    ),
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
    _passwordController.dispose();
    _apiSubscription?.cancel();
    super.dispose();
  }
}
