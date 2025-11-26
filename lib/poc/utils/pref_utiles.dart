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
  static const String _thresholdKey = 'dev_threshold_value';
  static const String _stableSampleKey = 'dev_required_stable_sample';
  static const String _selectedPlatformKey = 'selected_feeding_platform';

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

  Future<void> setThresholdValue(int value) async {
    // Clamp value between -100 and -40 dBm
    final clampedValue = value.clamp(-100, -40).toInt();
    if (_sharedPreferences == null) {
      await init();
    }
    await _sharedPreferences!.setInt(_thresholdKey, clampedValue);
  }

  int getThresholdValue() {
    try {
      if (_sharedPreferences == null) {
        return -70;
      }
      final storedValue = _sharedPreferences!.getInt(_thresholdKey);
      if (storedValue == null) return -70;
      return storedValue.clamp(-100, -40).toInt();
    } catch (e) {
      return -70;
    }
  }

  Future<void> setRequiredStableSample(int value) async {
    final normalizedValue = value <= 0 ? 1 : value;
    if (_sharedPreferences == null) {
      await init();
    }
    await _sharedPreferences!.setInt(_stableSampleKey, normalizedValue);
  }

  Future<SharedPreferences> getPrefs() async {
    if (_sharedPreferences == null) {
      await init();
    }
    return _sharedPreferences!;
  }

  int getRequiredStableSample() {
    try {
      if (_sharedPreferences == null) {
        return 5;
      }
      final storedValue = _sharedPreferences!.getInt(_stableSampleKey);
      if (storedValue == null || storedValue <= 0) return 5;
      return storedValue;
    } catch (e) {
      return 5;
    }
  }

  Future<void> setSelectedPlatform(String value) async {
    if (_sharedPreferences == null) {
      await init();
    }
    await _sharedPreferences!.setString(_selectedPlatformKey, value);
  }

  String? getSelectedPlatform() {
    try {
      if (_sharedPreferences == null) {
        return null;
      }
      return _sharedPreferences!.getString(_selectedPlatformKey);
    } catch (e) {
      return null;
    }
  }
}
