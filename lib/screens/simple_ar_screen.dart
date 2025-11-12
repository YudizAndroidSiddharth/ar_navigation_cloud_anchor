import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Simple AR Navigation POC Screen
/// - Tap anywhere to place anchors
/// - Auto-upload to cloud
/// - Show 3D spheres for anchors
/// - Display distance + direction to nearest anchor
class SimpleARScreen extends StatefulWidget {
  const SimpleARScreen({super.key});

  @override
  State<SimpleARScreen> createState() => _SimpleARScreenState();
}

class _SimpleARScreenState extends State<SimpleARScreen> {
  ARSessionManager? _sessionManager;
  ARAnchorManager? _anchorManager;
  ARObjectManager? _objectManager;

  // Anchor management
  final List<PlacedAnchor> _placedAnchors = [];
  int _anchorCounter = 1;
  bool _isUploading = false;
  Timer? _uploadTimeoutTimer;
  final Map<String, ARNode> _visualNodes =
      {}; // Track visual nodes for management
  String? _modelPath; // Path to 3D model GLB file in app documents folder

  // Navigation
  PlacedAnchor? _nearestAnchor;
  PlacedAnchor? _destinationAnchor; // Selected destination for navigation
  PlacedAnchor? _currentWaypoint; // Current waypoint in the path
  List<PlacedAnchor> _navigationPath =
      []; // Complete path from current position to destination
  int _currentWaypointIndex = 0; // Index in the navigation path
  double _nearestDistance = 0.0;
  double _destinationDistance = 0.0;
  double _waypointDistance = 0.0;
  Vector3? _devicePosition;
  Vector3? _lastValidPosition; // For position validation
  DateTime? _lastPositionUpdate; // Track position update timing
  double _deviceHeading =
      0.0; // Device heading in radians (relative to initial orientation)
  double _initialHeading =
      0.0; // Initial heading when AR session starts (for calibration)
  bool _isHeadingCalibrated = false;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  bool _isLoadingMap = false;
  String? _loadedMapId;
  bool _hasReachedDestination = false;

  // Firebase
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _copyModelAssetToDocuments(); // Prepare 3D model for markers
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required for AR features'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _uploadTimeoutTimer?.cancel();
    _magnetometerSubscription?.cancel();
    try {
      _sessionManager?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // AR View
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),

          // Path visualization overlay (shows connection lines)
          if (_navigationPath.isNotEmpty)
            Positioned.fill(child: _renderPathVisualization()),

          // Top status bar
          Positioned(top: 40, left: 16, right: 16, child: _renderStatusBar()),

          // Navigation info overlay
          if (_destinationAnchor != null || _nearestAnchor != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _renderNavigationInfo(),
            ),

          // Navigation arrow overlay (centered, pointing to destination or nearest anchor)
          if (_destinationAnchor != null || _nearestAnchor != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.5 - 40,
              left: MediaQuery.of(context).size.width * 0.5 - 40,
              child: _renderNavigationArrow(),
            ),

          // Destination selector button (if map is loaded)
          if (_loadedMapId != null && _placedAnchors.isNotEmpty)
            Positioned(
              top: 180,
              left: 16,
              right: 16,
              child: _renderDestinationSelector(),
            ),

          // Bottom controls
          Positioned(left: 16, right: 16, bottom: 24, child: _renderControls()),
        ],
      ),
    );
  }

  /// Renders visual path lines connecting waypoints
  Widget _renderPathVisualization() {
    if (_navigationPath.isEmpty) return const SizedBox.shrink();

    // CRITICAL FIX: Use accurate device position from position tracking system
    return CustomPaint(
      painter: PathLinePainter(
        navigationPath: _navigationPath,
        currentWaypointIndex: _currentWaypointIndex,
        devicePosition: _getCurrentDevicePosition(),
      ),
      child: Container(),
    );
  }

  Widget _renderStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Anchors: ${_placedAnchors.length}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (_isUploading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Uploading...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _renderNavigationInfo() {
    // Show current waypoint or nearest anchor
    final targetAnchor = _currentWaypoint ?? _nearestAnchor;
    if (targetAnchor == null) return const SizedBox.shrink();

    final isNavigating = _destinationAnchor != null && _currentWaypoint != null;
    final distance = isNavigating ? _waypointDistance : _nearestDistance;

    // Check if destination reached
    final isReached = _hasReachedDestination;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isReached
            ? Colors.orange.withOpacity(0.9)
            : isNavigating
            ? Colors.green.withOpacity(0.9)
            : Colors.blue.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isReached
                    ? Icons.check_circle
                    : isNavigating
                    ? Icons.navigation
                    : Icons.near_me,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isReached
                      ? '🎯 Destination Reached!'
                      : isNavigating
                      ? 'Waypoint: ${targetAnchor.name}'
                      : 'Nearest: ${targetAnchor.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isReached)
            Text(
              'You have reached ${_destinationAnchor!.name}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            )
          else ...[
            Text(
              'Distance: ${distance.toStringAsFixed(2)}m',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (isNavigating && _destinationAnchor != null) ...[
              const SizedBox(height: 4),
              Text(
                'Final Destination: ${_destinationAnchor!.name} (${_destinationDistance.toStringAsFixed(2)}m)',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Progress: ${_currentWaypointIndex + 1}/${_navigationPath.length} waypoints',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _renderNavigationArrow() {
    // Point to current waypoint (not final destination)
    final targetAnchor = _currentWaypoint ?? _nearestAnchor;
    if (targetAnchor == null) return const SizedBox.shrink();

    // Calculate direction to target anchor in world space
    // CRITICAL FIX: Use accurate device position from position tracking system
    final devicePos = _getCurrentDevicePosition();
    final anchorPos = targetAnchor.transform.getTranslation();
    final direction = anchorPos - devicePos;

    // Project direction onto horizontal plane (X-Z plane, ignoring Y for horizontal navigation)
    final horizontalDirection = Vector3(direction.x, 0, direction.z);

    final isNavigating = _destinationAnchor != null && _currentWaypoint != null;
    final isReached = _hasReachedDestination;

    if (horizontalDirection.length < 0.01) {
      // Anchor is directly above/below, show check or up arrow
      return Container(
        width: 80,
        height: 80,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isReached
              ? Colors.orange.withOpacity(0.9)
              : isNavigating
              ? Colors.green.withOpacity(0.9)
              : Colors.blue.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          isReached ? Icons.check_circle : Icons.arrow_upward,
          color: Colors.white,
          size: 40,
        ),
      );
    }

    // Calculate angle in horizontal plane
    // In ARCore: -Z is forward (camera looks down -Z axis initially)
    final worldAngle = math.atan2(
      horizontalDirection.x,
      -horizontalDirection.z,
    );

    // Adjust for device rotation to get relative angle
    final relativeAngle = worldAngle - _deviceHeading;

    return Transform.rotate(
      angle: relativeAngle,
      child: Container(
        width: 80,
        height: 80,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isReached
              ? Colors.orange.withOpacity(0.9)
              : isNavigating
              ? Colors.green.withOpacity(0.9)
              : Colors.blue.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          isReached ? Icons.check_circle : Icons.arrow_upward,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }

  Widget _renderDestinationSelector() {
    if (_placedAnchors.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.place, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _destinationAnchor != null
                  ? 'Destination: ${_destinationAnchor!.name}'
                  : 'Tap to select destination',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            onPressed: _showDestinationSelector,
          ),
        ],
      ),
    );
  }

  Widget _renderControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Load Map button row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoadingMap ? null : _loadMap,
                icon: _isLoadingMap
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.map),
                label: Text(_loadedMapId != null ? 'Map Loaded' : 'Load Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Clear and Save buttons row
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _clearAnchors,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Clear Anchors',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _saveMap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Save Map',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    log('=====🔵 AR View created - initializing...');
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;
    // locationManager available for future use

    // Initialize session
    _sessionManager!.onInitialize(
      showFeaturePoints: true,
      showPlanes: true, // Show planes to help with anchor placement accuracy
      customPlaneTexturePath: null,
      showWorldOrigin: true, // Show world origin for debugging
    );

    // Initialize object manager for 3D rendering
    _objectManager!.onInitialize();

    // Initialize cloud anchor mode
    _anchorManager!.initGoogleCloudAnchorMode();

    // Set up callbacks
    _sessionManager!.onPlaneOrPointTap = _onTap;
    _anchorManager!.onAnchorUploaded = _onAnchorUploaded;
    _anchorManager!.onAnchorDownloaded = _onAnchorDownloaded;

    // Initialize device position (camera starts at origin in ARCore)
    _devicePosition = Vector3.zero();

    // Track device position and orientation for navigation
    _startTrackingDevicePosition();

    log('=====✅ AR initialized');

    // Show initialization message with better guidance
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _showHint(
          '🎯 IMPORTANT: Move your device slowly in a circular pattern to scan the environment. Look for white planes appearing on surfaces.',
        );
      }
    });

    // Periodic tracking quality check
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _checkTrackingQuality();
    });
  }

  void _startTrackingDevicePosition() {
    // Start tracking device orientation using magnetometer
    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      if (!mounted) return;

      // Calculate device heading from magnetometer data
      // atan2(y, x) gives angle in horizontal plane relative to magnetic north
      final currentHeading = math.atan2(event.y, event.x);

      // Calibrate on first reading: store initial heading
      if (!_isHeadingCalibrated) {
        _initialHeading = currentHeading;
        _isHeadingCalibrated = true;
        _deviceHeading = 0.0; // Start at 0 relative to initial orientation
      } else {
        // Calculate relative heading from initial orientation
        _deviceHeading = currentHeading - _initialHeading;
      }

      // Trigger UI update
      if (mounted) {
        setState(() {
          // Force rebuild to update arrow rotation
        });
      }
    });

    // Poll device position and update navigation periodically
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Update camera/device position from AR session
      _updateCameraPosition();
      _updateNearestAnchor();
    });
  }

  /// Update the camera/device position from the AR session
  ///
  /// AR systems track the camera's movement in world space. The camera
  /// typically starts at the origin (0,0,0) when the AR session begins.
  /// As you move, the camera's position changes while anchors remain fixed
  /// in the world.
  ///
  /// CRITICAL FIX: This method now implements proper device position tracking
  /// using multiple strategies since ar_flutter_plugin doesn't directly expose
  /// the camera transform.
  void _updateCameraPosition() {
    try {
      Vector3? newPosition;

      // Strategy 1: Try to get camera position from AR session (if API available)
      newPosition = _getCameraPositionFromSession();

      // Strategy 2: Estimate position using anchor-based triangulation
      if (newPosition == null && _placedAnchors.length >= 2) {
        newPosition = _estimatePositionFromAnchors();
      }

      // Strategy 3: Use last anchor position as reference (when moving away)
      if (newPosition == null && _placedAnchors.isNotEmpty) {
        newPosition = _estimatePositionFromLastAnchor();
      }

      // Strategy 4: Fallback - stay at origin (only when no anchors exist)
      if (newPosition == null) {
        newPosition = Vector3.zero();
      }

      // Validate and apply position update
      if (_validatePositionUpdate(newPosition)) {
        _devicePosition = newPosition;
        _lastValidPosition = newPosition;
        _lastPositionUpdate = DateTime.now();

        // Debug logging (throttled to avoid spam)
        if (_lastPositionUpdate!.millisecondsSinceEpoch % 1000 < 100) {
          _debugPositionTracking();
        }
      } else {
        // Invalid position update - keep last valid position
        log(
          '=====⚠️ Invalid position update detected, keeping last valid position',
        );
      }
    } catch (e, stackTrace) {
      log('=====❌ Error updating camera position: $e');
      log('=====   Stack trace: $stackTrace');
      _devicePosition = _lastValidPosition ?? Vector3.zero();
    }
  }

  /// Strategy 1: Get camera position from AR session
  ///
  /// NOTE: ar_flutter_plugin v0.7.3 doesn't expose camera transform directly.
  /// This method attempts to access it if the API is extended in future versions.
  /// Returns null if not available.
  Vector3? _getCameraPositionFromSession() {
    try {
      if (_sessionManager == null) return null;

      // Check if camera transform is available (may not be in current plugin version)
      // This is left as a placeholder for future plugin updates
      // Example: final transform = _sessionManager!.getCameraTransform();
      // if (transform != null) return transform.getTranslation();

      return null; // Not available in current version
    } catch (e) {
      return null;
    }
  }

  /// Strategy 2: Estimate device position using anchor-based triangulation
  ///
  /// This method estimates the camera position by analyzing the spatial
  /// relationship between placed anchors. Since anchors are in world space,
  /// we can infer camera position by looking at the anchor network.
  Vector3? _estimatePositionFromAnchors() {
    if (_placedAnchors.length < 2) return null;

    try {
      // Get the two most recent anchors (they form the latest path segment)
      final anchor1 = _placedAnchors[_placedAnchors.length - 2];
      final anchor2 = _placedAnchors[_placedAnchors.length - 1];

      final pos1 = anchor1.transform.getTranslation();
      final pos2 = anchor2.transform.getTranslation();

      // The camera is likely near the most recent anchor when in placement mode
      // Weight towards the most recent anchor (80% recent, 20% previous)
      // This provides better distance estimates than using the origin
      final estimatedPos = pos2 * 0.8 + pos1 * 0.2;

      log('=====   📍 Position estimation (anchor-based):');
      log('=====      Anchor 1: ${pos1.toString()}');
      log('=====      Anchor 2: ${pos2.toString()}');
      log('=====      Estimated: ${estimatedPos.toString()}');

      return estimatedPos;
    } catch (e) {
      log('=====⚠️ Anchor-based estimation failed: $e');
      return null;
    }
  }

  /// Strategy 3: Estimate position from last placed anchor
  ///
  /// When the user is moving away from the last placed anchor to place
  /// the next one, we can estimate they are near the last anchor's position.
  /// This provides better distance calculations than using origin.
  Vector3? _estimatePositionFromLastAnchor() {
    if (_placedAnchors.isEmpty) return null;

    try {
      final lastAnchor = _placedAnchors.last;
      final lastAnchorPos = lastAnchor.transform.getTranslation();

      // If this is the first anchor, camera was at the position where anchor was placed
      // For subsequent anchors, assume camera is moving away from last anchor
      if (_placedAnchors.length == 1) {
        // Camera is very close to the first anchor (just placed it)
        return lastAnchorPos;
      } else {
        // Camera is somewhere between the last two anchors or beyond
        // Use the last anchor as a reference point
        // In navigation mode, this gives reasonable distance estimates
        return lastAnchorPos;
      }
    } catch (e) {
      log('=====⚠️ Last anchor estimation failed: $e');
      return null;
    }
  }

  /// Validate position update to prevent unrealistic jumps
  ///
  /// AR tracking can occasionally produce erroneous positions.
  /// This validation prevents sudden teleportation and maintains smooth tracking.
  bool _validatePositionUpdate(Vector3 newPosition) {
    // No previous position - accept any position
    if (_lastValidPosition == null) {
      return true;
    }

    // Calculate distance from last valid position
    final distance = (newPosition - _lastValidPosition!).length;

    // Check time since last update
    final timeSinceUpdate = _lastPositionUpdate != null
        ? DateTime.now().difference(_lastPositionUpdate!).inMilliseconds
        : 1000;

    // Maximum movement: ~10 m/s (realistic walking/running speed)
    // With 100ms updates: 1 meter per update max
    final maxDistance = (timeSinceUpdate / 1000.0) * 10.0;

    if (distance > maxDistance && distance > 2.0) {
      log('=====⚠️ POSITION VALIDATION FAILED:');
      log('=====   Distance: ${distance.toStringAsFixed(2)}m');
      log('=====   Max allowed: ${maxDistance.toStringAsFixed(2)}m');
      log('=====   Time delta: ${timeSinceUpdate}ms');
      return false; // Reject unrealistic jump
    }

    return true; // Position change is realistic
  }

  /// Debug position tracking information
  ///
  /// Provides detailed logging for troubleshooting position tracking issues.
  void _debugPositionTracking() {
    log('=====📍 POSITION DEBUG:');
    log('=====   Device Position: ${_devicePosition?.toString() ?? "null"}');

    if (_placedAnchors.isNotEmpty) {
      final lastAnchor = _placedAnchors.last;
      final lastPos = lastAnchor.transform.getTranslation();
      final distance = _devicePosition != null
          ? (_devicePosition! - lastPos).length
          : 0.0;

      log('=====   Last Anchor (${lastAnchor.name}): ${lastPos.toString()}');
      log('=====   Distance to last anchor: ${distance.toStringAsFixed(2)}m');
    }

    log('=====   Total anchors: ${_placedAnchors.length}');
    log(
      '   Tracking quality: ${_placedAnchors.length >= 2
          ? "Good (multi-anchor)"
          : _placedAnchors.length == 1
          ? "Fair (single anchor)"
          : "Poor (no anchors)"}',
    );
  }

  /// Get current device position with fallback handling
  ///
  /// This is the main accessor for device position throughout the app.
  /// Always returns a valid Vector3 (never null).
  Vector3 _getCurrentDevicePosition() {
    // Force position update if it's been too long
    final now = DateTime.now();
    if (_lastPositionUpdate == null ||
        now.difference(_lastPositionUpdate!).inSeconds > 1) {
      _updateCameraPosition();
    }

    return _devicePosition ?? Vector3.zero();
  }

  /// Calculate accurate distance to an anchor from current device position
  double _calculateDistanceToAnchor(PlacedAnchor anchor) {
    final currentPos = _getCurrentDevicePosition();
    final anchorPos = anchor.transform.getTranslation();
    final distance = (anchorPos - currentPos).length;

    // Debug logging for critical distance calculations
    if (distance < 0.5 || distance > 50.0) {
      log('=====⚠️ DISTANCE CALCULATION:');
      log('=====   Anchor: ${anchor.name} at ${anchorPos.toString()}');
      log('=====   Device: ${currentPos.toString()}');
      log('=====   Distance: ${distance.toStringAsFixed(2)}m');
    }

    return distance;
  }

  /// Check AR tracking quality and provide feedback
  void _checkTrackingQuality() {
    if (_placedAnchors.isEmpty) {
      return; // Don't check until we have anchors
    }

    // Provide helpful tips based on the current state
    final anchorCount = _placedAnchors.length;
    if (anchorCount == 1) {
      log('=====💡 Tracking quality check: 1 anchor placed');
      log('=====   Tip: Move 2-3 meters away before placing the next anchor');
    } else if (anchorCount > 1) {
      // Calculate distance between last two anchors
      final lastAnchor = _placedAnchors[anchorCount - 1];
      final secondLastAnchor = _placedAnchors[anchorCount - 2];
      final lastPos = lastAnchor.transform.getTranslation();
      final secondLastPos = secondLastAnchor.transform.getTranslation();
      final distance = (lastPos - secondLastPos).length;

      log('=====💡 Tracking quality check: $anchorCount anchors placed');
      log('=====   Last anchor distance: ${distance.toStringAsFixed(2)}m');

      if (distance < 0.5) {
        log('=====   ⚠️ WARNING: Anchors are very close together!');
        log(
          '=====   Tip: Move at least 2-3 meters before placing the next anchor',
        );
      }
    }
  }

  /// Debug coordinate system - show all anchor positions and device position
  ///
  /// Call this method to get a comprehensive view of the spatial layout
  /// for troubleshooting position tracking and navigation issues.
  void _debugCoordinateSystem() {
    log('=====🔍 ═══════════════════════════════════════════════');
    log('=====🔍 COORDINATE SYSTEM DEBUG');
    log('=====🔍 ═══════════════════════════════════════════════');

    final devicePos = _getCurrentDevicePosition();
    log(
      '📱 Device Position: (${devicePos.x.toStringAsFixed(2)}, ${devicePos.y.toStringAsFixed(2)}, ${devicePos.z.toStringAsFixed(2)})   Distance from origin: ${devicePos.length.toStringAsFixed(2)}m',
    );
    log('=====');

    if (_placedAnchors.isEmpty) {
      log('=====   No anchors placed yet');
    } else {
      log('=====⚓ Anchors (${_placedAnchors.length} total):');
      for (int i = 0; i < _placedAnchors.length; i++) {
        final anchor = _placedAnchors[i];
        final pos = anchor.transform.getTranslation();
        final distanceFromDevice = _calculateDistanceToAnchor(anchor);
        final marker = anchor == _currentWaypoint
            ? '🎯'
            : anchor == _destinationAnchor
            ? '🏁'
            : '  ';

        log(
          '$marker ${anchor.name}: (${pos.x.toStringAsFixed(2)}, ${pos.y.toStringAsFixed(2)}, ${pos.z.toStringAsFixed(2)})   Distance from device: ${distanceFromDevice.toStringAsFixed(2)}m',
        );

        if (i > 0) {
          final prevPos = _placedAnchors[i - 1].transform.getTranslation();
          final segmentDistance = (pos - prevPos).length;
          log(
            '       ↳ Distance from previous: ${segmentDistance.toStringAsFixed(2)}m',
          );
        }
      }
    }

    if (_destinationAnchor != null) {
      log('=====');
      log('=====🧭 Navigation:');
      log('=====   Destination: ${_destinationAnchor!.name}');
      log('=====   Current Waypoint: ${_currentWaypoint?.name ?? "None"}');
      log(
        '   Waypoint Index: $_currentWaypointIndex / ${_navigationPath.length}',
      );
      log(
        '=====   Distance to waypoint: ${_waypointDistance.toStringAsFixed(2)}m',
      );
      log(
        '   Distance to destination: ${_destinationDistance.toStringAsFixed(2)}m',
      );
      log('=====   Reached destination: $_hasReachedDestination');
    }

    log('=====🔍 ═══════════════════════════════════════════════');
  }

  Future<void> _onTap(List<ARHitTestResult> hitResults) async {
    if (_isUploading) {
      _showHint('Please wait for current upload to complete');
      return;
    }

    log('=====🔵 Tap detected - Hit results: ${hitResults.length}');

    // Ensure we have valid hit test results
    if (hitResults.isEmpty) {
      _showError(
        '❌ No surface detected!\n\nTips:\n1. Move device slowly to scan\n2. Look for white planes on surfaces\n3. Tap on a detected plane',
      );
      log('=====⚠️ No hit test results - cannot place anchor');
      return;
    }

    // Select the best hit result
    // Priority: Plane hits > Feature point hits
    // This ensures more accurate anchor placement
    ARHitTestResult? bestHit;

    // First, try to find a plane hit (most accurate)
    for (final hit in hitResults) {
      log('=====   Hit result - Distance: ${hit.distance.toStringAsFixed(2)}m');
      if (hit.distance > 0.1 && hit.distance < 10.0) {
        // Valid distance range (10cm to 10m)
        bestHit = hit;
        log(
          '   ✅ Selected hit at distance: ${hit.distance.toStringAsFixed(2)}m',
        );
        break;
      }
    }

    // If no valid hit found, use the first one as fallback
    bestHit ??= hitResults.first;

    final hitResult = bestHit;
    final transform = hitResult.worldTransform;

    log(
      '   Using hit test at distance: ${hitResult.distance.toStringAsFixed(2)}m',
    );

    // Debug: Log the position where anchor will be placed
    final position = transform.getTranslation();
    log(
      '📍 Placing anchor at world position: (${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)})',
    );
    log('=====   Distance from origin: ${position.length.toStringAsFixed(2)}m');

    // Log current device position for debugging
    final currentDevicePos = _getCurrentDevicePosition();
    log('=====   Current device position: ${currentDevicePos.toString()}');
    log(
      '   Distance device->anchor: ${(position - currentDevicePos).length.toStringAsFixed(2)}m',
    );

    // Check if anchor is too close to the last one
    if (_placedAnchors.isNotEmpty) {
      final lastAnchor = _placedAnchors.last;
      final lastPos = lastAnchor.transform.getTranslation();
      final distanceFromLast = (position - lastPos).length;

      log(
        '   Distance from last anchor: ${distanceFromLast.toStringAsFixed(2)}m',
      );

      if (distanceFromLast < 0.3) {
        _showError(
          '⚠️ Too close to previous anchor!\n\nMove at least 2-3 meters away before placing the next anchor.',
        );
        log('=====⚠️ Anchor too close to previous one - rejecting placement');
        return;
      }
    }

    await _placeAnchor(transform);
  }

  Future<void> _placeAnchor(Matrix4 transform) async {
    try {
      final position = transform.getTranslation();
      final currentDevicePos = _getCurrentDevicePosition();

      log('=====🔵 ═══════════════════════════════════════════════');
      log('=====🔵 PLACING ANCHOR $_anchorCounter');
      log('=====🔵 ═══════════════════════════════════════════════');
      log(
        '   Anchor World Position: (${position.x.toStringAsFixed(3)}, ${position.y.toStringAsFixed(3)}, ${position.z.toStringAsFixed(3)})',
      );
      log(
        '=====   Distance from origin: ${position.length.toStringAsFixed(3)}m',
      );
      log(
        '   Device Position: (${currentDevicePos.x.toStringAsFixed(3)}, ${currentDevicePos.y.toStringAsFixed(3)}, ${currentDevicePos.z.toStringAsFixed(3)})',
      );
      log(
        '   Device distance from origin: ${currentDevicePos.length.toStringAsFixed(3)}m',
      );

      // Log transform matrix for debugging
      final matrix = transform.storage;
      log('=====   Transform Matrix:');
      log(
        '      [${matrix[0].toStringAsFixed(2)}, ${matrix[4].toStringAsFixed(2)}, ${matrix[8].toStringAsFixed(2)}, ${matrix[12].toStringAsFixed(2)}]',
      );
      log(
        '      [${matrix[1].toStringAsFixed(2)}, ${matrix[5].toStringAsFixed(2)}, ${matrix[9].toStringAsFixed(2)}, ${matrix[13].toStringAsFixed(2)}]',
      );
      log(
        '      [${matrix[2].toStringAsFixed(2)}, ${matrix[6].toStringAsFixed(2)}, ${matrix[10].toStringAsFixed(2)}, ${matrix[14].toStringAsFixed(2)}]',
      );

      // Create anchor at the tapped location
      // IMPORTANT: ARPlaneAnchor with transformation parameter creates
      // an anchor at the specified world-space transform
      final anchor = ARPlaneAnchor(transformation: transform);
      final didAdd = await _anchorManager!.addAnchor(anchor);

      if (didAdd ?? false) {
        log('=====✅ Anchor added to AR session successfully');

        // Find previous anchor to connect to
        final previousAnchor = _placedAnchors.isEmpty
            ? null
            : _placedAnchors.last;

        // Create placed anchor record with connection info
        final placedAnchor = PlacedAnchor(
          id: 'anchor_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Anchor $_anchorCounter',
          arAnchor: anchor,
          transform: transform,
          status: AnchorStatus.uploading,
          previousAnchorId: previousAnchor?.id,
          sequenceNumber: _anchorCounter - 1,
        );

        // Update previous anchor's nextAnchorId to point to this new anchor
        if (previousAnchor != null) {
          previousAnchor.nextAnchorId = placedAnchor.id;
          final prevPos = previousAnchor.transform.getTranslation();
          final distance = (position - prevPos).length;
          final deviceToPrev = _calculateDistanceToAnchor(previousAnchor);
          final deviceToCurrent = (position - currentDevicePos).length;

          log('=====🔗 ANCHOR CONNECTION:');
          log(
            '   From: ${previousAnchor.name} at (${prevPos.x.toStringAsFixed(2)}, ${prevPos.y.toStringAsFixed(2)}, ${prevPos.z.toStringAsFixed(2)})',
          );
          log(
            '   To:   ${placedAnchor.name} at (${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)})',
          );
          log(
            '=====   Anchor-to-anchor distance: ${distance.toStringAsFixed(3)}m',
          );
          log(
            '   Device to previous anchor: ${deviceToPrev.toStringAsFixed(3)}m',
          );
          log(
            '   Device to new anchor: ${deviceToCurrent.toStringAsFixed(3)}m',
          );

          if (distance < 0.5) {
            log(
              '   ⚠️ WARNING: Distance is very small! AR might have lost tracking.',
            );
          } else if (distance > 10.0) {
            log(
              '   ⚠️ WARNING: Distance is very large! Check AR tracking quality.',
            );
          } else {
            log('=====   ✅ Distance looks good');
          }
        } else {
          log('=====📍 FIRST ANCHOR - No previous anchor to connect to');
          log(
            '   Device position at first anchor: ${currentDevicePos.toString()}',
          );
        }

        setState(() {
          _placedAnchors.add(placedAnchor);
          _anchorCounter++;
          _isUploading = true;
        });

        // Add 3D visual marker
        log('=====🔵 Adding 3D visual marker...');
        await _addSphereVisual(anchor, transform);

        // Start upload
        _uploadAnchor(placedAnchor);

        final message = previousAnchor != null
            ? '✅ ${placedAnchor.name} placed ${(position - previousAnchor.transform.getTranslation()).length.toStringAsFixed(2)}m from ${previousAnchor.name}'
            : '✅ ${placedAnchor.name} placed (first anchor)';
        _showHint(message);

        log('=====✅ ═══════════════════════════════════════════════');
        log('=====✅ ANCHOR PLACEMENT COMPLETE');
        log('=====✅ ═══════════════════════════════════════════════');

        // Debug: Show complete coordinate system after placing anchor
        _debugCoordinateSystem();
      } else {
        log('=====❌ Failed to add anchor to AR session');
        _showError('Failed to place anchor - AR system error');
      }
    } catch (e, stackTrace) {
      log('=====❌ Error placing anchor: $e');
      log('=====   Stack trace: $stackTrace');
      _showError('Error placing anchor: $e');
    }
  }

  Future<void> _addSphereVisual(ARAnchor anchor, Matrix4 transform) async {
    try {
      final position = transform.getTranslation();
      log(
        '🔵 Adding sphere visual at position: (${position.x.toStringAsFixed(2)}, ${position.y.toStringAsFixed(2)}, ${position.z.toStringAsFixed(2)})',
      );

      if (_objectManager == null) {
        log('=====❌ Object manager is null - cannot add visual marker');
        return;
      }

      // Ensure model is copied to documents folder
      if (_modelPath == null || !File(_modelPath!).existsSync()) {
        log('=====⚠️ 3D model not available, copying from assets...');
        await _copyModelAssetToDocuments();
      }

      if (_modelPath == null || !File(_modelPath!).existsSync()) {
        log('=====❌ 3D model file not available - cannot create visual marker');
        _showError('3D model not found. Cannot display visual marker.');
        return;
      }

      log('=====   Creating ARNode with model: $_modelPath');

      // Create a bright, visible sphere marker
      // Using the porche.glb model but scaling it down to be a marker
      //
      // IMPORTANT: When attaching a node to an anchor, the position should be
      // RELATIVE to the anchor, not absolute world coordinates.
      // Vector3.zero() places the node exactly at the anchor's location.
      // The anchor's transform (managed by ARCore) handles world positioning.
      final modelNode = ARNode(
        type: NodeType.fileSystemAppFolderGLB,
        uri: 'porche.glb', // Filename in app documents directory
        name: anchor.name, // Use anchor name for tracking
        position: Vector3.zero(), // Relative to anchor position
        scale: Vector3(
          0.15,
          0.15,
          0.15,
        ), // 15cm marker (visible but not too large)
      );

      log('=====   ARNode created: ${modelNode.name}');
      log('=====   Attempting to add node to scene...');

      // Add node to the scene
      final didAdd = await _objectManager!.addNode(
        modelNode,
        planeAnchor: anchor is ARPlaneAnchor ? anchor : null,
      );

      log('=====   addNode returned: $didAdd (type: ${didAdd.runtimeType})');

      if (didAdd == true) {
        _visualNodes[anchor.name] = modelNode;
        log('=====✅ 3D marker added successfully: ${anchor.name}');
        log('=====   Visual nodes count: ${_visualNodes.length}');
      } else {
        log(
          '⚠️ Failed to add visual node to scene - addNode returned: $didAdd',
        );
        _showError('Failed to display 3D marker for ${anchor.name}');
      }
    } catch (e, stackTrace) {
      log('=====❌ Error adding sphere visual: $e');
      log('=====   Stack trace: $stackTrace');
      _showError('Error displaying 3D marker: $e');
    }
  }

  /// Copy the 3D model from assets to app documents directory
  /// This is required because ARNode with NodeType.fileSystemAppFolderGLB
  /// expects the file to be in the app's documents folder
  Future<void> _copyModelAssetToDocuments() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/porche.glb');

      // Check if file already exists
      if (await modelFile.exists()) {
        _modelPath = modelFile.path;
        log('=====✅ 3D model already exists at: $_modelPath');
        return;
      }

      log('=====🔵 Copying 3D model from assets to documents folder...');

      // Load asset from Flutter assets
      final ByteData data = await rootBundle.load('assets/model/porche.glb');
      final bytes = data.buffer.asUint8List();

      // Write to app documents folder
      await modelFile.writeAsBytes(bytes);
      _modelPath = modelFile.path;
      log('=====✅ 3D model copied to: $_modelPath');
    } catch (e, stackTrace) {
      log('=====❌ Error copying 3D model: $e');
      log('=====   Stack trace: $stackTrace');
      _showError('Failed to load 3D model: $e');
    }
  }

  void _uploadAnchor(PlacedAnchor placedAnchor) {
    log('=====🔵 Uploading anchor: ${placedAnchor.name}');

    // Set timeout
    _uploadTimeoutTimer?.cancel();
    _uploadTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isUploading) {
        setState(() {
          placedAnchor.status = AnchorStatus.failed;
          _isUploading = false;
        });
        _showError('Upload timeout for ${placedAnchor.name}');
      }
    });

    // Upload anchor
    try {
      _anchorManager!.uploadAnchor(placedAnchor.arAnchor);
    } catch (e) {
      log('=====❌ Error uploading anchor: $e');
      _uploadTimeoutTimer?.cancel();
      setState(() {
        placedAnchor.status = AnchorStatus.failed;
        _isUploading = false;
      });
      _showError('Error uploading anchor: $e');
    }
  }

  void _onAnchorUploaded(ARAnchor anchor) async {
    log('=====🔵 Anchor uploaded callback');
    _uploadTimeoutTimer?.cancel();

    if (anchor is ARPlaneAnchor && anchor.cloudanchorid != null) {
      // Find matching placed anchor
      final placedAnchor = _placedAnchors.firstWhere(
        (a) => a.arAnchor == anchor,
        orElse: () => _placedAnchors.last,
      );

      placedAnchor.cloudAnchorId = anchor.cloudanchorid;
      placedAnchor.status = AnchorStatus.active;

      setState(() {
        _isUploading = false;
      });

      log('=====✅ Anchor uploaded: ${placedAnchor.cloudAnchorId}');
      _showHint('✅ ${placedAnchor.name} uploaded successfully');

      // Update navigation
      _updateNearestAnchor();
    }
  }

  ARAnchor _onAnchorDownloaded(Map<String, dynamic> serializedAnchor) {
    log('=====🔵 Anchor downloaded callback');
    log('=====   Cloud Anchor ID: ${serializedAnchor['cloudanchorid']}');

    // Find matching placed anchor by cloud anchor ID
    final cloudAnchorId = serializedAnchor['cloudanchorid'] as String?;
    if (cloudAnchorId != null) {
      final placedAnchor = _placedAnchors.firstWhere(
        (a) => a.cloudAnchorId == cloudAnchorId,
        orElse: () => _placedAnchors.last,
      );

      if (placedAnchor.status == AnchorStatus.draft) {
        placedAnchor.status = AnchorStatus.active;
        log('=====✅ Anchor resolved: ${placedAnchor.name}');
        _showHint('✅ ${placedAnchor.name} resolved');
      }

      // Return the existing anchor
      return placedAnchor.arAnchor;
    }

    // Fallback: create new anchor
    return ARPlaneAnchor(transformation: Matrix4.identity());
  }

  Future<void> _loadMap() async {
    try {
      setState(() {
        _isLoadingMap = true;
      });

      // Fetch all saved maps
      final mapsSnapshot = await _firestore
          .collection('maps')
          .orderBy('createdAt', descending: true)
          .get();

      if (mapsSnapshot.docs.isEmpty) {
        _showError('No saved maps found');
        setState(() {
          _isLoadingMap = false;
        });
        return;
      }

      // Show map selection dialog
      final selectedMap = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Map'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: mapsSnapshot.docs.length,
              itemBuilder: (context, index) {
                final mapDoc = mapsSnapshot.docs[index];
                final mapData = mapDoc.data();
                return ListTile(
                  title: Text(mapData['name'] ?? 'Unnamed Map'),
                  subtitle: Text(
                    '${mapData['anchorCount'] ?? 0} anchors • ${_formatDate(mapData['createdAt'])}',
                  ),
                  onTap: () =>
                      Navigator.pop(context, {'id': mapDoc.id, ...mapData}),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedMap == null) {
        setState(() {
          _isLoadingMap = false;
        });
        return;
      }

      // Load anchors from selected map
      await _loadAnchorsFromMap(selectedMap['id'] as String);

      setState(() {
        _loadedMapId = selectedMap['id'] as String;
        _isLoadingMap = false;
      });

      _showHint('✅ Map loaded: ${selectedMap['name']}');
    } catch (e) {
      log('=====❌ Error loading map: $e');
      setState(() {
        _isLoadingMap = false;
      });
      _showError('Error loading map: $e');
    }
  }

  Future<void> _loadAnchorsFromMap(String mapId) async {
    try {
      log('=====🔵 Loading anchors from map: $mapId');

      // Clear existing anchors
      for (final anchor in _placedAnchors) {
        try {
          await _anchorManager?.removeAnchor(anchor.arAnchor);
        } catch (e) {
          log('=====Error removing anchor: $e');
        }
      }

      setState(() {
        _placedAnchors.clear();
        _anchorCounter = 1;
        _destinationAnchor = null;
        _nearestAnchor = null;
      });

      // Fetch anchors from map
      final anchorsSnapshot = await _firestore
          .collection('maps')
          .doc(mapId)
          .collection('anchors')
          .get();

      if (anchorsSnapshot.docs.isEmpty) {
        _showError('No anchors found in this map');
        return;
      }

      log('=====🔵 Found ${anchorsSnapshot.docs.length} anchors in map');

      // First pass: Create all anchors
      for (final anchorDoc in anchorsSnapshot.docs) {
        final anchorData = anchorDoc.data();
        final cloudAnchorId = anchorData['cloudAnchorId'] as String?;

        if (cloudAnchorId == null || cloudAnchorId.isEmpty) {
          log('=====⚠️ Skipping anchor without cloud anchor ID');
          continue;
        }

        log('=====🔵 Resolving cloud anchor: $cloudAnchorId');

        // Download cloud anchor
        try {
          _anchorManager!.downloadAnchor(cloudAnchorId);

          // Create placeholder anchor (will be updated when downloaded)
          final positionData = anchorData['position'] as Map<String, dynamic>?;
          final position = positionData != null
              ? Vector3(
                  (positionData['x'] ?? 0.0).toDouble(),
                  (positionData['y'] ?? 0.0).toDouble(),
                  (positionData['z'] ?? 0.0).toDouble(),
                )
              : Vector3.zero();

          final transform = Matrix4.identity();
          transform.setTranslation(position);

          final placeholderAnchor = ARPlaneAnchor(transformation: transform);
          await _anchorManager!.addAnchor(placeholderAnchor);

          final placedAnchor = PlacedAnchor(
            id: anchorData['id'] ?? anchorDoc.id,
            name: anchorData['name'] ?? 'Anchor $_anchorCounter',
            arAnchor: placeholderAnchor,
            transform: transform,
            status: AnchorStatus.draft, // Will be updated when resolved
            cloudAnchorId: cloudAnchorId,
            previousAnchorId: anchorData['previousAnchorId'] as String?,
            nextAnchorId: anchorData['nextAnchorId'] as String?,
            sequenceNumber: (anchorData['sequenceNumber'] ?? 0) as int,
          );

          setState(() {
            _placedAnchors.add(placedAnchor);
            _anchorCounter++;
          });

          // Add visual
          _addSphereVisual(placeholderAnchor, transform);
        } catch (e) {
          log('=====❌ Error downloading anchor $cloudAnchorId: $e');
        }
      }

      // Sort anchors by sequence number to maintain path order
      _placedAnchors.sort(
        (a, b) => a.sequenceNumber.compareTo(b.sequenceNumber),
      );

      log(
        '✅ Loaded ${_placedAnchors.length} anchors from map with connections',
      );
    } catch (e) {
      log('=====❌ Error loading anchors from map: $e');
      _showError('Error loading anchors: $e');
    }
  }

  /// Build navigation path from current position to destination
  List<PlacedAnchor> _buildNavigationPath(PlacedAnchor destination) {
    final devicePos = _devicePosition ?? Vector3.zero();

    // Find the nearest anchor to the current device position
    PlacedAnchor? nearestAnchor;
    double minDistance = double.infinity;

    for (final anchor in _placedAnchors) {
      if (anchor.status != AnchorStatus.active) continue;

      final anchorPos = anchor.transform.getTranslation();
      final distance = (anchorPos - devicePos).length;

      if (distance < minDistance) {
        minDistance = distance;
        nearestAnchor = anchor;
      }
    }

    if (nearestAnchor == null) {
      log('=====⚠️ No active anchors found for path building');
      return [destination];
    }

    log(
      '🔵 Building path from ${nearestAnchor.name} (nearest) to ${destination.name}',
    );

    // Build path by following connections
    final path = <PlacedAnchor>[];

    // Determine direction: forward (nextAnchorId) or backward (previousAnchorId)
    if (nearestAnchor.sequenceNumber <= destination.sequenceNumber) {
      // Move forward through the path
      PlacedAnchor? current = nearestAnchor;
      while (current != null) {
        path.add(current);
        if (current.id == destination.id) break;

        // Find next anchor
        if (current.nextAnchorId != null) {
          current = _placedAnchors.firstWhere(
            (a) => a.id == current!.nextAnchorId,
            orElse: () => current!,
          );
          if (current.id == path.last.id) break; // Prevent infinite loop
        } else {
          break;
        }
      }
    } else {
      // Move backward through the path
      PlacedAnchor? current = nearestAnchor;
      while (current != null) {
        path.add(current);
        if (current.id == destination.id) break;

        // Find previous anchor
        if (current.previousAnchorId != null) {
          current = _placedAnchors.firstWhere(
            (a) => a.id == current!.previousAnchorId,
            orElse: () => current!,
          );
          if (current.id == path.last.id) break; // Prevent infinite loop
        } else {
          break;
        }
      }
    }

    if (path.isEmpty) {
      log('=====⚠️ Could not build path, using direct route to destination');
      return [destination];
    }

    log(
      '✅ Built path with ${path.length} waypoints: ${path.map((a) => a.name).join(" -> ")}',
    );
    return path;
  }

  void _showDestinationSelector() {
    if (_placedAnchors.isEmpty) {
      _showError('No anchors available');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Destination'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _placedAnchors.length,
            itemBuilder: (context, index) {
              final anchor = _placedAnchors[index];
              return ListTile(
                title: Text(anchor.name),
                subtitle: Text(
                  anchor.status == AnchorStatus.active
                      ? 'Active • Seq: ${anchor.sequenceNumber}'
                      : 'Status: ${anchor.status}',
                ),
                enabled: anchor.status == AnchorStatus.active,
                onTap: anchor.status == AnchorStatus.active
                    ? () {
                        log('=====🔵 Setting destination: ${anchor.name}');

                        // Build navigation path
                        final path = _buildNavigationPath(anchor);

                        setState(() {
                          _destinationAnchor = anchor;
                          _navigationPath = path;
                          _currentWaypointIndex = 0;
                          _currentWaypoint = path.isNotEmpty ? path[0] : null;
                          _nearestAnchor =
                              null; // Clear nearest when destination is set
                        });

                        Navigator.pop(context);
                        _showHint(
                          '✅ Navigation started to ${anchor.name}\n📍 Following ${path.length} waypoints',
                        );

                        // Immediately update navigation to show arrow and distance
                        _updateNavigationPath();
                      }
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _destinationAnchor = null;
                _navigationPath.clear();
                _currentWaypoint = null;
              });
              Navigator.pop(context);
              _showHint('Destination cleared');
            },
            child: const Text('Clear Destination'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  /// Update navigation path - handles waypoint progression and destination tracking
  void _updateNavigationPath() {
    if (_placedAnchors.isEmpty) {
      setState(() {
        _nearestAnchor = null;
        _currentWaypoint = null;
        _hasReachedDestination = false;
      });
      return;
    }

    // CRITICAL FIX: Use accurate device position from position tracking system
    final devicePos = _getCurrentDevicePosition();

    // If we have an active navigation path
    if (_destinationAnchor != null && _navigationPath.isNotEmpty) {
      // Update current waypoint
      if (_currentWaypointIndex < _navigationPath.length) {
        _currentWaypoint = _navigationPath[_currentWaypointIndex];

        // Calculate distance to current waypoint
        final waypointPos = _currentWaypoint!.transform.getTranslation();
        final waypointDist = (waypointPos - devicePos).length;

        // Calculate distance to final destination
        final destPos = _destinationAnchor!.transform.getTranslation();
        final destDist = (destPos - devicePos).length;

        // Check if current waypoint is reached (within 1.5 meters)
        if (waypointDist < 1.5 &&
            _currentWaypointIndex < _navigationPath.length - 1) {
          // Advance to next waypoint
          setState(() {
            _currentWaypointIndex++;
            _currentWaypoint = _navigationPath[_currentWaypointIndex];
          });

          log(
            '✅ Reached ${_navigationPath[_currentWaypointIndex - 1].name}, advancing to ${_currentWaypoint!.name}',
          );
          _showHint('✅ Waypoint reached! Moving to ${_currentWaypoint!.name}');
        }

        // Check if final destination is reached
        final isFinalDestination =
            _currentWaypoint!.id == _destinationAnchor!.id;
        final destinationReached = isFinalDestination && destDist < 2.0;

        setState(() {
          _waypointDistance = waypointDist;
          _destinationDistance = destDist;

          if (destinationReached && !_hasReachedDestination) {
            _hasReachedDestination = true;
            _showHint('🎯 You have reached ${_destinationAnchor!.name}!');
          } else if (!destinationReached && _hasReachedDestination) {
            _hasReachedDestination = false;
          }
        });
      }
    } else {
      // No destination set - find nearest anchor for reference
      PlacedAnchor? nearest;
      double minDistance = double.infinity;

      for (final anchor in _placedAnchors) {
        if (anchor.status != AnchorStatus.active) continue;

        final anchorPos = anchor.transform.getTranslation();
        final distance = (anchorPos - devicePos).length;

        if (distance < minDistance) {
          minDistance = distance;
          nearest = anchor;
        }
      }

      if (nearest != null && minDistance < double.infinity) {
        setState(() {
          _nearestAnchor = nearest;
          _nearestDistance = minDistance;
        });
      }
    }
  }

  void _updateNearestAnchor() {
    // Use the new path-based navigation system
    _updateNavigationPath();
  }

  Future<void> _clearAnchors() async {
    if (_placedAnchors.isEmpty) {
      _showHint('No anchors to clear');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Anchors?'),
        content: Text('This will remove all ${_placedAnchors.length} anchors.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Remove all anchors from AR
      for (final anchor in _placedAnchors) {
        try {
          await _anchorManager?.removeAnchor(anchor.arAnchor);
        } catch (e) {
          log('=====Error removing anchor: $e');
        }
      }

      setState(() {
        _placedAnchors.clear();
        _anchorCounter = 1;
        _nearestAnchor = null;
        _isUploading = false;
      });

      _uploadTimeoutTimer?.cancel();
      _showHint('All anchors cleared');
    }
  }

  Future<void> _saveMap() async {
    if (_placedAnchors.isEmpty) {
      _showError('No anchors to save');
      return;
    }

    // Filter only active anchors
    final activeAnchors = _placedAnchors
        .where((a) => a.status == AnchorStatus.active)
        .toList();

    if (activeAnchors.isEmpty) {
      _showError(
        'No active anchors to save. Please wait for uploads to complete.',
      );
      return;
    }

    try {
      setState(() {
        _isUploading = true;
      });

      // Create map document
      final mapId = 'map_${DateTime.now().millisecondsSinceEpoch}';
      final mapData = {
        'id': mapId,
        'name': 'Map ${DateTime.now().toString().substring(0, 16)}',
        'createdAt': DateTime.now().toIso8601String(),
        'anchorCount': activeAnchors.length,
      };

      // Save map to Firebase
      await _firestore.collection('maps').doc(mapId).set(mapData);

      // Save anchors as subcollection with connection info
      final anchorsRef = _firestore
          .collection('maps')
          .doc(mapId)
          .collection('anchors');
      for (final anchor in activeAnchors) {
        final anchorData = {
          'id': anchor.id,
          'name': anchor.name,
          'cloudAnchorId': anchor.cloudAnchorId,
          'position': {
            'x': anchor.transform.getTranslation().x,
            'y': anchor.transform.getTranslation().y,
            'z': anchor.transform.getTranslation().z,
          },
          'previousAnchorId': anchor.previousAnchorId,
          'nextAnchorId': anchor.nextAnchorId,
          'sequenceNumber': anchor.sequenceNumber,
          'createdAt': DateTime.now().toIso8601String(),
        };
        await anchorsRef.doc(anchor.id).set(anchorData);
      }

      log(
        '✅ Saved ${activeAnchors.length} anchors with connections to map $mapId',
      );

      setState(() {
        _isUploading = false;
      });

      _showHint('✅ Map saved successfully! (${activeAnchors.length} anchors)');
    } catch (e) {
      log('=====❌ Error saving map: $e');
      setState(() {
        _isUploading = false;
      });
      _showError('Error saving map: $e');
    }
  }

  void _showHint(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(msg)));
  }
}

/// Represents a placed anchor in the AR scene with connection support
class PlacedAnchor {
  final String id;
  final String name;
  final ARAnchor arAnchor;
  final Matrix4 transform;
  AnchorStatus status;
  String? cloudAnchorId;

  // Connection information for path navigation
  String? previousAnchorId; // ID of the previous anchor in the path
  String? nextAnchorId; // ID of the next anchor in the path
  int sequenceNumber; // Position in the path sequence (0-based)

  PlacedAnchor({
    required this.id,
    required this.name,
    required this.arAnchor,
    required this.transform,
    required this.status,
    this.cloudAnchorId,
    this.previousAnchorId,
    this.nextAnchorId,
    this.sequenceNumber = 0,
  });
}

/// Custom painter to draw path lines between connected waypoints
class PathLinePainter extends CustomPainter {
  final List<PlacedAnchor> navigationPath;
  final int currentWaypointIndex;
  final Vector3 devicePosition;

  PathLinePainter({
    required this.navigationPath,
    required this.currentWaypointIndex,
    required this.devicePosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (navigationPath.length < 2) return;

    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final completedPaint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final activePaint = Paint()
      ..color = Colors.blue.withOpacity(0.7)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw lines between consecutive waypoints
    for (int i = 0; i < navigationPath.length - 1; i++) {
      final anchor1 = navigationPath[i];
      final anchor2 = navigationPath[i + 1];

      // Get anchor positions in 3D space
      final pos1 = anchor1.transform.getTranslation();
      final pos2 = anchor2.transform.getTranslation();

      // Simple 2D projection (for demo - in production, use proper camera projection)
      // Map 3D world coordinates to 2D screen space
      // This is a simplified projection - adjust based on your AR coordinate system
      final screenPos1 = _projectToScreen(pos1, size);
      final screenPos2 = _projectToScreen(pos2, size);

      // Choose paint based on whether this segment is completed or active
      Paint segmentPaint;
      if (i < currentWaypointIndex) {
        segmentPaint = completedPaint; // Already passed this segment
      } else if (i == currentWaypointIndex) {
        segmentPaint = activePaint; // Currently navigating this segment
      } else {
        segmentPaint = paint
          ..color = Colors.orange.withOpacity(0.4); // Upcoming segment
      }

      // Draw the line
      if (screenPos1 != null && screenPos2 != null) {
        canvas.drawLine(screenPos1, screenPos2, segmentPaint);

        // Draw waypoint markers
        final markerPaint = Paint()
          ..color = i < currentWaypointIndex
              ? Colors.green
              : (i == currentWaypointIndex ? Colors.blue : Colors.orange)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(screenPos1, 8, markerPaint);
        if (i == navigationPath.length - 2) {
          // Draw final waypoint
          canvas.drawCircle(screenPos2, 10, markerPaint);
        }
      }
    }
  }

  /// Project 3D world coordinates to 2D screen space
  /// This is a simplified projection - in production, use proper camera projection matrix
  Offset? _projectToScreen(Vector3 worldPos, Size screenSize) {
    // Simple orthographic-like projection
    // In a real AR app, you'd use the camera's projection matrix
    // For now, we'll use a simplified approach

    // Calculate relative position from device
    final relativePos = worldPos - devicePosition;

    // Simple 2D projection onto screen
    // Map X (horizontal) and Z (depth) to screen coordinates
    final screenX =
        screenSize.width / 2 + (relativePos.x * 100); // Scale factor
    final screenY =
        screenSize.height / 2 - (relativePos.z * 100); // Flip Z for screen Y

    // Check if on screen
    if (screenX < -100 ||
        screenX > screenSize.width + 100 ||
        screenY < -100 ||
        screenY > screenSize.height + 100) {
      return null; // Off screen
    }

    return Offset(screenX, screenY);
  }

  @override
  bool shouldRepaint(covariant PathLinePainter oldDelegate) {
    return oldDelegate.currentWaypointIndex != currentWaypointIndex ||
        oldDelegate.navigationPath.length != navigationPath.length ||
        (oldDelegate.devicePosition - devicePosition).length > 0.1;
  }
}
