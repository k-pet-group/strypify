#! /bin/bash

echo $PATH
set -e

for src in example*.adoc; do
    base="${src%.adoc}"                 # example1 → example1
    expected="expected-${base}.html"    # → expected-example1.html
    output="${base}.html"               # → example1.html

    echo Running asciidoctor $src
    asciidoctor -I../../asciidoctor -r strypify-plugin "$src" --trace

    bash ./diff-html-body.sh "$expected" "$output" || {
        echo "Files for $base differ!"
        exit 1
    }
    bash ./check-links-exist.sh "$output" || {
          echo "Link(s) for $base pointed to missing file"
          exit 1
      }
done
