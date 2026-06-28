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
  test/show_behavior_test.dart
  test/table/bust_out_test.dart
  test/table/seat_personalities_test.dart
  test/table/button_rotation_test.dart
  test/analytics/personality_effect_test.dart
  test/ai/player_profile_test.dart
  test/ai/profile_calibration_test.dart
  test/ai/opponent_model_test.dart
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
