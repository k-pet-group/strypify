#!/usr/bin/env bash
# Usage: diff-html-body.sh file1.html file2.html

normalize_html_body() {
  # Remove the "Last updated" line BEFORE parsing
  cleaned=$1.cleaned
  grep -v 'Last updated' "$1" > "$cleaned"

  xmllint --html --xpath "//*[translate(local-name(), 'BODY', 'body') = 'body']" "$cleaned" 2>/dev/null |
      sed 's/^[[:space:]]*//;s/[[:space:]]*$//'

  rm -f "$cleaned"
}

diff -u <(normalize_html_body "$1") <(normalize_html_body "$2")
