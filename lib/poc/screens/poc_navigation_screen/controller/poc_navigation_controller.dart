import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../utiles/snackbar_utiles.dart';
import '../../../utils/pref_utiles.dart';
import '../../../models/ble_waypoint.dart';
import '../../../models/saved_location.dart';
import '../../../services/filtered_location_service.dart';
import '../../../services/gps_navigation_service.dart';
import '../../../services/ble_navigation_service.dart';
import '../../../utils/geo_utils.dart';

/// Production-ready POC Navigation Controller
/// Optimized for continuous BLE scanning with smooth UI updates
class PocNavigationController extends GetxController {
  PocNavigationController(this.target);

  final SavedLocation target;

  // BLE Configuration - Production optimized
  static const Duration _deviceTimeout = Duration(seconds: 4);
  static const double _rssiSmoothingFactor = 0.7;
  static const int _rssiHistorySize = 5;
  static const int _rssiOutlierThreshold = 12;

  // Waypoint Detection - Simplified & Reliable
  double _waypointReachedThreshold = -70; // default dBm
  int _requiredStableSamples = 5;
  static const Duration _stateChangeCooldown = Duration(milliseconds: 500);

  // Distance smoothing
  static const int _minStableGpsSamples = 3;
  static const double _distanceSmoothingFactor =
      0.55; // faster distance updates
  static const int _initialSamplesForBounds = 4;
  static const double _minMapSpanDegrees = 0.0008;
  static const double _minDistanceChangeMeters =
      1.5; // more responsive to smaller movements
  static const Duration _distanceUpdateDebounce = Duration(
    milliseconds: 200, // optimized from 700ms for faster updates
  ); // Debounce distance updates

  // Map jitter control - adaptive smoothing for map marker
  static const double _jitterIgnoreThresholdMeters =
      0.3; // optimized from 0.7m for more responsive updates
  static const double _smallMoveThresholdMeters = 3.0; // 0.7–3m = walk / slow

  // Movement detection for distance updates
  static const double _movingSpeedThresholdMps =
      0.4; // above this = clearly walking
  static const double _stationarySpeedThresholdMps =
      0.2; // below this = clearly stationary
  static const int _movementStableSamples =
      2; // optimized from 3 for faster movement detection

  // Signal strength display
  static const double _signalFloor = 0.0;

  // GPS & Location Services
  final FilteredLocationService _locationService = FilteredLocationService();
  final GpsNavigationService _gpsService = GpsNavigationService();

  // Core Observable State
  final totalDetections = 0.obs;
  final permissionsGranted = false.obs;
  final currentPosition = Rxn<LatLng>();
  final mapDisplayPosition = Rxn<LatLng>();
  final mapDisplayPositionFast =
      Rxn<LatLng>(); // Fast-update path for map display
  final headingDegrees = Rxn<double>();
  final displayDistanceMeters = Rxn<double>();
  final hasShownSuccess = false.obs;
  final isScanning = false.obs;
  final mapBounds = Rxn<MapBounds>();

  // BLE Signal State
  final RxMap<String, double> smoothedRssi = <String, double>{}.obs;
  final RxMap<String, double> signalStrength = <String, double>{}.obs;
  final RxMap<String, double> signalQuality = <String, double>{}.obs;
  final RxMap<String, int> detectionCount = <String, int>{}.obs;
  final RxMap<String, DateTime> lastSeen = <String, DateTime>{}.obs;

  // Waypoint Management
  final RxList<String> reachedWaypointHistory = <String>[].obs;
  final completedWaypoints = 0.obs;
  final RxBool isMovingBackward = false.obs;

  // Internal State
  final Map<String, List<int>> _rssiHistory = {};
  final Map<String, DateTime> _lastStateChange = {};
  final Map<String, int> _stableSampleCount = {};

  bool _isUserMoving = false;
  int _movingSamples = 0;
  int _stationarySamples = 0;

  // Compass heading state for validation and smoothing
  double? _lastValidHeading;
  DateTime? _lastHeadingUpdate;
  static const double _maxHeadingJumpDegrees =
      90.0; // Max valid jump between readings
  static const Duration _headingStalenessThreshold = Duration(seconds: 5);
  static const double _compassSmoothingFactor =
      0.3; // Light smoothing for compass (30% new, 70% old)

  // Synchronization: track last update timestamps to ensure position and heading are recent
  DateTime? _lastPositionUpdate;
  static const Duration _maxPositionHeadingAge = Duration(
    seconds: 2,
  ); // Max age for valid data pair

  // Waypoint Configuration
  final List<BleWaypoint> _waypoints = [
    BleWaypoint(id: 'BEACON_1', label: 'Entry Point', order: 1),
    BleWaypoint(id: 'BEACON_2', label: 'Midpoint', order: 2),
    BleWaypoint(id: 'BEACON_3', label: 'Destination', order: 3),
  ];

  final Map<String, BleWaypoint> _waypointMap = {};

  // Beacon Device Mapping
  final Map<String, String> _deviceToWaypointMap = {
    '6B:14:28:14:EF:C5': 'BEACON_1', // label no : 1
    'C7:81:19:F7:CA:75': 'BEACON_2', // label no : 4
    'EC:B9:75:AB:22:23': 'BEACON_3', // label no : 5
  };

  // BLE navigation service
  final BleNavigationService _bleService = BleNavigationService();

  // Scanning & timer state
  Timer? _timeoutTimer;
  Timer? _uiUpdateTimer;
  bool _isDisposed = false; // Track if controller is disposed

  // UI Update Workers
  Worker? _rssiWorker;
  Worker? _distanceWorker;

  double? _smoothedDistanceMeters;
  int _stableGpsCount = 0;
  final List<LatLng> _initialMapSamples = [];
  bool _mapBoundsLocked = false;
  Timer? _distanceUpdateTimer;
  double? _lastDisplayedDistance;

  /// Route points used for 2D mini-map polyline (start -> checkpoints -> destination).
  /// Backed by [List] so we can initialize after construction while keeping
  /// the controller compatible with GetX's default constructor usage.
  final List<LatLng> routePoints = [];

  /// Initialize the route for this navigation session.
  /// If [points] is null or empty, we fall back to a simple [start, destination]
  /// style route that uses only the target location.
  void initializeRoute(List<LatLng>? points) {
    routePoints.clear();

    debugPrint(
      '🗺️ [PocNavigationController] initializeRoute called with ${points?.length ?? 0} points',
    );

    if (points != null && points.isNotEmpty) {
      routePoints.addAll(points);
      debugPrint(
        '🗺️ [PocNavigationController] Route initialized with ${routePoints.length} points',
      );
      for (var i = 0; i < routePoints.length; i++) {
        debugPrint(
          '🗺️ [PocNavigationController] Route[$i]: lat=${routePoints[i].lat.toStringAsFixed(6)}, lng=${routePoints[i].lng.toStringAsFixed(6)}',
        );
      }
    } else {
      // Fallback: simple route that just uses the destination.
      routePoints.add(LatLng(target.latitude, target.longitude));
      debugPrint(
        '🗺️ [PocNavigationController] Fallback: using target only: lat=${target.latitude.toStringAsFixed(6)}, lng=${target.longitude.toStringAsFixed(6)}',
      );
    }
  }

  @override
  void onInit() {
    super.onInit();
    _loadDeveloperSettings();
    _initializeWaypoints();
    _setupUIWorkers();
  }

  @override
  void onReady() {
    super.onReady();
    _checkPermissions().then((granted) {
      if (granted) {
        _startNavigation();
      }
    });
  }

  @override
  void onClose() {
    _cleanup();
    super.onClose();
  }

  /// Initialize waypoint mappings and state
  void _initializeWaypoints() {
    for (final waypoint in _waypoints) {
      _waypointMap[waypoint.id] = waypoint;
      _rssiHistory[waypoint.id] = [];
      smoothedRssi[waypoint.id] = -100.0;
      signalStrength[waypoint.id] = _signalFloor;
      signalQuality[waypoint.id] = 0.0;
      detectionCount[waypoint.id] = 0;
      _stableSampleCount[waypoint.id] = 0;
    }
  }

  Future<void> _loadDeveloperSettings() async {
    try {
      await PrefUtils().init();
      final threshold = PrefUtils().getThresholdValue();
      final stableSamples = PrefUtils().getRequiredStableSample();
      _waypointReachedThreshold = threshold
          .clamp(-100, -40)
          .toDouble(); // safety clamp
      _requiredStableSamples = stableSamples <= 0 ? 5 : stableSamples;
      debugPrint(
        '⚙️ Developer settings loaded: threshold=$_waypointReachedThreshold, stableSamples=$_requiredStableSamples',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load developer settings: $e');
    }
  }

  /// Setup optimized UI update workers
  void _setupUIWorkers() {
    // Debounced RSSI updates for smooth UI
    _rssiWorker = debounce(
      smoothedRssi,
      (_) => _updateSignalDisplays(),
      time: const Duration(milliseconds: 50),
    );

    _distanceWorker = ever<double?>(
      displayDistanceMeters,
      (_) => _checkDestinationReached(),
    );
  }

  /// Start navigation with error handling
  Future<void> _startNavigation() async {
    try {
      await _startGpsTracking();
      await _startContinuousBleScanning();
      await WakelockPlus.enable();
    } catch (e) {
      _handleError('Navigation start failed', e);
    }
  }

  /// Start GPS tracking
  Future<void> _startGpsTracking() async {
    debugPrint('🛰️ Initializing GPS tracking...');
    try {
      await _gpsService.startTracking(
        locationService: _locationService,
        onPosition: _handleGpsUpdate,
        onHeading: _handleHeadingUpdate,
      );
      debugPrint('✅ GPS tracking initialized successfully');
    } catch (e, st) {
      debugPrint('❌ Failed to start GPS tracking: $e');
      debugPrint('Stack trace: $st');
      _handleError('GPS tracking failed', e);
      rethrow;
    }
  }

  /// Handle GPS updates with smoothing
  void _handleGpsUpdate(LatLng position) {
    // Guard: ignore updates if controller is disposed
    if (_isDisposed) {
      debugPrint('⚠️ GPS update ignored: controller is disposed');
      return;
    }

    debugPrint(
      '🔄 GPS update received: lat=${position.lat.toStringAsFixed(6)}, lng=${position.lng.toStringAsFixed(6)}',
    );

    _updateMovementState();

    // If the user/device is effectively stationary, ignore small GPS changes.
    // This prevents the blue dot and compass arrow from drifting when you are not moving.
    if (!_isUserMoving && currentPosition.value != null) {
      debugPrint('🛑 GPS update ignored: user detected as stationary');
      return;
    }

    // Store latest filtered position
    currentPosition.value = position;
    _lastPositionUpdate =
        DateTime.now(); // Track position update time for synchronization

    // Map uses adaptively smoothed marker (ignores jitter, responds to real movement)
    _updateMapDisplayPosition(position);

    // Distance uses the filtered GPS directly (no extra map smoothing)
    _updateDistanceFromPosition(position);
  }

  /// Update distance calculation from smoothed position
  void _updateDistanceFromPosition(LatLng position) {
    final distanceMeters = Geolocator.distanceBetween(
      position.lat,
      position.lng,
      target.latitude,
      target.longitude,
    );

    // Raw guard: unless we are clearly walking away,
    // do NOT allow the displayed distance to increase.
    if (_lastDisplayedDistance != null) {
      final rawDelta = distanceMeters - _lastDisplayedDistance!;

      // Case A: user is not moving → never allow increases
      if (!_isUserMoving && rawDelta >= 0) {
        return;
      }

      // Case B: user is moving, but distance wants to go UP.
      // Only accept this if direction + speed say "clearly walking away".
      if (_isUserMoving && rawDelta > 0) {
        final clearlyAway = _isClearlyWalkingAway(position, distanceMeters);
        if (!clearlyAway) {
          return;
        }
      }
    }

    // Initialize smoothed distance if null
    if (_smoothedDistanceMeters == null) {
      _smoothedDistanceMeters = distanceMeters;
      _stableGpsCount = 1;
      _lastDisplayedDistance = distanceMeters;
    } else {
      // Update smoothed distance using weighted average
      _smoothedDistanceMeters =
          _distanceSmoothingFactor * distanceMeters +
          (1 - _distanceSmoothingFactor) * _smoothedDistanceMeters!;
      _stableGpsCount++;

      // Safety clamp: do not allow sudden large increases (likely noise)
      if (_lastDisplayedDistance != null && _smoothedDistanceMeters != null) {
        final rawIncrease = _smoothedDistanceMeters! - _lastDisplayedDistance!;

        // If distance suddenly jumps up by more than 6m, treat it as noise
        if (rawIncrease > 6.0) {
          _smoothedDistanceMeters = _lastDisplayedDistance;
        }
      }
    }

    // Only update display distance once we have enough stable samples
    if (_stableGpsCount >= _minStableGpsSamples) {
      // Check if change is significant enough to update
      final change = _lastDisplayedDistance != null
          ? (_smoothedDistanceMeters! - _lastDisplayedDistance!).abs()
          : double.infinity;

      if (change >= _minDistanceChangeMeters ||
          _lastDisplayedDistance == null) {
        // Update immediately if change is significant
        _lastDisplayedDistance = _smoothedDistanceMeters;
        displayDistanceMeters.value = _smoothedDistanceMeters;
      } else {
        // Debounce small changes
        _distanceUpdateTimer?.cancel();
        _distanceUpdateTimer = Timer(_distanceUpdateDebounce, () {
          if (!_isDisposed && _smoothedDistanceMeters != null) {
            _lastDisplayedDistance = _smoothedDistanceMeters;
            displayDistanceMeters.value = _smoothedDistanceMeters;
          }
        });
      }
    }
  }

  /// Handle heading updates with validation, smoothing, and staleness tracking
  void _handleHeadingUpdate(double? heading) {
    // Guard: ignore updates if controller is disposed
    if (_isDisposed) {
      debugPrint('⚠️ Compass heading update ignored: controller is disposed');
      return;
    }

    final now = DateTime.now();

    // Handle null heading (compass unavailable or error)
    if (heading == null) {
      // Check if heading is stale (hasn't updated in a while)
      if (_lastHeadingUpdate != null &&
          now.difference(_lastHeadingUpdate!) > _headingStalenessThreshold) {
        debugPrint(
          '⚠️ Compass heading is stale (last update: ${_lastHeadingUpdate})',
        );
        // Keep last valid heading but mark as potentially stale
        // Don't clear it, just log the issue
      }
      return;
    }

    // Validate heading value
    if (!heading.isFinite || heading.isNaN) {
      debugPrint('⚠️ Invalid compass heading (NaN/Infinity): $heading');
      return;
    }

    // Normalize heading to 0-360 range
    double normalizedHeading = heading % 360.0;
    if (normalizedHeading < 0) normalizedHeading += 360.0;

    // Validate heading jump (detect unrealistic changes)
    if (_lastValidHeading != null) {
      final headingDiff = (normalizedHeading - _lastValidHeading!).abs();
      // Handle wraparound (e.g., 359° to 1° = 2° difference, not 358°)
      final actualDiff = headingDiff > 180 ? 360 - headingDiff : headingDiff;

      if (actualDiff > _maxHeadingJumpDegrees) {
        debugPrint(
          '⚠️ Compass heading jump too large: ${_lastValidHeading!.toStringAsFixed(1)}° → ${normalizedHeading.toStringAsFixed(1)}° (diff: ${actualDiff.toStringAsFixed(1)}°)',
        );
        // Reject the jump, keep last valid heading
        return;
      }
    }

    // Apply light smoothing to reduce jitter
    double smoothedHeading;
    if (_lastValidHeading == null) {
      // First valid reading, use as-is
      smoothedHeading = normalizedHeading;
    } else {
      // Smooth heading using exponential smoothing
      // Handle wraparound for smoothing (e.g., 359° to 1°)
      double headingDiff = normalizedHeading - _lastValidHeading!;
      if (headingDiff > 180) {
        headingDiff -= 360;
      } else if (headingDiff < -180) {
        headingDiff += 360;
      }

      smoothedHeading =
          _lastValidHeading! + _compassSmoothingFactor * headingDiff;
      // Normalize back to 0-360
      smoothedHeading = smoothedHeading % 360.0;
      if (smoothedHeading < 0) smoothedHeading += 360.0;
    }

    // Update state
    _lastValidHeading = smoothedHeading;
    _lastHeadingUpdate = now;
    headingDegrees.value = smoothedHeading;

    debugPrint(
      '🧭 Compass heading updated: raw=${normalizedHeading.toStringAsFixed(1)}°, smoothed=${smoothedHeading.toStringAsFixed(1)}°',
    );
  }

  /// Update internal movement state using filtered GPS speed.
  /// This lets us distinguish real walking from small GPS jitter.
  void _updateMovementState() {
    final speed = _locationService.currentSpeedMps ?? 0.0;

    if (speed > _movingSpeedThresholdMps) {
      _movingSamples++;
      _stationarySamples = 0;
      if (_movingSamples >= _movementStableSamples) {
        _isUserMoving = true;
      }
    } else if (speed < _stationarySpeedThresholdMps) {
      _stationarySamples++;
      _movingSamples = 0;
      if (_stationarySamples >= _movementStableSamples) {
        _isUserMoving = false;
      }
    } else {
      // In the hysteresis band between stationary and moving thresholds,
      // keep current state but don't accumulate counters.
      _movingSamples = 0;
      _stationarySamples = 0;
    }
  }

  /// Returns the user's position snapped to the nearest point on the route
  /// polyline (start -> checkpoints -> destination). Used only for drawing
  /// on the 2D mini-map; distance calculations still use GPS directly.
  /// Uses the standard smoothed position for backward compatibility.
  LatLng? get snappedUserPosition {
    final user = mapDisplayPosition.value;
    if (user == null || routePoints.length < 2) {
      return user;
    }
    return _snapToRoute(user);
  }

  /// Fast-update version: returns user position snapped to route using fast-update path.
  /// Provides near real-time updates for map display.
  LatLng? get snappedUserPositionFast {
    final user = mapDisplayPositionFast.value;
    if (user == null || routePoints.length < 2) {
      return user;
    }
    return _snapToRoute(user);
  }

  /// Project [user] onto the closest segment of the route in a local
  /// Cartesian approximation (meters), then convert back to LatLng.
  LatLng _snapToRoute(LatLng user) {
    // Use the first route point as local origin for an equirectangular
    // approximation. This is sufficient for short indoor/outdoor routes.
    final origin = routePoints.first;

    Offset toLocal(LatLng p) {
      const earthRadiusMeters = 6371000.0;
      final latRad = (p.lat - origin.lat) * (math.pi / 180.0);
      final lngRad = (p.lng - origin.lng) * (math.pi / 180.0);
      final x =
          earthRadiusMeters * lngRad * math.cos(origin.lat * (math.pi / 180.0));
      final y = earthRadiusMeters * latRad;
      return Offset(x, y);
    }

    LatLng toLatLng(Offset local) {
      const earthRadiusMeters = 6371000.0;
      final dLat = local.dy / earthRadiusMeters;
      final dLng =
          local.dx /
          (earthRadiusMeters * math.cos(origin.lat * (math.pi / 180.0)));
      final lat = origin.lat + dLat * (180.0 / math.pi);
      final lng = origin.lng + dLng * (180.0 / math.pi);
      return LatLng(lat, lng);
    }

    final userLocal = toLocal(user);

    double bestDistSq = double.infinity;
    Offset bestPoint = userLocal;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final aLocal = toLocal(routePoints[i]);
      final bLocal = toLocal(routePoints[i + 1]);
      final ab = bLocal - aLocal;
      final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;

      if (abLenSq == 0) {
        // Degenerate segment
        final distSq = (userLocal - aLocal).distanceSquared;
        if (distSq < bestDistSq) {
          bestDistSq = distSq;
          bestPoint = aLocal;
        }
        continue;
      }

      // Projection of user onto segment, clamped to [0,1]
      final t =
          ((userLocal.dx - aLocal.dx) * ab.dx +
              (userLocal.dy - aLocal.dy) * ab.dy) /
          abLenSq;
      final clampedT = t.clamp(0.0, 1.0);
      final proj = Offset(
        aLocal.dx + ab.dx * clampedT,
        aLocal.dy + ab.dy * clampedT,
      );

      final distSq = (userLocal - proj).distanceSquared;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestPoint = proj;
      }
    }

    return toLatLng(bestPoint);
  }

  /// Determine if user is clearly walking away from the target,
  /// using movement course vs bearing-to-target plus a minimum
  /// distance increase threshold.
  bool _isClearlyWalkingAway(LatLng position, double distanceMeters) {
    final course = _locationService.currentCourseDegrees;

    // If we don't have a reliable course yet, be conservative.
    if (course == null) {
      return false;
    }

    // If the increase is tiny, treat it as noise even if direction is ambiguous.
    if (_lastDisplayedDistance != null) {
      final rawDelta = distanceMeters - _lastDisplayedDistance!;
      if (rawDelta < 2.0) {
        return false;
      }
    }

    // Bearing from current position to the target
    final bearingToTarget = bearingBetween(
      position.lat,
      position.lng,
      target.latitude,
      target.longitude,
    );

    // Angle between where we are walking and where the target is.
    // ~0°  = walking straight towards target
    // ~180° = walking straight away from target
    final angleDiff = _angleDifferenceDegrees(course, bearingToTarget);

    // Consider "clearly walking away" only if our movement direction
    // is strongly opposite to the target direction.
    return angleDiff >= 120.0; // 120–180° = mostly away
  }

  /// Small helper to get absolute smallest angle difference between two bearings.
  double _angleDifferenceDegrees(double a, double b) {
    final diff = (a - b + 540.0) % 360.0 - 180.0;
    return diff.abs();
  }

  void _updateMapDisplayPosition(LatLng position) {
    final previous = mapDisplayPosition.value;

    // First update → just set and start collecting samples
    if (previous == null) {
      mapDisplayPosition.value = position;
      mapDisplayPositionFast.value = position; // Initialize fast path too
      _accumulateInitialMapSample(position);
      return;
    }

    // Distance between last drawn point and new GPS point
    final deltaMeters = Geolocator.distanceBetween(
      previous.lat,
      previous.lng,
      position.lat,
      position.lng,
    );

    // 1️⃣ Ignore very tiny movements → pure jitter
    if (deltaMeters < _jitterIgnoreThresholdMeters) {
      // Still use this point for initial bounds if not locked
      if (!_mapBoundsLocked) {
        _accumulateInitialMapSample(position);
      }
      return;
    }

    double t; // smoothing factor for lerp

    // 2️⃣ Small movement: optimized smoothing (avoid shaking while staying responsive)
    if (deltaMeters < _smallMoveThresholdMeters) {
      t = 0.5; // optimized from 0.25 to 0.5 for faster updates
    }
    // 3️⃣ Larger movement: follow user quickly
    else {
      t = 0.65; // jump most of the way towards new point
    }

    final smoothed = lerpLatLng(previous, position, t);
    mapDisplayPosition.value = smoothed;

    // Fast-update path for map display: adaptive smoothing based on movement state
    _updateMapDisplayPositionFast(position);

    // Use smoothed position to build initial bounds (optional, but fine)
    if (!_mapBoundsLocked) {
      _accumulateInitialMapSample(smoothed);
    }
  }

  /// Fast-update path for map display with adaptive smoothing.
  /// When user is moving: minimal smoothing (50% lerp) for near real-time updates.
  /// When stationary: more smoothing (25% lerp) to reduce jitter.
  void _updateMapDisplayPositionFast(LatLng position) {
    final previousFast = mapDisplayPositionFast.value;

    // First update → just set
    if (previousFast == null) {
      mapDisplayPositionFast.value = position;
      return;
    }

    // Distance between last fast position and new GPS point
    final deltaMeters = Geolocator.distanceBetween(
      previousFast.lat,
      previousFast.lng,
      position.lat,
      position.lng,
    );

    // Ignore very tiny movements (same threshold as main path)
    if (deltaMeters < _jitterIgnoreThresholdMeters) {
      return;
    }

    // Adaptive smoothing: fast when moving, smooth when stationary
    double tFast;
    if (_isUserMoving) {
      // User is moving: use 50% lerp for fast response
      tFast = 0.5;
    } else {
      // User is stationary: use 25% lerp to reduce jitter
      tFast = 0.25;
    }

    final smoothedFast = lerpLatLng(previousFast, position, tFast);
    mapDisplayPositionFast.value = smoothedFast;
  }

  void _accumulateInitialMapSample(LatLng position) {
    // If bounds are already locked, don't accumulate samples
    if (_mapBoundsLocked) {
      return;
    }

    // If bounds already exist, lock them immediately
    if (mapBounds.value != null) {
      _mapBoundsLocked = true;
      return;
    }

    _initialMapSamples.add(position);
    if (_initialMapSamples.length >= _initialSamplesForBounds) {
      final averaged = _averageLatLng(_initialMapSamples);
      mapBounds.value = calculateMapBounds(userPosition: averaged);
      _mapBoundsLocked = true;
      debugPrint('🗺️ Map bounds calculated and locked');
    }
  }

  LatLng _averageLatLng(List<LatLng> points) {
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.lat;
      sumLng += p.lng;
    }
    final count = points.isEmpty ? 1 : points.length;
    return LatLng(sumLat / count, sumLng / count);
  }

  /// Start continuous BLE scanning via BleNavigationService
  Future<void> _startContinuousBleScanning() async {
    // Don't start if disposed
    if (_isDisposed) {
      debugPrint('⚠️ Cannot start scanning - controller is disposed');
      return;
    }

    try {
      debugPrint('🚀 Starting continuous BLE scanning via service');

      await _bleService.startContinuousScanning(
        onScanResults: (results) {
          if (_isDisposed) return;
          _processScanResults(results);
        },
        onError: (message) {
          _handleError(message, null);
        },
        onBluetoothStateChanged: () {
          // Service will restart scanning when Bluetooth comes back.
          // Here we just update UI/state.
          isScanning.value = false;
          if (Get.context != null) {
            SnackBarUtil.showErrorSnackbar(
              Get.context!,
              'Bluetooth turned off. Scanning paused.',
            );
          }
        },
      );

      // Start timeout monitoring for individual devices
      _startTimeoutMonitoring();

      isScanning.value = true;
      debugPrint('✅ Continuous BLE scanning started successfully');
    } catch (e) {
      _handleError('Failed to start BLE scanning', e);
    }
  }

  /// Start device timeout monitoring
  void _startTimeoutMonitoring() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _handleDeviceTimeouts();
    });
  }

  /// Process BLE scan results with optimized filtering
  void _processScanResults(List<ScanResult> results) {
    // Guard: ignore if disposed
    if (_isDisposed) {
      debugPrint('⚠️ BLE scan results ignored: controller is disposed');
      return;
    }

    if (results.isEmpty) return;

    final now = DateTime.now();
    bool hasSignificantUpdate = false;

    for (final result in results) {
      final waypointId = _matchDevice(result.device);
      if (waypointId == null) continue;

      final rssi = result.rssi;
      lastSeen[waypointId] = now;
      detectionCount[waypointId] = (detectionCount[waypointId] ?? 0) + 1;

      // Process RSSI with enhanced filter
      final previousRssi = smoothedRssi[waypointId] ?? -100.0;
      final newRssi = _processRssiWithFiltering(waypointId, rssi);

      // Update signal metrics
      _updateSignalMetrics(waypointId, rssi, newRssi);

      // Check for waypoint state changes
      final stateChanged = _processWaypointDetection(waypointId, newRssi);

      if (stateChanged || (newRssi - previousRssi).abs() > 2.0) {
        hasSignificantUpdate = true;
      }

      smoothedRssi[waypointId] = newRssi;
    }

    totalDetections.value += results.length;

    if (hasSignificantUpdate) {
      smoothedRssi.refresh();
    }
  }

  /// Match device to waypoint with logging
  String? _matchDevice(BluetoothDevice device) {
    final deviceId = device.remoteId.toString().toUpperCase();
    final waypointId = _deviceToWaypointMap[deviceId];

    if (kDebugMode && waypointId != null) {
      debugPrint('📱 Matched device: $deviceId -> $waypointId');
    }

    return waypointId;
  }

  /// Process RSSI with enhanced filtering and outlier removal
  double _processRssiWithFiltering(String waypointId, int rawRssi) {
    final history = _rssiHistory[waypointId]!;
    final currentSmoothed = smoothedRssi[waypointId] ?? -100.0;

    // Add to history
    history.add(rawRssi);
    if (history.length > _rssiHistorySize) {
      history.removeAt(0);
    }

    // Handle significant signal jumps immediately
    final signalJump = (rawRssi - currentSmoothed).abs();
    if (signalJump > 15) {
      debugPrint('⚡ Signal jump detected for $waypointId: ${signalJump}dBm');
      return _rssiSmoothingFactor * rawRssi +
          (1 - _rssiSmoothingFactor) * currentSmoothed;
    }

    // Remove outliers
    final filtered = _removeOutliers(history);

    // Weighted moving average
    double sum = 0;
    double weight = 1;
    double weightSum = 0;

    for (final value in filtered.reversed) {
      sum += value * weight;
      weightSum += weight;
      weight *= 0.7;
    }

    final newSmoothed = sum / weightSum;

    return _rssiSmoothingFactor * newSmoothed +
        (1 - _rssiSmoothingFactor) * currentSmoothed;
  }

  /// Remove outliers based on median deviation
  List<int> _removeOutliers(List<int> readings) {
    if (readings.length < 3) return readings;

    final sorted = List<int>.from(readings)..sort();
    final median = sorted[sorted.length ~/ 2];

    return readings
        .where((rssi) => (rssi - median).abs() <= _rssiOutlierThreshold)
        .toList();
  }

  /// Update signal metrics (strength and quality)
  void _updateSignalMetrics(
    String waypointId,
    int rawRssi,
    double smoothedRssi,
  ) {
    // Update signal strength with floor
    final strengthPercent = _calculateSignalStrength(smoothedRssi);
    final currentStrength = signalStrength[waypointId] ?? _signalFloor;

    // Smooth strength updates
    final newStrength = math.max(
      _signalFloor,
      0.6 * strengthPercent + 0.4 * currentStrength,
    );
    signalStrength[waypointId] = newStrength;

    // Update signal quality based on consistency
    _updateSignalQuality(waypointId, smoothedRssi);
  }

  double _calculateSignalStrength(double rssi) {
    const minRssi = -100.0;
    const maxRssi = -40.0;
    final normalized = ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);
    return normalized * 100.0;
  }

  void _updateSignalQuality(String waypointId, double smoothedRssi) {
    final history = _rssiHistory[waypointId]!;
    if (history.length < 3) {
      signalQuality[waypointId] = 0.0;
      return;
    }

    final mean = history.reduce((a, b) => a + b) / history.length;
    final variance =
        history.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
        history.length;
    final stdDev = math.sqrt(variance);

    final quality =
        (1.0 - (stdDev / 20.0)).clamp(0.0, 1.0) *
        (smoothedRssi > _waypointReachedThreshold ? 1.0 : 0.7);

    signalQuality[waypointId] = quality * 100.0;
  }

  /// Handle waypoint detection with stability check
  bool _processWaypointDetection(String waypointId, double rssi) {
    final waypoint = _waypointMap[waypointId]!;
    final now = DateTime.now();

    // Check cooldown period
    final lastChange = _lastStateChange[waypointId];
    if (lastChange != null &&
        now.difference(lastChange) < _stateChangeCooldown) {
      return false;
    }

    final meetsThreshold = rssi >= _waypointReachedThreshold;
    final currentCount = _stableSampleCount[waypointId] ?? 0;

    if (meetsThreshold) {
      _stableSampleCount[waypointId] = currentCount + 1;

      if (_stableSampleCount[waypointId]! >= _requiredStableSamples) {
        if (!waypoint.reached) {
          _handleWaypointReached(waypoint);
          _lastStateChange[waypointId] = now;
          _stableSampleCount[waypointId] = 0;
          return true;
        } else {
          // Check backward movement using history
          if (_isBackwardMovement(waypointId)) {
            _handleWaypointUnreached(waypoint);
            _lastStateChange[waypointId] = now;
            _stableSampleCount[waypointId] = 0;
            return true;
          }
        }
      }
    } else {
      _stableSampleCount[waypointId] = 0;
    }

    return false;
  }

  /// Determine if user is moving backward based on waypoint order
  bool _isBackwardMovement(String waypointId) {
    if (reachedWaypointHistory.isEmpty) return false;

    final lastReachedId = reachedWaypointHistory.last;
    final lastWaypoint = _waypointMap[lastReachedId]!;
    final currentWaypoint = _waypointMap[waypointId]!;

    return currentWaypoint.order < lastWaypoint.order;
  }

  void _handleWaypointReached(BleWaypoint waypoint) {
    waypoint.reached = true;
    if (!reachedWaypointHistory.contains(waypoint.id)) {
      reachedWaypointHistory.add(waypoint.id);
    }

    completedWaypoints.value = waypoint.order;
    isMovingBackward.value = false;

    _updateWaypointProgression(waypoint);
  }

  void _handleWaypointUnreached(BleWaypoint waypoint) {
    waypoint.reached = false;

    _handleBackwardMovement(waypoint);

    isMovingBackward.value = true;
  }

  void _handleBackwardMovement(BleWaypoint targetWaypoint) {
    final targetOrder = targetWaypoint.order;

    // Remove all waypoints after the target from history
    reachedWaypointHistory.removeWhere((id) {
      final wp = _waypointMap[id]!;
      return wp.order > targetOrder;
    });

    // Mark all waypoints after the target as unreached
    for (final waypoint in _waypoints) {
      if (waypoint.order > targetOrder) {
        waypoint.reached = false;
      }
    }

    // Update completed waypoints count
    completedWaypoints.value = targetOrder;
  }

  void _updateWaypointProgression(BleWaypoint waypoint) {
    final currentOrder = waypoint.order;

    // Forward movement: if this is the next waypoint in sequence
    if (currentOrder == completedWaypoints.value + 1) {
      completedWaypoints.value = currentOrder;
      isMovingBackward.value = false;
      return;
    }

    // Backward movement: if this waypoint is before the last completed one
    if (currentOrder < completedWaypoints.value) {
      _handleBackwardMovement(waypoint);
      isMovingBackward.value = true;
      return;
    }

    // Jump movement: user directly reached a non-adjacent waypoint
    if (currentOrder > completedWaypoints.value + 1) {
      // Mark all intermediate waypoints as reached
      for (final intermediate in _waypoints) {
        if (intermediate.order > completedWaypoints.value &&
            intermediate.order < currentOrder) {
          intermediate.reached = true;
          if (!reachedWaypointHistory.contains(intermediate.id)) {
            reachedWaypointHistory.add(intermediate.id);
          }
        }
      }

      // Finally, mark the current waypoint as reached
      if (!reachedWaypointHistory.contains(waypoint.id)) {
        reachedWaypointHistory.add(waypoint.id);
      }

      completedWaypoints.value = currentOrder;
      isMovingBackward.value = false;
    }
  }

  /// Handle individual device timeout
  void _handleDeviceTimeouts() {
    final expiredThreshold = DateTime.now().subtract(_deviceTimeout);

    lastSeen.forEach((waypointId, lastSeenTime) {
      if (lastSeenTime.isBefore(expiredThreshold)) {
        // Gradual signal degradation instead of hard reset
        final currentStrength = signalStrength[waypointId] ?? _signalFloor;
        final newStrength = math.max(_signalFloor, currentStrength * 0.90);

        signalStrength[waypointId] = newStrength;
        signalQuality[waypointId] = 0.0;

        // Only reset RSSI, keep some signal strength
        smoothedRssi[waypointId] = -100.0;
        _stableSampleCount[waypointId] = 0;

        debugPrint('⏰ Timeout for $waypointId - graceful degradation');
      }
    });

    // Refresh UI if any changes occurred
    signalStrength.refresh();
    smoothedRssi.refresh();
  }

  /// Update signal displays for UI
  void _updateSignalDisplays() {
    smoothedRssi.refresh();
    signalStrength.refresh();
    signalQuality.refresh();
  }

  void _checkDestinationReached() {
    final distance = displayDistanceMeters.value;
    if (distance != null && distance <= 5.0 && !hasShownSuccess.value) {
      hasShownSuccess.value = true;
      if (Get.context != null) {
        SnackBarUtil.showSuccessSnackbar(
          Get.context!,
          'You have reached near your destination',
        );
      }
    }
  }

  /// Cleanup resources - Public method to allow manual cleanup
  void cleanup() {
    _cleanup();
  }

  /// Cleanup resources
  void _cleanup() {
    if (_isDisposed) {
      debugPrint('⚠️ Cleanup already called, skipping');
      return;
    }

    debugPrint('🧹 Cleaning up POC Navigation Controller');

    // Mark as disposed FIRST to prevent any restart attempts
    _isDisposed = true;

    // Set scanning to false immediately to prevent new operations
    isScanning.value = false;

    // Close any open snackbars first
    if (Get.context != null) {
      try {
        ScaffoldMessenger.of(Get.context!).clearSnackBars();
      } catch (e) {
        debugPrint('⚠️ Error clearing snackbars: $e');
      }
    }

    // Cancel timers
    try {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _uiUpdateTimer?.cancel();
      _uiUpdateTimer = null;
      _distanceUpdateTimer?.cancel();
      _distanceUpdateTimer = null;
    } catch (e) {
      debugPrint('⚠️ Error cancelling timers: $e');
    }

    // Dispose workers
    _rssiWorker?.dispose();
    _rssiWorker = null;
    _distanceWorker?.dispose();
    _distanceWorker = null;

    // Stop BLE scanning via service
    try {
      _bleService.dispose();
    } catch (e) {
      debugPrint('⚠️ Error disposing BLE service: $e');
    }

    // Stop GPS tracking and dispose location service
    try {
      _gpsService.stop(locationService: _locationService);
      // Also dispose the location service to close stream controller (fire-and-forget)
      _locationService.dispose().catchError((e) {
        debugPrint('⚠️ Error disposing location service: $e');
      });
    } catch (e) {
      debugPrint('⚠️ Error stopping GPS: $e');
    }

    // Clear observables to prevent further rebuilds
    currentPosition.value = null;
    mapDisplayPosition.value = null;
    mapDisplayPositionFast.value = null;
    headingDegrees.value = null;
    displayDistanceMeters.value = null;

    // Disable wakelock
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('⚠️ Error disabling wakelock: $e');
    }

    debugPrint('✅ POC Navigation Controller cleanup complete');
  }

  // Public API for UI

  /// Get ordered waypoints for display
  List<BleWaypoint> get orderedWaypoints =>
      List<BleWaypoint>.from(_waypoints)
        ..sort((a, b) => a.order.compareTo(b.order));

  /// Check if compass heading is available
  bool get hasHeading => headingDegrees.value != null;

  /// Check if compass heading is fresh (updated recently)
  bool get isHeadingFresh {
    if (_lastHeadingUpdate == null) return false;
    final age = DateTime.now().difference(_lastHeadingUpdate!);
    return age <= _headingStalenessThreshold;
  }

  /// Check if compass is calibrated and working properly
  bool get isCompassCalibrated {
    return hasHeading && isHeadingFresh;
  }

  /// Get compass calibration status message (for UI display if needed)
  String get compassStatusMessage {
    if (!hasHeading) {
      return 'Compass unavailable';
    } else if (!isHeadingFresh) {
      return 'Compass calibrating...';
    } else {
      return 'Compass ready';
    }
  }

  /// Get navigation arrow rotation with debug logging
  /// Uses fast-update position to match map display and checks data freshness
  double get navigationArrowRadians {
    // Use fast-update position to match map display (consistent source)
    final position =
        mapDisplayPositionFast.value ??
        mapDisplayPosition.value ??
        currentPosition.value;
    final heading = headingDegrees.value;
    final now = DateTime.now();

    // Check if data is available
    if (position == null || heading == null) {
      if (kDebugMode) {
        debugPrint(
          '🧭 Navigation: Missing data - Position: ${position != null ? "present" : "null"}, Heading: ${heading != null ? "present" : "null"}',
        );
      }
      return 0.0;
    }

    // Check data freshness: ensure position and heading are recent
    bool positionStale =
        _lastPositionUpdate == null ||
        now.difference(_lastPositionUpdate!) > _maxPositionHeadingAge;
    bool headingStale =
        _lastHeadingUpdate == null ||
        now.difference(_lastHeadingUpdate!) > _maxPositionHeadingAge;

    if (positionStale || headingStale) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Navigation data stale - Position: ${positionStale ? "stale" : "fresh"}, Heading: ${headingStale ? "stale" : "fresh"}',
        );
      }
      // Still calculate but log the issue
    }

    final bearing = bearingBetween(
      position.lat,
      position.lng,
      target.latitude,
      target.longitude,
    );

    final relativeDeg = (bearing - heading + 360.0) % 360.0;
    final radians = relativeDeg * (math.pi / 180.0);

    // Debug logs for compass testing
    if (kDebugMode) {
      debugPrint('🧭 === COMPASS DEBUG ===');
      debugPrint(
        '📍 Current: ${position.lat.toStringAsFixed(6)}, ${position.lng.toStringAsFixed(6)}',
      );
      debugPrint(
        '🎯 Target: ${target.latitude.toStringAsFixed(6)}, ${target.longitude.toStringAsFixed(6)}',
      );
      debugPrint('📐 True Bearing: ${bearing.toStringAsFixed(1)}°');
      debugPrint('🧭 Device Heading: ${heading.toStringAsFixed(1)}°');
      debugPrint('➡️ Relative Direction: ${relativeDeg.toStringAsFixed(1)}°');
      debugPrint(
        '🔄 Arrow Rotation: ${(radians * 180 / math.pi).toStringAsFixed(1)}°',
      );
      debugPrint('📏 Distance: ${distanceText}');
      debugPrint(
        '📊 Data freshness: Position=${positionStale ? "stale" : "fresh"}, Heading=${headingStale ? "stale" : "fresh"}',
      );
      debugPrint('🧭 ==================');
    }

    return radians;
  }

  /// Get distance text for UI
  String get distanceText {
    final distance = displayDistanceMeters.value ?? 0.0;

    if (distance >= 1000) {
      final km = distance / 1000;
      return '${km.toStringAsFixed(2)} km';
    } else {
      return '${distance.toStringAsFixed(0)} m';
    }
  }

  List<BleWaypoint> get waypoints => _waypoints;

  /// Get user progress position on the line (0 to 1)
  UserProgressPosition calculateUserPositionOnLineReversed(double height) {
    if (_waypoints.isEmpty) {
      return UserProgressPosition(currentY: height, targetY: height);
    }

    // Find nearest active waypoint based on signal strength
    String? strongestId;
    double strongestStrength = 0;

    signalStrength.forEach((waypointId, strength) {
      if (strength > strongestStrength) {
        strongestStrength = strength;
        strongestId = waypointId;
      }
    });

    if (strongestId == null) {
      return UserProgressPosition(currentY: height, targetY: height);
    }

    final strongestWaypoint = _waypointMap[strongestId]!;
    final index = _waypoints.indexOf(strongestWaypoint);

    // Position along the line (reverse)
    final segmentCount = _waypoints.length - 1;
    if (segmentCount <= 0) {
      return UserProgressPosition(currentY: height, targetY: height);
    }

    final segmentHeight = height / segmentCount;

    final currentY = height - (index * segmentHeight);
    final targetY = height - ((_waypoints.length - 1) * segmentHeight);

    return UserProgressPosition(currentY: currentY, targetY: targetY);
  }

  /// Distance helper for UI
  double calculateDistanceToTarget(
    double userLat,
    double userLng,
    double targetLat,
    double targetLng,
  ) {
    return Geolocator.distanceBetween(userLat, userLng, targetLat, targetLng);
  }

  /// Permissions handling
  Future<bool> _checkPermissions() async {
    // First check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ Location services are disabled');
      permissionsGranted.value = false;
      if (Get.context != null) {
        SnackBarUtil.showErrorSnackbar(
          Get.context!,
          'Please enable GPS/location services',
        );
      }
      return false;
    }

    final permissions = [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];

    final denied = <Permission>[];

    for (final permission in permissions) {
      final status = await permission.request();
      if (!status.isGranted) {
        denied.add(permission);
      }
    }

    if (denied.isEmpty) {
      permissionsGranted.value = true;
      debugPrint('✅ All permissions granted and location services enabled');
      return true;
    } else {
      permissionsGranted.value = false;
      _handlePermissionDenied(denied);
      return false;
    }
  }

  /// Handle permission denied
  void _handlePermissionDenied(List<Permission> denied) {
    final names = denied.map((p) => p.toString().split('.').last).join(', ');
    if (Get.context != null) {
      SnackBarUtil.showErrorSnackbar(
        Get.context!,
        'Permissions required: $names',
      );
    }

    Get.defaultDialog(
      title: 'Permissions Required',
      content: Text('Please grant: $names'),
      confirm: TextButton(
        onPressed: () {
          Get.back();
          openAppSettings();
        },
        child: const Text('Open Settings'),
      ),
      cancel: TextButton(
        onPressed: () => Get.back(),
        child: const Text('Cancel'),
      ),
    );
  }

  /// Get signal color for a waypoint based on signal strength
  Color signalColorFor(String waypointId) {
    final strength = signalStrength[waypointId] ?? 0.0;
    if (strength >= 85) return Colors.green;
    if (strength >= 65) return Colors.lightGreen;
    if (strength >= 45) return Colors.orange;
    if (strength >= 25) return Colors.deepOrange;
    return Colors.red;
  }

  /// Get signal strength percentage for a waypoint
  double signalPercentFor(String waypointId) {
    return signalStrength[waypointId] ?? 0.0;
  }

  /// Get signal quality label for a waypoint
  String signalQualityLabelFor(String waypointId) {
    final strength = signalStrength[waypointId] ?? 0.0;
    final quality = signalQuality[waypointId] ?? 0.0;

    // Combine strength and quality for overall assessment
    final overall = (strength * 0.7 + quality * 0.3);

    if (overall >= 85) return 'Excellent';
    if (overall >= 65) return 'Good';
    if (overall >= 45) return 'Fair';
    if (overall >= 25) return 'Weak';
    return 'Very Weak';
  }

  MapBounds calculateMapBounds({LatLng? userPosition}) {
    // If bounds are already locked, return existing bounds
    if (_mapBoundsLocked && mapBounds.value != null) {
      debugPrint('🗺️ [calculateMapBounds] Using locked bounds');
      return mapBounds.value!;
    }

    // If bounds exist but not locked, return them (safety check)
    if (mapBounds.value != null) {
      debugPrint('🗺️ [calculateMapBounds] Using existing (unlocked) bounds');
      return mapBounds.value!;
    }

    final userPoint =
        userPosition ?? mapDisplayPosition.value ?? currentPosition.value;

    debugPrint(
      '🗺️ [calculateMapBounds] Calculating new bounds: routePoints=${routePoints.length}, userPoint=${userPoint != null ? "present" : "null"}',
    );

    // Always start from the full route polyline so the entire zig-zag path
    // is visible on the mini-map.
    final points = <LatLng>[...routePoints, if (userPoint != null) userPoint];

    debugPrint(
      '🗺️ [calculateMapBounds] Total points for bounds calculation: ${points.length}',
    );
    for (var i = 0; i < points.length; i++) {
      debugPrint(
        '🗺️ [calculateMapBounds] Bounds point[$i]: lat=${points[i].lat.toStringAsFixed(6)}, lng=${points[i].lng.toStringAsFixed(6)}',
      );
    }

    // As an extra safety guard, if somehow routePoints is empty,
    // fall back to just the destination + user.
    if (points.isEmpty) {
      debugPrint(
        '🗺️ [calculateMapBounds] WARNING: points is empty, using fallback',
      );
      final destination = LatLng(target.latitude, target.longitude);
      points.add(destination);
      if (userPoint != null) {
        points.add(userPoint);
      }
    }

    final baseBounds = MapBounds.fromPoints(points)
        .enforceMinimumSpan(minSpan: _minMapSpanDegrees)
        // Symmetric padding so the whole route sits in the middle
        // of the mini-map instead of being pushed to the bottom.
        .withPadding(paddingFactor: 0.08, bottomBiasFactor: 0.0);

    debugPrint(
      '🗺️ [calculateMapBounds] Final bounds: minLat=${baseBounds.minLat.toStringAsFixed(6)}, maxLat=${baseBounds.maxLat.toStringAsFixed(6)}, minLng=${baseBounds.minLng.toStringAsFixed(6)}, maxLng=${baseBounds.maxLng.toStringAsFixed(6)}',
    );

    mapBounds.value = baseBounds;
    _mapBoundsLocked = true;
    return baseBounds;
  }

  Offset latLngToPixel(LatLng point, MapBounds bounds, Size mapSize) {
    final latRange = math.max(bounds.latRange, 1e-9);
    final lngRange = math.max(bounds.lngRange, 1e-9);

    final normalizedX = (point.lng - bounds.minLng) / lngRange;
    final normalizedY = (point.lat - bounds.minLat) / latRange;

    final clampedX = normalizedX.clamp(0.0, 1.0).toDouble();
    final clampedY = normalizedY.clamp(0.0, 1.0).toDouble();

    final dx = clampedX * mapSize.width;
    // Flip the vertical axis so that larger latitudes map towards the
    // bottom of the widget, effectively flipping the mini-map.
    final dy = clampedY * mapSize.height;

    return Offset(dx, dy);
  }

  void _handleError(String message, dynamic error) {
    debugPrint('❌ $message: $error');
    if (Get.context != null) {
      SnackBarUtil.showErrorSnackbar(Get.context!, '$message: $error');
    }
  }
}

/// User position data class
class UserProgressPosition {
  final double currentY;
  final double targetY;

  const UserProgressPosition({required this.currentY, required this.targetY});
}

class MapBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const MapBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  double get latRange => (maxLat - minLat).abs();
  double get lngRange => (maxLng - minLng).abs();

  factory MapBounds.fromPoints(List<LatLng> points) {
    double minLat = points.first.lat;
    double maxLat = points.first.lat;
    double minLng = points.first.lng;
    double maxLng = points.first.lng;

    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLng = math.min(minLng, point.lng);
      maxLng = math.max(maxLng, point.lng);
    }

    return MapBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  MapBounds enforceMinimumSpan({double minSpan = 0.0001}) {
    final adjustedLatRange = latRange < minSpan ? minSpan : latRange;
    final adjustedLngRange = lngRange < minSpan ? minSpan : lngRange;

    final latDelta = (adjustedLatRange - latRange) / 2;
    final lngDelta = (adjustedLngRange - lngRange) / 2;

    return MapBounds(
      minLat: minLat - latDelta,
      maxLat: maxLat + latDelta,
      minLng: minLng - lngDelta,
      maxLng: maxLng + lngDelta,
    );
  }

  MapBounds withPadding({
    double paddingFactor = 0.1,
    double bottomBiasFactor = 0.0,
  }) {
    final latPadding = latRange * paddingFactor;
    final lngPadding = lngRange * paddingFactor;
    final bottomPadding = latRange * bottomBiasFactor;

    return MapBounds(
      minLat: minLat - latPadding - bottomPadding,
      maxLat: maxLat + latPadding,
      minLng: minLng - lngPadding,
      maxLng: maxLng + lngPadding,
    );
  }
}
