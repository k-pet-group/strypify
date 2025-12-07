#! /bin/bash
set -euo pipefail

FILE="$1"
status=0

# Extract href values that begin with "."
while IFS= read -r href; do
    # Remove quotes just in case
    path="${href%\"}"
    path="${path#\"}"

    if [[ ! -e "$path" ]]; then
        echo "Missing: $path"
        status=1
    fi
done < <(
    xmllint --html --xpath '//a[starts-with(@href, ".")]/@href' "$FILE" 2>/dev/null \
    | sed -E 's/href=/"&\n/g' \
    | grep -o 'href="[^"]*"' \
    | cut -d'"' -f2
)

exit $status
