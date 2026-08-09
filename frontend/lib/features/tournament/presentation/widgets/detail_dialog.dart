import 'package:flutter/material.dart';

/// A small titled dialog wrapper for the HUD detail popups.
class DetailDialog extends StatelessWidget {
  const DetailDialog({super.key, required this.title, required this.body});
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: body,
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

/// A stack of aligned label/value rows, the shared body layout of the HUD
/// detail popups.
class DetailRows extends StatelessWidget {
  const DetailRows(this.items, {super.key});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (k, v) in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k, style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 16),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
    ],
  );
}
