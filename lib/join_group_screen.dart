

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gwid/api/api_service.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final TextEditingController _linkController = TextEditingController();
  StreamSubscription? _apiSubscription;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _listenToApiMessages();
  }

  @override
  void dispose() {
    _linkController.dispose();
    _apiSubscription?.cancel();
    super.dispose();
  }

  void _listenToApiMessages() {
    _apiSubscription = ApiService.instance.messages.listen((message) {
      if (!mounted) return;


      if (message['type'] == 'group_join_success') {
        setState(() {
          _isLoading = false;
        });

        final payload = message['payload'];
        final chat = payload['chat'];
        final chatTitle = chat?['title'] ?? 'Группа';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Успешно присоединились к группе "$chatTitle"!'),
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
          ),
        );


        Navigator.of(context).pop();
      }


      if (message['cmd'] == 3 && message['opcode'] == 57) {
        setState(() {
          _isLoading = false;
        });

        final errorPayload = message['payload'];
        String errorMessage = 'Неизвестная ошибка';
        if (errorPayload != null) {
          if (errorPayload['localizedMessage'] != null) {
            errorMessage = errorPayload['localizedMessage'];
          } else if (errorPayload['message'] != null) {
            errorMessage = errorPayload['message'];
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
  }


  String _extractJoinLink(String inputLink) {
    final link = inputLink.trim();


    if (link.startsWith('join/')) {
      print('Ссылка уже в правильном формате: $link');
      return link;
    }


    final joinIndex = link.indexOf('join/');
    if (joinIndex != -1) {
      final extractedLink = link.substring(joinIndex);
      print('Извлечена ссылка из полной ссылки: $link -> $extractedLink');
      return extractedLink;
    }


    print('Не найдено "join/" в ссылке: $link');
    return link;
  }

  void _joinGroup() async {
    final inputLink = _linkController.text.trim();

    if (inputLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите ссылку на группу'),
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


    final processedLink = _extractJoinLink(inputLink);


    if (!processedLink.contains('join/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Неверный формат ссылки. Ссылка должна содержать "join/"',
          ),
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

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.instance.joinGroupByLink(processedLink);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка присоединения к группе: ${e.toString()}'),
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
        title: const Text('Присоединиться к группе'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.group_add, color: colors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Присоединение к группе',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Введите ссылку на группу, чтобы присоединиться к ней. '
                        'Можно вводить как полную ссылку (https://max.ru/join/...), '
                        'так и короткую (join/...).',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),


                Text(
                  'Ссылка на группу',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _linkController,
                  decoration: InputDecoration(
                    labelText: 'Ссылка на группу',
                    hintText: 'https://max.ru/join/ABC123DEF456GHI789JKL',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.link),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.outline.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Формат ссылки:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Ссылка должна содержать "join/"\n'
                        '• После "join/" должен идти уникальный идентификатор группы\n'
                        '• Примеры:\n'
                        '  - https://max.ru/join/ABC123DEF456GHI789JKL\n'
                        '  - join/ABC123DEF456GHI789JKL',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _joinGroup,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.group_add),
                    label: Text(
                      _isLoading
                          ? 'Присоединение...'
                          : 'Присоединиться к группе',
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
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
}
