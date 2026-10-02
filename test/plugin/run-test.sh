#! /bin/bash

echo $PATH
set -e

rm -rf ./.image-cache
rm -rf ~/.strypify-image-cache/

for src in example*.adoc; do
    base="${src%.adoc}"                 # example1 → example1
    expected="expected-${base}.html"    # → expected-example1.html
    output="${base}.html"               # → example1.html
    failmarker="${base}.expect-fail"    # → example5.expect-fail (if present, this
                                         # example is expected to make the build fail,
                                         # e.g. invalid Python in a Strype block; the
                                         # file's content is a grep pattern that must
                                         # appear in stderr)

    echo Running asciidoctor $src

    if [[ -f "$failmarker" ]]; then
        if asciidoctor -I../../asciidoctor -r strypify-plugin "$src" --trace \
            > "${base}.stdout.log" 2> "${base}.stderr.log"; then
            echo "Expected $src to fail the build, but asciidoctor succeeded!"
            exit 1
        fi
        if ! grep -qf "$failmarker" "${base}.stderr.log"; then
            echo "Failure output for $src did not match the pattern in $failmarker. Actual stderr:"
            cat "${base}.stderr.log"
            exit 1
        fi
        echo "$src correctly failed the build as expected."
        continue
    fi

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
