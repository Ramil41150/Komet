/// Продолжительности анимаци1
class AppDurations {
  AppDurations._();

  /// нет анимки
  static const Duration instant = Duration.zero;

  /// микро анимация
  static const Duration animation50 = Duration(milliseconds: 50);

  /// быстрая анимация
  static const Duration animation100 = Duration(milliseconds: 100);

  /// короткая анимация, где то в fade эффектах юзается
  static const Duration animation150 = Duration(milliseconds: 150);

  /// стандартная микро анимация
  static const Duration animation200 = Duration(milliseconds: 200);

  /// переход между экранами
  static const Duration animation250 = Duration(milliseconds: 250);

  /// fade переходы и что то там
  static const Duration animation300 = Duration(milliseconds: 300);

  /// время появления панели сообщений
  static const Duration animation350 = Duration(milliseconds: 350);

  /// Скрол или подсветка соо
  static const Duration animation400 = Duration(milliseconds: 400);

  /// задержка перед действием и подсветка соо
  static const Duration animation500 = Duration(milliseconds: 500);

  /// помоему в загрузке
  static const Duration animation900 = Duration(milliseconds: 900);

  /// pulse анимация для сообщения или цикл
  static const Duration animation1000 = Duration(milliseconds: 1000);

  /// Задержка debounce для поиска и ввода текст
  static const Duration debounce = Duration(milliseconds: 300);

  /// специальная задержка для меню с эмодзи, а прошлое меню тогда нахуя...🥀
  static const Duration longPress = Duration(milliseconds: 350);

  /// Короткий Snackbar
  static const Duration snackbarShort = Duration(seconds: 2);

  /// Стандартный Snackbar
  static const Duration snackbarDefault = Duration(seconds: 3);

  /// Таймаут отправки статуса "печатает"
  static const Duration typingTimeout = Duration(seconds: 9);

  /// спустя сколько времени перестать отправлять "печатает"
  static const Duration typingDecay = Duration(seconds: 11);

  /// Таймаут запросов
  static const Duration networkTimeout = Duration(seconds: 10);

  /// Длинный таймаут
  static const Duration networkTimeoutLong = Duration(seconds: 15);

  /// Задержка скрытия контролов видеоплеера
  static const Duration hideControlsDelay = Duration(seconds: 3);

  /// Шаг перемотки видео
  static const Duration seekStep = Duration(seconds: 10);

  /// обновление видео
  static const Duration positionUpdateInterval = Duration(milliseconds: 100);

  /// проверка состояния
  static const Duration periodicCheck = Duration(seconds: 1);
}
