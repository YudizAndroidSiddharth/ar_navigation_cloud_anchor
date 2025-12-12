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

    // Check compass availability before subscribing
    final compassStream = FlutterCompass.events;
    if (compassStream == null) {
      debugPrint('⚠️ Compass is not available on this device');
      // Notify that compass is unavailable but continue with GPS tracking
      onHeading(null);
    } else {
      _compassSubscription = compassStream.listen(
        (event) {
          // Validate heading before passing it
          final heading = event.heading;
          if (heading != null && heading.isFinite) {
            onHeading(heading);
          } else {
            debugPrint('⚠️ Invalid compass heading received: $heading');
            onHeading(null);
          }
        },
        onError: (error, stackTrace) {
          debugPrint('❌ Compass stream error: $error');
          debugPrint('Stack trace: $stackTrace');
          // Notify error but continue
          onHeading(null);
        },
        cancelOnError: false, // Keep stream alive even on errors
      );
      debugPrint('✅ Compass tracking started');
    }
    debugPrint('✅ GPS tracking started');
  }

  Future<void> stop({required FilteredLocationService locationService}) async {
    debugPrint('🛑 Stopping GPS and compass tracking');

    try {
      // Cancel compass subscription first to stop compass updates immediately
      await _compassSubscription?.cancel();
      _compassSubscription = null;
      debugPrint('✅ Compass subscription cancelled');
    } catch (e) {
      debugPrint('⚠️ Error cancelling compass subscription: $e');
    }

    try {
      // Cancel position subscription
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      debugPrint('✅ GPS position subscription cancelled');
    } catch (e) {
      debugPrint('⚠️ Error cancelling position subscription: $e');
    }

    try {
      // Stop location service
      await locationService.stop();
      debugPrint('✅ Location service stopped');
    } catch (e) {
      debugPrint('⚠️ Error stopping location service: $e');
    }

    debugPrint('✅ GPS and compass tracking stopped');
  }
}
