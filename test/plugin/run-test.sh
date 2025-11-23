#! /bin/bash

echo $PATH

asciidoctor -I../../asciidoctor -r strypify-plugin example1.adoc --trace
bash ./diff-html-body.sh expected-example1.html example1.html || { echo "Files for example1 differ!"; exit 1; }

bash ./diff-html-body.sh -u expected-example1.html example1.html || { echo "Files differ!"; exit 1; }
