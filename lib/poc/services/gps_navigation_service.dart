import 'dart:async';

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
    await locationService.start();

    await _positionSubscription?.cancel();
    _positionSubscription = locationService.filteredPosition$.listen(
      onPosition,
    );

    await _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen(
      (event) => onHeading(event.heading),
    );
  }

  Future<void> stop({required FilteredLocationService locationService}) async {
    await _positionSubscription?.cancel();
    await _compassSubscription?.cancel();
    await locationService.stop();
  }
}
