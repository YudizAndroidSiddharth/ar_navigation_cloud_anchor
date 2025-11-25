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

  // GPS Configuration
  static const double _gpsDestinationThreshold = 3.0;
  static const double _signalFloor = 5.0; // Never show 0%

  // Services
  final FilteredLocationService _locationService = FilteredLocationService();
  final GpsNavigationService _gpsService = GpsNavigationService();

  // Core Observable State
  final totalDetections = 0.obs;
  final permissionsGranted = false.obs;
  final currentPosition = Rxn<LatLng>();
  final headingDegrees = Rxn<double>();
  final displayDistanceMeters = Rxn<double>();
  final hasShownSuccess = false.obs;
  final isScanning = false.obs;

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

  // Waypoint Configuration
  final List<BleWaypoint> _waypoints = [
    BleWaypoint(id: 'BEACON_1', label: 'Entry Point', order: 1),
    BleWaypoint(id: 'BEACON_2', label: 'Midpoint', order: 2),
    BleWaypoint(id: 'BEACON_3', label: 'Destination', order: 3),
  ];

  final Map<String, BleWaypoint> _waypointMap = {};

  // Beacon Device Mapping
  final Map<String, String> _deviceToWaypointMap = {
    '6B:14:28:14:EF:C5': 'BEACON_1', // lable no : 1
    'C7:81:19:F7:CA:75': 'BEACON_2', // lable no : 4
    'EC:B9:75:AB:22:23': 'BEACON_3', // lable no : 5
  };

  // Scanning State
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _timeoutTimer;
  Timer? _uiUpdateTimer;
  bool _isDisposed = false; // Track if controller is disposed

  // UI Update Workers
  Worker? _rssiWorker;
  Worker? _distanceWorker;

  double? _smoothedDistanceMeters;
  int _stableGpsCount = 0;

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
    _checkPermissions().then((_) => _startNavigation());
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
    await _gpsService.startTracking(
      locationService: _locationService,
      onPosition: _handleGpsUpdate,
      onHeading: _handleHeadingUpdate,
    );
  }

  /// Start continuous BLE scanning (no restarts)
  Future<void> _startContinuousBleScanning() async {
    // Don't start if disposed
    if (_isDisposed) {
      debugPrint('⚠️ Cannot start scanning - controller is disposed');
      return;
    }

    try {
      await _ensureBluetoothReady();

      // Stop any existing scan
      if (_scanSubscription != null) {
        await FlutterBluePlus.stopScan();
        await _scanSubscription?.cancel();
      }

      // Double check we're not disposed before starting
      if (_isDisposed) {
        debugPrint('⚠️ Controller disposed before starting scan');
        return;
      }

      debugPrint('🚀 Starting continuous BLE scanning');

      // Start continuous scan with no timeout
      await FlutterBluePlus.startScan(
        timeout: null, // Continuous scanning
        continuousUpdates: true, // Critical for real-time updates
        continuousDivisor: 1, // Process all advertisements
        oneByOne: false, // Deduplicated list mode
        androidScanMode: AndroidScanMode.lowLatency, // Fastest scanning
        androidUsesFineLocation: true,
      );

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        _processScanResults,
        onError: (e) => _handleError('BLE scan error', e),
      );

      // Monitor adapter state
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (state != BluetoothAdapterState.on) {
          _handleBluetoothStateChange(state);
        }
      });

      // Start timeout monitoring for individual devices
      _startTimeoutMonitoring();

      isScanning.value = true;
      debugPrint('✅ Continuous BLE scanning started successfully');
    } catch (e) {
      _handleError('Failed to start BLE scanning', e);
    }
  }

  /// Ensure Bluetooth is ready
  Future<void> _ensureBluetoothReady() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      if (adapterState == BluetoothAdapterState.off) {
        await FlutterBluePlus.turnOn();
      }

      // Wait for Bluetooth to be ready
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10));
    }
  }

  /// Monitor Bluetooth state changes
  void _handleBluetoothStateChange(BluetoothAdapterState state) {
    // Don't restart if controller is disposed
    if (_isDisposed) {
      debugPrint(
        '🔵 Bluetooth state changed but controller is disposed: $state',
      );
      return;
    }

    debugPrint('🔵 Bluetooth state changed: $state');

    if (state == BluetoothAdapterState.on) {
      // Restart scanning when Bluetooth comes back (only if not disposed)
      if (!_isDisposed) {
        _startContinuousBleScanning();
      }
    } else {
      isScanning.value = false;
      if (!_isDisposed && Get.context != null) {
        SnackBarUtil.showErrorSnackbar(Get.context!, 'Bluetooth disconnected');
      }
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
    if (results.isEmpty) return;

    final now = DateTime.now();
    bool hasSignificantUpdate = false;

    for (final result in results) {
      final waypointId = _matchDevice(result.device);
      if (waypointId == null) continue;

      final rssi = result.rssi;
      lastSeen[waypointId] = now;
      detectionCount[waypointId] = (detectionCount[waypointId] ?? 0) + 1;

      // Process RSSI with enhanced filtering
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

    if (waypointId != null) {
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

    // Remove outliers if we have enough samples
    final filteredHistory = history.length >= 3
        ? _removeOutliers(history)
        : history;

    // Calculate weighted average favoring recent samples
    double weightedSum = 0.0;
    double weightSum = 0.0;

    for (int i = 0; i < filteredHistory.length; i++) {
      final weight = math.pow(1.8, i).toDouble();
      weightedSum += filteredHistory[i] * weight;
      weightSum += weight;
    }

    final weightedAverage = weightSum > 0
        ? weightedSum / weightSum
        : rawRssi.toDouble();

    return _rssiSmoothingFactor * weightedAverage +
        (1 - _rssiSmoothingFactor) * currentSmoothed;
  }

  /// Remove RSSI outliers using median filtering
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

  /// Calculate signal strength percentage from RSSI
  double _calculateSignalStrength(double rssi) {
    const minRssi = -100.0;
    const maxRssi = -60.0;
    return math.max(
      _signalFloor,
      ((rssi - minRssi) / (maxRssi - minRssi) * 100).clamp(0.0, 100.0),
    );
  }

  /// Update signal quality based on consistency
  void _updateSignalQuality(String waypointId, double smoothedRssi) {
    final history = _rssiHistory[waypointId]!;
    if (history.length < 2) {
      signalQuality[waypointId] = 0.3;
      return;
    }

    // Calculate variance for consistency score
    final mean = history.reduce((a, b) => a + b) / history.length;
    final variance =
        history
            .map((rssi) => math.pow(rssi - mean, 2))
            .reduce((a, b) => a + b) /
        history.length;

    final consistencyScore = math.max(0.0, 1.0 - (variance / 200.0));
    final strengthScore = _calculateSignalStrength(smoothedRssi) / 100.0;
    final detections = detectionCount[waypointId] ?? 0;
    final frequencyScore = math.min(1.0, detections / 10.0);

    final quality =
        (consistencyScore * 0.4 + strengthScore * 0.4 + frequencyScore * 0.2)
            .clamp(0.0, 1.0);

    signalQuality[waypointId] = quality;
  }

  /// Process waypoint detection with stable sampling
  /// Process waypoint detection with stable sampling
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

      if (currentCount + 1 >= _requiredStableSamples) {
        if (!waypoint.reached) {
          // First time reaching this waypoint
          _handleWaypointReached(waypointId, now);
          _stableSampleCount[waypointId] = 0;
          return true;
        } else if (waypoint.reached && _isBackwardMovement(waypointId)) {
          // User moved backward to previously reached waypoint
          _handleWaypointUnreached(waypointId, now);
          _stableSampleCount[waypointId] = 0;
          return true;
        }
        // If waypoint.reached && !_isBackwardMovement -> user staying at same waypoint, do nothing
      }
    } else {
      _stableSampleCount[waypointId] = math.max(0, currentCount - 1);
    }

    return false;
  }

  /// Check if detecting this waypoint represents backward movement
  bool _isBackwardMovement(String waypointId) {
    if (reachedWaypointHistory.isEmpty) return false;

    final currentWaypoint = _waypointMap[waypointId]!;
    final lastReachedId = reachedWaypointHistory.last;
    final lastWaypoint = _waypointMap[lastReachedId]!;

    // Backward movement: current waypoint order < last reached waypoint order
    return currentWaypoint.order < lastWaypoint.order;
  }

  /// Handle waypoint reached with bidirectional logic
  void _handleWaypointReached(String waypointId, DateTime timestamp) {
    final waypoint = _waypointMap[waypointId]!;
    _lastStateChange[waypointId] = timestamp;

    _updateWaypointProgression(waypointId);

    final direction = isMovingBackward.value ? 'LEFT' : 'REACHED';
    final emoji = isMovingBackward.value ? '⬅️' : '✅';

    if (Get.context != null) {
      SnackBarUtil.showSuccessSnackbar(
        Get.context!,
        '$emoji $direction ${waypoint.label}',
      );
    }

    debugPrint('🎯 WAYPOINT $direction: ${waypoint.label}');
    debugPrint('   RSSI: ${smoothedRssi[waypointId]?.toStringAsFixed(1)}dBm');
    debugPrint(
      '   Strength: ${signalStrength[waypointId]?.toStringAsFixed(1)}%',
    );
  }

  /// Handle waypoint unreached (backward movement)
  void _handleWaypointUnreached(String waypointId, DateTime timestamp) {
    final waypoint = _waypointMap[waypointId]!;
    _lastStateChange[waypointId] = timestamp;

    // This means user returned to a previously reached waypoint
    // Mark all waypoints after this one as unreached
    _handleBackwardMovement(waypointId);

    //SnackBarUtil.showSuccessSnackbar('⬅️ RETURNED TO ${waypoint.label}');
    debugPrint('🎯 WAYPOINT LEFT: ${waypoint.label}');
  }

  /// Handle backward movement logic
  void _handleBackwardMovement(String targetWaypointId) {
    final targetIndex = reachedWaypointHistory.indexOf(targetWaypointId);
    if (targetIndex == -1) return;

    // Remove all waypoints after target from history
    while (reachedWaypointHistory.length > targetIndex + 1) {
      final removedId = reachedWaypointHistory.removeLast();
      final removedWaypoint = _waypointMap[removedId]!;
      removedWaypoint.reached = false;
      removedWaypoint.reset();
    }

    isMovingBackward.value = true;
    completedWaypoints.value = reachedWaypointHistory.length;
  }

  /// Update waypoint progression with bidirectional support
  void _updateWaypointProgression(String currentWaypointId) {
    final currentWaypoint = _waypointMap[currentWaypointId]!;

    if (reachedWaypointHistory.isEmpty) {
      // First waypoint reached
      reachedWaypointHistory.add(currentWaypointId);
      currentWaypoint.reached = true;
      isMovingBackward.value = false;
    } else {
      final lastReachedId = reachedWaypointHistory.last;
      final lastWaypoint = _waypointMap[lastReachedId]!;

      if (currentWaypoint.order == lastWaypoint.order + 1) {
        // Moving forward
        reachedWaypointHistory.add(currentWaypointId);
        currentWaypoint.reached = true;
        isMovingBackward.value = false;
      } else if (currentWaypoint.order == lastWaypoint.order - 1) {
        // Moving backward
        if (reachedWaypointHistory.isNotEmpty) {
          final removedId = reachedWaypointHistory.removeLast();
          final removedWaypoint = _waypointMap[removedId]!;
          removedWaypoint.reached = false;
          removedWaypoint.reset();
        }
        isMovingBackward.value = true;
      } else if (currentWaypointId != lastReachedId) {
        // Jump to non-adjacent waypoint
        _handleWaypointJump(currentWaypointId);
      }
    }

    completedWaypoints.value = reachedWaypointHistory.length;
  }

  /// Handle waypoint jump (rebuild progression)
  void _handleWaypointJump(String waypointId) {
    final waypoint = _waypointMap[waypointId]!;

    reachedWaypointHistory.clear();

    // Mark all waypoints up to current as reached
    for (final wp in _waypoints) {
      if (wp.order <= waypoint.order) {
        wp.reached = true;
        reachedWaypointHistory.add(wp.id);
      } else {
        wp.reached = false;
        wp.reset();
      }
    }

    isMovingBackward.value = false;
    debugPrint('🔄 Jump detected - rebuilt sequence to ${waypoint.label}');
  }

  /// Handle device timeouts with graceful degradation
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
    // This method is called by the debounced worker
    // Signals are already updated, just trigger UI refresh
    signalStrength.refresh();
  }

  /// Handle GPS position updates
  void _handleGpsUpdate(LatLng position) {
    currentPosition.value = position;

    final rawDistance = Geolocator.distanceBetween(
      position.lat,
      position.lng,
      target.latitude,
      target.longitude,
    );

    // Smooth distance updates
    if (_smoothedDistanceMeters == null) {
      _smoothedDistanceMeters = rawDistance;
    } else {
      _smoothedDistanceMeters =
          0.4 * rawDistance + 0.6 * _smoothedDistanceMeters!;
    }

    displayDistanceMeters.value = _smoothedDistanceMeters;
  }

  /// Handle compass heading updates
  void _handleHeadingUpdate(double? heading) {
    headingDegrees.value = heading;
  }

  /// Check if destination is reached via GPS
  void _checkDestinationReached() {
    if (hasShownSuccess.value) return;

    final distance = displayDistanceMeters.value;
    if (distance == null) return;

    if (distance <= _gpsDestinationThreshold) {
      _stableGpsCount++;
    } else {
      _stableGpsCount = 0;
    }

    if (_stableGpsCount >= 3) {
      _showDestinationReachedDialog();
    }
  }

  /// Show destination reached dialog
  void _showDestinationReachedDialog() {
    if (hasShownSuccess.value) return;
    hasShownSuccess.value = true;

    Get.defaultDialog(
      title: '🎉 Destination Reached!',
      barrierDismissible: false,
      content: Column(
        children: [
          Text('You have successfully navigated to "${target.name}".'),
          const SizedBox(height: 12),
          Text(
            'Waypoints completed: ${completedWaypoints.value}/${_waypoints.length}',
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      confirm: TextButton(
        onPressed: () {
          Get.back();
          Get.back();
        },
        child: const Text('Complete'),
      ),
    );
  }

  /// Check and request permissions
  Future<void> _checkPermissions() async {
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
    } else {
      _handlePermissionDenied(denied);
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
        child: const Text('Settings'),
      ),
    );
  }

  /// Handle errors with logging
  void _handleError(String message, dynamic error) {
    debugPrint('❌ $message: $error');
    if (Get.context != null) {
      SnackBarUtil.showErrorSnackbar(Get.context!, '$message: $error');
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
      SnackBarUtil.clearSnackBars(Get.context!);
    }

    // Cancel scan subscription FIRST - this stops processing scan results
    _scanSubscription?.cancel();
    _scanSubscription = null;

    // Cancel adapter state subscription
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;

    // Cancel all timers
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    // Dispose workers
    _rssiWorker?.dispose();
    _rssiWorker = null;
    _distanceWorker?.dispose();
    _distanceWorker = null;

    // Stop BLE scanning - call synchronously and handle errors
    try {
      // Stop scan immediately - don't wait for async completion
      FlutterBluePlus.stopScan()
          .then((_) {
            debugPrint('✅ BLE scanning stopped successfully');
          })
          .catchError((e) {
            debugPrint('⚠️ Error stopping scan: $e');
            // Try one more time
            FlutterBluePlus.stopScan().catchError((e2) {
              debugPrint('⚠️ Second attempt to stop scan also failed: $e2');
            });
          });
    } catch (e) {
      debugPrint('⚠️ Exception while stopping scan: $e');
    }

    // Stop GPS tracking
    try {
      _gpsService.stop(locationService: _locationService);
    } catch (e) {
      debugPrint('⚠️ Error stopping GPS: $e');
    }

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

  /// Get navigation arrow rotation with debug logging
  double get navigationArrowRadians {
    final position = currentPosition.value;
    final heading = headingDegrees.value;

    if (position == null || heading == null) {
      debugPrint(
        '🧭 Navigation: Missing data - Position: $position, Heading: $heading',
      );
      return 0.0;
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
    debugPrint('🧭 ==================');

    return radians;
  }

  /// Get distance text for display
  String get distanceText => displayDistanceMeters.value == null
      ? 'Calculating...'
      : '${displayDistanceMeters.value!.toStringAsFixed(1)} m away';

  /// Get navigation instructions
  String get navigationInstructions {
    final directionInfo = isMovingBackward.value ? ' - Moving backward ⬅️' : '';
    return hasHeading
        ? 'Follow the arrow to your destination.$directionInfo'
        : 'Calibrate compass by moving phone in figure-8.$directionInfo';
  }

  /// Get signal percentage for waypoint
  int signalPercentFor(String waypointId) {
    return (signalStrength[waypointId] ?? _signalFloor).round().clamp(0, 100);
  }

  /// Get signal quality label
  String signalQualityLabelFor(String waypointId) {
    final quality = signalQuality[waypointId] ?? 0.0;
    if (quality >= 0.8) return 'Excellent';
    if (quality >= 0.6) return 'Very Good';
    if (quality >= 0.4) return 'Good';
    if (quality >= 0.2) return 'Fair';
    return 'Weak';
  }

  /// Get signal color for UI
  Color signalColorFor(String waypointId) {
    final waypoint = _waypointMap[waypointId];
    if (waypoint?.reached == true) return Colors.green;

    final strength = signalStrength[waypointId] ?? _signalFloor;
    if (strength >= 80) return Colors.green;
    if (strength >= 60) return Colors.lightGreen;
    if (strength >= 40) return Colors.orange;
    if (strength >= 20) return Colors.deepOrange;
    return Colors.red;
  }

  /// Calculate user position on progress line
  UserProgressPosition calculateUserPositionOnLineReversed({
    required List<BleWaypoint> sortedWaypoints,
    required double lineHeight,
    required double lineTop,
  }) {
    if (sortedWaypoints.isEmpty) {
      return const UserProgressPosition(currentY: 0, completedHeight: 0);
    }

    final lastReachedIndex = reachedWaypointHistory.isEmpty
        ? -1
        : sortedWaypoints.indexWhere(
            (w) => w.id == reachedWaypointHistory.last,
          );

    final segmentHeight = lineHeight / (sortedWaypoints.length + 1);

    double completedHeight = 0.0;
    if (lastReachedIndex >= 0) {
      final reversedIndex = sortedWaypoints.length - 1 - lastReachedIndex;
      completedHeight = segmentHeight * (reversedIndex + 1);
    }

    double currentY;
    if (lastReachedIndex == sortedWaypoints.length - 1) {
      currentY = lineTop;
    } else if (lastReachedIndex < 0) {
      currentY = lineTop + lineHeight;
    } else {
      final nextIndex = lastReachedIndex + 1;
      final nextWaypoint = sortedWaypoints[nextIndex];

      final progress = ((signalStrength[nextWaypoint.id] ?? _signalFloor) / 100)
          .clamp(0.0, 1.0);

      final reversedLastIndex = sortedWaypoints.length - 1 - lastReachedIndex;
      final reversedNextIndex = sortedWaypoints.length - 1 - nextIndex;

      final lastY = lineTop + segmentHeight * (reversedLastIndex + 1);
      final nextY = lineTop + segmentHeight * (reversedNextIndex + 1);

      currentY = lastY + (nextY - lastY) * progress;
    }

    return UserProgressPosition(
      currentY: currentY,
      completedHeight: completedHeight,
    );
  }

  /// Public method to restart scanning if needed
  Future<void> restartScanning() async {
    debugPrint('🔄 Manual scan restart requested');
    _cleanup();
    await Future.delayed(const Duration(milliseconds: 500));
    await _startContinuousBleScanning();
  }
}

/// User position data class
class UserProgressPosition {
  final double currentY;
  final double completedHeight;

  const UserProgressPosition({
    required this.currentY,
    required this.completedHeight,
  });
}
