#!/usr/bin/env bash
# Plugin tests: no shell, no network. Needs qt6-declarative (qmltestrunner).
set -euo pipefail
cd "$(dirname "$0")/.."
# Text only through PlainText: the panel has no Text element of its own and never sets a text format.
if grep -nE '(^|[^A-Za-z])Text[[:space:]]*\{|textFormat|StyledText|RichText|AutoText' Panel.qml; then
  echo "FAIL: Panel.qml must show text only through PlainText"; exit 1
fi
grep -q 'textFormat: Text.PlainText' PlainText.qml
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_today.qml
