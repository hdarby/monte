#!/usr/bin/env bash
# Run Monte from a terminal, no IDE involved.
#
#   ./run.sh            release build on macOS — the one to play with
#   ./run.sh debug      hot reload + breakpoints
#   ./run.sh chrome     release build in the browser
#   ./run.sh test       the full suite
#   ./run.sh player     the interactive player creator
#
# Everything runs from frontend/, which is where the Flutter app actually is.
set -euo pipefail
cd "$(dirname "$0")/frontend"

case "${1:-release}" in
  release) exec flutter run -d macos --release ;;
  debug)   exec flutter run -d macos ;;
  chrome)  exec flutter run -d chrome --release ;;
  test)    exec flutter test ;;
  player)  exec dart run tool/create_player.dart ;;
  *) echo "usage: ./run.sh [release|debug|chrome|test|player]" >&2; exit 2 ;;
esac
