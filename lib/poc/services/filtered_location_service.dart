import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/geo_utils.dart';

/// Simple LatLng model is assumed to be defined in geo_utils.dart:
/// class LatLng { final double lat; final double lng; ... }
/// LatLng lerpLatLng(LatLng a, LatLng b, double t);

/// Internal representation of a filtered location sample.
class FilteredLocation {
  final double lat;
  final double lng;
  final DateTime timestamp;

  const FilteredLocation(this.lat, this.lng, this.timestamp);
}

/// Service that exposes a filtered, lightly-smoothed location stream suitable for UI.
///
/// Pipeline:
/// Raw GPS/WiFi/Cell location
///   ↓
/// Fused Location Provider (via Geolocator)
///   ↓
/// Accuracy Filter (discard low-quality readings)
///   ↓
/// Speed Filter (discard unrealistic speeds)
///   ↓
/// Jump Filter (discard large jumps/glitches)
///   ↓
/// Light Exponential Smoothing (alpha 0.6 - optimized for fast response)
///   ↓
/// Small Moving Average (window 2 - minimal lag)
///   ↓
/// Short Interpolation (100ms - smooth UI)
///   ↓
/// Final Position Stream for Map/UI (~3-6 second lag, optimized from 13-26s)
class FilteredLocationService {
  /// Max realistic speed (m/s). Anything above is discarded as noise.
  final double maxHumanSpeedMps;

  /// Max jump distance in [jumpTimeThreshold] allowed before discarding as glitch.
  final double jumpDistanceMeters;

  /// Time window to check for large jumps.
  final Duration jumpTimeThreshold;

  /// Exponential smoothing factor (0 < alpha < 1).
  /// Higher = faster response, less smoothing. 0.55 provides light smoothing with fast response.
  final double alpha;

  /// Window size for moving average.
  /// Small window (2) provides minimal lag while reducing jitter.
  final int movingAverageWindow;

  /// Threshold for discarding low-accuracy GPS readings.
  final double accuracyThresholdMeters;

  /// Duration for interpolating between filtered points for UI.
  /// Short duration (120ms) provides smooth movement with minimal delay.
  final Duration interpolationDuration;

  /// Tick duration for interpolation timer.
  final Duration interpolationTick;

  StreamSubscription<Position>? _positionSub;
  final StreamController<LatLng> _controller =
      StreamController<LatLng>.broadcast();

  FilteredLocation? _lastValid;
  LatLng? _lastSmoothed;
  final List<LatLng> _window = <LatLng>[];
  LatLng? _uiPosition;
  Timer? _interpTimer;

  /// Exposed derived values (optional but useful):
  ///
  ///
  double? currentSpeedMps; // computed from lastValid -> current
  double? currentCourseDegrees; // bearing of movement, 0–360°

  FilteredLocationService({
    this.maxHumanSpeedMps = 3.0, // indoor walking, ~11 km/h
    this.jumpDistanceMeters = 25.0,
    this.jumpTimeThreshold = const Duration(seconds: 3),
    this.alpha = 0.9, // very fast response for indoor navigation
    this.movingAverageWindow = 2, // reduced from 4 for less delay
    this.accuracyThresholdMeters = 75.0, // more permissive for indoor usage
    this.interpolationDuration = const Duration(
      milliseconds: 50,
    ), // kept short; interpolation will be bypassed for direct output
    this.interpolationTick = const Duration(milliseconds: 50),
  });

  /// Filtered, lightly-smoothed UI-ready position stream (~1-2 second lag).
  Stream<LatLng> get filteredPosition$ => _controller.stream;

  /// Start listening to location updates and feeding the pipeline.
  Future<void> start() async {
    await _positionSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // meters
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          _onRawPosition,
          onError: (e, st) {
            // Log GPS stream errors for debugging
            debugPrint('❌ FilteredLocationService GPS stream error: $e');
            debugPrint('Stack trace: $st');
            // Keep the stream alive, but log the error
          },
          cancelOnError: false, // Keep stream alive even on errors
        );
  }

  /// Stop listening to location stream and stop interpolation.
  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _interpTimer?.cancel();
    _interpTimer = null;
  }

  /// Close the stream controller completely (if you don't need this service anymore).
  /// Call this once (e.g. from a top-level dispose).
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  void _onRawPosition(Position pos) {
    // 0) Accuracy filter: discard very low-quality readings
    final accuracy = pos.accuracy;
    if (accuracy.isFinite && accuracy > accuracyThresholdMeters) {
      debugPrint(
        '📍 GPS position filtered out: accuracy ${accuracy.toStringAsFixed(1)}m > threshold ${accuracyThresholdMeters}m',
      );
      return;
    }

    // Log successful position reception
    final accuracyStr = accuracy.isFinite
        ? '${accuracy.toStringAsFixed(1)}m'
        : 'unknown';
    debugPrint(
      '✅ GPS position received: lat=${pos.latitude.toStringAsFixed(6)}, lng=${pos.longitude.toStringAsFixed(6)}, accuracy=$accuracyStr',
    );

    final timestamp = pos.timestamp;
    final raw = FilteredLocation(pos.latitude, pos.longitude, timestamp);

    // 1) Speed filter + course computation
    if (_lastValid != null) {
      final dtSec = _deltaSeconds(_lastValid!.timestamp, raw.timestamp);
      if (dtSec > 0) {
        final dist = Geolocator.distanceBetween(
          _lastValid!.lat,
          _lastValid!.lng,
          raw.lat,
          raw.lng,
        );
        final speed = dist / dtSec;

        // Expose for external usage (e.g. heading fusion later)
        currentSpeedMps = speed;

        // Bearing of movement (course)
        currentCourseDegrees = bearingBetween(
          _lastValid!.lat,
          _lastValid!.lng,
          raw.lat,
          raw.lng,
        );

        if (speed > maxHumanSpeedMps) {
          // Unrealistic speed → discard as glitch
          return;
        }
      }
    }

    // 2) Jump filter
    if (_lastValid != null) {
      final dt = raw.timestamp.difference(_lastValid!.timestamp);
      final dist = Geolocator.distanceBetween(
        _lastValid!.lat,
        _lastValid!.lng,
        raw.lat,
        raw.lng,
      );
      if (dt < jumpTimeThreshold && dist > jumpDistanceMeters) {
        // Big jump in small time window → discard as glitch
        return;
      }
    }

    // Raw point accepted as valid base
    _lastValid = raw;

    // 3) Light exponential smoothing on lat/lng (alpha 0.55 for fast response)
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

    // 4) Small moving average window (size 2 for minimal lag)
    _window.add(smoothed);
    if (_window.length > movingAverageWindow) {
      _window.removeAt(0);
    }
    final averaged = _average(_window);

    // Direct output for minimal latency (no interpolation)
    if (!_controller.isClosed) {
      _controller.add(averaged);
    }
  }

  double _deltaSeconds(DateTime a, DateTime b) {
    return b.difference(a).inMilliseconds / 1000.0;
  }

  LatLng _average(List<LatLng> pts) {
    double sumLat = 0;
    double sumLng = 0;

    for (final p in pts) {
      sumLat += p.lat;
      sumLng += p.lng;
    }

    final n = pts.isEmpty ? 1 : pts.length.toDouble();
    return LatLng(sumLat / n, sumLng / n);
  }

  void _interpolateTo(LatLng target) {
    _interpTimer?.cancel();

    final start = _uiPosition ?? target;
    _uiPosition ??= start;

    // If no movement, just push target once.
    if ((start.lat - target.lat).abs() < 1e-12 &&
        (start.lng - target.lng).abs() < 1e-12) {
      _uiPosition = target;
      if (!_controller.isClosed) {
        _controller.add(target);
      }
      return;
    }

    final totalMs = interpolationDuration.inMilliseconds;
    int elapsed = 0;

    _interpTimer = Timer.periodic(interpolationTick, (timer) {
      elapsed += interpolationTick.inMilliseconds;
      final t = (elapsed / totalMs).clamp(0.0, 1.0);

      final current = lerpLatLng(start, target, t);
      _uiPosition = current;

      if (!_controller.isClosed) {
        _controller.add(current);
      }

      if (t >= 1.0) {
        timer.cancel();
        _interpTimer = null;
      }
    });
  }
}
