

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gwid/api/api_service.dart';
import 'utils/theme_provider.dart';

class ConnectionLifecycleManager extends StatefulWidget {
  final Widget child;

  const ConnectionLifecycleManager({super.key, required this.child});

  @override
  _ConnectionLifecycleManagerState createState() =>
      _ConnectionLifecycleManagerState();
}

class _ConnectionLifecycleManagerState extends State<ConnectionLifecycleManager>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _isReconnecting = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );
  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        print("✅ Приложение возобновлено.");
        ApiService.instance.setAppInForeground(true);
        ApiService.instance.sendNavEvent('WARM_START');
        _checkAndReconnectIfNeeded();
        break;
      case AppLifecycleState.paused:
        print("⏸️ Приложение свернуто.");
        ApiService.instance.setAppInForeground(false);
        ApiService.instance.sendNavEvent('GO', screenTo: 1, screenFrom: 150);
        break;
      default:
        break;
    }
  }

  Future<void> _checkAndReconnectIfNeeded() async {
    final hasToken = await ApiService.instance.hasToken();
    if (!hasToken) {
      print("🔒 Токен отсутствует, переподключение не требуется");
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    final bool actuallyConnected = ApiService.instance.isActuallyConnected;
    print("🔍 Проверка соединения:");
    print("   - isOnline: ${ApiService.instance.isOnline}");
    print("   - isActuallyConnected: $actuallyConnected");

    if (!actuallyConnected) {
      print("🔌 Соединение потеряно. Запускаем переподключение...");
      if (mounted) {
        setState(() {
          _isReconnecting = true;
        });
        _animationController.forward();
      }

      try {
        await ApiService.instance.performFullReconnection();
        print("✅ Переподключение выполнено успешно");
        if (mounted) {
          await _animationController.reverse();
          setState(() {
            _isReconnecting = false;
          });
        }
      } catch (e) {
        print("❌ Ошибка при переподключении: $e");
        Future.delayed(const Duration(seconds: 3), () async {
          if (!ApiService.instance.isActuallyConnected) {
            print("🔁 Повторная попытка переподключения...");
            try {
              await ApiService.instance.performFullReconnection();
              if (mounted) {
                await _animationController.reverse();
                setState(() {
                  _isReconnecting = false;
                });
              }
            } catch (e) {
              print("❌ Повторная попытка не удалась: $e");
              if (mounted) {
                await _animationController.reverse();
                setState(() {
                  _isReconnecting = false;
                });
              }
            }
          }
        });
      }
    } else {
      print("✅ Соединение активно, переподключение не требуется");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final accentColor = theme.accentColor;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [widget.child]),
    );
  }
}
