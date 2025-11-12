import 'dart:async';
import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
// TODO: Migrate to ar_flutter_plugin after cloud anchor testing is complete
// Temporary: Using test screen for cloud anchor functionality
import 'ar_cloud_test_screen.dart';

class ARCameraScreen extends StatefulWidget {
  final Venue venue;
  final AnchorType anchorType;

  ARCameraScreen({required this.venue, this.anchorType = AnchorType.waypoint});

  @override
  _ARCameraScreenState createState() => _ARCameraScreenState();
}

class _ARCameraScreenState extends State<ARCameraScreen> {
  // TODO: Migrate to ar_flutter_plugin after cloud anchor testing is complete
  // Temporarily using test screen - old arcore_flutter_plugin removed
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera permission is required for AR features'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // TEMPORARY: Redirecting to test screen until migration is complete
    // The old arcore_flutter_plugin has been replaced with ar_flutter_plugin
    return Scaffold(
      appBar: AppBar(
        title: Text('Place AR Anchor'),
        backgroundColor: Colors.blue[600],
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showInstructions,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 64, color: Colors.blue[600]),
              SizedBox(height: 24),
              Text(
                'AR Screen Migration',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'The AR camera screen is being migrated to use ar_flutter_plugin '
                'for cloud anchor support.\n\n'
                'For now, please use the Cloud Anchor Test screen to test cloud anchor uploads.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ARCloudTestScreen(
                        venue: widget.venue,
                        anchorType: widget.anchorType,
                      ),
                    ),
                  ).then((result) {
                    // Return result to previous screen if anchor was saved
                    if (result == true && mounted) {
                      Navigator.pop(context, true);
                    }
                  });
                },
                icon: Icon(Icons.science),
                label: Text('Open Cloud Anchor Test Screen'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              SizedBox(height: 16),
              TextButton(
                onPressed: _showInstructions,
                child: Text('View Instructions'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Keep helper methods for future migration
  void _showInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('AR Screen Migration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The AR camera screen is currently being migrated to use ar_flutter_plugin '
                'for cloud anchor support.\n\n'
                'For testing cloud anchor uploads, please use the Cloud Anchor Test screen.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Next Steps:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Use Cloud Anchor Test screen to verify uploads'),
                    Text(
                      '2. Once confirmed working, this screen will be updated',
                    ),
                    Text('3. Full functionality will be restored'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ARCloudTestScreen(
                    venue: widget.venue,
                    anchorType: widget.anchorType,
                  ),
                ),
              ).then((result) {
                // Return result to previous screen if anchor was saved
                if (result == true && mounted) {
                  Navigator.pop(context, true);
                }
              });
            },
            child: Text('Open Test Screen'),
          ),
        ],
      ),
    );
  }

  // Helper methods for anchor types (kept for future migration)
  // ignore: unused_element
  Color _getAnchorTypeColor() {
    return _getColorForAnchorType(widget.anchorType);
  }

  // ignore: unused_element
  String _getAnchorTypeLabel() {
    return _getLabelForAnchorType(widget.anchorType);
  }

  Color _getColorForAnchorType(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return Colors.orange;
      case AnchorType.intersection:
        return Colors.blue;
      case AnchorType.destination:
        return Colors.green;
      case AnchorType.waypoint:
        return Colors.purple;
      case AnchorType.emergency:
        return Colors.red;
    }
  }

  String _getLabelForAnchorType(AnchorType type) {
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

  // ignore: unused_element
  String _getDescriptionForAnchorType(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return 'Main access points';
      case AnchorType.intersection:
        return 'Corridor junctions';
      case AnchorType.destination:
        return 'Important locations';
      case AnchorType.waypoint:
        return 'Navigation guidance';
      case AnchorType.emergency:
        return 'Emergency exits';
    }
  }

  // ignore: unused_element
  IconData _getIconForAnchorType(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return Icons.login;
      case AnchorType.intersection:
        return Icons.call_split;
      case AnchorType.destination:
        return Icons.place;
      case AnchorType.waypoint:
        return Icons.navigation;
      case AnchorType.emergency:
        return Icons.emergency;
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    super.dispose();
  }
}
