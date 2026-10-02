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
  $STRYPIFY --file=$PYFILE --output-file=$ACTUALFILE $OPTS || true
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
