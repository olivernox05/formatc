# FormatC

macOS SwiftUI utility for PDF ↔ Markdown / DOCX / HTML / images conversion and PDF merging.

## Build

    brew install xcodegen         # one-time
    cd app
    xcodegen generate
    open FormatC.xcodeproj

Then Cmd-R in Xcode.

## Runtime tooling

FormatC does what it can with pure Swift + PDFKit. Anything else is shelled
out to an installed CLI. The app detects which are present at launch and
tells you what's missing.

Native (always available):
- Merge / split PDFs
- Rasterize PDF pages → PNG
- Bundle images (PNG/JPG) → PDF

Uses `pdf2md.py` (Python, bundled — needs `pymupdf4llm` or `pdfplumber`):
- PDF → Markdown

Uses `pandoc` (`brew install pandoc`):
- Markdown ↔ HTML
- Markdown → PDF (needs a LaTeX engine like BasicTeX)
- PDF → DOCX, DOCX → PDF, DOCX ↔ Markdown

Install the Python engine for PDF → Markdown:

    /usr/bin/python3 -m pip install --user pymupdf4llm    # recommended
    /usr/bin/python3 -m pip install --user pdfplumber     # fallback
