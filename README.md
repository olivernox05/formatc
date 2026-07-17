# FormatC

A tiny macOS utility for document + image work. Drag files in, hit a button.

- **Convert** between PDF, Markdown, HTML, DOCX, RTF, ODT, EPUB, TXT, LaTeX, PNG, JPEG, WebP, HEIC, TIFF, GIF, BMP.
- **Merge** PDFs.
- **Split** PDFs — one file per page, or extract a range.
- **Edit PDF** — compress (re-render at chosen DPI + JPEG quality), number pages, crop margins.
- **Remove background** from images with Apple's on-device subject-isolation model (macOS 14+).

Native SwiftUI, no analytics, no accounts, no cloud round-trip. Everything runs locally.

---

## Install

**Download the app**

Grab the latest `FormatC.zip` from [Releases](https://github.com/olivernox05/formatc/releases/latest), unzip, and move `FormatC.app` to your Applications folder.

**First launch (Gatekeeper)**

Because the app isn't signed with a paid Apple Developer certificate, macOS will refuse the very first launch with something like *"cannot be opened because the developer cannot be verified."* Fix once:

- **Right-click** (or Control-click) `FormatC.app` → **Open** → **Open** again on the confirmation dialog.

That whitelist entry sticks — from then on, double-click launches normally.

**Optional tools**

FormatC does the geometry-only work (PDF merge, PDF → PNG, images → PDF) on its own. The **text** conversions shell out to open-source CLIs. Install them once:

```bash
curl -fsSL https://raw.githubusercontent.com/olivernox05/formatc/main/setup.sh | bash
```

Or if you'd rather do it by hand:

```bash
brew install pandoc                                # MD ↔ HTML, PDF ↔ DOCX
brew install --cask basictex                       # MD/HTML → PDF (needs sudo)
python3 -m pip install --user pymupdf4llm          # PDF → Markdown
```

After installing, click **Refresh** in the status bar at the bottom of the FormatC window. Each tool's chip turns green as the app detects it.

---

## What FormatC can do

Text formats (PDF, Markdown, HTML, DOCX, RTF, ODT, EPUB, TXT, LaTeX) convert any-to-any via pandoc, plus PDF → Markdown via [pdf2md.py](pdf2md.py) (better tables than pandoc's PDF reader). Anything → PDF that isn't already goes through `xelatex`.

Image formats (PNG, JPEG, WebP, HEIC, TIFF, GIF, BMP) convert any-to-any natively via Core Graphics / ImageIO — zero installs.

Cross-category:

- Any image → PDF (bundles into a single-page or multi-page PDF)
- PDF → PNG (rasterizes each page at 200 DPI)
- Any image → transparent PNG with background removed (Vision framework)

Plus **PDF merge** (drop-and-reorder), **PDF split** (per-page or range), **Edit PDF** (compress, number pages, crop margins), and **background removal**.

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel — the app is a universal binary

---

## Build from source

If you'd rather build it yourself:

```bash
brew install xcodegen                     # one-time
git clone https://github.com/olivernox05/formatc.git
cd formatc/app
xcodegen generate
open FormatC.xcodeproj                    # Cmd-R in Xcode
```

Or headless:

```bash
xcodebuild -project app/FormatC.xcodeproj \
  -scheme FormatC -configuration Release \
  -destination 'platform=macOS' build
```

To produce a **notarized** zip that macOS accepts without the right-click → Open dance, do the one-time setup in [docs/notarize.md](docs/notarize.md) and run `./scripts/release.sh`. Without the setup, the script still builds a working local .app — just falls back to ad-hoc signing.

---

## Under the hood

- SwiftUI + PDFKit for the native operations (`app/FormatC/Services/PDFOps.swift`, `ImagePDFOps.swift`)
- Bundles the [`pdf2md.py`](pdf2md.py) script — a heuristic PDF → Markdown converter with table detection, page-furniture stripping, and dehyphenation. Uses `pymupdf4llm` when available, falls back to `pdfplumber`.
- Shells out to `pandoc` for everything Markdown/HTML/DOCX-shaped, with `xelatex` for the PDF output path.

The app detects each tool at launch and greys out any conversion whose dependency is missing — you never see a scary error, just a chip that hasn't lit up yet.

---

## License

[MIT](LICENSE).
