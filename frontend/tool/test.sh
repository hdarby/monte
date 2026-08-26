#!/usr/bin/env bash
#
# Run Monte's Flutter tests, optionally split into "new" (recent feature work)
# and "old" (the established suite).
#
#   tool/test.sh           # everything (same as `all`)
#   tool/test.sh new       # only the recent-feature tests below
#   tool/test.sh old       # everything except the new tests
#   tool/test.sh all       # everything
#   tool/test.sh list      # print which files each group resolves to (no run)
#
# As features stabilise, move their test files out of NEW_TESTS so they join the
# "old" suite. Anything not listed here is "old" by definition.

set -euo pipefail
cd "$(dirname "$0")/.."

# Tests covering recently added features (bots, personalities, analytics sim, …).
NEW_TESTS=(
  # Poker judgement: stack depth / SPR, opening ranges, hand selection.
  test/ai/stack_context_test.dart
  test/ai/open_ranges_test.dart
  test/ai/open_sizing_test.dart
  test/ai/three_bet_sizing_test.dart
  test/ai/preflop_playability_test.dart
  test/ai/hand_range_test.dart
  test/ai/amateur_position_test.dart
  test/ai/stakes_pressure_test.dart
  # Character: signature moves and tilt.
  test/ai/signature_moves_test.dart
  test/ai/tilt_test.dart
  test/ai/profile_data_test.dart
  # Calibration gates — slow, and the ones most likely to move.
  test/ai/postflop_discipline_test.dart
  test/ai/deep_stack_discipline_test.dart
  # Tournament: saving, which hand the recap picks, and ICM/survival-pressure
  # discipline (short-stack push/fold, bubble/ladder folding, size damping,
  # the garbage-call trim).
  test/features/tournament/tournament_save_test.dart
  test/features/tournament/saved_tournaments_dialog_test.dart
  test/features/tournament/feature_hand_choice_test.dart
  test/features/tournament/icm_bots_test.dart
  test/features/tournament/tournament_survival_sizing_test.dart
  # Payouts: real pay jumps.
  test/features/tournament/domain/payout_structure_test.dart
  # Recap: cross-level leaderboard storylines, play-style breakdown.
  test/features/tournament/chronicle_test.dart
  test/features/tournament/chronicle_recorder_test.dart
  # Session review: this event's own finish, duplicate-run progress.
  test/eval_history/session_markdown_test.dart
  # Career: the standalone screen and its aggregation.
  test/features/tournament/career_screen_test.dart
  test/features/tournament/career_test.dart
  # Table UI.
  test/table/chip_legend_test.dart
  test/reads/clear_reads_test.dart
)

# Resolve the "old" set: every *_test.dart not in NEW_TESTS.
old_tests() {
  while IFS= read -r f; do
    local is_new=false
    for n in "${NEW_TESTS[@]}"; do
      [ "$f" = "$n" ] && { is_new=true; break; }
    done
    $is_new || printf '%s\n' "$f"
  done < <(find test -name '*_test.dart' | sort)
}

mode="${1:-all}"
case "$mode" in
  new)
    exec flutter test "${NEW_TESTS[@]}"
    ;;
  old)
    # shellcheck disable=SC2046
    exec flutter test $(old_tests)
    ;;
  all)
    exec flutter test
    ;;
  list)
    echo "NEW:"
    printf '  %s\n' "${NEW_TESTS[@]}"
    echo "OLD:"
    old_tests | sed 's/^/  /'
    ;;
  *)
    echo "usage: tool/test.sh [new|old|all|list]" >&2
    exit 2
    ;;
esac
