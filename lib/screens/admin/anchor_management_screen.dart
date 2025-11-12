import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AnchorManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.anchor, size: 64, color: Colors.blue[600]),
          SizedBox(height: 16),
          Text(
            'Anchor Management',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('Coming soon!'),
          ElevatedButton(
            onPressed: testAPIAccess,
            child: Text("Test Api Access"),
          ),
        ],
      ),
    );
  }

  Future<bool> testAPIAccess() async {
    const String API_KEY = 'AIzaSyA7IqsewBc6y369JvvVoGA_T9zaJ5YxAqs';
    try {
      // Test the ARCore API endpoint
      final response = await http.get(
        Uri.parse('https://arcore.googleapis.com/v1beta2/management/anchors'),
        headers: {
          'Authorization': 'Bearer $API_KEY',
          'Content-Type': 'application/json',
        },
      );

      print('API Response Status: ${response.statusCode}');
      print('API Response Body: ${response.body}');

      // 200 = success, 401 = unauthorized but API is accessible
      // 403 = forbidden but API exists
      return response.statusCode == 200 ||
          response.statusCode == 401 ||
          response.statusCode == 403;
    } catch (e) {
      print('API Test Error: $e');
      return false;
    }
  }
}
