import 'package:flutter/foundation.dart';

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
      final locations = SavedLocation.decodeList(data);
      // Validate and filter out invalid locations
      return locations.where((loc) {
        final isValid = loc.latitude.isFinite &&
            loc.longitude.isFinite &&
            loc.latitude >= -90 &&
            loc.latitude <= 90 &&
            loc.longitude >= -180 &&
            loc.longitude <= 180 &&
            loc.name.isNotEmpty;
        if (!isValid) {
          // Log invalid location for debugging
          debugPrint(
            '⚠️ Invalid location found and filtered: ${loc.name} '
            '(${loc.latitude}, ${loc.longitude})',
          );
        }
        return isValid;
      }).toList();
    } catch (e) {
      debugPrint('❌ Error loading locations: $e');
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
