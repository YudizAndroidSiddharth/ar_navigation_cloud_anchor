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
  static const double _rssiSmoothingFactor = 0.25;
  static const int _rssiHistorySize = 15;
  static const int _rssiOutlierThreshold = 20;

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
      final progress =
          ((smoothed - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);

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
    _signalWorker = ever(
      signalQuality,
      (_) => _recomputeActiveSignals(),
    );
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
      final names =
          denied.map((p) => _getPermissionDisplayName(p)).join(', ');
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
      final justReached = waypoint.updateRssi(
        newSmoothed.round(),
        threshold,
        _getAdaptiveStableSamples(matchedId),
      );

      if ((newSmoothed - previousSmoothed).abs() >= 2.0 || justReached) {
        significantUpdate = true;
      }

      smoothedRssi[matchedId] = newSmoothed;
      smoothedRssi.refresh();

      if (justReached && !wasReached) {
        completedWaypoints.value =
            _bleWaypoints.where((w) => w.reached).length;
        SnackBarUtil.showSuccessSnackbar('Reached ${waypoint.label}');
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

    final weightedAverage =
        weightSum > 0 ? weightedSum / weightSum : rawRssi.toDouble();

    final currentSmoothed = smoothedRssi[beaconId] ?? -100.0;
    final newSmoothed = _rssiSmoothingFactor * weightedAverage +
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

    final variance = _calculateRssiVariance(history);
    final consistencyScore = math.max(0.0, 1.0 - (variance / 400.0));
    final strengthScore = _calculateStrengthScore(smoothed);
    final detection = detectionCount[beaconId] ?? 0;
    final frequencyScore = math.min(1.0, detection / 20.0);

    final qualityScore =
        (consistencyScore * 0.4 + strengthScore * 0.4 + frequencyScore * 0.2)
            .clamp(0.0, 1.0);

    signalQuality[beaconId] = qualityScore;
    signalQuality.refresh();
  }

  double _calculateRssiVariance(List<int> readings) {
    if (readings.length < 2) return 0.0;

    final mean = readings.reduce((a, b) => a + b) / readings.length;
    final variance = readings
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

    if (quality > 0.8 && smoothedRssi >= -55) {
      return -55;
    } else if (quality > 0.6 && smoothedRssi >= -65) {
      return -65;
    } else {
      return -75;
    }
  }

  int _getAdaptiveStableSamples(String beaconId) {
    final quality = signalQuality[beaconId] ?? 0.5;
    if (quality > 0.8) return 2;
    if (quality > 0.6) return 3;
    return 5;
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
            nameUpper.contains(waypoint.label.toUpperCase().replaceAll(' ', ''))) {
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
    final hex = uuidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}'
        .toUpperCase();
  }

  void _handleDeviceTimeout() {
    final expiredThreshold = DateTime.now().subtract(_bleDeviceTimeout);

    _lastSeenTimestamp.removeWhere((id, lastSeen) {
      if (lastSeen.isBefore(expiredThreshold)) {
        smoothedRssi[id] = -100.0;
        signalQuality[id] = 0.0;
        detectionCount[id] = 0;
        _rssiHistory[id]?.clear();

        final waypoint = _beaconMap[id];
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
    final filtered = _bleWaypoints.where((waypoint) {
      final rssi = smoothedRssi[waypoint.id] ?? -100.0;
      final quality = signalQuality[waypoint.id] ?? 0.0;
      return rssi > -95.0 && quality > 0.1;
    }).toList()
      ..sort((a, b) {
        final rssiA = smoothedRssi[a.id] ?? -100.0;
        final rssiB = smoothedRssi[b.id] ?? -100.0;
        final qualityA = signalQuality[a.id] ?? 0.0;
        final qualityB = signalQuality[b.id] ?? 0.0;
        final scoreA = rssiA * (0.7 + qualityA * 0.3);
        final scoreB = rssiB * (0.7 + qualityB * 0.3);
        return scoreB.compareTo(scoreA);
      });

    activeSignals.assignAll(filtered);
    completedWaypoints.value =
        _bleWaypoints.where((w) => w.reached).length;
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

  int _calculateEnhancedSignalPercent(double rssi) {
    const minRssi = -100.0;
    const maxRssi = -30.0;

    final normalized = ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);
    final enhanced = math.pow(normalized, 0.6);
    return (enhanced * 100).round().clamp(0, 100);
  }

  String _calculatePreciseDistance(double rssi) {
    const txPower = -59.0;
    const pathLossExponent = 2.4;

    if (rssi >= -30) return '< 30cm';

    final distance = math.pow(10, (txPower - rssi) / (10 * pathLossExponent));

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
    final combinedScore = (rssi + 100) / 70 * 0.7 + quality * 0.3;

    if (combinedScore >= 0.8) return Colors.green;
    if (combinedScore >= 0.6) return Colors.lightGreen;
    if (combinedScore >= 0.4) return Colors.orange;
    if (combinedScore >= 0.2) return Colors.deepOrange;
    return Colors.red;
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
