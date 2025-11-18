import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SnackBarUtil {
  static void showSuccessSnackbar(String message) {
    Get.rawSnackbar(
      message: message,
      backgroundColor: Colors.green,
      snackPosition: SnackPosition.BOTTOM,
      duration: Duration(seconds: 3),
      borderRadius: 10,
      margin: EdgeInsets.all(10),
    );
  }

  static void showPrimarySnackbar(String message) {
    Get.rawSnackbar(
      message: message,
      backgroundColor: Color(0xFF00D3D6),
      snackPosition: SnackPosition.BOTTOM,
      duration: Duration(seconds: 3),
      borderRadius: 10,
      margin: EdgeInsets.all(10),
    );
  }

  static void showErrorSnackbar(String message) {
    Get.rawSnackbar(
      message: message,
      backgroundColor: Colors.red,
      snackPosition: SnackPosition.BOTTOM,
      duration: Duration(seconds: 3),
      borderRadius: 10,
      margin: EdgeInsets.all(10),
    );
  }
}
