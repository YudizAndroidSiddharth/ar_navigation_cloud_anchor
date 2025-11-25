import 'package:flutter/material.dart';

///usage example:
/// ```dart
///CustomButton(
//   isLoading: _isLoading,
//   onPressed: _handlePress,
//   text: 'Press Me', // Text has priority
// )
/// Or with custom child:
///CustomButton(
//   isLoading: _isLoading,
//   onPressed: _handlePress,
//   child: const Text('Custom Widget'),
// )
class CustomButton extends StatefulWidget {
  final String? text;
  final Widget? child;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double? width;
  final Color buttonColor;
  final Color textColor;
  final double borderOpacity;

  const CustomButton({
    super.key,
    this.text,
    this.child,
    this.onPressed,
    this.isLoading = false,
    this.width,
    this.buttonColor = Colors.green,
    this.textColor = Colors.white,
    this.borderOpacity = 0,
  }) : assert(
         text != null || child != null,
         'Either text or child must be provided',
       );

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed == null || widget.isLoading
          ? null
          : (_) => setState(() => _isPressed = true),
      onTapUp: widget.onPressed == null || widget.isLoading
          ? null
          : (_) => setState(() => _isPressed = false),
      onTapCancel: widget.onPressed == null || widget.isLoading
          ? null
          : () => setState(() => _isPressed = false),
      onTap: widget.onPressed == null || widget.isLoading
          ? null
          : widget.onPressed,
      child: Container(
        width: widget.width ?? 198,
        height: 56,
        // constraints: const BoxConstraints(minWidth: 144),
        decoration: BoxDecoration(
          color: widget.buttonColor,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: widget.buttonColor.withOpacity(widget.borderOpacity),
              offset: const Offset(0, 0),
              blurRadius: 0,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: widget.isLoading
              ? CircularProgressIndicator()
              : widget.text != null
              ? Text(
                  widget.text!.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Dosis',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    height: 24 / 18,
                    letterSpacing: -0.18,
                    color: widget.textColor,
                  ),
                  textAlign: TextAlign.center,
                )
              : widget.child!,
        ),
      ),
    );
  }
}
