import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_location.dart';

class LocationStorage {
  static const String _kKey = 'poc_saved_locations';

  Future<List<SavedLocation>> getLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_kKey);
    if (data == null || data.isEmpty) return [];
    try {
      return SavedLocation.decodeList(data);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocations(List<SavedLocation> locations) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = SavedLocation.encodeList(locations);
    await prefs.setString(_kKey, encoded);
  }

  Future<void> addLocation(SavedLocation location) async {
    final current = await getLocations();
    final updated = List<SavedLocation>.from(current)..add(location);
    await saveLocations(updated);
  }
}


