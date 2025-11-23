#! /bin/bash

echo $PATH

asciidoctor -I../../asciidoctor -r strypify-plugin example1.adoc --trace
bash ./diff-html-body.sh expected-example1.html example1.html || { echo "Files for example1 differ!"; exit 1; }

asciidoctor -I../../asciidoctor -r strypify-plugin example2.adoc --trace
bash ./diff-html-body.sh expected-example2.html example2.html || { echo "Files for example2 differ!"; exit 1; }
