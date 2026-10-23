#! /bin/bash

# The normal path discards all of Strypify's stdout/stderr (the result is passed back on fd 3),
# but --version prints its result on stdout, so let that one through.
#
# Strypify prints the version at once, but can then hang or crash while exiting (a core dump can hold it for
# minutes). If we waited for the exit, the caller's timeout would kill this script before it passed on the
# version it already had, which showed up as "produced no output" with nothing on stderr. So, as for a render
# below, once the version is there give the process a few seconds to exit, and then stop it. And if it never
# prints anything, give up after STRYPIFY_VERSION_TIMEOUT seconds (which has to be less than the caller's own
# timeout) and show its stderr, so that the failure is diagnosable rather than silent.
case " $* " in
  *" --version "*|*" -v "*)
    VOUT_FILE=$(mktemp)
    VERR=$(mktemp)
    setsid xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb >"$VOUT_FILE" 2>"$VERR" </dev/null &
    PID=$!
    START=$SECONDS
    TICKS=0
    STOPPED=
    while kill -0 $PID 2>/dev/null; do
      if [ -s "$VOUT_FILE" ]; then
        TICKS=$((TICKS + 1))
        if [ "$TICKS" -ge 30 ]; then
          STOPPED="version printed but Strypify had not exited after 3s; stopped it"
          break
        fi
      elif [ $((SECONDS - START)) -ge "${STRYPIFY_VERSION_TIMEOUT:-40}" ]; then
        STOPPED="no output after ${STRYPIFY_VERSION_TIMEOUT:-40}s; stopped it"
        break
      fi
      sleep 0.1
    done
    if [ -n "$STOPPED" ]; then
      kill -TERM -- -$PID 2>/dev/null
      sleep 1
      kill -KILL -- -$PID 2>/dev/null
    fi
    wait $PID 2>/dev/null
    VRC=$?
    VOUT=$(cat "$VOUT_FILE")
    # Stopping it after the version was printed is not a failure:
    [ -n "$STOPPED" ] && [ -n "$VOUT" ] && VRC=0
    if [ "$VRC" -ne 0 ] || [ -z "$VOUT" ]; then
      echo "strypify-headless: --version exit code $VRC, output [$VOUT]${STOPPED:+ ($STOPPED)}; stderr follows:" >&2
      cat "$VERR" >&2
    fi
    rm -f "$VOUT_FILE" "$VERR"
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
