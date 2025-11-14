import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../utils/geo_utils.dart';

class FilteredLocation {
  final double lat;
  final double lng;
  final DateTime timestamp;
  const FilteredLocation(this.lat, this.lng, this.timestamp);
}

class FilteredLocationService {
  final double maxHumanSpeedMps;
  final double jumpDistanceMeters;
  final Duration jumpTimeThreshold;
  final double alpha; // exponential smoothing factor
  final int movingAverageWindow;
  final Duration interpolationDuration;
  final Duration interpolationTick;

  StreamSubscription<Position>? _positionSub;
  final StreamController<LatLng> _controller =
      StreamController<LatLng>.broadcast();

  FilteredLocation? _lastValid;
  LatLng? _lastSmoothed;
  final List<LatLng> _window = <LatLng>[];
  LatLng? _uiPosition;
  Timer? _interpTimer;

  FilteredLocationService({
    this.maxHumanSpeedMps = 15.0,
    this.jumpDistanceMeters = 50.0,
    this.jumpTimeThreshold = const Duration(seconds: 5),
    this.alpha = 0.2,
    this.movingAverageWindow = 5,
    this.interpolationDuration = const Duration(milliseconds: 350),
    this.interpolationTick = const Duration(milliseconds: 30),
  });

  Stream<LatLng> get filteredPosition$ => _controller.stream;

  Future<void> start() async {
    await _positionSub?.cancel();
    final settings = const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          _onRawPosition,
          onError: (e, st) {
            // swallow errors but keep the stream alive
          },
        );
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _interpTimer?.cancel();
    _interpTimer = null;
  }

  void _onRawPosition(Position pos) {
    final now = DateTime.now();
    final raw = FilteredLocation(pos.latitude, pos.longitude, now);

    // Step 1: Speed filter
    if (_lastValid != null) {
      final dtSec =
          now.difference(_lastValid!.timestamp).inMilliseconds / 1000.0;
      if (dtSec > 0) {
        final dist = Geolocator.distanceBetween(
          _lastValid!.lat,
          _lastValid!.lng,
          raw.lat,
          raw.lng,
        );
        final speed = dist / dtSec;
        if (speed > maxHumanSpeedMps) {
          return;
        }
      }
    }

    // Step 2: Jump filter
    if (_lastValid != null) {
      final dt = now.difference(_lastValid!.timestamp);
      final dist = Geolocator.distanceBetween(
        _lastValid!.lat,
        _lastValid!.lng,
        raw.lat,
        raw.lng,
      );
      if (dt < jumpTimeThreshold && dist > jumpDistanceMeters) {
        return;
      }
    }

    _lastValid = raw;

    // Step 3: Exponential smoothing
    LatLng smoothed;
    if (_lastSmoothed == null) {
      smoothed = LatLng(raw.lat, raw.lng);
    } else {
      final prev = _lastSmoothed!;
      final newLat = prev.lat + alpha * (raw.lat - prev.lat);
      final newLng = prev.lng + alpha * (raw.lng - prev.lng);
      smoothed = LatLng(newLat, newLng);
    }
    _lastSmoothed = smoothed;

    // Step 4: Moving average
    _window.add(smoothed);
    if (_window.length > movingAverageWindow) {
      _window.removeAt(0);
    }
    final avg = _average(_window);

    // Step 5: Interpolation for UI
    _interpolateTo(avg);
  }

  LatLng _average(List<LatLng> pts) {
    double sumLat = 0, sumLng = 0;
    for (final p in pts) {
      sumLat += p.lat;
      sumLng += p.lng;
    }
    return LatLng(sumLat / pts.length, sumLng / pts.length);
  }

  void _interpolateTo(LatLng target) {
    _interpTimer?.cancel();
    final start = _uiPosition ?? target;
    _uiPosition ??= start;
    if ((start.lat - target.lat).abs() < 1e-12 &&
        (start.lng - target.lng).abs() < 1e-12) {
      _controller.add(target);
      _uiPosition = target;
      return;
    }

    final totalMs = interpolationDuration.inMilliseconds;
    int elapsed = 0;
    _interpTimer = Timer.periodic(interpolationTick, (timer) {
      elapsed += interpolationTick.inMilliseconds;
      final t = math.min(1.0, elapsed / totalMs);
      final current = lerpLatLng(start, target, t);
      _uiPosition = current;
      _controller.add(current);
      if (t >= 1.0) {
        timer.cancel();
      }
    });
  }
}
