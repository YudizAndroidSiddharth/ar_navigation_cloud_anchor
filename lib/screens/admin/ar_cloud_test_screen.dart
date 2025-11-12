import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart'
    as hit_test;
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:ar_navigation_cloud_anchor/services/venue_service.dart';

/// Minimal AR screen to place one anchor and upload it to Google Cloud Anchors
class ARCloudTestScreen extends StatefulWidget {
  final Venue? venue;
  final AnchorType? anchorType;

  const ARCloudTestScreen({
    super.key,
    this.venue,
    this.anchorType,
  });

  @override
  State<ARCloudTestScreen> createState() => _ARCloudTestScreenState();
}

class _ARCloudTestScreenState extends State<ARCloudTestScreen> {
  ARSessionManager? _sessionManager;
  ARAnchorManager? _anchorManager;
  ARObjectManager? _objectManager;

  ARPlaneAnchor? _placedAnchor; // The single test anchor (plane anchor)
  String? _cloudAnchorId;
  bool _isUploading = false;
  bool _readyToUpload = false;
  bool _isSavingToFirebase = false;
  Timer? _uploadTimeoutTimer;
  final VenueService _venueService = VenueService();

  @override
  void dispose() {
    // Clean up AR resources
    _uploadTimeoutTimer?.cancel();
    try {
      _sessionManager?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Anchor Test')),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_cloudAnchorId != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud Anchor ID: $_cloudAnchorId',
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (_isSavingToFirebase)
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Row(
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
                                  'Saving to Firebase...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _placedAnchor == null && !_isUploading
                            ? () => _showHint(
                                'Tap directly on a yellow plane marker to place an anchor',
                              )
                            : null,
                        child: Text(
                          _placedAnchor == null
                              ? 'Tap plane to place'
                              : 'Anchor placed ✓',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _placedAnchor != null &&
                                _readyToUpload &&
                                !_isUploading
                            ? _uploadAnchor
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _placedAnchor != null && _readyToUpload
                              ? Colors.green
                              : Colors.grey,
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Upload Anchor'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Debug info
                if (_placedAnchor != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Debug: Anchor placed=${_placedAnchor != null}, Ready=${_readyToUpload}, Uploading=${_isUploading}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _placedAnchor == null
                      ? 'Instructions: Move device to detect planes (yellow markers), then TAP directly on a yellow plane to place an anchor.'
                      : _readyToUpload
                      ? '✅ Anchor placed! Press "Upload Anchor" to host to cloud.'
                      : _isUploading
                      ? 'Uploading anchor... (this may take 10-30 seconds)\nPlease wait and keep the device steady.'
                      : 'Anchor placed. Waiting for upload readiness...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 8),

                // API Key warning
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    print('🔵 AR View created - initializing managers...');
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;
    // locationManager not used in this simple test screen

    // Initialize session
    print('🔵 Initializing session...');
    _sessionManager!.onInitialize(
      showFeaturePoints: true,
      showPlanes: true,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
    );

    // Initialize object manager
    print('🔵 Initializing object manager...');
    _objectManager!.onInitialize();

    // Initialize cloud anchor mode (REQUIRED for cloud anchors)
    print('🔵 Initializing Google Cloud Anchor mode...');
    _anchorManager!.initGoogleCloudAnchorMode();
    print('✅ Cloud anchor mode initialized');

    // Set up callbacks
    print('🔵 Setting up callbacks...');
    _sessionManager!.onPlaneOrPointTap = _onPlaneOrPointTap;
    _anchorManager!.onAnchorUploaded = _onAnchorUploaded;
    _anchorManager!.onAnchorDownloaded = _onAnchorDownloaded;
    print('✅ Callbacks set up');
  }

  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hitResults) async {
    print('🔵 Tap detected! Hit results count: ${hitResults.length}');

    if (_placedAnchor != null) {
      _showHint('Anchor already placed. Upload or reset.');
      return;
    }

    if (hitResults.isEmpty) {
      _showError('No hit. Please tap on a detected plane');
      print('⚠️ No hit results');
      return;
    }

    print('🔵 Processing ${hitResults.length} hit results');
    for (int i = 0; i < hitResults.length; i++) {
      final hit = hitResults[i];
      print('  Hit $i: type=${hit.type}, distance=${hit.distance}');
    }

    final hit = hitResults.first;
    print('🔵 First hit type: ${hit.type}');
    print('🔵 Expected plane type: ${hit_test.ARHitTestResultType.plane}');

    if (hit.type != hit_test.ARHitTestResultType.plane) {
      _showError('Please tap on a detected plane (got type: ${hit.type})');
      print('⚠️ Wrong hit type: ${hit.type}');
      return;
    }

    try {
      print('🔵 Creating plane anchor...');
      // Create a plane anchor at the tapped location
      final newAnchor = ARPlaneAnchor(transformation: hit.worldTransform);
      print('🔵 Anchor created, adding to manager...');

      final didAdd = await _anchorManager!.addAnchor(newAnchor);
      print('🔵 addAnchor result: $didAdd');

      if (didAdd ?? false) {
        print('✅ Anchor placed successfully!');
        setState(() {
          _placedAnchor = newAnchor;
          _readyToUpload = true;
        });
        print(
          '🔵 State updated: _placedAnchor=${_placedAnchor != null}, _readyToUpload=$_readyToUpload',
        );
        _showHint('✅ Anchor placed! You can upload now.');
      } else {
        print('❌ Failed to add anchor');
        _showError('Failed to place anchor (addAnchor returned false)');
      }
    } catch (e, stackTrace) {
      print('❌ Place anchor error: $e');
      print('Stack trace: $stackTrace');
      _showError('Place anchor error: $e');
    }
  }

  void _uploadAnchor() {
    print('🔵 Upload anchor called');
    if (_placedAnchor == null || !_readyToUpload) {
      print(
        '⚠️ Cannot upload: _placedAnchor=${_placedAnchor != null}, _readyToUpload=$_readyToUpload',
      );
      return;
    }

    print('🔵 Starting upload...');
    setState(() {
      _isUploading = true;
      _readyToUpload = false;
    });

    // Set up timeout in case callback doesn't fire (e.g., API key error)
    // ARCore uploads typically take 10-30 seconds, so we use 30 seconds
    _uploadTimeoutTimer?.cancel();
    _uploadTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_isUploading) {
        print('⏱️ Upload timeout - no callback received after 30 seconds');
        setState(() {
          _isUploading = false;
          _readyToUpload = true;
        });
        _showError(
          'Upload timeout after 30 seconds.\n\n'
          'This usually means:\n'
          '• API key is invalid or not enabled for ARCore\n'
          '• ARCore API is not enabled in Google Cloud Console\n'
          '• No internet connection\n'
          '• Slow network connection\n\n'
          'Check Android logs (logcat) for specific errors.',
        );
      }
    });

    // Upload anchor - the callback will be called when done
    try {
      _anchorManager!.uploadAnchor(_placedAnchor!);
      print('✅ uploadAnchor called successfully');
    } catch (e, stackTrace) {
      print('❌ Error calling uploadAnchor: $e');
      print('Stack trace: $stackTrace');
      _uploadTimeoutTimer?.cancel();
      setState(() {
        _isUploading = false;
        _readyToUpload = true;
      });
      _showError('Error starting upload: $e');
    }
  }

  void _onAnchorUploaded(ARAnchor anchor) async {
    print('🔵 onAnchorUploaded callback called');
    print('🔵 Anchor type: ${anchor.runtimeType}');

    // Cancel timeout since callback was received
    _uploadTimeoutTimer?.cancel();

    // This callback is called when upload succeeds
    // Cast to ARPlaneAnchor to access cloudanchorid property
    if (anchor is ARPlaneAnchor) {
      print('🔵 Anchor is ARPlaneAnchor');
      print('🔵 Cloud anchor ID: ${anchor.cloudanchorid}');

      setState(() {
        _isUploading = false;
        _cloudAnchorId = anchor.cloudanchorid;
        _readyToUpload = false;
      });

      if (anchor.cloudanchorid != null && anchor.cloudanchorid!.isNotEmpty) {
        print('✅ Upload successful! Cloud Anchor ID: ${anchor.cloudanchorid}');
        
        // Save to Firebase if venue is provided
        if (widget.venue != null) {
          await _saveAnchorToFirebase(anchor.cloudanchorid!);
        } else {
          _showHint(
            '✅ Upload successful! Cloud Anchor ID: ${anchor.cloudanchorid}\n'
            'Note: Not saving to Firebase (no venue provided)',
          );
        }
      } else {
        print('⚠️ Upload completed but no cloud anchor ID');
        _showError('Upload completed but no cloud anchor ID received');
      }
    } else {
      print('⚠️ Anchor is not ARPlaneAnchor, it is: ${anchor.runtimeType}');
      setState(() {
        _isUploading = false;
        _readyToUpload = false;
      });
      _showError('Upload completed but anchor type is not ARPlaneAnchor');
    }
  }

  Future<void> _saveAnchorToFirebase(String cloudAnchorId) async {
    if (widget.venue == null) {
      print('⚠️ Cannot save anchor: no venue provided');
      return;
    }

    setState(() {
      _isSavingToFirebase = true;
    });

    try {
      print('💾 Saving anchor to Firebase...');
      print('   Venue ID: ${widget.venue!.id}');
      print('   Cloud Anchor ID: $cloudAnchorId');
      print('   Anchor Type: ${widget.anchorType ?? AnchorType.waypoint}');

      // Extract position from the placed anchor's transformation matrix
      final transformation = _placedAnchor?.transformation;
      double x = 0.0, y = 0.0, z = 0.0;
      if (transformation != null) {
        // Extract translation from transformation matrix
        x = transformation.getTranslation().x;
        y = transformation.getTranslation().y;
        z = transformation.getTranslation().z;
      }

      // Create CloudAnchorPoint
      final anchorPoint = CloudAnchorPoint(
        id: 'anchor_${DateTime.now().millisecondsSinceEpoch}',
        cloudAnchorId: cloudAnchorId,
        name: _getAnchorTypeLabel(widget.anchorType ?? AnchorType.waypoint),
        description: 'AR anchor placed at ${widget.venue!.name}',
        position: AnchorPosition(x: x, y: y, z: z),
        type: widget.anchorType ?? AnchorType.waypoint,
        status: AnchorStatus.active,
        quality: 1.0, // Default quality, can be improved later
      );

      // Save to Firebase using VenueService
      final success = await _venueService.addAnchorToVenue(
        widget.venue!.id,
        anchorPoint,
      );

      if (success) {
        print('✅ Anchor saved to Firebase successfully!');
        _showHint(
          '✅ Upload & Save Complete!\n'
          'Cloud Anchor ID: $cloudAnchorId\n'
          'Saved to venue: ${widget.venue!.name}',
        );
        
        // Return success result to previous screen
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        print('❌ Failed to save anchor to Firebase');
        _showError(
          '✅ Cloud upload successful, but failed to save to Firebase.\n'
          'Cloud Anchor ID: $cloudAnchorId',
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error saving anchor to Firebase: $e');
      print('Stack trace: $stackTrace');
      _showError(
        '✅ Cloud upload successful, but error saving to Firebase: $e\n'
        'Cloud Anchor ID: $cloudAnchorId',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingToFirebase = false;
        });
      }
    }
  }

  String _getAnchorTypeLabel(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return 'Entrance';
      case AnchorType.intersection:
        return 'Intersection';
      case AnchorType.destination:
        return 'Destination';
      case AnchorType.waypoint:
        return 'Waypoint';
      case AnchorType.emergency:
        return 'Emergency Exit';
    }
  }

  ARAnchor _onAnchorDownloaded(Map<String, dynamic> serializedAnchor) {
    // Not used in this simple test screen, but required by API
    // Return a placeholder anchor - in real usage, you'd deserialize it
    print('Anchor downloaded: ${serializedAnchor['cloudanchorid']}');
    // Return the existing anchor if available, otherwise create a placeholder
    return _placedAnchor ?? ARPlaneAnchor(transformation: Matrix4.identity());
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
