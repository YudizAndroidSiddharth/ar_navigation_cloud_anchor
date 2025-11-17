import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../models/saved_location.dart';
import '../services/filtered_location_service.dart';
import '../utils/geo_utils.dart';

/// Screen that guides the user to a saved [SavedLocation]
/// using a compass-based arrow and distance with waypoint progress.
class PocNavigationScreen extends StatefulWidget {
  final SavedLocation target;

  const PocNavigationScreen({super.key, required this.target});

  @override
  State<PocNavigationScreen> createState() => _PocNavigationScreenState();
}

class _PocNavigationScreenState extends State<PocNavigationScreen> {
  /// Real-world GPS is noisy: 10m is often too strict.
  /// 20m is a more realistic "you've arrived" threshold outdoors.
  static const double _reachThresholdMeters = 5.0;

  /// Require N consecutive samples below threshold
  /// to avoid random dips under the line causing early success.
  static const int _stableSamplesRequired = 5;

  /// Distance between waypoints in meters
  static const double _waypointIntervalMeters = 10.0;

  /// Proximity threshold to mark waypoint as completed
  static const double _waypointReachThreshold = 8.0;

  final FilteredLocationService _locationService = FilteredLocationService();

  StreamSubscription<LatLng>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;

  LatLng? _currentPosition;
  LatLng? _startPosition;
  double? _headingDegrees; // 0..360°
  double? _rawDistanceMeters;
  double? _smoothedDistanceMeters;
  double? _displayDistanceMeters;

  bool _hasShownSuccess = false;
  int _stableBelowThresholdCount = 0;

  // Waypoint tracking
  WaypointTracker? _waypointTracker;
  int _totalWaypoints = 0;
  bool _waypointsInitialized = false;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    await _locationService.start();

    _positionSub = _locationService.filteredPosition$.listen((position) {
      // position is already a LatLng object from your FilteredLocationService

      // Initialize waypoints when we get first position
      if (!_waypointsInitialized && _startPosition == null) {
        _startPosition = position;
        _initializeWaypoints(position);
      }

      final rawDistance = Geolocator.distanceBetween(
        position.lat,
        position.lng,
        widget.target.latitude,
        widget.target.longitude,
      );

      // Exponential smoothing to kill jitter on distance
      const alpha = 0.25; // 0 < alpha < 1; smaller = smoother
      if (_smoothedDistanceMeters == null) {
        _smoothedDistanceMeters = rawDistance;
      } else {
        _smoothedDistanceMeters =
            alpha * rawDistance + (1 - alpha) * _smoothedDistanceMeters!;
      }

      // Update waypoint progress
      if (_waypointsInitialized && _waypointTracker != null) {
        _waypointTracker!.updateProgress(position);
      }

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _rawDistanceMeters = rawDistance;
        _displayDistanceMeters = _smoothedDistanceMeters;
      });

      _checkReached();
    });

    // Listen to compass heading
    _compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() {
        _headingDegrees = event.heading; // can be null during calibration
      });
    });
  }

  void _initializeWaypoints(LatLng startPosition) {
    final totalDistance = Geolocator.distanceBetween(
      startPosition.lat,
      startPosition.lng,
      widget.target.latitude,
      widget.target.longitude,
    );

    _totalWaypoints = (totalDistance / _waypointIntervalMeters).ceil();

    // Generate waypoints along the route
    final waypoints = _generateWaypoints(
      startPosition,
      LatLng(widget.target.latitude, widget.target.longitude),
      _waypointIntervalMeters,
    );

    _waypointTracker = WaypointTracker(waypoints);
    _waypointsInitialized = true;

    print(
      'Initialized ${waypoints.length} waypoints for ${totalDistance.toStringAsFixed(1)}m journey',
    );
  }

  List<LatLng> _generateWaypoints(
    LatLng start,
    LatLng destination,
    double intervalMeters,
  ) {
    List<LatLng> waypoints = [];

    double totalDistance = Geolocator.distanceBetween(
      start.lat,
      start.lng,
      destination.lat,
      destination.lng,
    );

    if (totalDistance <= intervalMeters) {
      // If destination is closer than interval, just add the destination
      waypoints.add(destination);
      return waypoints;
    }

    int waypointCount = (totalDistance / intervalMeters).ceil();

    for (int i = 1; i <= waypointCount; i++) {
      double fraction = (i * intervalMeters) / totalDistance;
      if (fraction > 1.0) fraction = 1.0;

      // Linear interpolation between start and destination
      double lat = start.lat + (destination.lat - start.lat) * fraction;
      double lng = start.lng + (destination.lng - start.lng) * fraction;

      waypoints.add(LatLng(lat, lng));
    }

    return waypoints;
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
        title: const Text('Success'),
        content: Text('You have reached "${widget.target.name}".'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // close dialog
              Navigator.of(context).pop(); // go back to previous screen
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
    _locationService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heading = _headingDegrees;
    final hasHeading = heading != null;
    final current = _currentPosition;

    // Rotation for the arrow
    double arrowRadians = 0.0;
    if (current != null && hasHeading) {
      // Bearing from user -> target
      final bearing = bearingBetween(
        current.lat,
        current.lng,
        widget.target.latitude,
        widget.target.longitude,
      );

      // Relative angle between phone heading & target bearing
      final relativeDeg = (bearing - heading + 360.0) % 360.0;
      arrowRadians = relativeDeg * (math.pi / 180.0);
    }

    final distanceValue = _displayDistanceMeters;
    final distanceText = distanceValue == null
        ? '--.- m away'
        : '${distanceValue.toStringAsFixed(1)} m away';

    // Optional debug info, can be removed later
    final debugRawText = _rawDistanceMeters == null
        ? ''
        : ' (raw: ${_rawDistanceMeters!.toStringAsFixed(1)} m)';

    return Scaffold(
      appBar: AppBar(
        title: Text('Navigate to ${widget.target.name}'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0f2027),
                  Color(0xFF203a43),
                  Color(0xFF2c5364),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 48),
                Expanded(
                  child: Center(
                    child: Transform.rotate(
                      angle: arrowRadians,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.navigation,
                          size: 120,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$distanceText$debugRawText',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasHeading
                            ? 'Turn until the arrow points up, then walk forward.'
                            : 'Calibrating compass… move your phone in a figure-8.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reach threshold: ${_reachThresholdMeters.toStringAsFixed(0)} m\n'
                        'Need $_stableSamplesRequired stable readings below threshold.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Waypoint progress widget overlay
          if (_waypointsInitialized &&
              _totalWaypoints > 0 &&
              _waypointTracker != null)
            WaypointProgressWidget(
              totalWaypoints: _totalWaypoints,
              completedWaypoints: _waypointTracker!.completedCount,
            ),
        ],
      ),
    );
  }
}

/// Widget that displays waypoint progress as colored circles
class WaypointProgressWidget extends StatelessWidget {
  final int totalWaypoints;
  final int completedWaypoints;

  const WaypointProgressWidget({
    super.key,
    required this.totalWaypoints,
    required this.completedWaypoints,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      left: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(totalWaypoints, (index) {
                bool isCompleted = index < completedWaypoints;
                return Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? Colors.green
                        : Colors.grey.withOpacity(0.6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCompleted ? Colors.greenAccent : Colors.white38,
                      width: 1,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Text(
              '$completedWaypoints / $totalWaypoints checkpoints',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper class to track waypoint progress
class WaypointTracker {
  final List<LatLng> waypoints;
  final Set<int> completedIndices = {};

  WaypointTracker(this.waypoints);

  void updateProgress(LatLng currentPosition) {
    for (int i = 0; i < waypoints.length; i++) {
      if (completedIndices.contains(i)) continue;

      double distance = Geolocator.distanceBetween(
        currentPosition.lat,
        currentPosition.lng,
        waypoints[i].lat,
        waypoints[i].lng,
      );

      // If within threshold of waypoint, mark as completed
      if (distance <= _PocNavigationScreenState._waypointReachThreshold) {
        completedIndices.add(i);
        print(
          'Waypoint ${i + 1} completed! Distance: ${distance.toStringAsFixed(1)}m',
        );
      }
    }
  }

  int get completedCount => completedIndices.length;
  int get totalCount => waypoints.length;
  double get progressPercentage =>
      totalCount > 0 ? (completedCount / totalCount) : 0.0;
}
