#!/usr/bin/env bash
# scripts/update_coverage_badge.sh
# Reads luacov.report.out, extracts the Total coverage percentage,
# picks a shields.io colour, and rewrites the coverage badge URL in README.md.
# Called by `make badge` (which runs coverage first).
#
# Always resolves paths relative to the project root (parent of this script),
# so it works correctly regardless of the caller's working directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

REPORT="${ROOT}/luacov.report.out"
README="${ROOT}/README.md"

if [[ ! -f "$REPORT" ]]; then
  echo "error: $REPORT not found — run 'make coverage' first" >&2
  exit 1
fi

# Extract the numeric percentage from the Total line:
#   Total   190  254   42.79%
PCT=$(grep -E '^Total\s' "$REPORT" | grep -oE '[0-9]+\.[0-9]+' | tail -1)

if [[ -z "$PCT" ]]; then
  echo "error: could not parse coverage percentage from $REPORT" >&2
  exit 1
fi

# Round to nearest integer for the badge label
PCT_INT=$(printf "%.0f" "$PCT")

# Pick colour based on thresholds:
#   100       → brightgreen
#   80 – 99   → green  (meets the minimum bar)
#   60 – 79   → yellow (below target)
#   40 – 59   → orange
#   < 40      → red
if   [[ "$PCT_INT" -ge 100 ]]; then COLOR="brightgreen"
elif [[ "$PCT_INT" -ge 80  ]]; then COLOR="green"
elif [[ "$PCT_INT" -ge 60  ]]; then COLOR="yellow"
elif [[ "$PCT_INT" -ge 40  ]]; then COLOR="orange"
else                                COLOR="red"
fi

# Build the new shields.io static badge URL.
# %25 is the URL-encoded % sign.
NEW_URL="https://img.shields.io/badge/coverage-${PCT_INT}%25-${COLOR}?style=flat-square&logo=lua"

# Replace the coverage badge line in README.md.
# We match the whole line that starts with [![Coverage] and replace entirely.
# Using perl instead of sed to avoid & being interpreted as a back-reference.
perl -i -pe "s{^\[!\[Coverage\].*\$}{[![Coverage](${NEW_URL})](luacov.report.out)}" "$README"

echo "coverage: ${PCT}% → badge updated (${COLOR})"
