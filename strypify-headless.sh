#! /bin/bash

# The normal path discards all of Strypify's stdout/stderr (the result is passed back on fd 3),
# but --version prints its result on stdout, so let that one through.
case " $* " in
  *" --version "*|*" -v "*)
    xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 2>/dev/null
    exit $?
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
xvfb-run --auto-servernum Strypify $* --no-sandbox --disable-setuid-sandbox --disable-setuid-sandbox --disable-gpu --disable-software-rasterizer --disable-dev-shm-usage --headless --disable-features=UseOzonePlatform --use-gl=swiftshader --force-color-profile=srgb 3>&1 > /dev/null 2>"$ERRLOG"
RC=$?
if [ "$RC" -ne 0 ] || [ -n "$STRYPIFY_HEADLESS_DEBUG" ]; then
  echo "strypify-headless: exit code $RC after $((SECONDS - START))s; stderr follows:" >&2
  cat "$ERRLOG" >&2
fi
[ -z "$KEEPLOG" ] && rm -f "$ERRLOG"
exit $RC
