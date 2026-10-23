#! /bin/bash

echo $PATH
set -e

# Per-example limit so a hang fails instead of stalling CI. It must comfortably exceed the
# plugin's own per-render timeout and retries (see STRYPIFY_TIMEOUT in strypify-plugin.rb),
# otherwise it kills asciidoctor before the plugin gets a chance to retry a stalled launch.
# (macOS runners have no `timeout`, so fall back to running without one there.)
run_limited() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 600 "$@"
    elif command -v perl >/dev/null 2>&1; then
        # macOS has no timeout command, but has perl:
        perl -e 'alarm shift; exec @ARGV' 600 "$@"
    else
        "$@"
    fi
}

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
        if run_limited asciidoctor -I../../asciidoctor -r strypify-plugin "$src" --trace \
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

    run_limited asciidoctor -I../../asciidoctor -r strypify-plugin "$src" --trace || {
        echo "asciidoctor failed or timed out (exit $?) on $src"
        exit 1
    }

    bash ./diff-html-body.sh "$expected" "$output" || {
        echo "Files for $base differ!"
        exit 1
    }
    bash ./check-links-exist.sh "$output" || {
          echo "Link(s) for $base pointed to missing file"
          exit 1
      }
done
