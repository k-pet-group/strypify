#! /bin/bash
# Tests how strypify-headless.sh handles `--version`, using stand-ins for xvfb-run and Strypify that simulate
# the ways the real thing misbehaves. In particular a Strypify that prints the version and then hangs while
# exiting must still give us the version, rather than the caller's timeout killing the script with nothing
# printed (which showed up as "strypify-headless.sh --version produced no output (stderr: )").
#
# Usage: bash test-headless-version.sh   (from anywhere; needs bash, and setsid or perl)

HEADLESS="$(cd "$(dirname "$0")/.." && pwd)/strypify-headless.sh"
FAKE_DIR=$(mktemp -d)
trap 'rm -rf "$FAKE_DIR"; pkill -f "$FAKE_DIR" 2>/dev/null' EXIT

# xvfb-run stand-in: drop its own options and run the command.
cat > "$FAKE_DIR/xvfb-run" <<'FAKE'
#!/bin/bash
while [[ "$1" == --* ]]; do shift; done
exec "$@"
FAKE
# Strypify stand-in, which behaves as FAKE_MODE says:
cat > "$FAKE_DIR/Strypify" <<'FAKE'
#!/bin/bash
case "$FAKE_MODE" in
  ok)          echo "9.9.9" ;;
  hang-after)  echo "9.9.9"; sleep 60 ;;                  # prints the version, then hangs while exiting
  silent-hang) sleep 60 ;;                                # never prints anything
  fail)        echo "something went wrong" >&2; exit 3 ;; # prints nothing, but says why
esac
FAKE
chmod +x "$FAKE_DIR/xvfb-run" "$FAKE_DIR/Strypify"
# setsid isn't available everywhere (e.g. macOS), but perl can do the same:
if ! command -v setsid >/dev/null 2>&1; then
  printf '#!/bin/bash\nexec perl -e '"'"'use POSIX; setsid(); exec @ARGV'"'"' "$@"\n' > "$FAKE_DIR/setsid"
  chmod +x "$FAKE_DIR/setsid"
fi
export PATH="$FAKE_DIR:$PATH"

FAILED=0
# run_case NAME MODE MAX_SECONDS EXPECT_STDOUT EXPECT_EXIT_ZERO(yes/no) STDERR_PATTERN
run_case() {
  local name=$1 mode=$2 max=$3 want_out=$4 want_ok=$5 err_pattern=$6
  local start=$SECONDS out err rc elapsed problems=""
  out=$(FAKE_MODE=$mode STRYPIFY_VERSION_TIMEOUT=3 bash "$HEADLESS" --version 2>"$FAKE_DIR/stderr")
  rc=$?
  err=$(cat "$FAKE_DIR/stderr")
  elapsed=$((SECONDS - start))
  [ "$out" = "$want_out" ] || problems="$problems stdout was [$out], wanted [$want_out];"
  if [ "$want_ok" = yes ]; then [ $rc -eq 0 ] || problems="$problems exit code was $rc, wanted 0;"
  else [ $rc -ne 0 ] || problems="$problems exit code was 0, wanted non-zero;"; fi
  [ "$elapsed" -le "$max" ] || problems="$problems took ${elapsed}s, wanted at most ${max}s;"
  if [ -n "$err_pattern" ]; then
    echo "$err" | grep -q -e "$err_pattern" || problems="$problems stderr did not match [$err_pattern] (was [$err]);"
  else
    [ -z "$err" ] || problems="$problems stderr was [$err], wanted none;"
  fi
  if [ -z "$problems" ]; then echo "PASS: $name (${elapsed}s)"; else echo "FAIL: $name:$problems"; FAILED=1; fi
}

run_case "exits normally"                       ok          5  "9.9.9" yes ""
run_case "prints the version, then hangs"       hang-after  12 "9.9.9" yes ""
run_case "prints nothing and hangs"             silent-hang 12 ""      no  "no output after 3s"
run_case "prints nothing and fails with a message" fail      5  ""      no  "something went wrong"

[ $FAILED -eq 0 ] && echo "All --version handling tests passed" || { echo "Some --version handling tests FAILED"; exit 1; }
