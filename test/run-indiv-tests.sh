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

  $STRYPIFY --file=$PYFILE --output-file=$ACTUALFILE $OPTS
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
