#!/usr/bin/env bash
# Plugin tests: no shell, no keyring. Needs qt6-declarative (qmltestrunner).
set -euo pipefail
cd "$(dirname "$0")/.."
# Text only through PlainText (and the kit's plain-text section header): the panel has no Text element of its own.
if grep -nE '(^|[^A-Za-z])Text[[:space:]]*\{|textFormat|StyledText|RichText|AutoText' Panel.qml; then
  echo "FAIL: Panel.qml must show text only through PlainText"; exit 1
fi
grep -q 'textFormat: Text.PlainText' PlainText.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_keys.qml
