

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gwid/api/api_service.dart';
import 'dart:convert';

class QrLoginScreen extends StatefulWidget {
  const QrLoginScreen({super.key});

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> {
  String? _token;
  String? _qrData;
  bool _isLoading = true;
  bool _isQrVisible = false;
  String? _error;

  Timer? _qrRefreshTimer; // Таймер для регенерации QR-кода (1 раз в минуту)
  Timer?
  _countdownTimer; // 👈 1. Таймер для обратного отсчета (1 раз в секунду)
  int _countdownSeconds = 60; // 👈 2. Переменная для хранения секунд

  @override
  void initState() {
    super.initState();
    _initializeAndStartTimers();
  }

  @override
  void dispose() {
    _qrRefreshTimer?.cancel();
    _countdownTimer?.cancel(); // 👈 3. Не забываем отменить второй таймер
    super.dispose();
  }


  Future<void> _initializeAndStartTimers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = ApiService.instance.token;
      if (token == null || token.isEmpty) {
        throw Exception("Не удалось получить токен авторизации.");
      }

      if (mounted) {
        _token = token;
        _regenerateQrData(); // Первичная генерация


        _qrRefreshTimer?.cancel();
        _qrRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
          _regenerateQrData();
        });


        _startCountdownTimer();

        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }


  void _regenerateQrData() {
    if (_token == null) return;
    final data = {
      "type": "komet_auth_v1",
      "token": _token!,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
    if (mounted) {
      setState(() {
        _qrData = jsonEncode(data);
        _countdownSeconds = 60; // Сбрасываем счетчик на 60
      });
    }
  }


  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_countdownSeconds > 0) {
            _countdownSeconds--;
          } else {


            _countdownSeconds = 60;
          }
        });
      }
    });
  }

  void _toggleQrVisibility() {
    if (_token != null) {
      setState(() {
        _isQrVisible = !_isQrVisible;
      });
    }
  }



  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text(
              "Ошибка загрузки данных",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _initializeAndStartTimers,
              icon: const Icon(Icons.refresh),
              label: const Text("Повторить"),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQrDisplay(),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _toggleQrVisibility,
          icon: Icon(
            _isQrVisible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          label: Text(
            _isQrVisible ? "Скрыть QR-код" : "Показать QR-код для входа",
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQrDisplay() {
    final colors = Theme.of(context).colorScheme;

    if (!_isQrVisible) {
      return Center(
        child: Column(
          children: [
            Icon(
              Icons.qr_code_scanner_rounded,
              size: 150,
              color: colors.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              "QR-код скрыт",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              "Нажмите кнопку ниже, чтобы отобразить его.",
              style: TextStyle(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }


    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  spreadRadius: 2,
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: _qrData!,
              version: QrVersions.auto,
              size: 280.0,
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: colors.primary,
              ),
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: colors.primary,
              ),
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_outlined,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "Обновится через: $_countdownSeconds сек.",
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Вход по QR-коду")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.errorContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gpp_bad_outlined, color: Colors.red, size: 32),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Любой, кто отсканирует этот код, получит полный доступ к вашему аккаунту. Не показывайте его посторонним.",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _buildContent(),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
