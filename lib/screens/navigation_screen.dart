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
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Navigation Screen
/// - Select a map
/// - Load resolved anchors with markers
/// - Select a marker to navigate to
/// - Arrow guides to selected destination
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  ARSessionManager? _sessionManager;
  ARAnchorManager? _anchorManager;
  ARObjectManager? _objectManager;

  // Anchor management
  final List<PlacedAnchor> _placedAnchors = [];
  PlacedAnchor? _nearestAnchor;
  PlacedAnchor? _destinationAnchor;
  double _destinationDistance = 0.0;
  double _nearestDistance = 0.0;
  double _waypointDistance = 0.0;
  Vector3? _devicePosition;
  Vector3? _lastValidPosition;
  DateTime? _lastPositionUpdate;
  double _deviceHeading = 0.0;
  double _initialHeading = 0.0;
  bool _isHeadingCalibrated = false;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  bool _isLoadingMap = false;
  String? _loadedMapId;
  bool _hasReachedDestination = false;
  final Map<String, ARNode> _visualNodes =
      {}; // Track visual nodes for management
  String? _modelPath; // Path to 3D model GLB file in app documents folder

  // Navigation path/waypoints
  List<PlacedAnchor> _navigationPath = [];
  PlacedAnchor? _currentWaypoint;
  int _currentWaypointIndex = 0;

  // Firebase
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isDeletingAllMaps = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _copyModelAssetToDocuments();
  }

  Future<void> _copyModelAssetToDocuments() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/porche.glb');

      // Check if file already exists
      if (await modelFile.exists()) {
        _modelPath = modelFile.path;
        log('-----✅ 3D model already exists at: $_modelPath');
        return;
      }

      log('-----🔵 Copying 3D model from assets to documents folder...');

      // Load asset from Flutter assets
      final ByteData data = await rootBundle.load('assets/model/porche.glb');
      final bytes = data.buffer.asUint8List();

      // Write to app documents folder
      await modelFile.writeAsBytes(bytes);
      _modelPath = modelFile.path;

      log('-----✅ 3D model copied to: $_modelPath');
    } catch (e) {
      log('-----⚠️ Error copying 3D model: $e');
    }
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

          // Top status bar
          Positioned(top: 40, left: 16, right: 16, child: _renderStatusBar()),

          // Navigation info overlay (only when navigating)
          if (_currentWaypoint != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _renderNavigationInfo(),
            ),

          // Map selector button (only when no map loaded)
          if (_loadedMapId == null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _renderMapSelector(),
            ),

          // Bottom controls
          Positioned(left: 16, right: 16, bottom: 24, child: _renderControls()),

          // Prominent 3D-style navigation arrow
          if (_currentWaypoint != null) _renderEnhanced3DNavigationArrow(),
        ],
      ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Anchors: ${_placedAnchors.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                'Visuals: ${_visualNodes.length}',
                style: TextStyle(
                  color: _visualNodes.length == _placedAnchors.length
                      ? Colors.green
                      : Colors.orange,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (_isLoadingMap)
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
                  'Loading...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _renderMapSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.map, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Select a Map',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
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
              label: const Text('Load Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderAnchorList() {
    final activeAnchors = _placedAnchors
        .where((a) => a.status == AnchorStatus.active)
        .toList();

    if (activeAnchors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No active anchors available. Waiting for resolution...',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.place, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Select Destination',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: activeAnchors.length,
              itemBuilder: (context, index) {
                final anchor = activeAnchors[index];
                final isSelected = _destinationAnchor?.id == anchor.id;
                return GestureDetector(
                  onTap: () {
                    // Build and start navigation path
                    final path = _buildNavigationPath(anchor);
                    setState(() {
                      _destinationAnchor = anchor;
                      _navigationPath = path;
                      _currentWaypointIndex = 0;
                      _currentWaypoint = path.isNotEmpty ? path[0] : null;
                      _hasReachedDestination = false;
                      _nearestAnchor = null;
                    });
                    _showHint(
                      '✅ Navigation set to ${anchor.name} • Waypoints: ${path.length}',
                    );
                    _updateNavigationPath();
                  },
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.green
                          : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.place, color: Colors.white, size: 30),
                        const SizedBox(height: 4),
                        Text(
                          anchor.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderNavigationInfo() {
    // Show current waypoint or nearest anchor
    final target = _currentWaypoint ?? _nearestAnchor ?? _destinationAnchor;
    if (target == null) return const SizedBox.shrink();

    final isNavigating = _destinationAnchor != null && _currentWaypoint != null;
    final distance = isNavigating
        ? _waypointDistance
        : (_nearestDistance > 0 ? _nearestDistance : _destinationDistance);
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
              Text(
                isReached
                    ? '🎯 Destination Reached!'
                    : isNavigating
                    ? 'Waypoint: ${target.name}'
                    : 'Nearest: ${target.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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
                'Progress: Step ${_currentWaypointIndex + 1} of ${_navigationPath.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Final Goal: ${_destinationAnchor!.name} (${_destinationDistance.toStringAsFixed(2)}m)',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _navigationPath.isEmpty
                    ? 0
                    : (_currentWaypointIndex + 1) / _navigationPath.length,
                backgroundColor: Colors.white24,
                color: Colors.white,
                minHeight: 6,
              ),
              const SizedBox(height: 6),
              Text(
                _getNavigationInstruction(
                  target,
                  _currentWaypointIndex,
                  _navigationPath.length,
                ),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _renderEnhanced3DNavigationArrow() {
    final target = _currentWaypoint;
    if (target == null) return const SizedBox.shrink();

    final devicePos = _getCurrentDevicePosition();
    final targetPos = target.transform.getTranslation();
    final direction = targetPos - devicePos;
    final horizontalDirection = Vector3(direction.x, 0, direction.z);
    final distance = horizontalDirection.length;

    // Enhanced debug logging
    log('-----🧭 3D Arrow Debug:');
    log('-----   Target: ${target.name}');
    log('-----   Distance: ${distance.toStringAsFixed(2)}m');
    log(
      '----Device Heading: ${(_deviceHeading * 180 / math.pi).toStringAsFixed(1)}°',
    );

    // "You're here" indicator when very close
    if (distance < 1.0) {
      return Positioned(
        top: MediaQuery.of(context).size.height * 0.5 - 75,
        left: MediaQuery.of(context).size.width * 0.5 - 75,
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                Colors.green.withOpacity(0.9),
                Colors.green.withOpacity(0.7),
                Colors.green.withOpacity(0.95),
              ],
              stops: const [0.2, 0.7, 1.0],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 5),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.6),
                blurRadius: 30,
                spreadRadius: 10,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on,
                color: Colors.white,
                size: 50,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(1, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'YOU\'RE HERE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      offset: Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate arrow rotation toward target
    final worldAngle = math.atan2(
      horizontalDirection.x,
      -horizontalDirection.z,
    );
    final relativeAngle = worldAngle - _deviceHeading;

    // Progressive arrow size based on distance
    final double arrowSize = math.min(
      160.0,
      math.max(120.0, 100.0 + (distance * 8.0)),
    );

    return Positioned(
      top: MediaQuery.of(context).size.height * 0.5 - arrowSize / 2,
      left: MediaQuery.of(context).size.width * 0.5 - arrowSize / 2,
      child: Transform.rotate(
        angle: relativeAngle,
        child: Container(
          width: arrowSize,
          height: arrowSize,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: [
                Colors.orange.withOpacity(0.95),
                Colors.orange.withOpacity(0.8),
                Colors.orange.withOpacity(0.9),
                Colors.deepOrange.withOpacity(0.95),
              ],
              stops: const [0.0, 0.4, 0.7, 1.0],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 25,
                spreadRadius: 5,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.orange.withOpacity(0.6),
                blurRadius: 35,
                spreadRadius: 12,
                offset: const Offset(0, 0),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
                offset: const Offset(-2, -2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.navigation,
                color: Colors.white,
                size: arrowSize * 0.45,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.8),
                    offset: const Offset(3, 3),
                    blurRadius: 6,
                  ),
                  Shadow(
                    color: Colors.orange.withOpacity(0.5),
                    offset: const Offset(-1, -1),
                    blurRadius: 3,
                  ),
                ],
              ),
              Positioned(
                bottom: arrowSize * 0.12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    '${distance.toStringAsFixed(0)}m',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: arrowSize * 0.1,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.7),
                          offset: const Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            if (_destinationAnchor != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _destinationAnchor = null;
                    });
                    _showHint('Destination cleared');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Clear Destination',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Delete all maps button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isDeletingAllMaps ? null : _confirmDeleteAllMaps,
            icon: _isDeletingAllMaps
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_forever),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            label: Text(
              _isDeletingAllMaps ? 'Deleting…' : 'Delete All Maps',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
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
    log('-----🔵 AR View created - initializing...');
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    _sessionManager!.onInitialize(
      showFeaturePoints:
          false, // Disable yellow feature point cubes for cleaner view
      showPlanes: false,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
    );

    _objectManager!.onInitialize();
    _anchorManager!.initGoogleCloudAnchorMode();

    _anchorManager!.onAnchorDownloaded = _onAnchorDownloaded;

    _devicePosition = Vector3.zero();
    _startTrackingDevicePosition();

    log('-----✅ AR initialized');
  }

  void _startTrackingDevicePosition() {
    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      if (!mounted) return;

      final currentHeading = math.atan2(event.y, event.x);

      if (!_isHeadingCalibrated) {
        _initialHeading = currentHeading;
        _isHeadingCalibrated = true;
        _deviceHeading = 0.0;
      } else {
        _deviceHeading = currentHeading - _initialHeading;
      }

      if (mounted) {
        setState(() {});
      }
    });

    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Update device position and navigation progress
      _updateCameraPosition();
      _updateNavigationPath();
    });
  }

  // ===== Device position tracking (multi-strategy) =====
  void _updateCameraPosition() {
    try {
      Vector3? newPosition;

      // Strategy 1: Try to get camera position from AR session (if API available)
      newPosition = _getCameraPositionFromSession();

      // Strategy 2: Estimate position using anchor-based triangulation
      if (newPosition == null && _placedAnchors.length >= 2) {
        newPosition = _estimatePositionFromAnchors();
      }

      // Strategy 3: Use last anchor position as reference
      if (newPosition == null && _placedAnchors.isNotEmpty) {
        newPosition = _estimatePositionFromLastAnchor();
      }

      // Strategy 4: Fallback to origin if nothing else (early session)
      newPosition ??= Vector3.zero();

      if (_validatePositionUpdate(newPosition)) {
        _devicePosition = newPosition;
        _lastValidPosition = newPosition;
        _lastPositionUpdate = DateTime.now();
      } else {
        // keep last valid
        _devicePosition = _lastValidPosition ?? _devicePosition;
      }
    } catch (e) {
      _devicePosition = _lastValidPosition ?? _devicePosition ?? Vector3.zero();
    }
  }

  Vector3? _getCameraPositionFromSession() {
    try {
      if (_sessionManager == null) return null;
      // Placeholder for potential API from ar_flutter_plugin in the future.
      return null;
    } catch (_) {
      return null;
    }
  }

  Vector3? _estimatePositionFromAnchors() {
    if (_placedAnchors.length < 2) return null;
    try {
      final a1 = _placedAnchors[_placedAnchors.length - 2];
      final a2 = _placedAnchors[_placedAnchors.length - 1];
      final p1 = a1.transform.getTranslation();
      final p2 = a2.transform.getTranslation();
      return p2 * 0.8 + p1 * 0.2;
    } catch (_) {
      return null;
    }
  }

  Vector3? _estimatePositionFromLastAnchor() {
    if (_placedAnchors.isEmpty) return null;
    try {
      final last = _placedAnchors.last;
      return last.transform.getTranslation();
    } catch (_) {
      return null;
    }
  }

  bool _validatePositionUpdate(Vector3 newPosition) {
    if (_lastValidPosition == null) return true;
    final distance = (newPosition - _lastValidPosition!).length;
    final dtMs = _lastPositionUpdate != null
        ? DateTime.now().difference(_lastPositionUpdate!).inMilliseconds
        : 1000;
    final maxDistance = (dtMs / 1000.0) * 10.0; // ~10 m/s cap
    if (distance > maxDistance && distance > 2.0) {
      return false;
    }
    return true;
  }

  Vector3 _getCurrentDevicePosition() {
    final now = DateTime.now();
    if (_lastPositionUpdate == null ||
        now.difference(_lastPositionUpdate!).inSeconds > 1) {
      _updateCameraPosition();
    }
    return _devicePosition ?? Vector3.zero();
  }

  double _calculateDistanceToAnchor(PlacedAnchor anchor) {
    final devicePos = _getCurrentDevicePosition();
    final anchorPos = anchor.transform.getTranslation();
    return (anchorPos - devicePos).length;
  }

  // ===== Path-based navigation =====
  List<PlacedAnchor> _buildNavigationPath(PlacedAnchor destination) {
    final devicePos = _getCurrentDevicePosition();

    // Find nearest active anchor to start from
    PlacedAnchor? startAnchor;
    double minDistance = double.infinity;
    for (final anchor in _placedAnchors) {
      if (anchor.status != AnchorStatus.active) continue;
      final distance = (anchor.transform.getTranslation() - devicePos).length;
      if (distance < minDistance) {
        minDistance = distance;
        startAnchor = anchor;
      }
    }

    if (startAnchor == null) return [destination];

    // Build sequential path using anchor connectivity
    List<PlacedAnchor> path = [];
    Set<String> visited = {}; // Prevent infinite loops

    if (startAnchor.sequenceNumber <= destination.sequenceNumber) {
      // Navigate forward through anchor chain
      PlacedAnchor? current = startAnchor;
      while (current != null && !visited.contains(current.id)) {
        path.add(current);
        visited.add(current.id);
        if (current.id == destination.id) break;

        // Find next anchor in sequence
        current = _placedAnchors.cast<PlacedAnchor?>().firstWhere(
          (a) => a?.id == current?.nextAnchorId,
          orElse: () => null,
        );
      }
    } else {
      // Navigate backward through anchor chain
      PlacedAnchor? current = startAnchor;
      while (current != null && !visited.contains(current.id)) {
        path.add(current);
        visited.add(current.id);
        if (current.id == destination.id) break;

        // Find previous anchor in sequence
        current = _placedAnchors.cast<PlacedAnchor?>().firstWhere(
          (a) => a?.id == current?.previousAnchorId,
          orElse: () => null,
        );
      }
    }

    return path.isNotEmpty ? path : [destination];
  }

  // Build the complete forward route starting from the first (lowest sequence) anchor.
  List<PlacedAnchor> _buildCompleteSequentialRoute(
    PlacedAnchor startingAnchor,
  ) {
    final route = <PlacedAnchor>[];
    final visited = <String>{};

    log('-----🔍 DEBUG: Building route starting from: ${startingAnchor.name}');
    log('-----   Starting anchor nextAnchorId: ${startingAnchor.nextAnchorId}');
    log(
      '----Starting anchor previousAnchorId: ${startingAnchor.previousAnchorId}',
    );
    log(
      '-----   Starting anchor sequenceNumber: ${startingAnchor.sequenceNumber}',
    );

    // log all available anchors for visibility
    log('-----   Available anchors:');
    for (final anchor in _placedAnchors) {
      log(
        '     - ${anchor.name}: id=${anchor.id}, seq=${anchor.sequenceNumber}, '
        'next=${anchor.nextAnchorId}, prev=${anchor.previousAnchorId}, status=${anchor.status}',
      );
    }

    PlacedAnchor? current = startingAnchor;

    while (current != null && !visited.contains(current.id)) {
      route.add(current);
      visited.add(current.id);
      log('-----   Added to route: ${current.name}');

      if (_destinationAnchor != null && current.id == _destinationAnchor!.id) {
        log(
          '-----   Reached destination anchor in route build: ${current.name}',
        );
        break;
      }

      if (current.nextAnchorId != null) {
        log('-----   Looking for next anchor with ID: ${current.nextAnchorId}');
        current = _placedAnchors.cast<PlacedAnchor?>().firstWhere(
          (a) => a?.id == current?.nextAnchorId,
          orElse: () => null,
        );
        if (current != null) {
          log('-----   Found next: ${current.name}');
        } else {
          log(
            '-----   ❌ Next anchor not found for ID: ${route.last.nextAnchorId}',
          );
        }
      } else {
        log('-----   No nextAnchorId, ending chain');
        break;
      }
    }

    log(
      '📍 Built route with ${route.length} waypoints: ${route.map((a) => a.name).join(" → ")}',
    );
    return route;
  }

  void _initializeSequentialNavigation() {
    if (_placedAnchors.isEmpty) return;
    // Sort to find the lowest sequence as starting point
    _placedAnchors.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final startingAnchor = _placedAnchors.first;

    final fullRoute = _buildCompleteSequentialRoute(startingAnchor);
    if (fullRoute.length < 2) {
      _showError('Route needs at least 2 waypoints for navigation');
      return;
    }

    setState(() {
      _navigationPath = fullRoute;
      _currentWaypointIndex = 0;
      _currentWaypoint = fullRoute[0];
      _destinationAnchor = fullRoute.last;
      _hasReachedDestination = false;
    });

    log(
      '------🗺️ Auto-started navigation: ${fullRoute.map((a) => a.name).join(" → ")}',
    );
    _showHint(
      '🎯 Navigation started! Follow the arrow through ${fullRoute.length} waypoints',
    );
  }

  void _updateNavigationPath() {
    if (_placedAnchors.isEmpty) {
      setState(() {
        _nearestAnchor = null;
        _currentWaypoint = null;
        _hasReachedDestination = false;
      });
      return;
    }

    final devicePos = _getCurrentDevicePosition();

    if (_destinationAnchor != null && _navigationPath.isNotEmpty) {
      if (_currentWaypointIndex < _navigationPath.length) {
        _currentWaypoint = _navigationPath[_currentWaypointIndex];
        final waypointPos = _currentWaypoint!.transform.getTranslation();
        final waypointDist = (waypointPos - devicePos).length;

        // Dynamic threshold: 1-2 meters based on proximity
        final threshold = math.max(1.0, math.min(2.0, waypointDist * 0.6));

        // Check if reached current waypoint
        if (waypointDist < threshold) {
          if (_currentWaypointIndex < _navigationPath.length - 1) {
            // Advance to next waypoint
            final oldWaypoint = _currentWaypoint!.name;
            setState(() {
              _currentWaypointIndex++;
              _currentWaypoint = _navigationPath[_currentWaypointIndex];
            });
            log(
              '------✅ Reached $oldWaypoint, advancing to ${_currentWaypoint!.name}',
            );
            _showHint(
              '✅ $oldWaypoint reached! Next: ${_currentWaypoint!.name}',
            );
          } else {
            // Reached final destination
            if (!_hasReachedDestination) {
              setState(() {
                _hasReachedDestination = true;
              });
              log(
                '-----🎯 Final destination reached: ${_destinationAnchor!.name}',
              );
              _showHint(
                '🎯 Congratulations! You have reached ${_destinationAnchor!.name}!',
              );
            }
          }
        }

        // Update distance tracking
        final destPos = _destinationAnchor!.transform.getTranslation();
        final destDist = (destPos - devicePos).length;
        setState(() {
          _waypointDistance = waypointDist;
          _destinationDistance = destDist;
        });
      }
    } else {
      // No destination set - just track nearest anchor
      PlacedAnchor? nearest;
      double minDistance = double.infinity;
      for (final anchor in _placedAnchors) {
        if (anchor.status != AnchorStatus.active) continue;
        final distance = (anchor.transform.getTranslation() - devicePos).length;
        if (distance < minDistance) {
          minDistance = distance;
          nearest = anchor;
        }
      }
      if (nearest != null) {
        setState(() {
          _nearestAnchor = nearest;
          _nearestDistance = minDistance;
        });
      }
    }
  }

  String _getNavigationInstruction(
    PlacedAnchor waypoint,
    int index,
    int total,
  ) {
    if (total == 1) {
      return 'Navigate directly to ${waypoint.name}';
    }
    if (index == 0) {
      return 'Start: Head towards ${waypoint.name}';
    } else if (index == total - 1) {
      return 'Final destination: ${waypoint.name}';
    } else {
      final remaining = total - index - 1;
      return 'Continue to ${waypoint.name} ($remaining more stops)';
    }
  }

  void _debugNavigationSystem() {
    log('-----📍 NAVIGATION DEBUG:');
    log('-----   Device Position: ${_getCurrentDevicePosition()}');
    log('-----   Current Waypoint: ${_currentWaypoint?.name}');
    log(
      '------Navigation Path: ${_navigationPath.map((a) => a.name).join(" → ")}',
    );
    log(
      '------Waypoint Progress: ${_currentWaypointIndex + 1}/${_navigationPath.length}',
    );
  }

  Future<void> _loadMap() async {
    try {
      setState(() {
        _isLoadingMap = true;
      });

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
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete map',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Map?'),
                          content: Text(
                            'This will permanently delete "${mapData['name'] ?? 'Unnamed Map'}" and all its anchors.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await _deleteMap(mapDoc.id);
                          if (mounted) {
                            Navigator.pop(context); // Close map selector
                            _showHint('🗑️ Map deleted');
                          }
                        } catch (e) {
                          if (mounted) {
                            _showError('Failed to delete map: $e');
                          }
                        }
                      }
                    },
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

      await _loadAnchorsFromMap(selectedMap['id'] as String);

      setState(() {
        _loadedMapId = selectedMap['id'] as String;
        _isLoadingMap = false;
      });

      _showHint('✅ Map loaded: ${selectedMap['name']}');
    } catch (e) {
      log('-----❌ Error loading map: $e');
      setState(() {
        _isLoadingMap = false;
      });
      _showError('Error loading map: $e');
    }
  }

  Future<void> _loadAnchorsFromMap(String mapId) async {
    try {
      log('-----🔵 Loading anchors from map: $mapId');

      for (final anchor in _placedAnchors) {
        try {
          await _anchorManager?.removeAnchor(anchor.arAnchor);
        } catch (e) {
          log('-----Error removing anchor: $e');
        }
      }

      setState(() {
        _placedAnchors.clear();
        _destinationAnchor = null;
        _navigationPath.clear();
        _currentWaypoint = null;
        _currentWaypointIndex = 0;
        _nearestAnchor = null;
        _visualNodes.clear();
      });

      final anchorsSnapshot = await _firestore
          .collection('maps')
          .doc(mapId)
          .collection('anchors')
          .get();

      if (anchorsSnapshot.docs.isEmpty) {
        _showError('No anchors found in this map');
        return;
      }

      log('-----🔵 Found ${anchorsSnapshot.docs.length} anchors in map');

      for (final anchorDoc in anchorsSnapshot.docs) {
        final anchorData = anchorDoc.data();
        final cloudAnchorId = anchorData['cloudAnchorId'] as String?;

        if (cloudAnchorId == null || cloudAnchorId.isEmpty) {
          continue;
        }

        log('-----🔵 Resolving cloud anchor: $cloudAnchorId');

        try {
          // Initiate cloud anchor resolution ONLY (no placeholders)
          _anchorManager!.downloadAnchor(cloudAnchorId);

          // Store metadata entry; real AR anchor and transform will be set upon resolution
          final placedAnchor = PlacedAnchor(
            id: anchorData['id'] ?? anchorDoc.id,
            name: anchorData['name'] ?? 'Anchor ${_placedAnchors.length + 1}',
            arAnchor: ARPlaneAnchor(
              transformation: Matrix4.identity(),
            ), // temporary
            transform: Matrix4.identity(), // will be updated on resolve
            status: AnchorStatus.draft,
            cloudAnchorId: cloudAnchorId,
            previousAnchorId: anchorData['previousAnchorId'] as String?,
            nextAnchorId: anchorData['nextAnchorId'] as String?,
            sequenceNumber: (anchorData['sequenceNumber'] ?? 0) as int,
          );

          setState(() {
            _placedAnchors.add(placedAnchor);
          });
        } catch (e) {
          log('-----❌ Error downloading anchor $cloudAnchorId: $e');
        }
      }

      // Maintain sequence ordering for path building
      _placedAnchors.sort(
        (a, b) => a.sequenceNumber.compareTo(b.sequenceNumber),
      );
      log(
        '-----✅ Initiated download for ${_placedAnchors.length} cloud anchors',
      );
    } catch (e) {
      log('-----❌ Error loading anchors from map: $e');
      _showError('Error loading anchors: $e');
    }
  }

  // Debug helper: dump Firebase anchor data for a given map
  Future<void> _debugFirebaseData(String mapId) async {
    try {
      log('-----🔍 DEBUG: Checking Firebase data for map: $mapId');
      final anchorsSnapshot = await _firestore
          .collection('maps')
          .doc(mapId)
          .collection('anchors')
          .get();
      log('-----   Found ${anchorsSnapshot.docs.length} anchors in Firebase:');
      for (final doc in anchorsSnapshot.docs) {
        final data = doc.data();
        log('-----     - ${data['name']}');
        log('-----       ID: ${data['id']}');
        log('-----       Sequence: ${data['sequenceNumber']}');
        log('-----       Previous: ${data['previousAnchorId']}');
        log('-----       Next: ${data['nextAnchorId']}');
      }
    } catch (e) {
      log('-----❌ Error checking Firebase data: $e');
    }
  }

  Future<void> _addMarkerVisual(
    ARAnchor anchor,
    Matrix4 transform,
    String anchorId,
  ) async {
    try {
      log('-----🔵 Loading 3D model at resolved anchor origin');
      log('-----   Anchor ID: $anchorId');
      log(
        '------Object Manager: ${_objectManager != null ? "initialized" : "null"}',
      );

      // Create node with your downloaded 3D model
      if (_objectManager != null) {
        try {
          // Ensure model is copied to documents folder
          if (_modelPath == null || !File(_modelPath!).existsSync()) {
            log('-----⚠️ 3D model not available, copying from assets...');
            await _copyModelAssetToDocuments();
          }

          if (_modelPath == null || !File(_modelPath!).existsSync()) {
            log(
              '-----❌ 3D model file not available - cannot create visual marker',
            );
            log('-----🔄 Trying fallback built-in sphere...');
            // Fallback to built-in sphere if model loading fails
            await _addBuiltInSphere(Vector3.zero(), anchorId);
            return;
          }

          log('-----   Creating ARNode with local file: $_modelPath');

          // Create ARNode with 3D model from app documents folder
          // Note: NodeType.fileSystemAppFolderGLB expects just the filename, not full path
          final modelNode = ARNode(
            type: NodeType
                .fileSystemAppFolderGLB, // Load from app documents folder
            uri:
                'porche.glb', // Just the filename - plugin prepends app folder path
            name: anchorId, // Use anchor ID for tracking
            // Position RELATIVE to anchor (match Upload Screen)
            position: Vector3.zero(),
            scale: Vector3(0.2, 0.2, 0.2), // Adjust size (20cm)
          );

          log('-----   ARNode created: ${modelNode.name}');
          log('-----   Attempting to add node to scene...');

          // Add node to AR scene attached to the anchor
          final didAdd = await _objectManager!.addNode(
            modelNode,
            // Attach to the resolved anchor to respect real-world pose
            planeAnchor: anchor is ARPlaneAnchor ? anchor : null,
          );

          log(
            '-----   addNode returned: $didAdd (type: ${didAdd.runtimeType})',
          );

          if (didAdd == true) {
            _visualNodes[anchorId] = modelNode;
            log('-----✅ 3D model attached to anchor successfully');
            log('-----   Visual nodes count: ${_visualNodes.length}');
          } else {
            log(
              '⚠️ Failed to add visual node to scene - addNode returned false',
            );
            log('-----🔄 Trying fallback built-in sphere...');
            // Fallback to built-in sphere if model loading fails
            await _addBuiltInSphere(Vector3.zero(), anchorId);
          }
        } catch (e, stackTrace) {
          log('-----❌ Failed to load 3D model: $e');
          log('-----   Error type: ${e.runtimeType}');
          log('-----🔍 Error details: ${e.toString()}');
          log('-----   Stack trace: $stackTrace');
          log('-----🔄 Trying fallback built-in sphere...');
          // Fallback to built-in sphere if model loading fails
          await _addBuiltInSphere(Vector3.zero(), anchorId);
        }
      } else {
        log('-----❌ Object manager is null - cannot add visual marker');
      }
    } catch (e, stackTrace) {
      log('-----❌ Error in _addMarkerVisual: $e');
      log('-----   Stack trace: $stackTrace');
    }
  }

  // Fallback method using ARCore built-in shapes
  Future<void> _addBuiltInSphere(Vector3 position, String anchorId) async {
    try {
      // Note: ar_flutter_plugin doesn't have built-in ArCoreSphere
      // We'll create a simple fallback using a basic shape if available
      // For now, just log that fallback was attempted
      log('-----⚠️ Fallback sphere creation attempted for anchor: $anchorId');
      log('-----   Position: $position');
      // If you have a fallback sphere model, you could load it here
    } catch (e) {
      log('-----❌ Both model and fallback failed: $e');
    }
  }

  // Clear all visual markers
  Future<void> _clearAllVisualMarkers() async {
    try {
      for (final entry in _visualNodes.entries) {
        try {
          await _objectManager?.removeNode(entry.value);
        } catch (e) {
          log('-----⚠️ Error removing node ${entry.key}: $e');
        }
      }
      _visualNodes.clear();
      log('-----✅ All visual markers cleared');
    } catch (e) {
      log('-----❌ Error clearing markers: $e');
    }
  }

  // Remove specific marker
  Future<void> _removeVisualMarker(String markerId) async {
    try {
      if (_visualNodes.containsKey(markerId)) {
        await _objectManager?.removeNode(_visualNodes[markerId]!);
        _visualNodes.remove(markerId);
        log('-----✅ Marker removed: $markerId');
      }
    } catch (e) {
      log('-----❌ Error removing marker: $e');
    }
  }

  // Update marker scale/position
  Future<void> _updateMarkerScale(String markerId, double scale) async {
    try {
      // Remove old marker
      await _removeVisualMarker(markerId);

      // Find the anchor data and recreate with new scale
      final anchor = _placedAnchors.firstWhere(
        (a) => a.id == markerId,
        orElse: () => _placedAnchors.first,
      );

      // Recreate marker with new scale
      await _addMarkerVisual(anchor.arAnchor, anchor.transform, anchor.id);

      log('-----🔄 Marker scale updated to: $scale');
    } catch (e) {
      log('-----❌ Error updating marker: $e');
    }
  }

  ARAnchor _onAnchorDownloaded(Map<String, dynamic> serializedAnchor) {
    log('-----🔵 Anchor downloaded callback');
    final cloudAnchorId = serializedAnchor['cloudanchorid'] as String?;
    final dynamic resolved = serializedAnchor['anchor'];
    ARAnchor? resolvedAnchor;
    if (resolved is ARAnchor) {
      resolvedAnchor = resolved;
    } else {
      // Try to construct from provided transform if available
      final dynamic t = serializedAnchor['transformation'];
      if (t is List) {
        try {
          final m = Matrix4.fromList(t.cast<double>());
          resolvedAnchor = ARPlaneAnchor(transformation: m);
        } catch (_) {}
      }
    }

    if (cloudAnchorId != null && resolvedAnchor != null) {
      // Find the corresponding PlacedAnchor (metadata record)
      final index = _placedAnchors.indexWhere(
        (a) => a.cloudAnchorId == cloudAnchorId,
      );
      if (index == -1) {
        log('-----❌ Resolved anchor not found for cloud ID: $cloudAnchorId');
        return resolvedAnchor;
      }

      final existing = _placedAnchors[index];
      final resolvedTransform =
          (resolvedAnchor as dynamic).transformation as Matrix4? ??
          Matrix4.identity();

      // Replace metadata entry with a new PlacedAnchor that holds the real AR anchor
      final updated = PlacedAnchor(
        id: existing.id,
        name: existing.name,
        arAnchor: resolvedAnchor,
        transform: resolvedTransform,
        status: AnchorStatus.active,
        cloudAnchorId: existing.cloudAnchorId,
        previousAnchorId: existing.previousAnchorId,
        nextAnchorId: existing.nextAnchorId,
        sequenceNumber: existing.sequenceNumber,
      );

      setState(() {
        _placedAnchors[index] = updated;
      });

      // Add visual marker USING the resolved anchor and its transform
      _addMarkerVisual(resolvedAnchor, resolvedTransform, updated.id);

      _checkResolutionProgress();
      log('-----✅ Cloud anchor resolved and visual added: ${updated.name}');
      return resolvedAnchor;
    }

    return resolvedAnchor ?? ARPlaneAnchor(transformation: Matrix4.identity());
  }

  void _updateNearestAnchor() {
    // Delegate to path-based navigation updater
    _updateNavigationPath();
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

  void _checkResolutionProgress() {
    final total = _placedAnchors.length;
    final resolved = _placedAnchors
        .where((a) => a.status == AnchorStatus.active)
        .length;
    log('-----📊 Resolution Progress: $resolved/$total anchors resolved');
    if (resolved < total) {
      _showHint('Resolving anchors... $resolved/$total complete');
      return;
    }
    // All anchors resolved - debug chain integrity and auto-start
    log('-----🔍 DEBUG: All anchors resolved, checking chain integrity...');
    for (final anchor in _placedAnchors) {
      log(
        '   Anchor: ${anchor.name}, id=${anchor.id}, seq=${anchor.sequenceNumber}, '
        'next=${anchor.nextAnchorId}, prev=${anchor.previousAnchorId}',
      );
    }
    if (_loadedMapId != null) {
      _debugFirebaseData(_loadedMapId!);
    }
    _showHint('✅ All anchors resolved! Starting navigation...');
    // AUTO-START: Initialize sequential navigation when all are resolved
    if (total > 0 && _navigationPath.isEmpty) {
      _initializeSequentialNavigation();
    }
  }

  Future<void> _deleteMap(String mapId) async {
    try {
      // Delete all anchors from the subcollection
      final anchorsRef = _firestore
          .collection('maps')
          .doc(mapId)
          .collection('anchors');
      final anchorsSnapshot = await anchorsRef.get();
      for (final doc in anchorsSnapshot.docs) {
        await anchorsRef.doc(doc.id).delete();
      }
      // Delete the map doc itself
      await _firestore.collection('maps').doc(mapId).delete();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _deleteAllMaps() async {
    try {
      final mapsSnapshot = await _firestore.collection('maps').get();
      int deleted = 0;
      for (final mapDoc in mapsSnapshot.docs) {
        await _deleteMap(mapDoc.id);
        deleted++;
      }
      if (mounted) {
        _showHint('🗑️ Deleted $deleted map(s)');
      }
      // Reset local state
      setState(() {
        _loadedMapId = null;
        _placedAnchors.clear();
        _visualNodes.clear();
        _navigationPath.clear();
        _currentWaypoint = null;
        _destinationAnchor = null;
        _nearestAnchor = null;
      });
    } catch (e) {
      if (mounted) _showError('Failed to delete all maps: $e');
    }
  }

  Future<void> _confirmDeleteAllMaps() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ALL Maps?'),
        content: const Text(
          'This will permanently delete all maps and their anchors. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (mounted) {
        setState(() {
          _isDeletingAllMaps = true;
        });
      }
      try {
        await _deleteAllMaps();
      } finally {
        if (mounted) {
          setState(() {
            _isDeletingAllMaps = false;
          });
        }
      }
    }
  }
}

/// Represents a placed anchor in the AR scene
class PlacedAnchor {
  final String id;
  final String name;
  final ARAnchor arAnchor;
  final Matrix4 transform;
  AnchorStatus status;
  String? cloudAnchorId;
  String? previousAnchorId;
  String? nextAnchorId;
  int sequenceNumber;

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
