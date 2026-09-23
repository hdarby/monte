import 'package:flutter/material.dart';

/// A small, unobtrusive round button for the tournament's own chrome.
class ChromeButton extends StatelessWidget {
  const ChromeButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: onPressed == null ? Colors.white24 : Colors.white70,
          ),
        ),
      ),
    ),
  );
}
