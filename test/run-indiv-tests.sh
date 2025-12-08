#! /bin/bash

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    STRYPIFY="strypify-headless.sh"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
    STRYPIFY="Strypify.exe"
fi

echo Strypify: $STRYPIFY
PYTHON=$(command -v python3 || command -v python)
echo Python: $PYTHON

for PYFILE in example*.py; do
  echo Testing: $PYFILE
  EXPECTEDFILE="expected-${PYFILE%.py}.png"
  ACTUALFILE="actual-${PYFILE%.py}.png"
  rm $ACTUALFILE
  $STRYPIFY --file=$PYFILE --output-file=$ACTUALFILE
  if [ ! -f "$ACTUALFILE" ]; then
    echo "Image $ACTUALFILE does not exist!"
    exit 1
  fi
  echo Comparing $ACTUALFILE to $EXPECTEDFILE
  export ACTUALFILE
  export EXPECTEDFILE
  $PYTHON run-test.py
done
