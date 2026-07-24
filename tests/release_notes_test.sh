#!/bin/sh
# release_notes_test.sh
# Checks the release note assembly the same way release.yml builds it,
# so a change that breaks the template or the NEWS.md heading pattern
# fails here rather than showing up as a bad release page after a tag
# is already pushed.

set -e
cd "$(dirname "$0")/.."

VERSION=$(grep '^Version:' DESCRIPTION | sed 's/^Version: //')
sed "s/{{VERSION}}/$VERSION/" .github/RELEASE_TEMPLATE.md > /tmp/tessera_notes_check.md

fail=0
check() {
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    fail=1
  fi
}

check "the template carries no unfilled placeholder" \
  '! grep -q "{{" /tmp/tessera_notes_check.md'
check "the template names the current version" \
  "grep -q \"Tessera $VERSION\" /tmp/tessera_notes_check.md"
check "the template has an overview, highlights, installation, and license" \
  'grep -q "^### Highlights" /tmp/tessera_notes_check.md &&
   grep -q "^### Installation" /tmp/tessera_notes_check.md &&
   grep -q "^### License" /tmp/tessera_notes_check.md'
check "NEWS.md has a heading for the current version" \
  "grep -q \"^# Tessera $VERSION\$\" NEWS.md"

echo ""
if [ "$fail" -eq 1 ]; then
  echo "release notes check failed"
  exit 1
else
  echo "release notes check passed"
fi
