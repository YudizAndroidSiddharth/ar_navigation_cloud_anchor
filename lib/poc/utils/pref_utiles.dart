import 'package:shared_preferences/shared_preferences.dart';

class PrefUtils {
  PrefUtils._privateConstructor() {
    init();
  }

  static final PrefUtils _instance = PrefUtils._privateConstructor();

  factory PrefUtils() {
    return _instance;
  }

  static SharedPreferences? _sharedPreferences;

  Future<void> init() async {
    _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  // Balance methods
  static const String _balanceKey = 'available_balance';

  Future<void> setAvailableBalance(int value) async {
    if (_sharedPreferences == null) {
      await init();
    }
    await _sharedPreferences!.setInt(_balanceKey, value);
  }

  int getAvailableBalance() {
    try {
      if (_sharedPreferences == null) {
        return 0;
      }
      return _sharedPreferences!.getInt(_balanceKey) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // Add other existing methods here (tokens, userId, etc.) as needed
}
