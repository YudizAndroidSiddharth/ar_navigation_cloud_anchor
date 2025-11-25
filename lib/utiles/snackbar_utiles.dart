import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SnackBarUtil {
  /// Clear all snackbars from the scaffold messenger
  static void clearSnackBars(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  /// Show a snackbar with custom message, color, and optional action
  static void showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Clear any existing snackbars first
    clearSnackBars(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.notoSansDevanagari()),
        backgroundColor: backgroundColor,
        action: action,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Show success snackbar
  static void showSuccessSnackbar(BuildContext context, String message) {
    showSnackBar(context, message, Colors.green);
  }

  /// Show error snackbar
  static void showErrorSnackbar(BuildContext context, String message) {
    showSnackBar(context, message, Colors.red);
  }

  /// Show warning snackbar
  static void showWarningSnackbar(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) {
    showSnackBar(context, message, Colors.orange, action: action);
  }

  /// Show info snackbar with green theme
  static void showInfoSnackbar(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) {
    showSnackBar(context, message, const Color(0xFF3C8C4E), action: action);
  }
}
