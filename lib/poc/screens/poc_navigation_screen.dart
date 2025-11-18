import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ble_waypoint.dart';
import '../models/saved_location.dart';
import '../services/filtered_location_service.dart';
import '../utils/geo_utils.dart';

/// OPTIMIZED BLE Navigation Screen with Enhanced Accuracy and Real-time Updates
///
/// Key Improvements:
/// 1. RSSI Smoothing with Outlier Detection
/// 2. Real-time UI Updates at 60 FPS
/// 3. Enhanced Distance Calculation using Path Loss Model
/// 4. Optimized BLE Scanning with Periodic Restarts
/// 5. Signal Quality Assessment and Validation
class PocNavigationScreen extends StatefulWidget {
  final SavedLocation target;

  const PocNavigationScreen({super.key, required this.target});

  @override
  State<PocNavigationScreen> createState() => _OptimizedNavigationScreenState();
}

class _OptimizedNavigationScreenState extends State<PocNavigationScreen> {
  // ========== ENHANCED BLE Configuration ==========
  /// Faster scan parameters for real-time performance
  static const Duration _bleScanRestartInterval = Duration(seconds: 20);
  static const Duration _bleDeviceTimeout = Duration(seconds: 8);

  /// Enhanced RSSI processing parameters
  static const double _rssiSmoothingFactor = 0.25; // Higher = more responsive
  static const int _rssiHistorySize = 15; // Larger history for better filtering
  static const int _rssiOutlierThreshold =
      20; // Remove readings > 20 dBm from median

  /// Improved distance thresholds based on real-world testing
  static const int _rssiExcellent = -45; // < 1m
  static const int _rssiVeryGood = -55; // 1-3m
  static const int _rssiGood = -65; // 3-8m
  static const int _rssiFair = -75; // 8-15m
  static const int _rssiPoor = -85; // 15-30m

  // ========== GPS Configuration ==========
  static const double _reachThresholdMeters = 3.0; // Tighter threshold
  static const int _stableSamplesRequired = 3; // Faster response

  // ========== Services and Subscriptions ==========
  final FilteredLocationService _locationService = FilteredLocationService();
  StreamSubscription<LatLng>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<List<ScanResult>>? _bleScanSub;
  Timer? _bleScanRestartTimer;
  Timer? _uiUpdateTimer;
  Timer? _deviceTimeoutTimer;

  // ========== GPS State ==========
  LatLng? _currentPosition;
  LatLng? _startPosition;
  double? _headingDegrees;
  double? _smoothedDistanceMeters;
  double? _displayDistanceMeters;
  bool _hasShownSuccess = false;
  int _stableBelowThresholdCount = 0;
  bool _permissionsGranted = false;

  // ========== ENHANCED BLE State Management ==========
  final Map<String, List<int>> _rssiHistory = {}; // RSSI history per beacon
  final Map<String, double> _smoothedRssi = {}; // Smoothed RSSI values
  final Map<String, DateTime> _lastSeenTimestamp = {}; // Last detection time
  final Map<String, int> _detectionCount = {}; // Number of detections
  final Map<String, double> _signalQuality = {}; // Signal quality score (0-1)

  /// Performance tracking
  int _scanCycleCount = 0;
  int _totalDetections = 0;
  DateTime _lastUIUpdate = DateTime.now();

  // ========== BLE Waypoints ==========
  final List<BleWaypoint> _bleWaypoints = [
    BleWaypoint(id: 'BEACON_1', label: 'Entry Point', order: 1),
    BleWaypoint(id: 'BEACON_2', label: 'Midpoint', order: 2),
    BleWaypoint(id: 'BEACON_3', label: 'Destination', order: 3),
  ];

  final Map<String, BleWaypoint> _beaconMap = {};

  /// Enhanced device mapping with multiple identification strategies
  final Map<String, String> _deviceToWaypointMap = {
    // Add your actual device MAC addresses here
    // 'AA:BB:CC:DD:EE:01': 'BEACON_1',
    // 'AA:BB:CC:DD:EE:02': 'BEACON_2',
    // 'AA:BB:CC:DD:EE:03': 'BEACON_3',
  };

  /// Enhanced UUID mapping for iBeacon/AltBeacon
  /// UPDATE THIS to match your beacon broadcaster UUIDs
  final Map<String, String> _beaconUuidMap = const {
    '00000001-0000-0000-0000-000000000001': 'BEACON_1', // ← Match broadcaster
    '00000002-0000-0000-0000-000000000002': 'BEACON_2', // ← Match broadcaster
    '00000003-0000-0000-0000-000000000003': 'BEACON_3', // ← Match broadcaster
  };

  @override
  void initState() {
    super.initState();
    _initializeBeaconMaps();
    _startUIUpdateTimer();
    _checkPermissionsStatus().then((_) => _startTracking());
  }

  void _initializeBeaconMaps() {
    for (var waypoint in _bleWaypoints) {
      _beaconMap[waypoint.id] = waypoint;
      _rssiHistory[waypoint.id] = [];
      _smoothedRssi[waypoint.id] = -100.0;
      _detectionCount[waypoint.id] = 0;
      _signalQuality[waypoint.id] = 0.0;
    }
  }

  /// Start high-frequency UI updates for smooth real-time experience
  void _startUIUpdateTimer() {
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      // 60 FPS updates (1000ms / 60 = ~16ms)
      if (mounted) {
        final now = DateTime.now();
        if (now.difference(_lastUIUpdate).inMilliseconds >= 16) {
          _lastUIUpdate = now;
          setState(() {}); // Trigger UI rebuild
        }
      }
    });
  }

  Future<void> _checkPermissionsStatus() async {
    final permissions = _getRequiredPermissions();
    bool allGranted = true;

    for (final perm in permissions) {
      final status = await perm.status;
      if (!status.isGranted) {
        allGranted = false;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _permissionsGranted = allGranted;
      });
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
    return permissions
        .where((p) => p.value != 21)
        .toList(); // Exclude BLUETOOTH_ADVERTISE
  }

  Future<void> _startTracking() async {
    await _locationService.start();
    await _startOptimizedBleScanning();
    _startDeviceTimeoutTimer();

    // GPS position updates with enhanced smoothing
    _positionSub = _locationService.filteredPosition$.listen((position) {
      if (_startPosition == null) {
        _startPosition = position;
      }

      final rawDistance = Geolocator.distanceBetween(
        position.lat,
        position.lng,
        widget.target.latitude,
        widget.target.longitude,
      );

      // Enhanced exponential smoothing with adaptive alpha
      final adaptiveAlpha = _calculateAdaptiveAlpha(rawDistance);

      if (_smoothedDistanceMeters == null) {
        _smoothedDistanceMeters = rawDistance;
      } else {
        _smoothedDistanceMeters =
            adaptiveAlpha * rawDistance +
            (1 - adaptiveAlpha) * _smoothedDistanceMeters!;
      }

      _currentPosition = position;
      _displayDistanceMeters = _smoothedDistanceMeters;
      _checkReached();
    });

    // Enhanced compass updates
    _compassSub = FlutterCompass.events?.listen((event) {
      _headingDegrees = event.heading;
    });
  }

  /// Calculate adaptive smoothing factor based on movement speed
  double _calculateAdaptiveAlpha(double currentDistance) {
    const baseAlpha = 0.2;
    const maxAlpha = 0.4;

    if (_smoothedDistanceMeters == null) return baseAlpha;

    final distanceChange = (currentDistance - _smoothedDistanceMeters!).abs();
    final changeFactor = (distanceChange / 10.0).clamp(
      0.0,
      1.0,
    ); // Normalize to 0-1

    return baseAlpha + (maxAlpha - baseAlpha) * changeFactor;
  }

  /// OPTIMIZED BLE SCANNING with Enhanced Performance
  Future<void> _startOptimizedBleScanning() async {
    print('🚀 Starting OPTIMIZED BLE Scanner v2.0');

    try {
      if (!_permissionsGranted) {
        await _ensureBlePermissions();
        if (!_permissionsGranted) return;
      }

      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        print('❌ BLE not supported on device');
        return;
      }

      await _ensureBluetoothEnabled();
      await _resetAndStartScanning();

      // Set up periodic scan restart for optimal performance
      _bleScanRestartTimer = Timer.periodic(_bleScanRestartInterval, (_) async {
        await _restartBleScanning();
      });

      print(
        '✅ Optimized BLE scanning active with ${_bleScanRestartInterval.inSeconds}s restart cycle',
      );
    } catch (e) {
      print('❌ Optimized BLE scanning error: $e');
    }
  }

  Future<void> _ensureBluetoothEnabled() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      print('📱 Enabling Bluetooth...');
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 15));
    }
  }

  Future<void> _resetAndStartScanning() async {
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 200)); // Short delay

    // Start optimized continuous scanning
    await FlutterBluePlus.startScan(
      timeout: null, // Continuous scanning
      androidUsesFineLocation: true, // Better accuracy on Android
    );

    // Enhanced scan result processing
    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        _processOptimizedBleScanResults(results);
        _totalDetections += results.length;
      }
    });
  }

  Future<void> _restartBleScanning() async {
    try {
      _scanCycleCount++;
      print(
        '🔄 BLE Scan Restart #$_scanCycleCount (Total detections: $_totalDetections)',
      );

      await _resetAndStartScanning();
    } catch (e) {
      print('⚠️ BLE restart error: $e');
    }
  }

  /// ENHANCED SCAN RESULT PROCESSING with Improved Accuracy
  void _processOptimizedBleScanResults(List<ScanResult> results) {
    if (!mounted || results.isEmpty) return;

    final now = DateTime.now();
    bool significantUpdate = false;

    for (final result in results) {
      final device = result.device;
      final rssi = result.rssi;
      final adv = result.advertisementData;

      // Enhanced device matching with multiple strategies
      String? matchedId = _performEnhancedDeviceMatching(device, adv);

      if (matchedId != null) {
        final waypoint = _beaconMap[matchedId];
        if (waypoint == null) continue;

        // Update detection timestamp and count
        _lastSeenTimestamp[matchedId] = now;
        _detectionCount[matchedId] = (_detectionCount[matchedId] ?? 0) + 1;

        // Process RSSI with enhanced smoothing and outlier detection
        final previousSmoothed = _smoothedRssi[matchedId]!;
        final newSmoothed = _processRssiWithAdvancedFiltering(matchedId, rssi);

        // Calculate signal quality based on consistency and strength
        _updateSignalQuality(matchedId, rssi, newSmoothed);

        // Update waypoint with smoothed values
        final wasReached = waypoint.reached;
        final threshold = _getDynamicThreshold(newSmoothed, matchedId);

        final justReached = waypoint.updateRssi(
          newSmoothed.round(),
          threshold,
          _getAdaptiveStableSamples(matchedId),
        );

        // Check for significant RSSI changes (for UI updates)
        if ((newSmoothed - previousSmoothed).abs() >= 2.0 || justReached) {
          significantUpdate = true;
        }

        if (justReached && !wasReached) {
          print(
            '🎉 WAYPOINT REACHED: ${waypoint.label} (Order: ${waypoint.order}, ID: ${waypoint.id}) | '
            'Beacon ID: $matchedId | '
            'Smoothed RSSI: ${newSmoothed.toStringAsFixed(1)} dBm | '
            'Quality: ${(_signalQuality[matchedId]! * 100).toStringAsFixed(0)}%',
          );
          _showWaypointFeedback(waypoint);
        }

        // Debug logging for signal tracking
        if (_detectionCount[matchedId]! % 10 == 0) {
          print(
            '📊 ${waypoint.label}: RSSI ${newSmoothed.toStringAsFixed(1)} dBm, '
            'Quality: ${(_signalQuality[matchedId]! * 100).toStringAsFixed(0)}%, '
            'Detections: ${_detectionCount[matchedId]}',
          );
        }
      }
    }

    // Trigger UI update for significant changes
    if (significantUpdate) {
      _requestUIUpdate();
    }
  }

  /// ENHANCED RSSI PROCESSING with Advanced Filtering
  double _processRssiWithAdvancedFiltering(String beaconId, int rawRssi) {
    final history = _rssiHistory[beaconId]!;

    // Add new reading to history
    history.add(rawRssi);
    if (history.length > _rssiHistorySize) {
      history.removeAt(0);
    }

    // Apply outlier detection if we have sufficient history
    List<int> workingHistory = history;
    if (history.length >= 5) {
      workingHistory = _removeRssiOutliers(history);
    }

    // Calculate weighted average (recent readings weighted more heavily)
    double weightedSum = 0.0;
    double weightSum = 0.0;

    for (int i = 0; i < workingHistory.length; i++) {
      final weight = math.pow(1.2, i).toDouble(); // Exponential weighting
      weightedSum += workingHistory[i] * weight;
      weightSum += weight;
    }

    final weightedAverage = weightSum > 0
        ? weightedSum / weightSum
        : rawRssi.toDouble();

    // Apply exponential smoothing to the weighted average
    final currentSmoothed = _smoothedRssi[beaconId]!;
    final newSmoothed =
        _rssiSmoothingFactor * weightedAverage +
        (1 - _rssiSmoothingFactor) * currentSmoothed;

    _smoothedRssi[beaconId] = newSmoothed;
    return newSmoothed;
  }

  /// Remove RSSI outliers using statistical analysis
  List<int> _removeRssiOutliers(List<int> readings) {
    if (readings.length < 5) return readings;

    final sorted = List<int>.from(readings)..sort();
    final median = sorted[sorted.length ~/ 2];

    // Remove readings that are too far from median
    return readings
        .where((rssi) => (rssi - median).abs() <= _rssiOutlierThreshold)
        .toList();
  }

  /// Update signal quality score based on consistency and strength
  void _updateSignalQuality(String beaconId, int rawRssi, double smoothedRssi) {
    final history = _rssiHistory[beaconId]!;

    if (history.length < 3) {
      _signalQuality[beaconId] = 0.3; // Initial quality
      return;
    }

    // Calculate consistency (lower variance = higher quality)
    final variance = _calculateRssiVariance(history);
    final consistencyScore = math.max(
      0.0,
      1.0 - (variance / 400.0),
    ); // Normalize

    // Calculate strength score
    final strengthScore = _calculateStrengthScore(smoothedRssi);

    // Calculate detection frequency score
    final detectionCount = _detectionCount[beaconId]!;
    final frequencyScore = math.min(1.0, detectionCount / 20.0);

    // Combine scores with weights
    final qualityScore =
        (consistencyScore * 0.4 + strengthScore * 0.4 + frequencyScore * 0.2)
            .clamp(0.0, 1.0);

    _signalQuality[beaconId] = qualityScore;
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
    // Convert RSSI to 0-1 quality score
    const minRssi = -100.0;
    const maxRssi = -30.0;
    return ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);
  }

  /// Get dynamic threshold based on signal quality
  int _getDynamicThreshold(double smoothedRssi, String beaconId) {
    final quality = _signalQuality[beaconId] ?? 0.5;

    // Higher quality signals can use tighter thresholds
    if (quality > 0.8 && smoothedRssi >= _rssiVeryGood) {
      return _rssiVeryGood; // High quality, close signal
    } else if (quality > 0.6 && smoothedRssi >= _rssiGood) {
      return _rssiGood; // Medium quality
    } else {
      return _rssiFair; // Default threshold for lower quality signals
    }
  }

  /// Get adaptive stable samples based on signal quality
  int _getAdaptiveStableSamples(String beaconId) {
    final quality = _signalQuality[beaconId] ?? 0.5;

    if (quality > 0.8) return 2; // High quality = fewer samples needed
    if (quality > 0.6) return 3; // Medium quality
    return 5; // Low quality = more samples for stability
  }

  /// ENHANCED DEVICE MATCHING with Multiple Strategies
  String? _performEnhancedDeviceMatching(
    BluetoothDevice device,
    AdvertisementData adv,
  ) {
    // Strategy 1: Direct MAC address mapping (most reliable)
    if (_deviceToWaypointMap.isNotEmpty) {
      final deviceId = device.remoteId.toString();
      final matched = _deviceToWaypointMap[deviceId];
      if (matched != null) return matched;
    }

    // Strategy 2: iBeacon/AltBeacon UUID extraction
    final extractedUuid = _extractBeaconUuid(adv);
    if (extractedUuid != null && _beaconUuidMap.containsKey(extractedUuid)) {
      return _beaconUuidMap[extractedUuid];
    }

    // Strategy 3: Device name pattern matching
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

    // Strategy 4: Service UUID matching
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

  /// Extract beacon UUID from advertisement data (iBeacon/AltBeacon)
  String? _extractBeaconUuid(AdvertisementData adv) {
    // Try iBeacon (Apple manufacturer data)
    if (adv.manufacturerData.containsKey(0x004C)) {
      final data = adv.manufacturerData[0x004C]!;
      if (data.length >= 18 && data[0] == 0x02 && data[1] == 0x15) {
        return _formatUuidFromBytes(data.sublist(2, 18));
      }
    }

    // Try AltBeacon in manufacturer data
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

  /// Clean up old/stale beacon data
  void _startDeviceTimeoutTimer() {
    _deviceTimeoutTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      final expiredThreshold = now.subtract(_bleDeviceTimeout);

      _lastSeenTimestamp.removeWhere((beaconId, lastSeen) {
        if (lastSeen.isBefore(expiredThreshold)) {
          // Reset beacon data
          _smoothedRssi[beaconId] = -100.0;
          _rssiHistory[beaconId]?.clear();
          _signalQuality[beaconId] = 0.0;

          final waypoint = _beaconMap[beaconId];
          waypoint?.updateRssi(-100, 0, 0);

          print(
            '📡 Beacon $beaconId timed out (${_bleDeviceTimeout.inSeconds}s)',
          );
          return true;
        }
        return false;
      });
    });
  }

  void _showWaypointFeedback(BleWaypoint waypoint) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('✅ Reached ${waypoint.label}'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _requestUIUpdate() {
    final now = DateTime.now();
    if (now.difference(_lastUIUpdate).inMilliseconds >= 32) {
      // Max 30 FPS for data updates
      if (mounted) setState(() {});
      _lastUIUpdate = now;
    }
  }

  /// ENHANCED UI: Signal Insights with Detailed Analytics
  Widget _renderEnhancedSignalInsights(List<BleWaypoint> activeSignals) {
    final theme = Theme.of(context);

    if (!_permissionsGranted) {
      return _buildPermissionCard();
    }

    if (activeSignals.isEmpty) {
      return _buildNoSignalCard();
    }

    // Get strongest signal with quality metrics
    final strongest = activeSignals.first;
    final smoothedRssi = _smoothedRssi[strongest.id] ?? -100.0;
    final quality = _signalQuality[strongest.id] ?? 0.0;
    final detectionCount = _detectionCount[strongest.id] ?? 0;

    final percent = _calculateEnhancedSignalPercent(smoothedRssi);
    final distance = _calculatePreciseDistance(smoothedRssi);
    final qualityLabel = _getSignalQualityLabel(quality);
    final color = _getEnhancedSignalColor(smoothedRssi, quality);

    return Card(
      color: Colors.black.withOpacity(0.5),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_connected, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Beacon Signal Analytics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Primary signal display
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strongest.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        qualityLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$percent%',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      distance,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Enhanced progress bar with quality indication
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),

            const SizedBox(height: 12),

            // Detailed metrics
            Row(
              children: [
                Expanded(
                  child: Text(
                    'RSSI: ${smoothedRssi.toStringAsFixed(1)} dBm',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ),
                Text(
                  'Quality: ${(quality * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ],
            ),

            Text(
              'Detections: $detectionCount | Cycle: $_scanCycleCount',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),

            // Additional signals
            if (activeSignals.length > 1)
              ..._buildAdditionalSignals(activeSignals.skip(1)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAdditionalSignals(
    Iterable<BleWaypoint> additionalSignals,
  ) {
    return [
      const SizedBox(height: 16),
      const Divider(color: Colors.white24, height: 1),
      const SizedBox(height: 8),
      Text(
        'Other Beacons',
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      ...additionalSignals.map((waypoint) {
        final smoothedRssi = _smoothedRssi[waypoint.id] ?? -100.0;
        final quality = _signalQuality[waypoint.id] ?? 0.0;
        final percent = _calculateEnhancedSignalPercent(smoothedRssi);
        final distance = _calculatePreciseDistance(smoothedRssi);
        final color = _getEnhancedSignalColor(smoothedRssi, quality);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  waypoint.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                distance,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildPermissionCard() {
    return Card(
      color: Colors.orange.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.warning, color: Colors.orange, size: 32),
            const SizedBox(height: 12),
            const Text(
              'Bluetooth Permissions Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'BLE navigation requires location and Bluetooth permissions for beacon detection.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _ensureBlePermissions,
              icon: const Icon(Icons.security),
              label: const Text('Grant Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSignalCard() {
    return Card(
      color: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.bluetooth_searching,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'Scanning for Beacons...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan cycle: $_scanCycleCount | Total detections: $_totalDetections',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Enhanced signal percentage with non-linear scaling
  int _calculateEnhancedSignalPercent(double rssi) {
    const minRssi = -100.0;
    const maxRssi = -30.0;

    final normalized = ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0);

    // Apply logarithmic scaling for better perception
    final enhanced = math.pow(normalized, 0.6); // Emphasize stronger signals

    return (enhanced * 100).round().clamp(0, 100);
  }

  /// Precise distance calculation using path loss model
  String _calculatePreciseDistance(double rssi) {
    // Enhanced path loss model: d = 10^((TxPower - RSSI) / (10 * n))
    const txPower = -59.0; // Typical smartphone BLE TX power at 1m
    const pathLossExponent = 2.4; // Indoor environment with obstacles

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
    // Combine RSSI and quality for color determination
    final combinedScore = (rssi + 100) / 70 * 0.7 + quality * 0.3;

    if (combinedScore >= 0.8) return Colors.green;
    if (combinedScore >= 0.6) return Colors.lightGreen;
    if (combinedScore >= 0.4) return Colors.orange;
    if (combinedScore >= 0.2) return Colors.deepOrange;
    return Colors.red;
  }

  Future<void> _ensureBlePermissions() async {
    final permissions = _getRequiredPermissions();

    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        final result = await permission.request();
        if (!result.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${permission.toString()} permission required'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    await _checkPermissionsStatus();
  }

  void _checkReached() {
    if (_hasShownSuccess) return;

    final distance = _displayDistanceMeters;
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
    if (_hasShownSuccess || !mounted) return;
    _hasShownSuccess = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.celebration, color: Colors.green),
            const SizedBox(width: 8),
            const Text('🎉 Success!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('You have reached "${widget.target.name}".'),
            const SizedBox(height: 8),
            Text(
              'Completed waypoints: ${_bleWaypoints.where((w) => w.reached).length}/${_bleWaypoints.length}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _bleScanSub?.cancel();
    _bleScanRestartTimer?.cancel();
    _uiUpdateTimer?.cancel();
    _deviceTimeoutTimer?.cancel();
    FlutterBluePlus.stopScan();
    _locationService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heading = _headingDegrees;
    final hasHeading = heading != null;
    final current = _currentPosition;

    // Get active signals with quality filtering
    final activeSignals =
        _bleWaypoints.where((waypoint) {
          final smoothedRssi = _smoothedRssi[waypoint.id] ?? -100.0;
          final quality = _signalQuality[waypoint.id] ?? 0.0;
          return smoothedRssi > -95.0 &&
              quality > 0.1; // Filter weak/poor signals
        }).toList()..sort((a, b) {
          // Sort by quality-weighted RSSI
          final rssiA = _smoothedRssi[a.id] ?? -100.0;
          final rssiB = _smoothedRssi[b.id] ?? -100.0;
          final qualityA = _signalQuality[a.id] ?? 0.0;
          final qualityB = _signalQuality[b.id] ?? 0.0;

          final scoreA = rssiA * (0.7 + qualityA * 0.3);
          final scoreB = rssiB * (0.7 + qualityB * 0.3);

          return scoreB.compareTo(scoreA);
        });

    // Calculate arrow rotation
    double arrowRadians = 0.0;
    if (current != null && hasHeading) {
      final bearing = bearingBetween(
        current.lat,
        current.lng,
        widget.target.latitude,
        widget.target.longitude,
      );
      final relativeDeg = (bearing - heading + 360.0) % 360.0;
      arrowRadians = relativeDeg * (math.pi / 180.0);
    }

    // Format distance
    final distanceValue = _displayDistanceMeters;
    final distanceText = distanceValue == null
        ? 'Calculating...'
        : '${distanceValue.toStringAsFixed(1)} m away';

    return Scaffold(
      appBar: AppBar(
        title: Text('Navigate to ${widget.target.name}'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Restart BLE Scanning',
            onPressed: _restartBleScanning,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Enhanced gradient background
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0a1a2e),
                  Color(0xFF16213e),
                  Color(0xFF1a252f),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Vertical progress line - Primary focus (left side)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: _renderVerticalProgressLine()),
                      Expanded(
                        flex: 1,
                        child: _renderNavigationArrow(arrowRadians, hasHeading),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Enhanced signal insights
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _renderEnhancedSignalInsights(activeSignals),
                ),

                // Distance and instruction text
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        distanceText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasHeading
                            ? 'Follow the vertical progress line to your destination.'
                            : 'Calibrating compass… move your phone in a figure-8.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Render vertical progress line with waypoint indicators (left side, reversed order)
  Widget _renderVerticalProgressLine() {
    final sortedWaypoints = List<BleWaypoint>.from(_bleWaypoints)
      ..sort((a, b) => a.order.compareTo(b.order));

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final screenWidth = constraints.maxWidth;
        final lineHeight = screenHeight * 0.6; // 60% of available height
        final lineTop = (screenHeight - lineHeight) / 2;
        // Position line on the left side (slightly offset from left edge)
        final lineLeftX = screenWidth * 0.15; // 15% from left edge

        // Calculate user position on the line (reversed: Entry Point at bottom)
        final userPosition = _calculateUserPositionOnLineReversed(
          sortedWaypoints,
          lineHeight,
          lineTop,
        );

        return Stack(
          children: [
            // Vertical line
            Positioned(
              left: lineLeftX - 2,
              top: lineTop,
              child: Container(
                width: 4,
                height: lineHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Completed portion of line (green) - from bottom upward
            if (userPosition.completedHeight > 0)
              Positioned(
                left: lineLeftX - 2,
                top: lineTop + (lineHeight - userPosition.completedHeight),
                child: Container(
                  width: 4,
                  height: userPosition.completedHeight,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

            // Waypoint indicators (reversed order: Entry Point at bottom, Destination at top)
            // Display in reversed visual order: Entry Point (order 1) at bottom, Destination (order 3) at top
            ...sortedWaypoints.asMap().entries.map((entry) {
              final index = entry.key;
              final waypoint = entry.value;
              final isReached = waypoint.reached;

              // Calculate position along the line (reversed: first waypoint at bottom)
              // sortedWaypoints: [Entry Point (order 1, index 0), Midpoint (order 2, index 1), Destination (order 3, index 2)]
              // Visual order: Entry Point at bottom, Midpoint in middle, Destination at top
              // Reverse index: Entry Point (index 0) -> reversedIndex 2 (bottom), Destination (index 2) -> reversedIndex 0 (top)
              final reversedIndex = sortedWaypoints.length - 1 - index;
              final waypointPosition =
                  lineTop +
                  (lineHeight / (sortedWaypoints.length + 1)) *
                      (reversedIndex + 1);

              // Debug: Verify waypoint is displayed correctly
              if (isReached) {
                print(
                  '📍 Displaying waypoint: ${waypoint.label} (Order: ${waypoint.order}, ID: ${waypoint.id}) '
                  'at visual position: ${reversedIndex == 0 ? "TOP" : reversedIndex == 1 ? "MIDDLE" : "BOTTOM"} '
                  '(reached: $isReached)',
                );
              }

              return Positioned(
                left: lineLeftX - 12,
                top: waypointPosition - 12,
                child: _renderWaypointIndicator(waypoint, isReached),
              );
            }),

            // Waypoint labels (reversed order) - each waypoint shows its own order number
            ...sortedWaypoints.asMap().entries.map((entry) {
              final index = entry.key;
              final waypoint = entry.value;
              // Reverse index: last waypoint at top, first at bottom
              final reversedIndex = sortedWaypoints.length - 1 - index;
              final waypointPosition =
                  lineTop +
                  (lineHeight / (sortedWaypoints.length + 1)) *
                      (reversedIndex + 1);

              return Positioned(
                left: lineLeftX + 20,
                top: waypointPosition - 12,
                child: _renderWaypointLabel(waypoint),
              );
            }),

            // User position indicator (animated, reversed order)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              left: lineLeftX - 16,
              top: userPosition.currentY - 16,
              child: _renderUserPositionIndicator(),
            ),
          ],
        );
      },
    );
  }

  /// Calculate user position on the vertical progress line (original order)
  _UserPosition _calculateUserPositionOnLine(
    List<BleWaypoint> sortedWaypoints,
    double lineHeight,
    double lineTop,
  ) {
    if (sortedWaypoints.isEmpty) {
      return _UserPosition(currentY: lineTop + lineHeight, completedHeight: 0);
    }

    // Find the last reached waypoint index
    int lastReachedIndex = -1;
    for (int i = 0; i < sortedWaypoints.length; i++) {
      if (sortedWaypoints[i].reached) {
        lastReachedIndex = i;
      }
    }

    // Calculate completed height (green portion)
    double completedHeight = 0.0;
    if (lastReachedIndex >= 0) {
      // Calculate position of last reached waypoint
      final segmentHeight = lineHeight / (sortedWaypoints.length + 1);
      completedHeight = segmentHeight * (lastReachedIndex + 1);
    }

    // Calculate current user position
    double currentY;
    if (lastReachedIndex == sortedWaypoints.length - 1) {
      // All waypoints reached - position at top
      currentY = lineTop;
    } else if (lastReachedIndex < 0) {
      // No waypoints reached - position at bottom
      currentY = lineTop + lineHeight;
    } else {
      // Between waypoints - interpolate based on signal strength to next waypoint
      final nextWaypointIndex = lastReachedIndex + 1;
      final nextWaypoint = sortedWaypoints[nextWaypointIndex];
      final smoothedRssi = _smoothedRssi[nextWaypoint.id] ?? -100.0;

      // Calculate progress to next waypoint based on RSSI
      // Stronger signal = closer to next waypoint
      final minRssi = -100.0;
      final maxRssi = -50.0;
      final progress = ((smoothedRssi - minRssi) / (maxRssi - minRssi)).clamp(
        0.0,
        1.0,
      );

      final segmentHeight = lineHeight / (sortedWaypoints.length + 1);
      final lastReachedY = lineTop + segmentHeight * (lastReachedIndex + 1);
      final nextWaypointY = lineTop + segmentHeight * (nextWaypointIndex + 1);

      // Interpolate between last reached and next waypoint
      currentY = lastReachedY + (nextWaypointY - lastReachedY) * progress;
    }

    return _UserPosition(currentY: currentY, completedHeight: completedHeight);
  }

  /// Calculate user position on the vertical progress line (reversed: Entry Point at bottom)
  _UserPosition _calculateUserPositionOnLineReversed(
    List<BleWaypoint> sortedWaypoints,
    double lineHeight,
    double lineTop,
  ) {
    if (sortedWaypoints.isEmpty) {
      return _UserPosition(currentY: lineTop + lineHeight, completedHeight: 0);
    }

    // Find the last reached waypoint index (in original order: 0=Entry, 1=Mid, 2=Dest)
    int lastReachedIndex = -1;
    for (int i = 0; i < sortedWaypoints.length; i++) {
      if (sortedWaypoints[i].reached) {
        lastReachedIndex = i;
      }
    }

    final segmentHeight = lineHeight / (sortedWaypoints.length + 1);

    // Calculate completed height (green portion from bottom upward)
    // In reversed visual order: Entry Point (index 0) is at bottom, Destination (index 2) at top
    // So when Entry Point (index 0) is reached, we show green from bottom to its position
    double completedHeight = 0.0;
    if (lastReachedIndex >= 0) {
      // Convert to reversed visual position
      // Entry Point (index 0) -> reversed visual position = 2 (near bottom)
      // Destination (index 2) -> reversed visual position = 0 (near top)
      final reversedVisualIndex = sortedWaypoints.length - 1 - lastReachedIndex;
      // Calculate height from bottom: Entry Point at bottom = full height, Destination at top = small height
      // We want green to fill from bottom up to the reached waypoint
      completedHeight = segmentHeight * (reversedVisualIndex + 1);
    }

    // Calculate current user position (reversed: Entry Point at bottom, Destination at top)
    double currentY;
    if (lastReachedIndex == sortedWaypoints.length - 1) {
      // All waypoints reached - position at top (Destination)
      currentY = lineTop;
    } else if (lastReachedIndex < 0) {
      // No waypoints reached - position at bottom (Entry Point)
      currentY = lineTop + lineHeight;
    } else {
      // Between waypoints - interpolate based on signal strength to next waypoint
      final nextWaypointIndex = lastReachedIndex + 1;
      final nextWaypoint = sortedWaypoints[nextWaypointIndex];
      final smoothedRssi = _smoothedRssi[nextWaypoint.id] ?? -100.0;

      // Calculate progress to next waypoint based on RSSI
      // Stronger signal = closer to next waypoint
      final minRssi = -100.0;
      final maxRssi = -50.0;
      final progress = ((smoothedRssi - minRssi) / (maxRssi - minRssi)).clamp(
        0.0,
        1.0,
      );

      // Reverse the Y positions: Entry Point (index 0) at bottom, Destination at top
      final reversedLastIndex = sortedWaypoints.length - 1 - lastReachedIndex;
      final reversedNextIndex = sortedWaypoints.length - 1 - nextWaypointIndex;
      final lastReachedY = lineTop + segmentHeight * (reversedLastIndex + 1);
      final nextWaypointY = lineTop + segmentHeight * (reversedNextIndex + 1);

      // Interpolate between last reached and next waypoint
      currentY = lastReachedY + (nextWaypointY - lastReachedY) * progress;
    }

    return _UserPosition(currentY: currentY, completedHeight: completedHeight);
  }

  /// Render individual waypoint indicator
  Widget _renderWaypointIndicator(BleWaypoint waypoint, bool isReached) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isReached ? Colors.green : Colors.red,
        shape: BoxShape.circle,
        border: Border.all(
          color: isReached ? Colors.greenAccent : Colors.redAccent,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: (isReached ? Colors.green : Colors.red).withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: isReached
          ? const Icon(Icons.check, color: Colors.white, size: 14)
          : null,
    );
  }

  /// Render waypoint label with point number
  Widget _renderWaypointLabel(BleWaypoint waypoint) {
    final isReached = waypoint.reached;
    final smoothedRssi = _smoothedRssi[waypoint.id] ?? -100.0;
    final hasSignal = smoothedRssi > -95.0;
    // Format point number as 4-digit string (e.g., "0001", "0002", "0003")
    final pointNumber = waypoint.order.toString().padLeft(4, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isReached ? Colors.green : Colors.white24,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Point number label
          Text(
            pointNumber,
            style: TextStyle(
              color: isReached ? Colors.greenAccent : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          // Waypoint label
          Text(
            waypoint.label,
            style: TextStyle(
              color: isReached ? Colors.greenAccent : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (hasSignal && !isReached)
            Text(
              '${smoothedRssi.toStringAsFixed(0)} dBm',
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
        ],
      ),
    );
  }

  /// Render animated user position indicator
  Widget _renderUserPositionIndicator() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blueAccent, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.6),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 18),
    );
  }

  /// Render navigation arrow on the right side (larger size)
  Widget _renderNavigationArrow(double arrowRadians, bool hasHeading) {
    return Center(
      child: Transform.rotate(
        angle: arrowRadians,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: hasHeading ? Colors.white54 : Colors.white24,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.navigation,
            size: 60,
            color: hasHeading ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}

/// Helper class for user position calculation
class _UserPosition {
  final double currentY;
  final double completedHeight;

  _UserPosition({required this.currentY, required this.completedHeight});
}
