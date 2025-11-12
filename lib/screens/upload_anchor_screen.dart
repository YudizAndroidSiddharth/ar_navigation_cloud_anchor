import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Upload Anchor Screen
/// - Tap to place marker (visual indicator)
/// - Click "Upload Anchor" button to upload selected marker
class UploadAnchorScreen extends StatefulWidget {
  const UploadAnchorScreen({super.key});

  @override
  State<UploadAnchorScreen> createState() => _UploadAnchorScreenState();
}

class _UploadAnchorScreenState extends State<UploadAnchorScreen> {
  ARSessionManager? _sessionManager;
  ARAnchorManager? _anchorManager;
  ARObjectManager? _objectManager;

  // Marker management (placed but not uploaded)
  final List<PlacedMarker> _placedMarkers = [];
  final List<PlacedMarker> _uploadedMarkers =
      []; // Successfully uploaded markers
  PlacedMarker? _selectedMarker;
  int _markerCounter = 1;
  bool _isUploading = false;
  Timer? _uploadTimeoutTimer;
  String? _currentMapId; // Current map being built
  final Map<String, ARNode> _visualNodes =
      {}; // Track visual nodes for management
  String? _modelPath; // Path to 3D model GLB file in app documents folder
  Vector3 _devicePosition = Vector3.zero();

  // Firebase
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime? _lastPlaneTapAt; // for double-tap gating on AR hit-tests

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
        log('--------✅ 3D model already exists at: $_modelPath');
        return;
      }

      log('--------🔵 Copying 3D model from assets to documents folder...');

      // Load asset from Flutter assets
      final ByteData data = await rootBundle.load('assets/model/porche.glb');
      final bytes = data.buffer.asUint8List();

      // Write to app documents folder
      await modelFile.writeAsBytes(bytes);
      _modelPath = modelFile.path;

      log('--------✅ 3D model copied to: $_modelPath');
    } catch (e) {
      log('--------⚠️ Error copying 3D model: $e');
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
    _uploadTimeoutTimer?.cancel();
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
          // AR View - use AR hit-tests instead of manual double-tap guessing
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),

          // Top status bar
          Positioned(top: 40, left: 16, right: 16, child: _renderStatusBar()),

          // Instructions
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: _renderInstructions(),
          ),

          // Bottom controls
          Positioned(left: 16, right: 16, bottom: 24, child: _renderControls()),

          // Save Map button (if anchors uploaded)
          if (_uploadedMarkers.isNotEmpty)
            Positioned(
              top: 180,
              left: 16,
              right: 16,
              child: _renderSaveMapButton(),
            ),
        ],
      ),
    );
  }

  Widget _renderStatusBar() {
    final devicePos = _getCurrentDevicePosition();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Markers: ${_placedMarkers.length}',
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
          const SizedBox(height: 6),
          Text(
            'Device: (${devicePos.x.toStringAsFixed(1)}, ${devicePos.y.toStringAsFixed(1)}, ${devicePos.z.toStringAsFixed(1)})',
            style: const TextStyle(color: Colors.yellow, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _renderInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.info, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Instructions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Double-tap anywhere to place 3D marker\n'
            '2. The Porsche model shows anchor location\n'
            '3. Select marker & click "Upload Anchor"',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _renderSaveMapButton() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.save, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_uploadedMarkers.length} anchor(s) uploaded',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          ElevatedButton(
            onPressed: _saveMap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.green,
            ),
            child: const Text('Save Map'),
          ),
        ],
      ),
    );
  }

  Widget _renderControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Upload button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedMarker != null && !_isUploading
                ? _uploadSelectedMarker
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: Colors.grey,
            ),
            child: Text(
              _selectedMarker != null
                  ? 'Upload Anchor: ${_selectedMarker!.name}'
                  : 'Select a marker to upload',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Clear and Back buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _clearMarkers,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
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
    log('--------🔵 AR View created - initializing...');
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    // Initialize session
    _sessionManager!.onInitialize(
      showFeaturePoints: false, // Hide yellow feature point cubes
      showPlanes: true, // Visualize detected planes
      customPlaneTexturePath: null,
      showWorldOrigin: false,
    );

    // Initialize object manager for 3D rendering
    _objectManager!.onInitialize();

    // Initialize cloud anchor mode
    _anchorManager!.initGoogleCloudAnchorMode();

    // Set up callbacks
    _anchorManager!.onAnchorUploaded = _onAnchorUploaded;
    // Real-world placement using AR hit tests
    _sessionManager!.onPlaneOrPointTap = _onPlaneOrPointTap;
    // Optional: select markers by tapping the model
    _objectManager!.onNodeTap = _onNodeTap;

    // Initialize simple device position model (near origin)
    _devicePosition = Vector3.zero();
    log('--------✅ AR initialized (simple device position model)');
  }

  // Removed obsolete double-tap placement in favor of AR hit-tests

  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hits) async {
    try {
      if (hits.isEmpty) {
        _showError('No surface found');
        return;
      }
      // Double-tap gating: require two taps within 300ms
      final now = DateTime.now();
      if (_lastPlaneTapAt == null ||
          now.difference(_lastPlaneTapAt!).inMilliseconds > 300) {
        _lastPlaneTapAt = now;
        _showHint('Double-tap to place marker');
        return;
      }
      _lastPlaneTapAt = null; // reset after a successful double tap
      // Prefer planes over feature points
      hits.sort((a, b) => a.type.index.compareTo(b.type.index));
      final hit = hits.first;

      // Use real-world pose from AR (handle different plugin typings)
      final dynamic wt = hit.worldTransform;
      Matrix4 world;
      if (wt is Matrix4) {
        world = wt;
      } else if (wt is List) {
        world = Matrix4.fromList(wt.cast<double>());
      } else {
        world = Matrix4.identity();
      }

      // Log delta from previous anchor for validation
      if (_placedMarkers.isNotEmpty) {
        final last = _placedMarkers.last.transform.getTranslation();
        final cur = world.getTranslation();
        final delta = (cur - last).length;
        log('--------📏 Δ between anchors: ${delta.toStringAsFixed(2)}m');
      }

      await _placeMarker(world);
    } catch (e) {
      log('--------❌ Error in _onPlaneOrPointTap: $e');
    }
  }

  void _onNodeTap(List<String> nodeNames) {
    if (nodeNames.isEmpty) return;
    final id = nodeNames.first;
    final found = _placedMarkers.where((m) => m.id == id).toList();
    if (found.isNotEmpty) {
      setState(() {
        _selectedMarker = found.first;
      });
      _showHint('Selected: ${_selectedMarker!.name}');
    }
  }

  Future<void> _placeMarker(Matrix4 transform) async {
    try {
      log('--------🔵 Placing marker $_markerCounter...');

      // Debug current device and marker distances
      final devicePos = _getCurrentDevicePosition();
      final markerPos = transform.getTranslation();
      final distanceFromDevice = (markerPos - devicePos).length;
      log('--------📍 Device position: ${devicePos.toString()}');
      log('--------📍 Marker position: ${markerPos.toString()}');
      log(
        '--------📏 Distance from device: ${distanceFromDevice.toStringAsFixed(2)}m',
      );

      // Optional: Placement sanity check (no repositioning)
      if (distanceFromDevice < 0.5 || distanceFromDevice > 5.0) {
        log(
          '--------⚠️ Placement distance looks unusual: ${distanceFromDevice.toStringAsFixed(2)}m',
        );
      }

      // Create anchor for marker
      final anchor = ARPlaneAnchor(transformation: transform);
      final didAdd = await _anchorManager!.addAnchor(anchor);

      if (didAdd ?? false) {
        // Link to previous marker if exists
        final previous = _placedMarkers.isNotEmpty ? _placedMarkers.last : null;

        // Create marker record
        final marker = PlacedMarker(
          id: 'marker_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Marker $_markerCounter',
          arAnchor: anchor,
          transform: transform,
          previousMarkerId: previous?.id,
          sequenceNumber: _markerCounter - 1,
        );

        // Update previous marker's next link in memory
        if (previous != null) {
          previous.nextMarkerId = marker.id;
        }

        setState(() {
          _placedMarkers.add(marker);
          _selectedMarker = marker; // Auto-select newly placed marker
          _markerCounter++;
        });

        // Add visual marker
        _addMarkerVisual(anchor, transform, marker);

        _showHint('✅ Marker placed: ${marker.name}');
      } else {
        _showError('Failed to place marker');
      }
    } catch (e) {
      log('--------❌ Error placing marker: $e');
      _showError('Error placing marker: $e');
    }
  }

  Future<void> _addMarkerVisual(
    ARAnchor anchor,
    Matrix4 transform,
    PlacedMarker marker,
  ) async {
    try {
      final position = transform.getTranslation();

      log(
        '--------🔵 Loading 3D model at position: x=${position.x}, y=${position.y}, z=${position.z}',
      );
      log('--------   Marker ID: ${marker.id}, Name: ${marker.name}');
      log(
        '--------   Object Manager: ${_objectManager != null ? "initialized" : "null"}',
      );
      // Coordinate system debug
      log('--------🔧 ANCHOR DEBUG:');
      log('--------   Anchor type: ${anchor.runtimeType}');
      try {
        // Not all anchors expose transformation; guard with try
        // ignore: unnecessary_cast
        final dyn = anchor as dynamic;
        log('--------   Anchor transformation: ${dyn.transformation}');
      } catch (_) {
        log('--------   Anchor transformation: <unavailable>');
      }
      log('--------   Transform position (from matrix): $position');
      log('--------   Marker label: ${marker.name}');

      // Create node with your downloaded 3D model
      if (_objectManager != null) {
        try {
          // Ensure model is copied to documents folder
          if (_modelPath == null || !File(_modelPath!).existsSync()) {
            log('--------⚠️ 3D model not available, copying from assets...');
            await _copyModelAssetToDocuments();
          }

          if (_modelPath == null || !File(_modelPath!).existsSync()) {
            log(
              '--------❌ 3D model file not available - cannot create visual marker',
            );
            log('--------🔄 Trying fallback built-in sphere...');
            // Fallback to built-in sphere if model loading fails
            await _addBuiltInSphere(position, marker);
            return;
          }

          log('--------   Creating ARNode with local file: $_modelPath');

          // Create ARNode with 3D model from app documents folder
          // Note: NodeType.fileSystemAppFolderGLB expects just the filename, not full path
          final modelNode = ARNode(
            type: NodeType
                .fileSystemAppFolderGLB, // Load from app documents folder
            uri:
                'porche.glb', // Just the filename - plugin prepends app folder path
            name: marker.id, // Important for tracking and removal
            // Position relative to the anchor origin
            position: Vector3.zero(),
            scale: Vector3(0.2, 0.2, 0.2), // Adjust size (20cm)
          );

          log('--------   ARNode created: ${modelNode.name}');
          log('--------   Attempting to add node to scene...');

          // Add node to AR scene attached to the anchor
          // Attach node to its corresponding anchor so it appears at the anchor's world position
          final didAdd = await _objectManager!.addNode(
            modelNode,
            planeAnchor: anchor is ARPlaneAnchor ? anchor : null,
          );

          log(
            '--------   addNode returned: $didAdd (type: ${didAdd.runtimeType})',
          );

          if (didAdd == true) {
            // Store node reference for later management
            _visualNodes[marker.id] = modelNode;
            log('--------✅ 3D model loaded successfully: ${marker.name}');
            log('--------   Visual nodes count: ${_visualNodes.length}');
          } else {
            log(
              '--------⚠️ Failed to add visual node to scene - addNode returned false',
            );
            log('--------🔄 Trying fallback built-in sphere...');
            // Fallback to built-in sphere if model loading fails
            await _addBuiltInSphere(position, marker);
          }
        } catch (e, stackTrace) {
          log('--------❌ Failed to load 3D model: $e');
          log('--------   Error type: ${e.runtimeType}');
          log('--------🔍 Error details: ${e.toString()}');
          log('--------   Stack trace: $stackTrace');
          log('--------🔄 Trying fallback built-in sphere...');
          // Fallback to built-in sphere if model loading fails
          await _addBuiltInSphere(position, marker);
        }
      } else {
        log(
          '--------❌ Object manager not initialized - cannot add visual marker',
        );
      }
    } catch (e, stackTrace) {
      log('--------❌ Error in _addMarkerVisual: $e');
      log('--------   Stack trace: $stackTrace');
    }
  }

  // Fallback method using ARCore built-in shapes
  Future<void> _addBuiltInSphere(Vector3 position, PlacedMarker marker) async {
    try {
      // Note: ar_flutter_plugin doesn't have built-in ArCoreSphere
      // We'll create a simple fallback using a basic shape if available
      // For now, just log that fallback was attempted
      log(
        '--------⚠️ Fallback sphere creation attempted for marker: ${marker.name}',
      );
      log('--------   Position: $position');
      // If you have a fallback sphere model, you could load it here
    } catch (e) {
      log('--------❌ Both model and fallback failed: $e');
    }
  }

  // Clear all visual markers
  Future<void> _clearAllVisualMarkers() async {
    try {
      for (final entry in _visualNodes.entries) {
        try {
          await _objectManager?.removeNode(entry.value);
        } catch (e) {
          log('--------⚠️ Error removing node ${entry.key}: $e');
        }
      }
      _visualNodes.clear();
      log('--------✅ All visual markers cleared');
    } catch (e) {
      log('--------❌ Error clearing markers: $e');
    }
  }

  // Removed unused _removeVisualMarker function (no references)

  // Removed unused _updateMarkerScale function (was not referenced)

  Future<void> _uploadSelectedMarker() async {
    if (_selectedMarker == null) {
      _showError('No marker selected');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    // Set timeout
    _uploadTimeoutTimer?.cancel();
    _uploadTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isUploading) {
        setState(() {
          _isUploading = false;
        });
        _showError('Upload timeout');
      }
    });

    // Upload anchor
    try {
      _anchorManager!.uploadAnchor(_selectedMarker!.arAnchor);
    } catch (e) {
      log('--------❌ Error uploading anchor: $e');
      _uploadTimeoutTimer?.cancel();
      setState(() {
        _isUploading = false;
      });
      _showError('Error uploading anchor: $e');
    }
  }

  // Simple device position for indoor anchor placement
  Vector3 _getCurrentDevicePosition() {
    // If no markers, assume origin
    if (_placedMarkers.isEmpty) {
      return Vector3.zero();
    }
    // If one marker, keep device near origin but biased toward marker's Z
    if (_placedMarkers.length == 1) {
      final markerPos = _placedMarkers.first.transform.getTranslation();
      _devicePosition = Vector3(
        markerPos.x * 0.1,
        markerPos.y * 0.1,
        markerPos.z + 1.5,
      );
      return _devicePosition;
    }
    // Multiple markers: stay stable; optionally bias toward average Z a little
    final avg =
        _placedMarkers
            .map((m) => m.transform.getTranslation())
            .reduce((a, b) => a + b) /
        _placedMarkers.length.toDouble();
    _devicePosition = Vector3(avg.x * 0.1, avg.y * 0.1, avg.z + 1.5);
    return _devicePosition;
  }

  void _onAnchorUploaded(ARAnchor anchor) async {
    log('--------🔵 Anchor uploaded callback');
    _uploadTimeoutTimer?.cancel();

    if (anchor is ARPlaneAnchor && anchor.cloudanchorid != null) {
      // Find matching marker
      final marker = _placedMarkers.firstWhere(
        (m) => m.arAnchor == anchor,
        orElse: () => _placedMarkers.first,
      );

      // Save to Firebase
      await _saveAnchorToFirebase(marker, anchor.cloudanchorid!);

      setState(() {
        _isUploading = false;
        _selectedMarker = null;
        // Move marker to uploaded list
        _placedMarkers.remove(marker);
        _uploadedMarkers.add(marker);
      });

      _showHint('✅ ${marker.name} uploaded successfully!');
    }
  }

  Future<void> _saveAnchorToFirebase(
    PlacedMarker marker,
    String cloudAnchorId,
  ) async {
    try {
      // Initialize map if not exists
      if (_currentMapId == null) {
        _currentMapId = 'map_${DateTime.now().millisecondsSinceEpoch}';
        final mapData = {
          'id': _currentMapId,
          'name': 'Map ${DateTime.now().toString().substring(0, 16)}',
          'createdAt': DateTime.now().toIso8601String(),
          'anchorCount': 0,
        };
        await _firestore.collection('maps').doc(_currentMapId).set(mapData);
      }

      // Save anchor to map
      final anchorData = {
        'id': marker.id,
        'name': marker.name,
        'cloudAnchorId': cloudAnchorId,
        'position': {
          'x': marker.transform.getTranslation().x,
          'y': marker.transform.getTranslation().y,
          'z': marker.transform.getTranslation().z,
        },
        // Connectivity metadata
        'previousAnchorId': marker.previousMarkerId,
        'nextAnchorId': marker.nextMarkerId,
        'sequenceNumber': marker.sequenceNumber,
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _firestore
          .collection('maps')
          .doc(_currentMapId)
          .collection('anchors')
          .doc(marker.id)
          .set(anchorData);

      // Try to update the previous anchor's nextAnchorId if it already exists in Firestore
      if (marker.previousMarkerId != null) {
        final prevDocRef = _firestore
            .collection('maps')
            .doc(_currentMapId)
            .collection('anchors')
            .doc(marker.previousMarkerId);
        try {
          await prevDocRef.update({'nextAnchorId': marker.id});
        } catch (e) {
          // It's possible previous anchor hasn't been uploaded yet; ignore
          log(
            '--------ℹ️ Could not update previous anchor nextAnchorId (may not exist yet): $e',
          );
        }
      }

      // Update map anchor count
      await _firestore.collection('maps').doc(_currentMapId).update({
        'anchorCount': _uploadedMarkers.length + 1,
      });

      log('--------✅ Anchor saved to Firebase map: $_currentMapId');
    } catch (e) {
      log('--------❌ Error saving anchor to Firebase: $e');
    }
  }

  Future<void> _saveMap() async {
    if (_uploadedMarkers.isEmpty) {
      _showError('No uploaded anchors to save');
      return;
    }

    if (_currentMapId == null) {
      _showError('No map to save');
      return;
    }

    try {
      // Update map with final anchor count
      await _firestore.collection('maps').doc(_currentMapId).update({
        'anchorCount': _uploadedMarkers.length,
      });

      _showHint(
        '✅ Map saved successfully with ${_uploadedMarkers.length} anchors!',
      );

      // Optionally clear uploaded markers or keep them
      // setState(() {
      //   _uploadedMarkers.clear();
      //   _currentMapId = null;
      // });
    } catch (e) {
      log('--------❌ Error saving map: $e');
      _showError('Error saving map: $e');
    }
  }

  Future<void> _clearMarkers() async {
    if (_placedMarkers.isEmpty) {
      _showHint('No markers to clear');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Markers?'),
        content: Text('This will remove all ${_placedMarkers.length} markers.'),
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
      for (final marker in _placedMarkers) {
        try {
          await _anchorManager?.removeAnchor(marker.arAnchor);
        } catch (e) {
          log('--------Error removing anchor: $e');
        }
      }

      // Clear all visual markers
      await _clearAllVisualMarkers();

      setState(() {
        _placedMarkers.clear();
        _selectedMarker = null;
        _markerCounter = 1;
        _isUploading = false;
      });

      _uploadTimeoutTimer?.cancel();
      _showHint('All markers cleared');
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

/// Represents a placed marker (not yet uploaded)
class PlacedMarker {
  final String id;
  final String name;
  final ARAnchor arAnchor;
  final Matrix4 transform;
  final Color color; // Color for visual marker
  String? previousMarkerId; // Link to previous in placement order
  String? nextMarkerId; // Link to next in placement order
  int sequenceNumber; // Placement sequence number

  PlacedMarker({
    required this.id,
    required this.name,
    required this.arAnchor,
    required this.transform,
    this.color = Colors.red, // Default to red
    this.previousMarkerId,
    this.nextMarkerId,
    this.sequenceNumber = 0,
  });
}
