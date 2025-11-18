import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../utiles/snackbar_utiles.dart';
import '../../../models/ble_waypoint.dart';
import '../../../models/saved_location.dart';
import '../../../services/ble_navigation_service.dart';
import '../../../services/filtered_location_service.dart';
import '../../../services/gps_navigation_service.dart';
import '../../../utils/geo_utils.dart';

class PocNavigationController extends GetxController {
  PocNavigationController(this.target);

  final SavedLocation target;

  // BLE configuration
  static const Duration _bleScanRestartInterval = Duration(seconds: 20);
  static const Duration _bleDeviceTimeout = Duration(seconds: 8);
  static const double _rssiSmoothingFactor =
      0.15; // More responsive for sub-meter accuracy
  static const int _rssiHistorySize = 15;
  static const int _rssiOutlierThreshold = 20;

  // Enhanced RSSI thresholds optimized for 1.5m detection radius
  static const int _rssiNear =
      -55; // 1-2m (target threshold for 1.5m detection)
  static const int _rssiMedium = -60; // 2-3m
  static const int _rssiFar = -65; // 3-5m

  // GPS configuration
  static const double _reachThresholdMeters = 3.0;
  static const int _stableSamplesRequired = 3;

  final FilteredLocationService _locationService = FilteredLocationService();
  final BleNavigationService _bleService = BleNavigationService();
  final GpsNavigationService _gpsService = GpsNavigationService();

  // Observable BLE state
  final scanCycleCount = 0.obs;
  final totalDetections = 0.obs;
  final permissionsGranted = false.obs;

  // Observable GPS state
  final currentPosition = Rxn<LatLng>();
  final headingDegrees = Rxn<double>();
  final displayDistanceMeters = Rxn<double>();
  final hasShownSuccess = false.obs;

  // Observable UI state
  final activeSignals = <BleWaypoint>[].obs;
  final completedWaypoints = 0.obs;

  // Complex state maps
  final RxMap<String, double> smoothedRssi = <String, double>{}.obs;
  final RxMap<String, double> signalQuality = <String, double>{}.obs;
  final RxMap<String, int> detectionCount = <String, int>{}.obs;

  final Map<String, List<int>> _rssiHistory = {};
  final Map<String, DateTime> _lastSeenTimestamp = {};

  final List<BleWaypoint> _bleWaypoints = [
    BleWaypoint(id: 'BEACON_1', label: 'Entry Point', order: 1),
    BleWaypoint(id: 'BEACON_2', label: 'Midpoint', order: 2),
    BleWaypoint(id: 'BEACON_3', label: 'Destination', order: 3),
  ];

  final Map<String, BleWaypoint> _beaconMap = {};

  final Map<String, String> _deviceToWaypointMap = {
    // 'AA:BB:CC:DD:EE:01': 'BEACON_1',
    // 'AA:BB:CC:DD:EE:02': 'BEACON_2',
    // 'AA:BB:CC:DD:EE:03': 'BEACON_3',
  };

  final Map<String, String> _beaconUuidMap = const {
    '00000001-0000-0000-0000-000000000001': 'BEACON_1',
    '00000002-0000-0000-0000-000000000002': 'BEACON_2',
    '00000003-0000-0000-0000-000000000003': 'BEACON_3',
  };

  LatLng? _startPosition;
  double? _smoothedDistanceMeters;
  int _stableBelowThresholdCount = 0;

  Worker? _rssiWorker;
  Worker? _signalWorker;
  Worker? _distanceWorker;

  @override
  void onInit() {
    super.onInit();
    _initializeBeaconMaps();
    _setupWorkers();
  }

  @override
  void onReady() {
    super.onReady();
    _checkPermissionsStatus().then((_) => _startTracking());
  }

  @override
  void onClose() {
    _rssiWorker?.dispose();
    _signalWorker?.dispose();
    _distanceWorker?.dispose();
    _bleService.dispose();
    _gpsService.stop(locationService: _locationService);
    WakelockPlus.disable();
    super.onClose();
  }

  List<BleWaypoint> get orderedWaypoints =>
      List<BleWaypoint>.from(_bleWaypoints)
        ..sort((a, b) => a.order.compareTo(b.order));

  List<BleWaypoint> get sortedActiveSignals =>
      List<BleWaypoint>.from(activeSignals);

  bool get hasHeading => headingDegrees.value != null;

  String get distanceText => displayDistanceMeters.value == null
      ? 'Calculating...'
      : '${displayDistanceMeters.value!.toStringAsFixed(1)} m away';

  String get navigationInstructions => hasHeading
      ? 'Follow the vertical progress line to your destination.'
      : 'Calibrating compass… move your phone in a figure-8.';

  double get navigationArrowRadians {
    final position = currentPosition.value;
    final heading = headingDegrees.value;
    if (position == null || heading == null) return 0.0;

    final bearing = bearingBetween(
      position.lat,
      position.lng,
      target.latitude,
      target.longitude,
    );
    final relativeDeg = (bearing - heading + 360.0) % 360.0;
    return relativeDeg * (math.pi / 180.0);
  }

  Future<void> restartBleScanning() async {
    await _bleService.stopScanning();
    await _startBleScanning();
  }

  Future<void> checkAndRequestPermissions() async {
    await _ensureBlePermissions();
  }

  UserProgressPosition calculateUserPositionOnLineReversed({
    required List<BleWaypoint> sortedWaypoints,
    required double lineHeight,
    required double lineTop,
  }) {
    if (sortedWaypoints.isEmpty) {
      return const UserProgressPosition(currentY: 0, completedHeight: 0);
    }

    int lastReachedIndex = -1;
    for (int i = 0; i < sortedWaypoints.length; i++) {
      if (sortedWaypoints[i].reached) {
        lastReachedIndex = i;
      }
    }

    final segmentHeight = lineHeight / (sortedWaypoints.length + 1);

    double completedHeight = 0.0;
    if (lastReachedIndex >= 0) {
      final reversedVisualIndex = sortedWaypoints.length - 1 - lastReachedIndex;
      completedHeight = segmentHeight * (reversedVisualIndex + 1);
    }

    double currentY;
    if (lastReachedIndex == sortedWaypoints.length - 1) {
      currentY = lineTop;
    } else if (lastReachedIndex < 0) {
      currentY = lineTop + lineHeight;
    } else {
      final nextWaypointIndex = lastReachedIndex + 1;
      final nextWaypoint = sortedWaypoints[nextWaypointIndex];
      final smoothed = smoothedRssi[nextWaypoint.id] ?? -100.0;

      const minRssi = -100.0;
      const maxRssi = -50.0;
      final progress = ((smoothed - minRssi) / (maxRssi - minRssi)).clamp(
        0.0,
        1.0,
      );

      final reversedLastIndex = sortedWaypoints.length - 1 - lastReachedIndex;
      final reversedNextIndex = sortedWaypoints.length - 1 - nextWaypointIndex;
      final lastReachedY = lineTop + segmentHeight * (reversedLastIndex + 1);
      final nextWaypointY = lineTop + segmentHeight * (reversedNextIndex + 1);

      currentY = lastReachedY + (nextWaypointY - lastReachedY) * progress;
    }

    return UserProgressPosition(
      currentY: currentY,
      completedHeight: completedHeight,
    );
  }

  int signalPercentFor(String waypointId) {
    final rssi = smoothedRssi[waypointId] ?? -100;
    return _calculateEnhancedSignalPercent(rssi);
  }

  String signalDistanceFor(String waypointId) {
    final rssi = smoothedRssi[waypointId] ?? -100;
    return _calculatePreciseDistance(rssi);
  }

  String signalQualityLabelFor(String waypointId) {
    final quality = signalQuality[waypointId] ?? 0.0;
    return _getSignalQualityLabel(quality);
  }

  Color signalColorFor(String waypointId) {
    final rssi = smoothedRssi[waypointId] ?? -100;
    final quality = signalQuality[waypointId] ?? 0.0;
    return _getEnhancedSignalColor(rssi, quality);
  }

  Future<void> _startTracking() async {
    try {
      await _gpsService.startTracking(
        locationService: _locationService,
        onPosition: _handlePositionUpdate,
        onHeading: _handleHeadingUpdate,
      );
      await _startBleScanning();
    } catch (e) {
      SnackBarUtil.showErrorSnackbar('Navigation start failed: $e');
    }
  }

  Future<void> _startBleScanning() async {
    try {
      await _bleService.startOptimizedBleScanning(
        permissionsGranted: permissionsGranted.value,
        ensurePermissions: _ensureBlePermissions,
        ensureBluetoothEnabled: _ensureBluetoothEnabled,
        scanRestartInterval: _bleScanRestartInterval,
        timeoutTickInterval: const Duration(seconds: 2),
        onScanResults: _processOptimizedBleScanResults,
        onRestart: () => scanCycleCount.value++,
        onTimeoutTick: _handleDeviceTimeout,
      );
      await WakelockPlus.enable();
    } catch (e) {
      SnackBarUtil.showErrorSnackbar('BLE scanning error: $e');
    }
  }

  void _initializeBeaconMaps() {
    for (final waypoint in _bleWaypoints) {
      _beaconMap[waypoint.id] = waypoint;
      _rssiHistory[waypoint.id] = [];
      smoothedRssi[waypoint.id] = -100.0;
      detectionCount[waypoint.id] = 0;
      signalQuality[waypoint.id] = 0.0;
    }
  }

  void _setupWorkers() {
    _rssiWorker = debounce(
      smoothedRssi,
      (_) => _recomputeActiveSignals(),
      time: const Duration(milliseconds: 80),
    );
    _signalWorker = ever(signalQuality, (_) => _recomputeActiveSignals());
    _distanceWorker = ever<double?>(
      displayDistanceMeters,
      (_) => _checkReached(),
    );
  }

  Future<void> _checkPermissionsStatus() async {
    final permissionsList = _getRequiredPermissions();
    bool allGranted = true;

    for (final perm in permissionsList) {
      final status = await perm.status;
      if (!status.isGranted) {
        allGranted = false;
        break;
      }
    }

    permissionsGranted.value = allGranted;
  }

  Future<void> _ensureBlePermissions() async {
    final permissionsList = _getRequiredPermissions();
    final denied = <Permission>[];

    for (final permission in permissionsList) {
      final status = await permission.status;
      if (status.isGranted) continue;

      final result = await permission.request();
      if (!result.isGranted) {
        denied.add(permission);
      }
    }

    if (denied.isNotEmpty) {
      final names = denied.map((p) => _getPermissionDisplayName(p)).join(', ');
      SnackBarUtil.showErrorSnackbar('Permission denied: $names');
      final shouldOpenSettings = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Permissions Required'),
          content: Text(
            'Please grant the following permissions to continue:\n\n$names',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
        await Future.delayed(const Duration(milliseconds: 500));
        await _checkPermissionsStatus();
      }
    } else {
      permissionsGranted.value = true;
    }
  }

  Future<void> _ensureBluetoothEnabled() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 15));
    }
  }

  List<Permission> _getRequiredPermissions() {
    final permissions = <Permission>[
      Permission.location,
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if (Platform.isAndroid) Permission.bluetooth,
    ];
    return permissions.where((p) => p.value != 21).toList();
  }

  String _getPermissionDisplayName(Permission permission) {
    switch (permission) {
      case Permission.location:
        return 'Location';
      case Permission.locationWhenInUse:
        return 'Location (When in use)';
      case Permission.bluetoothScan:
        return 'Bluetooth Scan';
      case Permission.bluetoothConnect:
        return 'Bluetooth Connect';
      case Permission.bluetooth:
        return 'Bluetooth';
      default:
        return permission.value.toString();
    }
  }

  void _handlePositionUpdate(LatLng position) {
    if (_startPosition == null) {
      _startPosition = position;
    }

    final rawDistance = Geolocator.distanceBetween(
      position.lat,
      position.lng,
      target.latitude,
      target.longitude,
    );

    final adaptiveAlpha = _calculateAdaptiveAlpha(rawDistance);
    if (_smoothedDistanceMeters == null) {
      _smoothedDistanceMeters = rawDistance;
    } else {
      _smoothedDistanceMeters =
          adaptiveAlpha * rawDistance +
          (1 - adaptiveAlpha) * _smoothedDistanceMeters!;
    }

    currentPosition.value = position;
    displayDistanceMeters.value = _smoothedDistanceMeters;
  }

  void _handleHeadingUpdate(double? heading) {
    headingDegrees.value = heading;
  }

  double _calculateAdaptiveAlpha(double currentDistance) {
    const baseAlpha = 0.2;
    const maxAlpha = 0.4;

    if (_smoothedDistanceMeters == null) return baseAlpha;

    final distanceChange = (currentDistance - _smoothedDistanceMeters!).abs();
    final changeFactor = (distanceChange / 10.0).clamp(0.0, 1.0);

    return baseAlpha + (maxAlpha - baseAlpha) * changeFactor;
  }

  void _processOptimizedBleScanResults(List<ScanResult> results) {
    if (results.isEmpty) return;

    final now = DateTime.now();
    bool significantUpdate = false;

    for (final result in results) {
      final device = result.device;
      final rssi = result.rssi;
      final adv = result.advertisementData;

      final matchedId = _performEnhancedDeviceMatching(device, adv);
      if (matchedId == null) continue;

      final waypoint = _beaconMap[matchedId];
      if (waypoint == null) continue;

      _lastSeenTimestamp[matchedId] = now;
      detectionCount[matchedId] = (detectionCount[matchedId] ?? 0) + 1;
      detectionCount.refresh();

      final previousSmoothed = smoothedRssi[matchedId] ?? -100.0;
      final newSmoothed = _processRssiWithAdvancedFiltering(matchedId, rssi);

      _updateSignalQuality(matchedId, rssi, newSmoothed);

      final wasReached = waypoint.reached;
      final threshold = _getDynamicThreshold(newSmoothed, matchedId);
      final stableSamples = _getAdaptiveStableSamples(matchedId);

      // Multi-factor validation before marking as reached (optimized for 1.5m detection)
      final quality = signalQuality[matchedId] ?? 0.0;
      final signalPercent = _calculateEnhancedSignalPercent(newSmoothed);
      final calculatedDistance = _calculateDistanceFromRssi(newSmoothed);

      // Check all conditions for waypoint detection (1.5m radius)
      // At 1.5m: Signal% ≈ 62.5%, RSSI ≈ -55 dBm, Distance = 1.5m
      final meetsRssiThreshold = newSmoothed >= threshold;
      final meetsQualityThreshold =
          quality > 0.60; // 60% quality for reliable detection
      final meetsSignalPercentThreshold =
          signalPercent >= 60; // 60% signal = ~1.5m (62.5% at exactly 1.5m)
      final meetsDistanceThreshold =
          calculatedDistance < 1.5; // Exactly 1.5m radius

      // Only proceed with updateRssi if all conditions are met (or already reached)
      bool shouldCheckReached =
          wasReached ||
          (meetsRssiThreshold &&
              meetsQualityThreshold &&
              meetsSignalPercentThreshold &&
              meetsDistanceThreshold);

      final justReached = shouldCheckReached
          ? waypoint.updateRssi(newSmoothed.round(), threshold, stableSamples)
          : false;

      if ((newSmoothed - previousSmoothed).abs() >= 2.0 || justReached) {
        significantUpdate = true;
      }

      smoothedRssi[matchedId] = newSmoothed;
      smoothedRssi.refresh();

      if (justReached && !wasReached) {
        completedWaypoints.value = _bleWaypoints.where((w) => w.reached).length;
        SnackBarUtil.showSuccessSnackbar('✅ Reached ${waypoint.label}');
        print(
          '🎯 WAYPOINT REACHED: ${waypoint.label} | '
          'RSSI: ${newSmoothed.toStringAsFixed(1)} dBm | '
          'Quality: ${(quality * 100).toStringAsFixed(0)}% | '
          'Signal: $signalPercent% | '
          'Distance: ${calculatedDistance.toStringAsFixed(2)}m',
        );
      }
    }

    totalDetections.value += results.length;

    if (significantUpdate) {
      _recomputeActiveSignals();
    }
  }

  double _processRssiWithAdvancedFiltering(String beaconId, int rawRssi) {
    final history = _rssiHistory[beaconId]!;

    history.add(rawRssi);
    if (history.length > _rssiHistorySize) {
      history.removeAt(0);
    }

    List<int> workingHistory = history;
    if (history.length >= 5) {
      workingHistory = _removeRssiOutliers(history);
    }

    double weightedSum = 0.0;
    double weightSum = 0.0;

    for (int i = 0; i < workingHistory.length; i++) {
      final weight = math.pow(1.2, i).toDouble();
      weightedSum += workingHistory[i] * weight;
      weightSum += weight;
    }

    final weightedAverage = weightSum > 0
        ? weightedSum / weightSum
        : rawRssi.toDouble();

    final currentSmoothed = smoothedRssi[beaconId] ?? -100.0;
    final newSmoothed =
        _rssiSmoothingFactor * weightedAverage +
        (1 - _rssiSmoothingFactor) * currentSmoothed;

    return newSmoothed;
  }

  List<int> _removeRssiOutliers(List<int> readings) {
    if (readings.length < 5) return readings;

    final sorted = List<int>.from(readings)..sort();
    final median = sorted[sorted.length ~/ 2];

    return readings
        .where((rssi) => (rssi - median).abs() <= _rssiOutlierThreshold)
        .toList();
  }

  void _updateSignalQuality(String beaconId, int rawRssi, double smoothed) {
    final history = _rssiHistory[beaconId]!;

    if (history.length < 3) {
      signalQuality[beaconId] = 0.3;
      signalQuality.refresh();
      return;
    }

    // Stricter variance threshold (200.0 instead of 400.0)
    final variance = _calculateRssiVariance(history);
    final consistencyScore = math.max(0.0, 1.0 - (variance / 200.0));

    // Non-linear penalty for inconsistency
    final consistencyPenalty = math.pow(consistencyScore, 1.5);

    final strengthScore = _calculateStrengthScore(smoothed);
    final detection = detectionCount[beaconId] ?? 0;

    // Higher detection requirements (50+ for max score instead of 20)
    final frequencyScore = math.min(1.0, detection / 50.0);

    // Quality score with stricter weighting - rarely exceeds 90% except at very close range
    final qualityScore =
        (consistencyPenalty * 0.5 + strengthScore * 0.3 + frequencyScore * 0.2)
            .clamp(0.0, 1.0);

    signalQuality[beaconId] = qualityScore;
    signalQuality.refresh();
  }

  double _calculateRssiVariance(List<int> readings) {
    if (readings.length < 2) return 0.0;

    final mean = readings.reduce((a, b) => a + b) / readings.length;
    final variance =
        readings
            .map((rssi) => math.pow(rssi - mean, 2))
            .reduce((a, b) => a + b) /
        readings.length;
    return variance;
  }

  double _calculateStrengthScore(double rssi) {
    const minRssi = -100.0;
    const maxRssi = -30.0;
    return ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);
  }

  int _getDynamicThreshold(double smoothedRssi, String beaconId) {
    final quality = signalQuality[beaconId] ?? 0.5;

    // Optimized for 1.5m detection: RSSI ≈ -55 dBm at 1.5m
    if (quality > 0.60 && smoothedRssi >= _rssiNear) {
      return _rssiNear; // -55 dBm for 1.5m detection (1-2m range)
    } else if (quality > 0.50 && smoothedRssi >= _rssiMedium) {
      return _rssiMedium; // -60 dBm (2-3m range)
    } else if (quality > 0.40 && smoothedRssi >= _rssiFar) {
      return _rssiFar; // -65 dBm (3-5m range)
    } else {
      return _rssiFar; // -65 dBm (far away, definitely not reached)
    }
  }

  int _getAdaptiveStableSamples(String beaconId) {
    final quality = signalQuality[beaconId] ?? 0.5;
    if (quality > 0.70) return 3; // Very good quality needs 3 samples
    if (quality > 0.60) return 4; // Good quality needs 4
    if (quality > 0.50) return 5; // Fair quality needs 5
    return 6; // Poor quality needs 6 samples
  }

  String? _performEnhancedDeviceMatching(
    BluetoothDevice device,
    AdvertisementData adv,
  ) {
    if (_deviceToWaypointMap.isNotEmpty) {
      final deviceId = device.remoteId.toString();
      final matched = _deviceToWaypointMap[deviceId];
      if (matched != null) return matched;
    }

    final extractedUuid = _extractBeaconUuid(adv);
    if (extractedUuid != null && _beaconUuidMap.containsKey(extractedUuid)) {
      return _beaconUuidMap[extractedUuid];
    }

    if (device.platformName.isNotEmpty) {
      final nameUpper = device.platformName.toUpperCase();
      for (var waypoint in _bleWaypoints) {
        if (nameUpper.contains(waypoint.id) ||
            nameUpper.contains('BEACON') ||
            nameUpper.contains('WAYPOINT') ||
            nameUpper.contains(
              waypoint.label.toUpperCase().replaceAll(' ', ''),
            )) {
          return waypoint.id;
        }
      }
    }

    for (var serviceUuid in adv.serviceUuids) {
      final uuidStr = serviceUuid.toString().toUpperCase();
      for (var entry in _beaconUuidMap.entries) {
        if (uuidStr.contains(entry.key.replaceAll('-', ''))) {
          return entry.value;
        }
      }
    }

    return null;
  }

  String? _extractBeaconUuid(AdvertisementData adv) {
    if (adv.manufacturerData.containsKey(0x004C)) {
      final data = adv.manufacturerData[0x004C]!;
      if (data.length >= 18 && data[0] == 0x02 && data[1] == 0x15) {
        return _formatUuidFromBytes(data.sublist(2, 18));
      }
    }

    for (final data in adv.manufacturerData.values) {
      if (data.length >= 18 && data[0] == 0xBE && data[1] == 0xAC) {
        return _formatUuidFromBytes(data.sublist(2, 18));
      }
    }

    return null;
  }

  String _formatUuidFromBytes(List<int> uuidBytes) {
    final hex = uuidBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
            '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
            '${hex.substring(20)}'
        .toUpperCase();
  }

  void _handleDeviceTimeout() {
    final expiredThreshold = DateTime.now().subtract(_bleDeviceTimeout);

    _lastSeenTimestamp.removeWhere((id, lastSeen) {
      if (lastSeen.isBefore(expiredThreshold)) {
        final waypoint = _beaconMap[id];

        // CRITICAL: Don't reset waypoints that are already reached
        // Once a waypoint is reached, it should stay reached even if signal is lost
        if (waypoint != null && waypoint.reached) {
          // Keep reached waypoint data but mark signal as lost
          // Don't clear RSSI completely, just set to a low value for display
          // This preserves the waypoint's reached status
          return false; // Keep in timestamp map to avoid resetting
        }

        // Only clear data for unreached waypoints
        smoothedRssi[id] = -100.0;
        signalQuality[id] = 0.0;
        detectionCount[id] = 0;
        _rssiHistory[id]?.clear();

        // Only reset unreached waypoints
        waypoint?.reset();
        return true;
      }
      return false;
    });

    smoothedRssi.refresh();
    signalQuality.refresh();
    detectionCount.refresh();
    _recomputeActiveSignals();
  }

  void _recomputeActiveSignals() {
    // Include waypoints that either:
    // 1. Have active signal (RSSI > -95 and quality > 0.1), OR
    // 2. Are already reached (preserve reached status even if signal is lost)
    final filtered =
        _bleWaypoints.where((waypoint) {
          if (waypoint.reached) {
            // Always include reached waypoints, even if signal is lost
            return true;
          }
          // For unreached waypoints, only include if they have active signal
          final rssi = smoothedRssi[waypoint.id] ?? -100.0;
          final quality = signalQuality[waypoint.id] ?? 0.0;
          return rssi > -95.0 && quality > 0.1;
        }).toList()..sort((a, b) {
          // Prioritize reached waypoints, then by signal strength
          if (a.reached && !b.reached) return -1;
          if (!a.reached && b.reached) return 1;

          final rssiA = smoothedRssi[a.id] ?? -100.0;
          final rssiB = smoothedRssi[b.id] ?? -100.0;
          final qualityA = signalQuality[a.id] ?? 0.0;
          final qualityB = signalQuality[b.id] ?? 0.0;
          final scoreA = rssiA * (0.7 + qualityA * 0.3);
          final scoreB = rssiB * (0.7 + qualityB * 0.3);
          return scoreB.compareTo(scoreA);
        });

    activeSignals.assignAll(filtered);
    completedWaypoints.value = _bleWaypoints.where((w) => w.reached).length;
  }

  void _checkReached() {
    if (hasShownSuccess.value) return;

    final distance = displayDistanceMeters.value;
    if (distance == null) return;

    if (distance <= _reachThresholdMeters) {
      _stableBelowThresholdCount++;
    } else {
      _stableBelowThresholdCount = 0;
    }

    if (_stableBelowThresholdCount >= _stableSamplesRequired) {
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    if (hasShownSuccess.value) return;
    hasShownSuccess.value = true;

    Get.defaultDialog(
      title: '🎉 Success!',
      barrierDismissible: false,
      content: Column(
        children: [
          Text('You have reached "${target.name}".'),
          const SizedBox(height: 8),
          Text(
            'Completed waypoints: ${completedWaypoints.value}/${_bleWaypoints.length}',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
      confirm: TextButton(
        onPressed: () {
          Get.back();
          Get.back();
        },
        child: const Text('OK'),
      ),
    );
  }

  /// Physics-based signal percentage calculation using path loss model
  ///
  /// Returns accurate percentage based on actual proximity:
  /// - 95%+ when < 0.5m from beacon
  /// - 70%+ when < 1m from beacon
  /// - 40%+ when < 3m from beacon
  int _calculateEnhancedSignalPercent(double rssi) {
    // Path loss model parameters
    const txPower = -59.0; // Typical BLE beacon transmit power
    const pathLossExponent = 2.4; // Indoor environment

    // Calculate distance from RSSI using path loss model
    // Distance = 10^((TxPower - RSSI) / (10 * n))
    final distance = math
        .pow(10, (txPower - rssi) / (10 * pathLossExponent))
        .toDouble();

    // Convert distance to percentage using exponential decay
    // At 0m: 100%, At 0.5m: ~95%, At 1m: ~70%, At 3m: ~40%, At 10m: ~10%
    double percent;
    if (distance <= 0.5) {
      // Very close (<0.5m): 95-100%
      percent = 95.0 + (0.5 - distance) * 10.0; // Linear from 95% to 100%
    } else if (distance <= 1.0) {
      // Close (0.5-1m): 70-95%
      percent = 70.0 + (1.0 - distance) * 50.0; // Linear from 70% to 95%
    } else if (distance <= 3.0) {
      // Medium (1-3m): 40-70%
      percent = 40.0 + (3.0 - distance) * 15.0; // Linear from 40% to 70%
    } else if (distance <= 10.0) {
      // Far (3-10m): 10-40%
      percent = 10.0 + (10.0 - distance) * 4.29; // Linear from 10% to 40%
    } else {
      // Very far (>10m): 0-10%
      percent = math.max(0.0, 10.0 - (distance - 10.0) * 1.0);
    }

    return percent.round().clamp(0, 100);
  }

  /// Calculate distance in meters from RSSI using path loss model
  double _calculateDistanceFromRssi(double rssi) {
    const txPower = -59.0;
    const pathLossExponent = 2.4;

    if (rssi >= -30) return 0.1; // Very close, assume <10cm

    final distance = math
        .pow(10, (txPower - rssi) / (10 * pathLossExponent))
        .toDouble();
    return distance.clamp(0.0, 100.0); // Cap at 100m
  }

  String _calculatePreciseDistance(double rssi) {
    final distance = _calculateDistanceFromRssi(rssi);

    if (distance < 0.3) return '< 30cm';
    if (distance < 0.5) return '≈ ${(distance * 100).round()} cm';
    if (distance < 1.0) return '≈ ${(distance * 100).round()} cm';
    if (distance < 5.0) return '≈ ${distance.toStringAsFixed(1)} m';
    if (distance < 20.0) return '≈ ${distance.toStringAsFixed(0)} m';
    return '> 20 m';
  }

  String _getSignalQualityLabel(double quality) {
    if (quality >= 0.9) return 'Excellent Signal';
    if (quality >= 0.75) return 'Very Good Signal';
    if (quality >= 0.6) return 'Good Signal';
    if (quality >= 0.4) return 'Fair Signal';
    if (quality >= 0.2) return 'Weak Signal';
    return 'Poor Signal';
  }

  Color _getEnhancedSignalColor(double rssi, double quality) {
    // Use physics-based signal percentage for color determination
    final signalPercent = _calculateEnhancedSignalPercent(rssi);

    // Combine signal percentage with quality for color
    final combinedScore = (signalPercent / 100.0) * 0.7 + quality * 0.3;

    if (combinedScore >= 0.85) return Colors.green; // Very close (<1m)
    if (combinedScore >= 0.70) return Colors.lightGreen; // Close (1-2m)
    if (combinedScore >= 0.50) return Colors.orange; // Medium (2-3m)
    if (combinedScore >= 0.30) return Colors.deepOrange; // Far (3-5m)
    return Colors.red; // Very far (>5m)
  }
}

class UserProgressPosition {
  final double currentY;
  final double completedHeight;

  const UserProgressPosition({
    required this.currentY,
    required this.completedHeight,
  });
}
