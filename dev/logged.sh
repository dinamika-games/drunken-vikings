#!/usr/bin/env bash
# Run a fuzzing test (the end-to-end test, the balance bot) with all its
# output in a log file, and delete the log only when the test passes; when it
# fails, keep the log, so that nobody has to run the test again only to see
# what went wrong, and show its end.
#
#   dev/logged.sh <log file> <command> [<arguments>...]
#
# E.g.:
#
#   dev/logged.sh playthrough.log $GODOT --headless --fixed-fps 60 --path . \
#       --script tests/godot/end2end/test_playthrough.gd -- --no-camera
#
# The exit code is the test's.

set -u

if [ $# -lt 2 ]; then
    echo "Usage: $0 <log file> <command> [<arguments>...]" >&2
    exit 2
fi

log=$1
shift

if [ -e "$log" ] && [ ! -f "$log" ]; then
    echo "The log $log is not a regular file; refusing to write it." >&2
    exit 2
fi
mkdir -p "$(dirname "$log")"

"$@" > "$log" 2>&1
status=$?

if [ "$status" -eq 0 ]; then
    rm -f -- "$log"
    echo "PASSED (the log is deleted): $*"
else
    tail -n 40 "$log"
    echo
    echo "FAILED with the exit code $status; the whole output is kept in: $log"
fi
exit "$status"
