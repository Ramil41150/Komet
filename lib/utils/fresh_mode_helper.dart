import 'package:gwid/consts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FreshModeHelper {
  static bool get isEnabled => AppSettings.startFresh;

  static Future<SharedPreferences> getSharedPreferences() async {
    if (isEnabled) {
      return SharedPreferences.getInstance().then((prefs) {
        prefs.clear();
        return prefs;
      });
    }
    return SharedPreferences.getInstance();
  }

  static bool shouldSkipSave() => isEnabled;
  static bool shouldSkipLoad() => isEnabled;
}
