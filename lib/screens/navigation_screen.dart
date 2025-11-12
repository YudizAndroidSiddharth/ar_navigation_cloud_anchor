import 'dart:async';
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
        print('✅ 3D model already exists at: $_modelPath');
        return;
      }

      print('🔵 Copying 3D model from assets to documents folder...');

      // Load asset from Flutter assets
      final ByteData data = await rootBundle.load('assets/model/porche.glb');
      final bytes = data.buffer.asUint8List();

      // Write to app documents folder
      await modelFile.writeAsBytes(bytes);
      _modelPath = modelFile.path;

      print('✅ 3D model copied to: $_modelPath');
    } catch (e) {
      print('⚠️ Error copying 3D model: $e');
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

          // Navigation info overlay
          if (_destinationAnchor != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _renderNavigationInfo(),
            ),

          // Map selector button
          if (_loadedMapId == null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _renderMapSelector(),
            ),

          // Anchor list (if map loaded)
          if (_loadedMapId != null && _placedAnchors.isNotEmpty)
            Positioned(
              top: _destinationAnchor != null ? 180 : 100,
              left: 16,
              right: 16,
              child: _renderAnchorList(),
            ),

          // Bottom controls
          Positioned(left: 16, right: 16, bottom: 24, child: _renderControls()),

          // Navigation arrow overlay (rendered last to ensure it's on top)
          if (_destinationAnchor != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.5 - 40,
              left: MediaQuery.of(context).size.width * 0.5 - 40,
              child: _renderNavigationArrow(),
            ),
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
                'Final Destination: ${_destinationAnchor!.name} (${_destinationDistance.toStringAsFixed(2)}m)',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Progress: ${_currentWaypointIndex + 1}/${_navigationPath.length} waypoints',
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

  Widget _renderNavigationArrow() {
    // Arrow should point to current waypoint (not directly to final destination)
    final target = _currentWaypoint ?? _nearestAnchor ?? _destinationAnchor;
    if (target == null) return const SizedBox.shrink();

    final devicePos = _getCurrentDevicePosition();
    final anchorPos = target.transform.getTranslation();
    final direction = anchorPos - devicePos;

    final horizontalDirection = Vector3(direction.x, 0, direction.z);

    final isNavigating = _destinationAnchor != null && _currentWaypoint != null;
    final isReached = _hasReachedDestination;

    // Debug: Print arrow state
    print(
      '🧭 Navigation Arrow - Heading: ${(_deviceHeading * 180 / math.pi).toStringAsFixed(1)}°, '
      'Target: ${target.name}, '
      'Mode: ${isNavigating ? "waypoint" : "nearest"}',
    );

    // If very close or directly above/below, show up arrow
    if (horizontalDirection.length < 0.01) {
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
              color: Colors.black.withOpacity(0.5),
              blurRadius: 15,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Icon(
          isReached ? Icons.check_circle : Icons.arrow_upward,
          color: Colors.white,
          size: 50,
        ),
      );
    }

    // Calculate angle to destination
    final worldAngle = math.atan2(
      horizontalDirection.x,
      -horizontalDirection.z,
    );
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
              color: Colors.black.withOpacity(0.5),
              blurRadius: 15,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Icon(
          isReached ? Icons.check_circle : Icons.arrow_upward,
          color: Colors.white,
          size: 50,
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
    print('🔵 AR View created - initializing...');
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

    print('✅ AR initialized');
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

    // Find nearest active anchor
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
      print('⚠️ No active anchors for path');
      return [destination];
    }

    final path = <PlacedAnchor>[];
    if (nearestAnchor.sequenceNumber <= destination.sequenceNumber) {
      PlacedAnchor? current = nearestAnchor;
      while (current != null) {
        path.add(current);
        if (current.id == destination.id) break;
        if (current.nextAnchorId != null) {
          final next = _placedAnchors
              .where((a) => a.id == current!.nextAnchorId)
              .toList();
          if (next.isEmpty) break;
          current = next.first;
          if (current.id == path.last.id) break;
        } else {
          break;
        }
      }
    } else {
      PlacedAnchor? current = nearestAnchor;
      while (current != null) {
        path.add(current);
        if (current.id == destination.id) break;
        if (current.previousAnchorId != null) {
          final prev = _placedAnchors
              .where((a) => a.id == current!.previousAnchorId)
              .toList();
          if (prev.isEmpty) break;
          current = prev.first;
          if (current.id == path.last.id) break;
        } else {
          break;
        }
      }
    }

    if (path.isEmpty) return [destination];
    return path;
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

        final destPos = _destinationAnchor!.transform.getTranslation();
        final destDist = (destPos - devicePos).length;

        if (waypointDist < 1.5 &&
            _currentWaypointIndex < _navigationPath.length - 1) {
          setState(() {
            _currentWaypointIndex++;
            _currentWaypoint = _navigationPath[_currentWaypointIndex];
          });
          print('✅ Waypoint reached, advancing to ${_currentWaypoint!.name}');
        }

        final isFinal = _currentWaypoint!.id == _destinationAnchor!.id;
        final reached = isFinal && destDist < 2.0;
        setState(() {
          _waypointDistance = waypointDist;
          _destinationDistance = destDist;
          if (reached && !_hasReachedDestination) {
            _hasReachedDestination = true;
            _showHint('🎯 You have reached ${_destinationAnchor!.name}!');
          } else if (!reached && _hasReachedDestination) {
            _hasReachedDestination = false;
          }
        });
      }
    } else {
      // No destination: maintain nearest anchor
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
    if (total <= 1) return 'Head towards ${waypoint.name}';
    if (index == 0) return 'Head towards ${waypoint.name}';
    if (index == total - 1) return 'Final destination: ${waypoint.name}';
    return 'Continue to ${waypoint.name}';
  }

  void _debugNavigationSystem() {
    print('📍 NAVIGATION DEBUG:');
    print('   Device Position: ${_getCurrentDevicePosition()}');
    print('   Current Waypoint: ${_currentWaypoint?.name}');
    print(
      '   Navigation Path: ${_navigationPath.map((a) => a.name).join(" → ")}',
    );
    print(
      '   Waypoint Progress: ${_currentWaypointIndex + 1}/${_navigationPath.length}',
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
      print('❌ Error loading map: $e');
      setState(() {
        _isLoadingMap = false;
      });
      _showError('Error loading map: $e');
    }
  }

  Future<void> _loadAnchorsFromMap(String mapId) async {
    try {
      print('🔵 Loading anchors from map: $mapId');

      for (final anchor in _placedAnchors) {
        try {
          await _anchorManager?.removeAnchor(anchor.arAnchor);
        } catch (e) {
          print('Error removing anchor: $e');
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

      print('🔵 Found ${anchorsSnapshot.docs.length} anchors in map');

      for (final anchorDoc in anchorsSnapshot.docs) {
        final anchorData = anchorDoc.data();
        final cloudAnchorId = anchorData['cloudAnchorId'] as String?;

        if (cloudAnchorId == null || cloudAnchorId.isEmpty) {
          continue;
        }

        print('🔵 Resolving cloud anchor: $cloudAnchorId');

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
          print('❌ Error downloading anchor $cloudAnchorId: $e');
        }
      }

      // Maintain sequence ordering for path building
      _placedAnchors.sort(
        (a, b) => a.sequenceNumber.compareTo(b.sequenceNumber),
      );
      print('✅ Initiated download for ${_placedAnchors.length} cloud anchors');
    } catch (e) {
      print('❌ Error loading anchors from map: $e');
      _showError('Error loading anchors: $e');
    }
  }

  Future<void> _addMarkerVisual(
    ARAnchor anchor,
    Matrix4 transform,
    String anchorId,
  ) async {
    try {
      print('🔵 Loading 3D model at resolved anchor origin');
      print('   Anchor ID: $anchorId');
      print(
        '   Object Manager: ${_objectManager != null ? "initialized" : "null"}',
      );

      // Create node with your downloaded 3D model
      if (_objectManager != null) {
        try {
          // Ensure model is copied to documents folder
          if (_modelPath == null || !File(_modelPath!).existsSync()) {
            print('⚠️ 3D model not available, copying from assets...');
            await _copyModelAssetToDocuments();
          }

          if (_modelPath == null || !File(_modelPath!).existsSync()) {
            print(
              '❌ 3D model file not available - cannot create visual marker',
            );
            print('🔄 Trying fallback built-in sphere...');
            // Fallback to built-in sphere if model loading fails
            await _addBuiltInSphere(Vector3.zero(), anchorId);
            return;
          }

          print('   Creating ARNode with local file: $_modelPath');

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

          print('   ARNode created: ${modelNode.name}');
          print('   Attempting to add node to scene...');

          // Add node to AR scene attached to the anchor
          final didAdd = await _objectManager!.addNode(
            modelNode,
            // Attach to the resolved anchor to respect real-world pose
            planeAnchor: anchor is ARPlaneAnchor ? anchor : null,
          );

          print('   addNode returned: $didAdd (type: ${didAdd.runtimeType})');

          if (didAdd == true) {
            _visualNodes[anchorId] = modelNode;
            print('✅ 3D model attached to anchor successfully');
            print('   Visual nodes count: ${_visualNodes.length}');
          } else {
            print(
              '⚠️ Failed to add visual node to scene - addNode returned false',
            );
            print('🔄 Trying fallback built-in sphere...');
            // Fallback to built-in sphere if model loading fails
            await _addBuiltInSphere(Vector3.zero(), anchorId);
          }
        } catch (e, stackTrace) {
          print('❌ Failed to load 3D model: $e');
          print('   Error type: ${e.runtimeType}');
          print('🔍 Error details: ${e.toString()}');
          print('   Stack trace: $stackTrace');
          print('🔄 Trying fallback built-in sphere...');
          // Fallback to built-in sphere if model loading fails
          await _addBuiltInSphere(Vector3.zero(), anchorId);
        }
      } else {
        print('❌ Object manager is null - cannot add visual marker');
      }
    } catch (e, stackTrace) {
      print('❌ Error in _addMarkerVisual: $e');
      print('   Stack trace: $stackTrace');
    }
  }

  // Fallback method using ARCore built-in shapes
  Future<void> _addBuiltInSphere(Vector3 position, String anchorId) async {
    try {
      // Note: ar_flutter_plugin doesn't have built-in ArCoreSphere
      // We'll create a simple fallback using a basic shape if available
      // For now, just log that fallback was attempted
      print('⚠️ Fallback sphere creation attempted for anchor: $anchorId');
      print('   Position: $position');
      // If you have a fallback sphere model, you could load it here
    } catch (e) {
      print('❌ Both model and fallback failed: $e');
    }
  }

  // Clear all visual markers
  Future<void> _clearAllVisualMarkers() async {
    try {
      for (final entry in _visualNodes.entries) {
        try {
          await _objectManager?.removeNode(entry.value);
        } catch (e) {
          print('⚠️ Error removing node ${entry.key}: $e');
        }
      }
      _visualNodes.clear();
      print('✅ All visual markers cleared');
    } catch (e) {
      print('❌ Error clearing markers: $e');
    }
  }

  // Remove specific marker
  Future<void> _removeVisualMarker(String markerId) async {
    try {
      if (_visualNodes.containsKey(markerId)) {
        await _objectManager?.removeNode(_visualNodes[markerId]!);
        _visualNodes.remove(markerId);
        print('✅ Marker removed: $markerId');
      }
    } catch (e) {
      print('❌ Error removing marker: $e');
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

      print('🔄 Marker scale updated to: $scale');
    } catch (e) {
      print('❌ Error updating marker: $e');
    }
  }

  ARAnchor _onAnchorDownloaded(Map<String, dynamic> serializedAnchor) {
    print('🔵 Anchor downloaded callback');
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
        print('❌ Resolved anchor not found for cloud ID: $cloudAnchorId');
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
      print('✅ Cloud anchor resolved and visual added: ${updated.name}');
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
    print('📊 Resolution Progress: $resolved/$total anchors resolved');
    if (resolved < total) {
      _showHint('Resolving anchors... $resolved/$total complete');
    } else if (total > 0) {
      _showHint('✅ All anchors resolved! Navigation ready.');
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
