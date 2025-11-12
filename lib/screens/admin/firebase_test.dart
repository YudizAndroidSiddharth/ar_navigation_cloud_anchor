import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class FirebaseTestScreen extends StatefulWidget {
  @override
  _FirebaseTestScreenState createState() => _FirebaseTestScreenState();
}

class _FirebaseTestScreenState extends State<FirebaseTestScreen> {
  bool _isLoading = false;
  String _testResult = '';
  Color _resultColor = Colors.grey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Firebase Connection Test'),
        backgroundColor: Colors.blue[600],
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.storage, size: 48, color: Colors.blue[600]),
                    SizedBox(height: 16),
                    Text(
                      'Firebase Firestore Test',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This will test if Firebase is properly configured and can read/write data.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isLoading ? null : _testFirebaseConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                padding: EdgeInsets.all(16),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Testing Firebase...'),
                      ],
                    )
                  : Text(
                      'Test Firebase Connection',
                      style: TextStyle(fontSize: 16),
                    ),
            ),

            SizedBox(height: 20),

            if (_testResult.isNotEmpty) ...[
              Card(
                color: _resultColor.withOpacity(0.1),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _resultColor == Colors.green
                                ? Icons.check_circle
                                : Icons.error,
                            color: _resultColor,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Test Result',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _resultColor,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        _testResult,
                        style: TextStyle(
                          fontSize: 14,
                          color: _resultColor == Colors.green
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            Spacer(),

            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Firebase Setup Checklist:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '□ Firebase project created\n'
                    '□ Firestore database enabled\n'
                    '□ google-services.json downloaded\n'
                    '□ Android build.gradle files updated\n'
                    '□ SHA-1 fingerprint added',
                    style: TextStyle(fontSize: 12, color: Colors.orange[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testFirebaseConnection() async {
    setState(() {
      _isLoading = true;
      _testResult = '';
    });

    try {
      // Test 1: Check if Firebase is initialized
      final app = Firebase.app();
      print('✅ Firebase app initialized: ${app.name}');

      // Test 2: Try to write a test document
      final firestore = FirebaseFirestore.instance;
      final testData = {
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'Firebase connection test successful!',
      };

      await firestore
          .collection('connection_test')
          .doc('test_doc')
          .set(testData);

      print('✅ Test document written successfully');

      // Test 3: Try to read the test document
      final docSnapshot = await firestore
          .collection('connection_test')
          .doc('test_doc')
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        print('✅ Test document read successfully: $data');

        setState(() {
          _testResult =
              '✅ Firebase connection successful!\n\n'
              'Firebase is properly configured and working:\n'
              '• App initialized correctly\n'
              '• Firestore write operation successful\n'
              '• Firestore read operation successful\n'
              '• Ready for venue data storage!';
          _resultColor = Colors.green;
        });
      } else {
        throw Exception('Test document not found after writing');
      }
    } catch (e) {
      print('❌ Firebase test failed: $e');
      setState(() {
        _testResult =
            '❌ Firebase connection failed!\n\n'
            'Error: $e\n\n'
            'Check:\n'
            '• google-services.json file is in android/app/\n'
            '• Firebase project is properly configured\n'
            '• Internet connection is available\n'
            '• Firestore database is enabled';
        _resultColor = Colors.red;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
