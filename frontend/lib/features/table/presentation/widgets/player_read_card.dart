import 'package:flutter/material.dart';
import 'package:monte/core/domain/ai/player_read.dart';

/// A compact, translucent HUD card summarising the two-way read on a player:
/// [seatRead.mine] is how the hero reads them, [seatRead.ofMe] (when present) is
/// how that player — through their own style bias — reads the hero. Rendered
/// once, centered on the felt, so it never clips against a table edge. Fonts are
/// kept at ~10pt so all six stats stay readable.
class PlayerReadCard extends StatelessWidget {
  const PlayerReadCard({
    super.key,
    required this.name,
    required this.seatRead,
    this.humanName = 'You',
    this.selfView = false,
  });

  final String name;
  final SeatRead seatRead;

  /// The hero's display name, used as the subject of the "read of you" section.
  final String humanName;

  /// The human hovering their own seat: show just the headline stats, without a
  /// "read" sentence or tags (you don't need a prose read of yourself).
  final bool selfView;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gold.withValues(alpha: 0.45)),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live reads first, above the historical ones. They are the volatile
          // half — true this orbit and false the next — and they are also the
          // half that changes what you do on *this* hand, so they lead and they
          // are coloured by urgency rather than sharing the gold of a settled
          // tag.
          if (!selfView && seatRead.live.isNotEmpty) ...[
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                for (final l in seatRead.live) _liveChip(l),
              ],
            ),
            const SizedBox(height: 7),
          ],
          if (selfView)
            _section(gold, 'YOUR STATS', name, seatRead.mine,
                subjectIsName: true, statsOnly: true)
          else
            _section(gold, 'YOUR READ', name, seatRead.mine,
                subjectIsName: true),
          if (!selfView && seatRead.ofMe != null) ...[
            const SizedBox(height: 10),
            Divider(color: gold.withValues(alpha: 0.25), height: 1),
            const SizedBox(height: 10),
            _section(gold, "$name'S READ OF ${humanName.toUpperCase()}",
                humanName, seatRead.ofMe!,
                subjectIsName: humanName.toLowerCase() != 'you'),
          ],
        ],
      ),
    );
  }

  /// Colour by urgency: a tilting opponent is an opportunity, a heater is
  /// information, and somebody who has you read is a warning.
  static Widget _liveChip(LiveRead l) {
    final color = switch (l.kind) {
      LiveReadKind.tilt => const Color(0xFFFF7043),
      LiveReadKind.rush => const Color(0xFF42A5F5),
      LiveReadKind.danger => const Color(0xFFEF5350),
      LiveReadKind.stack => const Color(0xFFB0BEC5),
    };
    final icon = switch (l.kind) {
      LiveReadKind.tilt => Icons.local_fire_department,
      LiveReadKind.rush => Icons.trending_up,
      LiveReadKind.danger => Icons.visibility,
      LiveReadKind.stack => Icons.layers,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(l.label.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _section(Color gold, String heading, String subject, PlayerRead read,
      {required bool subjectIsName, bool statsOnly = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading,
            style: TextStyle(
                color: gold.withValues(alpha: 0.8),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 4),
        if (!statsOnly)
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 10, height: 1.3),
            children: [
              TextSpan(
                  text: subject,
                  style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
              TextSpan(
                text: read.thin
                    ? ' — ${read.description}'
                    : ' ${subjectIsName ? "is" : "are"} ${read.description}.',
                style: TextStyle(
                    color: Colors.white,
                    fontStyle:
                        read.thin ? FontStyle.italic : FontStyle.normal),
              ),
            ],
          ),
        ),
        if (!statsOnly && read.tags.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            runSpacing: 3,
            children: [
              for (final t in read.tags)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(t, style: TextStyle(color: gold, fontSize: 9)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (label, value) in read.stats)
              Column(
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  Text(label,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 8)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('${read.handsSeen} hands',
            style: const TextStyle(color: Colors.white38, fontSize: 8)),
      ],
    );
  }
}
