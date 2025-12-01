import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../utils/geo_utils.dart';
import 'filtered_location_service.dart';

class GpsNavigationService {
  StreamSubscription<LatLng>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  Future<void> startTracking({
    required FilteredLocationService locationService,
    required void Function(LatLng position) onPosition,
    required void Function(double? heading) onHeading,
  }) async {
    debugPrint('🛰️ Starting GPS tracking...');
    await locationService.start();

    await _positionSubscription?.cancel();
    _positionSubscription = locationService.filteredPosition$.listen(
      (position) {
        debugPrint(
          '📍 GPS position callback: lat=${position.lat.toStringAsFixed(6)}, lng=${position.lng.toStringAsFixed(6)}',
        );
        onPosition(position);
      },
      onError: (error, stackTrace) {
        debugPrint('❌ GPS position stream error: $error');
        debugPrint('Stack trace: $stackTrace');
      },
      cancelOnError: false,
    );

    await _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen(
      (event) => onHeading(event.heading),
      onError: (error, stackTrace) {
        debugPrint('❌ Compass stream error: $error');
      },
    );
    debugPrint('✅ GPS tracking started');
  }

  Future<void> stop({required FilteredLocationService locationService}) async {
    await _positionSubscription?.cancel();
    await _compassSubscription?.cancel();
    await locationService.stop();
  }
}
