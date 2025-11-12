import 'package:ar_navigation_cloud_anchor/screens/admin/create_venue_screen.dart';
import 'package:ar_navigation_cloud_anchor/screens/admin/firebase_test.dart';
import 'package:ar_navigation_cloud_anchor/screens/admin/venue_screen.dart';
import 'package:ar_navigation_cloud_anchor/services/cloud_anchor_test_service.dart';
import 'package:flutter/material.dart';
import 'anchor_management_screen.dart';
import 'analytics_screen.dart';

class AdminModuleScreen extends StatefulWidget {
  @override
  _AdminModuleScreenState createState() => _AdminModuleScreenState();
}

class _AdminModuleScreenState extends State<AdminModuleScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    VenueListScreen(),
    AnchorManagementScreen(),
    AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Module'),
        backgroundColor: Colors.orange[600],
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.orange[600],
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.business), label: 'Venues'),
          BottomNavigationBarItem(icon: Icon(Icons.anchor), label: 'Anchors'),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 || _selectedIndex == 1
          ? FloatingActionButton(
              onPressed: () {
                if (_selectedIndex == 0) {
                  _createNewVenue();
                } else {
                  _createNewAnchor();
                }
              },
              backgroundColor: Colors.orange[600],
              child: Icon(Icons.add),
            )
          : null,
    );
  }

  void _createNewVenue() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VenueCreationScreen()),
    );
  }

  void _createNewAnchor() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Anchor creation will be available after venue selection',
        ),
        backgroundColor: Colors.orange[600],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.settings, color: Colors.orange[600]),
            SizedBox(width: 8),
            Text('Admin Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cloud Anchors API Test Section
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_sync, color: Colors.blue[600], size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Cloud Anchors API',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Test your API connection',
                    style: TextStyle(color: Colors.blue[600], fontSize: 14),
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _testCloudConnection,
                    icon: Icon(Icons.play_circle_outline),
                    label: Text('Test Cloud API'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 36),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // Firebase Test Section - NEW
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storage, color: Colors.green[600], size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Firebase Database',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Test database connection',
                    style: TextStyle(color: Colors.green[600], fontSize: 14),
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _testFirebaseConnection,
                    icon: Icon(Icons.play_circle_outline),
                    label: Text('Test Firebase'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 36),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // System Status
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.wifi, color: Colors.green[600]),
              title: Text('Network'),
              subtitle: Text('Connected'),
              trailing: Icon(Icons.check_circle, color: Colors.green[600]),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.camera, color: Colors.green[600]),
              title: Text('Camera Permission'),
              subtitle: Text('Required for AR features'),
              trailing: Icon(Icons.check_circle, color: Colors.green[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  // Existing Cloud API test method
  Future<void> _testCloudConnection() async {
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('Testing Cloud Anchors API...'),
          ],
        ),
        duration: Duration(seconds: 10),
        backgroundColor: Colors.blue[600],
      ),
    );

    try {
      final networkOk = await CloudAnchorTest.testNetworkConnectivity();
      if (!networkOk) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ No internet connection'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final result = await CloudAnchorTest.testAPIAccess();
      ScaffoldMessenger.of(context).clearSnackBars();

      final success = result['success'] ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✅ Cloud API is working!' : '❌ Cloud API failed',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Test failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // NEW Firebase test method
  void _testFirebaseConnection() {
    Navigator.pop(context); // Close settings dialog

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FirebaseTestScreen()),
    );
  }
}
