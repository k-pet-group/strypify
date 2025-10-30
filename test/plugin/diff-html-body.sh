#!/usr/bin/env bash
# Usage: diff-html-body.sh file1.html file2.html

normalize_html_body() {
  xmllint --html --xpath "//body//text()" "$1" 2>/dev/null |
    tr -s '[:space:]' ' ' |
    grep -v '^Last updated' |
    sed 's/^ *//;s/ *$//'
}

diff -u <(normalize_html_body "$1") <(normalize_html_body "$2")
