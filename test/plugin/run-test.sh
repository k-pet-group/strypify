#! /bin/bash

PATH=../../artifact/Strypify*/:../../Strypify*/:$PATH asciidoctor -I../../asciidoctor -r strypify-plugin example1.adoc --trace

diff -u expected-example1.html example1.html || { echo "Files differ!"; exit 1; }
