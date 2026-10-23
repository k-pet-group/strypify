#! /bin/bash

set -e

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    STRYPIFY="../Strypify-linux-x64/strypify-headless.sh"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
    STRYPIFY="../Strypify-windows-x64/Strypify.exe"
else
    STRYPIFY="../Strypify-darwin-arm64/Strypify.app/Contents/MacOS/Strypify"
fi

if [[ ! -f "$STRYPIFY" ]]; then
    # Strip everything before the last `/` to use PATH:
    STRYPIFY="${STRYPIFY##*/}"
fi

echo Strypify: $STRYPIFY
PYTHON=$(command -v python3 || command -v python)
echo Python: $PYTHON

# Per-attempt limit, so a stalled Strypify launch fails (and is retried) quickly rather than
# eating minutes of CI time. A normal render takes around 10 seconds
# (up to ~20 for a cold start).
STRYPIFY_TIMEOUT=${STRYPIFY_TIMEOUT:-40}
run_limited() {
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 5 "$STRYPIFY_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 5 "$STRYPIFY_TIMEOUT" "$@"
  elif command -v perl >/dev/null 2>&1; then
    # macOS has no timeout command, but has perl:
    perl -e 'alarm shift; exec @ARGV' "$STRYPIFY_TIMEOUT" "$@"
  else
    "$@"
  fi
}

for PYFILE in example*.py; do
  echo Testing: $PYFILE
  EXPECTEDFILE="expected-${PYFILE%.py}.png"
  ACTUALFILE="actual-${PYFILE%.py}.png"
  rm -rf $ACTUALFILE
  # Read command line args if file exists:
  OPTS=""
  if [[ -f "${PYFILE%.py}.args" ]]; then
    OPTS=$(<"${PYFILE%.py}.args")
  fi

  # Strypify can occasionally crash during its own window/GTK teardown on
  # some headless Linux setups *after* it has already written the output
  # file correctly, which would make this exit non-zero despite a real
  # success. Don't let `set -e` abort on that; the file-existence check
  # right below this is the real test of whether it worked.
  # Strypify can also occasionally fail to produce any output at all on a
  # given run, so retry a couple of times before giving up.
  for ATTEMPT in 1 2 3; do
    ATTEMPT_START=$SECONDS
    run_limited $STRYPIFY --file=$PYFILE --output-file=$ACTUALFILE $OPTS || echo "Attempt $ATTEMPT exited with status $? after $((SECONDS - ATTEMPT_START))s"
    [ -f "$ACTUALFILE" ] && break
    echo "Attempt $ATTEMPT did not produce $ACTUALFILE (after $((SECONDS - ATTEMPT_START))s)"
    sleep 2
  done
  if [ ! -f "$ACTUALFILE" ]; then
    echo "Image $ACTUALFILE does not exist!"
    exit 1
  fi
  if [ ! -f "$EXPECTEDFILE" ]; then
      echo "Image $EXPECTEDFILE does not exist!"
      exit 1
    fi
  echo Comparing $ACTUALFILE to $EXPECTEDFILE
  export ACTUALFILE
  export EXPECTEDFILE
  $PYTHON run-test.py
done
