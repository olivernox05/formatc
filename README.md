# FormatC

A tiny macOS utility for **converting between PDF, Markdown, HTML, Word (.docx), and images**, and **merging PDFs**. Drag files in, pick a target, hit Convert.

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

| From \ To | PDF | Markdown | HTML | DOCX | PNG |
|---|---|---|---|---|---|
| **PDF**      | —           | pymupdf4llm | pandoc      | pandoc     | native |
| **Markdown** | pandoc+TeX  | —           | pandoc      | pandoc     | —      |
| **HTML**     | pandoc+TeX  | pandoc      | —           | pandoc     | —      |
| **DOCX**     | pandoc      | pandoc      | pandoc      | —          | —      |
| **PNG/JPG**  | native      | —           | —           | —          | —      |

Plus **PDF merge** — drop N PDFs into the Merge tab, drag to reorder, hit Save.

"Native" cells work with zero installs; the others need the tool named.

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

---

## Under the hood

- SwiftUI + PDFKit for the native operations (`app/FormatC/Services/PDFOps.swift`, `ImagePDFOps.swift`)
- Bundles the [`pdf2md.py`](pdf2md.py) script — a heuristic PDF → Markdown converter with table detection, page-furniture stripping, and dehyphenation. Uses `pymupdf4llm` when available, falls back to `pdfplumber`.
- Shells out to `pandoc` for everything Markdown/HTML/DOCX-shaped, with `xelatex` for the PDF output path.

The app detects each tool at launch and greys out any conversion whose dependency is missing — you never see a scary error, just a chip that hasn't lit up yet.

---

## License

[MIT](LICENSE).
