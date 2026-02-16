#!/usr/bin/env bash
set -euo pipefail

# Scan staged file contents for common secret patterns before commit.
# To intentionally allow a matching line, add: secret-scan: allow

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repository."
  exit 1
fi

staged_files="$(git diff --cached --name-only --diff-filter=ACM)"
if [[ -z "${staged_files}" ]]; then
  exit 0
fi

regex='AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]* )?PRIVATE KEY-----|(api[_-]?key|secret|token|password)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{10,}["'"'"']'

tmp_matches="$(mktemp)"
trap 'rm -f "$tmp_matches"' EXIT
found=0

while IFS= read -r file; do
  [[ -z "${file}" ]] && continue

  # Read staged content, not working tree content.
  if ! git show ":${file}" >"$tmp_matches" 2>/dev/null; then
    continue
  fi

  # Skip binary files.
  if LC_ALL=C grep -qU $'\x00' "$tmp_matches"; then
    continue
  fi

  if grep -nE "$regex" "$tmp_matches" | grep -v "secret-scan: allow" >/dev/null; then
    if [[ "$found" -eq 0 ]]; then
      echo "Secret scan failed. Potential secrets detected in staged changes:"
    fi
    found=1
    echo ""
    echo "File: $file"
    grep -nE "$regex" "$tmp_matches" | grep -v "secret-scan: allow" || true
  fi
done <<<"$staged_files"

if [[ "$found" -eq 1 ]]; then
  echo ""
  echo "Commit blocked. Remove secrets or annotate intentional test lines with: secret-scan: allow"
  exit 1
fi

exit 0
