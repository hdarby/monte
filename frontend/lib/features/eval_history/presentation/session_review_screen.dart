import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays a markdown session review.
///
/// Renders the small subset of markdown the report actually uses — headings,
/// tables, bold, italics, bullets — rather than pulling in a dependency for it.
/// The raw text stays one tap away via Copy, so it can go anywhere.
class SessionReviewScreen extends StatefulWidget {
  const SessionReviewScreen({
    super.key,
    required this.markdown,
    this.pending,
  });

  final String markdown;

  /// A slower section still being computed — the duplicate run, which replays
  /// every hand a few hundred times and cannot hold up the first page.
  ///
  /// Started before this screen opens, so it is already running while the first
  /// page is being read. It resolves to markdown appended at the end.
  final Future<String>? pending;

  @override
  State<SessionReviewScreen> createState() => _SessionReviewScreenState();
}

class _SessionReviewScreenState extends State<SessionReviewScreen> {
  String? _extra;
  Object? _failed;

  @override
  void initState() {
    super.initState();
    widget.pending?.then(
      (md) { if (mounted) setState(() => _extra = md); },
      onError: (Object e) { if (mounted) setState(() => _failed = e); },
    );
  }

  String get markdown => widget.markdown + (_extra ?? '');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Session review'),
          actions: [
            IconButton(
              tooltip: 'Copy markdown',
              icon: const Icon(Icons.copy_all),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: markdown));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Review copied')),
                  );
                }
              },
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ...renderMarkdown(context, markdown),
                if (widget.pending != null && _extra == null && _failed == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Replaying your hands with someone else in your '
                            'seat…'),
                      ],
                    ),
                  ),
                if (_failed != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('The duplicate run failed; the rest of the '
                        'review is unaffected.'),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// Turns the report's markdown into widgets. Public so it can be tested and
/// reused in a dialog.
List<Widget> renderMarkdown(BuildContext context, String md) {
  final text = Theme.of(context).textTheme;
  final out = <Widget>[];
  final rows = <List<String>>[];

  void flushTable() {
    if (rows.isEmpty) return;
    // A leading row of dashes is markdown's header separator, not data.
    final body = [
      for (final r in rows)
        if (!r.every((c) => c.replaceAll(RegExp(r'[-: ]'), '').isEmpty)) r
    ];
    if (body.isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var i = 0; i < body.length; i++)
              TableRow(
                decoration: i == 0
                    ? BoxDecoration(color: Colors.white.withValues(alpha: 0.06))
                    : null,
                children: [
                  for (final cell in body[i])
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: _inline(cell, i == 0
                          ? text.bodyMedium!.copyWith(fontWeight: FontWeight.w700)
                          : text.bodyMedium!),
                    ),
                ],
              ),
          ],
        ),
      ));
    }
    rows.clear();
  }

  for (final raw in md.split('\n')) {
    final line = raw.trimRight();
    if (line.startsWith('|')) {
      rows.add(line
          .substring(1, line.endsWith('|') ? line.length - 1 : line.length)
          .split('|')
          .map((c) => c.trim())
          .toList());
      continue;
    }
    flushTable();
    if (line.trim().isEmpty) {
      out.add(const SizedBox(height: 8));
    } else if (line.startsWith('### ')) {
      out.add(_h(context, line.substring(4), text.titleSmall));
    } else if (line.startsWith('## ')) {
      out.add(_h(context, line.substring(3), text.titleMedium));
    } else if (line.startsWith('# ')) {
      out.add(_h(context, line.substring(2), text.headlineSmall));
    } else if (line.startsWith('- ')) {
      out.add(Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: _inline(line.substring(2), text.bodyMedium!)),
          ],
        ),
      ));
    } else {
      out.add(_inline(line, text.bodyMedium!));
    }
  }
  flushTable();
  return out;
}

Widget _h(BuildContext context, String s, TextStyle? style) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(s, style: style?.copyWith(fontWeight: FontWeight.w700)),
    );

/// Handles `**bold**`, `_italic_` and `` `code` `` within a line.
Widget _inline(String s, TextStyle base) {
  final spans = <TextSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|_(.+?)_|`(.+?)`');
  var i = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
          text: m.group(2),
          style: TextStyle(
              fontStyle: FontStyle.italic,
              color: base.color?.withValues(alpha: 0.75))));
    } else {
      spans.add(TextSpan(
          text: m.group(3),
          style: const TextStyle(fontFamily: 'monospace', letterSpacing: 0.4)));
    }
    i = m.end;
  }
  if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
  return SelectableText.rich(TextSpan(style: base, children: spans));
}
