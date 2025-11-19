import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/otp_screen.dart';
import 'package:gwid/proxy_service.dart';
import 'package:gwid/screens/settings/proxy_settings_screen.dart';
import 'package:gwid/screens/settings/session_spoofing_screen.dart';
import 'package:gwid/token_auth_screen.dart';
import 'package:gwid/tos_screen.dart'; // Импорт экрана ToS
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class Country {
  final String name;
  final String code;
  final String flag;
  final String mask;
  final int digits;

  const Country({
    required this.name,
    required this.code,
    required this.flag,
    required this.mask,
    required this.digits,
  });
}

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen>
    with TickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();

  static const List<Country> _countries = [
    Country(
      name: 'Россия',
      code: '+7',
      flag: '🇷🇺',
      mask: '+7 (###) ###-##-##',
      digits: 10,
    ),
    Country(
      name: 'Беларусь',
      code: '+375',
      flag: '🇧🇾',
      mask: '+375 (##) ###-##-##',
      digits: 9,
    ),
  ];

  Country _selectedCountry = _countries[0];
  late MaskTextInputFormatter _maskFormatter;
  bool _isButtonEnabled = false;
  bool _isLoading = false;
  bool _hasCustomAnonymity = false;
  bool _hasProxyConfigured = false;
  StreamSubscription? _apiSubscription;
  bool _showContent = false;
  bool _isTosAccepted = false; // Состояние для отслеживания принятия соглашения

  late final AnimationController _animationController;
  late final Animation<Alignment> _topAlignmentAnimation;
  late final Animation<Alignment> _bottomAlignmentAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );

    _topAlignmentAnimation =
        AlignmentTween(
          begin: Alignment.topLeft,
          end: Alignment.topRight,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
    _bottomAlignmentAnimation =
        AlignmentTween(
          begin: Alignment.bottomRight,
          end: Alignment.bottomLeft,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );

    _animationController.repeat(reverse: true);

    _initializeMaskFormatter();
    _checkAnonymitySettings();
    _checkProxySettings();
    _phoneController.addListener(_onPhoneChanged);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showContent = true);
    });

    _apiSubscription = ApiService.instance.messages.listen((message) {
      if (message['opcode'] == 17 && mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isLoading = false);
        });
        final payload = message['payload'];
        if (payload != null && payload['token'] != null) {
          final String token = payload['token'];
          final String fullPhoneNumber =
              _selectedCountry.code + _maskFormatter.getUnmaskedText();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  OTPScreen(phoneNumber: fullPhoneNumber, otpToken: token),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось запросить код. Попробуйте позже.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  void _initializeMaskFormatter() {
    final mask = _selectedCountry.mask
        .replaceFirst(RegExp(r'^\+\d+\s?'), '')
        .trim();
    _maskFormatter = MaskTextInputFormatter(
      mask: mask,
      filter: {"#": RegExp(r'[0-9]')},
      type: MaskAutoCompletionType.lazy,
    );
  }

  void _onPhoneChanged() {
    final text = _phoneController.text;
    if (text.isNotEmpty) {
      Country? detectedCountry = _detectCountryFromInput(text);
      if (detectedCountry != null && detectedCountry != _selectedCountry) {
        if (_shouldClearFieldForCountry(text, detectedCountry)) {
          _phoneController.clear();
        }
        setState(() {
          _selectedCountry = detectedCountry;
          _initializeMaskFormatter();
        });
      }
    }
    final isFull =
        _maskFormatter.getUnmaskedText().length == _selectedCountry.digits;
    if (isFull != _isButtonEnabled) {
      setState(() => _isButtonEnabled = isFull);
    }
  }

  bool _shouldClearFieldForCountry(String input, Country country) {
    final cleanInput = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (country.code == '+7') {
      return !(cleanInput.startsWith('+7') || cleanInput.startsWith('7'));
    } else if (country.code == '+375') {
      return !(cleanInput.startsWith('+375') || cleanInput.startsWith('375'));
    }
    return true;
  }

  Country? _detectCountryFromInput(String input) {
    final cleanInput = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanInput.startsWith('+7') || cleanInput.startsWith('7')) {
      return _countries.firstWhere((c) => c.code == '+7');
    } else if (cleanInput.startsWith('+375') || cleanInput.startsWith('375')) {
      return _countries.firstWhere((c) => c.code == '+375');
    }
    return null;
  }

  void _onCountryChanged(Country? country) {
    if (country != null && country != _selectedCountry) {
      setState(() {
        _selectedCountry = country;
        _phoneController.clear();
        _initializeMaskFormatter();
        _isButtonEnabled = false;
      });
    }
  }

  void _checkAnonymitySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final anonymityEnabled = prefs.getBool('anonymity_enabled') ?? false;
    if (mounted) setState(() => _hasCustomAnonymity = anonymityEnabled);
  }

  Future<void> _checkProxySettings() async {
    final settings = await ProxyService.instance.loadProxySettings();
    if (mounted) {
      setState(() {
        _hasProxyConfigured = settings.isEnabled && settings.host.isNotEmpty;
      });
    }
  }

  void refreshProxySettings() {
    _checkProxySettings();
  }

  void _requestOtp() async {
    if (!_isButtonEnabled || _isLoading || !_isTosAccepted) return;
    setState(() => _isLoading = true);
    final String fullPhoneNumber =
        _selectedCountry.code + _maskFormatter.getUnmaskedText();
    try {
      ApiService.instance.errorStream.listen((error) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showErrorDialog(error);
        }
      });
      await ApiService.instance.requestOtp(fullPhoneNumber);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorDialog('Ошибка подключения: ${e.toString()}');
      }
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Ошибка валидации'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _topAlignmentAnimation.value,
                    end: _bottomAlignmentAnimation.value,
                    colors: [
                      Color.lerp(colors.surface, colors.primary, 0.2)!,
                      Color.lerp(colors.surface, colors.tertiary, 0.15)!,
                      colors.surface,
                      Color.lerp(colors.surface, colors.secondary, 0.15)!,
                      Color.lerp(colors.surface, colors.primary, 0.25)!,
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOut,
                      opacity: _showContent ? 1.0 : 0.0,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 48),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.primary.withOpacity(0.1),
                              ),
                              child: const Image(
                                image: AssetImage(
                                  'assets/images/komet_512.png',
                                ),
                                width: 75,
                                height: 75,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Komet',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              textStyle: textTheme.headlineLarge,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Введите номер телефона для входа',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              textStyle: textTheme.titleMedium,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 48),
                          _PhoneInput(
                            phoneController: _phoneController,
                            maskFormatter: _maskFormatter,
                            selectedCountry: _selectedCountry,
                            countries: _countries,
                            onCountryChanged: _onCountryChanged,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                value: _isTosAccepted,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _isTosAccepted = value ?? false;
                                  });
                                },
                                visualDensity: VisualDensity.compact,
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: GoogleFonts.manrope(
                                      textStyle: textTheme.bodySmall,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Я принимаю '),
                                      TextSpan(
                                        text: 'Пользовательское соглашение',
                                        style: TextStyle(
                                          color: colors.primary,
                                          decoration: TextDecoration.underline,
                                          decorationColor: colors.primary,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const TosScreen(),
                                              ),
                                            );
                                          },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _isButtonEnabled && _isTosAccepted
                                ? _requestOtp
                                : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              'Далее',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _isTosAccepted
                                ? () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const TokenAuthScreen(),
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.vpn_key_outlined),
                            label: Text(
                              'Альтернативные способы входа',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _AnonymityCard(isConfigured: _hasCustomAnonymity),
                          const SizedBox(height: 16),
                          _ProxyCard(isConfigured: _hasProxyConfigured),
                          const SizedBox(height: 24),
                          Text.rich(
                            textAlign: TextAlign.center,
                            TextSpan(
                              style: GoogleFonts.manrope(
                                textStyle: textTheme.bodySmall,
                                color: colors.onSurfaceVariant.withOpacity(0.8),
                              ),
                              children: [
                                const TextSpan(
                                  text:
                                      'Используя Komet, вы принимаете на себя всю ответственность за использование стороннего клиента.\n',
                                ),
                                TextSpan(
                                  text: '@TeamKomet',
                                  style: TextStyle(
                                    color: colors.primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: colors.primary,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () async {
                                      final Uri url = Uri.parse(
                                        'https://t.me/TeamKomet',
                                      );
                                      if (!await launchUrl(url)) {
                                        debugPrint('Could not launch $url');
                                      }
                                    },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: colors.scrim.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Отправляем код...',
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    _apiSubscription?.cancel();
    super.dispose();
  }
}

class _PhoneInput extends StatelessWidget {
  final TextEditingController phoneController;
  final MaskTextInputFormatter maskFormatter;
  final Country selectedCountry;
  final List<Country> countries;
  final ValueChanged<Country?> onCountryChanged;

  const _PhoneInput({
    required this.phoneController,
    required this.maskFormatter,
    required this.selectedCountry,
    required this.countries,
    required this.onCountryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: phoneController,
      inputFormatters: [maskFormatter],
      keyboardType: TextInputType.number,
      style: GoogleFonts.manrope(
        textStyle: Theme.of(context).textTheme.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: maskFormatter.getMask()?.replaceAll('#', '0'),
        prefixIcon: _CountryPicker(
          selectedCountry: selectedCountry,
          countries: countries,
          onCountryChanged: onCountryChanged,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      autofocus: true,
    );
  }
}

class _CountryPicker extends StatelessWidget {
  final Country selectedCountry;
  final List<Country> countries;
  final ValueChanged<Country?> onCountryChanged;

  const _CountryPicker({
    required this.selectedCountry,
    required this.countries,
    required this.onCountryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Country>(
          value: selectedCountry,
          onChanged: onCountryChanged,
          icon: Icon(Icons.keyboard_arrow_down, color: colors.onSurfaceVariant),
          items: countries.map((Country country) {
            return DropdownMenuItem<Country>(
              value: country,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.flag, style: textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text(
                    country.code,
                    style: GoogleFonts.manrope(
                      textStyle: textTheme.titleMedium,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _AnonymityCard extends StatelessWidget {
  final bool isConfigured;
  const _AnonymityCard({required this.isConfigured});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color cardColor = isConfigured
        ? colors.secondaryContainer
        : colors.surfaceContainerHighest.withOpacity(0.5);
    final Color onCardColor = isConfigured
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final IconData icon = isConfigured
        ? Icons.verified_user_outlined
        : Icons.visibility_outlined;

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outline.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: onCardColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConfigured
                        ? 'Активны кастомные настройки анонимности'
                        : 'Настройте анонимность для скрытия данных',
                    style: GoogleFonts.manrope(
                      textStyle: textTheme.bodyMedium,
                      color: onCardColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isConfigured
                  ? FilledButton.tonalIcon(
                      onPressed: _navigateToSpoofingScreen(context),
                      icon: const Icon(Icons.settings, size: 18),
                      label: Text(
                        'Изменить настройки',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _navigateToSpoofingScreen(context),
                      icon: const Icon(Icons.visibility_off, size: 18),
                      label: Text(
                        'Настроить анонимность',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback _navigateToSpoofingScreen(BuildContext context) {
    return () {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const SessionSpoofingScreen()),
      );
    };
  }
}

class _ProxyCard extends StatelessWidget {
  final bool isConfigured;
  const _ProxyCard({required this.isConfigured});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color cardColor = isConfigured
        ? colors.secondaryContainer
        : colors.surfaceContainerHighest.withOpacity(0.5);
    final Color onCardColor = isConfigured
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final IconData icon = isConfigured ? Icons.vpn_key : Icons.vpn_key_outlined;

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outline.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: onCardColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConfigured
                        ? 'Прокси-сервер настроен и активен'
                        : 'Настройте прокси-сервер для подключения',
                    style: GoogleFonts.manrope(
                      textStyle: textTheme.bodyMedium,
                      color: onCardColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isConfigured
                  ? FilledButton.tonalIcon(
                      onPressed: _navigateToProxyScreen(context),
                      icon: const Icon(Icons.settings, size: 18),
                      label: Text(
                        'Изменить настройки',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _navigateToProxyScreen(context),
                      icon: const Icon(Icons.vpn_key, size: 18),
                      label: Text(
                        'Настроить прокси',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback _navigateToProxyScreen(BuildContext context) {
    return () async {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const ProxySettingsScreen()),
      );
      if (context.mounted) {
        final state = context.findAncestorStateOfType<_PhoneEntryScreenState>();
        state?.refreshProxySettings();
      }
    };
  }
}
