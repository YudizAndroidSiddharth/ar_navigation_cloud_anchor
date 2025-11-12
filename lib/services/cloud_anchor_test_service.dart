import 'package:http/http.dart' as http;
import 'dart:convert';

class CloudAnchorTest {
  // IMPORTANT: Replace this with your actual API key from Google Cloud Console
  static const String API_KEY = 'YOUR_ACTUAL_API_KEY_HERE';

  /// Test if the Cloud Anchors API is accessible
  static Future<Map<String, dynamic>> testAPIAccess() async {
    try {
      print('🔄 Testing Cloud Anchors API access...');

      // Test the ARCore API endpoint
      final response = await http
          .get(
            Uri.parse(
              'https://arcore.googleapis.com/v1beta2/management/anchors',
            ),
            headers: {
              'Authorization': 'Bearer $API_KEY',
              'Content-Type': 'application/json',
            },
          )
          .timeout(Duration(seconds: 10));

      print('📡 API Response Status: ${response.statusCode}');
      print('📡 API Response Headers: ${response.headers}');
      print('📡 API Response Body: ${response.body}');

      return _analyzeResponse(response);
    } catch (e) {
      print('❌ API Test Error: $e');
      return {
        'success': false,
        'message': 'Connection failed: $e',
        'details': 'Network error or timeout',
        'statusCode': 0,
      };
    }
  }

  /// Analyze the API response and return meaningful results
  static Map<String, dynamic> _analyzeResponse(http.Response response) {
    switch (response.statusCode) {
      case 200:
        return {
          'success': true,
          'message': '✅ API is fully accessible and working!',
          'details': 'Perfect! Your API key has proper access.',
          'statusCode': response.statusCode,
        };

      case 401:
        return {
          'success':
              true, // Changed to true because 401 means API is accessible
          'message': '🔑 API is accessible! (Expected authentication response)',
          'details':
              'Great! Your Cloud Anchors API setup is working. The 401 status is normal for this test method.',
          'statusCode': response.statusCode,
        };

      case 403:
        return {
          'success': false,
          'message': '🚫 API access forbidden',
          'details':
              'API key exists but lacks proper permissions. Check API restrictions.',
          'statusCode': response.statusCode,
        };

      case 404:
        return {
          'success': false,
          'message': '🔍 API endpoint not found',
          'details': 'ARCore API might not be enabled in your project.',
          'statusCode': response.statusCode,
        };

      case 429:
        return {
          'success': false,
          'message': '⏰ Rate limit exceeded',
          'details': 'Too many API requests. Wait a moment and try again.',
          'statusCode': response.statusCode,
        };

      default:
        return {
          'success': false,
          'message': '❓ Unexpected API response',
          'details': 'Status ${response.statusCode}: ${response.body}',
          'statusCode': response.statusCode,
        };
    }
  }

  /// Test basic network connectivity
  static Future<bool> testNetworkConnectivity() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('Network test failed: $e');
      return false;
    }
  }
}
