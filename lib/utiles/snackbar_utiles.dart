import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SnackBarUtil {
  /// Clear all snackbars from the scaffold messenger
  static void clearSnackBars(BuildContext context) {
    try {
      // Check if context is still valid before accessing ScaffoldMessenger
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (e) {
      // Silently ignore errors when context is deactivated
      debugPrint('⚠️ Error clearing snackbars: $e');
    }
  }

  /// Show a snackbar with custom message, color, and optional action
  static void showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    try {
      // Check if context is still valid before accessing ScaffoldMessenger
      if (!context.mounted) {
        debugPrint('⚠️ Cannot show snackbar: context is not mounted');
        return;
      }

      // Clear any existing snackbars first
      clearSnackBars(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.notoSansDevanagari()),
          backgroundColor: backgroundColor,
          action: action,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      // Silently ignore errors when context is deactivated
      debugPrint('⚠️ Error showing snackbar: $e');
    }
  }

  /// Show success snackbar
  static void showSuccessSnackbar(BuildContext context, String message) {
    showSnackBar(context, message, const Color(0xFF3C8C4E));
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
