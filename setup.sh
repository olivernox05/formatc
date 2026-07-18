#!/usr/bin/env bash
# Format — install every optional tool the app can shell out to.
# Everything native (PDF merge, images↔PDF, PDF→PNG) already works with zero
# installs; this script only unlocks the *text* conversions.
#
# Safe to re-run: brew and pip skip anything already installed.

set -e

echo "== Format setup =="

if ! command -v brew >/dev/null 2>&1; then
    cat >&2 <<'MSG'
Homebrew isn't installed. Get it from https://brew.sh — one-liner:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
Then re-run this script.
MSG
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found. macOS ships one; run: xcode-select --install"
    exit 1
fi

echo
echo "-- pandoc (Markdown ↔ HTML, PDF ↔ DOCX) --"
brew list pandoc >/dev/null 2>&1 && echo "  already installed" || brew install pandoc

echo
echo "-- BasicTeX (Markdown/HTML → PDF) --"
if [ -x /Library/TeX/texbin/xelatex ]; then
    echo "  already installed"
else
    echo "  This step needs sudo to install the .pkg — you'll be prompted."
    brew install --cask basictex
fi

echo
echo "-- pymupdf4llm (PDF → Markdown) --"
python3 -m pip install --user --quiet pymupdf4llm && echo "  ok"

echo
echo "All set. Open Format and click Refresh in the status bar."
