import '../models/saved_location.dart';
import '../utils/pref_utiles.dart';

class LocationStorage {
  static const String _kKey = 'poc_saved_locations';
  final PrefUtils _prefUtils = PrefUtils();

  Future<List<SavedLocation>> getLocations() async {
    final prefs = await _prefUtils.getPrefs();
    final data = prefs.getString(_kKey);
    if (data == null || data.isEmpty) return [];
    try {
      return SavedLocation.decodeList(data);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocations(List<SavedLocation> locations) async {
    final prefs = await _prefUtils.getPrefs();
    final encoded = SavedLocation.encodeList(locations);
    await prefs.setString(_kKey, encoded);
  }

  Future<void> addLocation(SavedLocation location) async {
    final current = await getLocations();
    final updated = List<SavedLocation>.from(current)..add(location);
    await saveLocations(updated);
  }

  Future<void> removeLocation(SavedLocation location) async {
    final current = await getLocations();
    final updated = current
        .where((loc) => !_isSameLocation(loc, location))
        .toList();
    await saveLocations(updated);
  }

  bool _isSameLocation(SavedLocation a, SavedLocation b) {
    return a.name == b.name &&
        a.latitude == b.latitude &&
        a.longitude == b.longitude;
  }
}
