import 'package:flutter/material.dart';

import 'package:monte/core/theme/app_theme.dart';

/// The app's entry point: three big cards — Cash Games, Tournaments, Options —
/// each an icon over its label. Tapping one hands off to [onCashGames],
/// [onTournaments], or [onOptions].
class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.onCashGames,
    required this.onTournaments,
    required this.onOptions,
  });

  final VoidCallback onCashGames;
  final VoidCallback onTournaments;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Monte',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how you want to play',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: 32),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 640;
                      final cards = [
                        _LandingOptionCard(
                          label: 'Cash Games',
                          image: 'assets/cash_games.jpeg',
                          onTap: onCashGames,
                          key: const Key('landing_cash_games'),
                        ),
                        _LandingOptionCard(
                          label: 'Tournaments',
                          image: 'assets/tournaments.jpeg',
                          onTap: onTournaments,
                          key: const Key('landing_tournaments'),
                        ),
                        _LandingOptionCard(
                          label: 'Options',
                          icon: const Icon(
                            Icons.settings,
                            size: 72,
                            color: Colors.white,
                          ),
                          onTap: onOptions,
                          key: const Key('landing_options'),
                        ),
                      ];
                      if (isWide) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final c in cards)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: c,
                                ),
                              ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          for (final c in cards)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: c,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingOptionCard extends StatelessWidget {
  const _LandingOptionCard({
    super.key,
    required this.label,
    this.icon,
    this.image,
    required this.onTap,
  }) : assert(
         icon != null || image != null,
         'a card needs either an icon or a photo',
       );

  final String label;

  /// A drawn icon (used for Options, which has no representative photo).
  final Widget? icon;

  /// An asset path for a full-bleed photo filling the top of the card,
  /// instead of a small centered [icon].
  final String? image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.felt,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.feltEdge, width: 2),
          ),
          child: image != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 11,
                      child: Image.asset(image!, fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: _label(context),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon!,
                      const SizedBox(height: 20),
                      _label(context),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    ),
  );
}
