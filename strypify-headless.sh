#! /bin/bash

# The normal path discards all of Strypify's stdout/stderr (the result is passed back on fd 3),
# but --version prints its result on stdout, so let that one through. Its stderr is kept and shown
# if the run fails or prints nothing, so that a failure is diagnosable rather than silent.
case " $* " in
  *" --version "*|*" -v "*)
    VERR=$(mktemp)
    VOUT=$(xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 2>"$VERR" </dev/null)
    VRC=$?
    if [ "$VRC" -ne 0 ] || [ -z "$VOUT" ]; then
      echo "strypify-headless: --version exit code $VRC, output [$VOUT]; stderr follows:" >&2
      cat "$VERR" >&2
    fi
    rm -f "$VERR"
    [ -n "$VOUT" ] && printf '%s\n' "$VOUT"
    exit $VRC
    ;;
esac

# Keep stderr (Strypify's and xvfb-run's) in a temp file rather than discarding it, so that a
# failed or stalled render can be diagnosed. It is only shown if the run fails, or if
# STRYPIFY_HEADLESS_DEBUG is set.
# If STRYPIFY_HEADLESS_LOG_DIR is set, the log is written there and kept instead (CI uploads it).
# That matters for stalls: the caller's timeout kills this script before it can print anything.
# With STRYPIFY_HEADLESS_DEBUG set, Electron's own logging is turned on too.
[ -n "$STRYPIFY_HEADLESS_DEBUG" ] && export ELECTRON_ENABLE_LOGGING=1
if [ -n "$STRYPIFY_HEADLESS_LOG_DIR" ]; then
  mkdir -p "$STRYPIFY_HEADLESS_LOG_DIR"
  ERRLOG="$STRYPIFY_HEADLESS_LOG_DIR/headless-$(date +%H%M%S)-$$.log"
  KEEPLOG=1
else
  ERRLOG=$(mktemp)
fi
START=$SECONDS
RESULT=$(mktemp)
# Strypify writes the result (the output file name) on fd 3 once the image is complete, then exits.
# It occasionally crashes or hangs while exiting (and a core dump can then hold it for minutes), by
# which time the image is already written. So don't wait for the exit forever: once the result is
# there, give the process a few seconds to exit and then stop it. setsid puts it in its own process
# group so that Xvfb and all of Electron's child processes can be stopped together.
setsid xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 3>"$RESULT" > /dev/null 2>"$ERRLOG" &
PID=$!
TICKS=0
KILLED=
while kill -0 $PID 2>/dev/null; do
  if [ -s "$RESULT" ]; then
    TICKS=$((TICKS + 1))
    if [ "$TICKS" -ge 50 ]; then
      echo "strypify-headless: result written but Strypify had not exited after 5s; stopping it" >&2
      kill -TERM -- -$PID 2>/dev/null
      sleep 1
      kill -KILL -- -$PID 2>/dev/null
      KILLED=1
      break
    fi
  fi
  sleep 0.1
done
wait $PID 2>/dev/null
RC=$?
[ -n "$KILLED" ] && RC=0
cat "$RESULT"
rm -f "$RESULT"
if [ "$RC" -ne 0 ] || [ -n "$STRYPIFY_HEADLESS_DEBUG" ]; then
  echo "strypify-headless: exit code $RC after $((SECONDS - START))s; stderr follows:" >&2
  cat "$ERRLOG" >&2
fi
[ -z "$KEEPLOG" ] && rm -f "$ERRLOG"
exit $RC
