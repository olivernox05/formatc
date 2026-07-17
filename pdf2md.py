#!/usr/bin/env python3
"""
pdf2md - convert PDF files to Markdown.

Usage:
    python3 pdf2md.py input.pdf                  # writes input.md
    python3 pdf2md.py input.pdf -o out.md
    python3 pdf2md.py *.pdf -d out_dir/          # batch
    python3 pdf2md.py input.pdf --pages 1-5
    python3 pdf2md.py input.pdf --images         # extract images to <name>_assets/
    python3 pdf2md.py input.pdf --engine plumber # force fallback engine

Engines (auto-selected, best first):
    pymupdf4llm  - highest fidelity. pip install pymupdf4llm
    plumber      - pure-python fallback. pip install pdfplumber

Scanned/image-only PDFs produce little or no text; they need OCR first
(e.g. `ocrmypdf in.pdf out.pdf`).
"""

import argparse
import os
import re
import statistics
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# engine detection
# --------------------------------------------------------------------------


def available_engines():
    found = []
    try:
        import pymupdf4llm  # noqa: F401

        found.append("pymupdf4llm")
    except ImportError:
        pass
    try:
        import pdfplumber  # noqa: F401

        found.append("plumber")
    except ImportError:
        pass
    return found


# --------------------------------------------------------------------------
# engine 1: pymupdf4llm
# --------------------------------------------------------------------------


def convert_pymupdf4llm(path, pages, want_images, asset_dir):
    import pymupdf4llm

    kwargs = {}
    if pages:
        kwargs["pages"] = [p - 1 for p in pages]  # 0-based
    if want_images:
        asset_dir.mkdir(parents=True, exist_ok=True)
        kwargs.update(
            write_images=True,
            image_path=str(asset_dir),
            image_format="png",
        )
    return pymupdf4llm.to_markdown(str(path), **kwargs)


# --------------------------------------------------------------------------
# engine 2: pdfplumber fallback
# --------------------------------------------------------------------------

BULLET = re.compile(r"^\s*[•‣●○·⁃\-\*–]\s+")
NUMBERED = re.compile(r"^\s*(\d{1,2})[.)]\s+")


def _md_escape(text):
    # Escape only characters that would start unintended markdown constructs.
    return re.sub(r"^(\s*)([#>|])", r"\1\\\2", text)


def _table_to_md(table):
    rows = [
        ["" if c is None else " ".join(str(c).split()).replace("|", "\\|") for c in row]
        for row in table
        if row is not None
    ]
    rows = [r for r in rows if any(c.strip() for c in r)]
    if not rows:
        return ""
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    head, body = rows[0], rows[1:]
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * width]
    out += ["| " + " | ".join(r) + " |" for r in body]
    return "\n".join(out)


def _line_text(line):
    return "".join(c["text"] for c in line["chars"])


def _heading_level(size, body_size, size_ranks):
    """Map a font size to an h1-h4 level, or None for body text."""
    if size <= body_size + 0.6:
        return None
    bigger = [s for s in size_ranks if s > body_size + 0.6]
    if not bigger:
        return None
    # Largest distinct size -> h1, next -> h2, capped at h4.
    try:
        idx = bigger.index(size)
    except ValueError:
        idx = min(
            range(len(bigger)), key=lambda i: abs(bigger[i] - size)
        )
    return min(idx + 1, 4)


def _find_tables(page):
    """Find tables using ruling lines; fall back to whitespace alignment.

    Many PDFs (LaTeX, Word) draw tables with no vertical rules at all, so the
    default 'lines' strategy misses them entirely. The text strategy catches
    those but over-fires on ordinary prose, so we only accept its results when
    they look genuinely tabular.
    """
    tables = page.find_tables()
    if tables:
        return tables

    # No full grid. Locate candidate regions using whatever ruling lines exist
    # (booktabs-style tables have only top/mid/bottom rules), then split rows
    # and columns by text alignment *inside* that confirmed region. Running a
    # text/text strategy on the whole page instead would read a page of prose
    # as one giant table, so it is always scoped to a region.
    regions = page.find_tables(
        {"vertical_strategy": "text", "horizontal_strategy": "lines",
         "intersection_tolerance": 5}
    )
    good = []
    for region in regions:
        if not _looks_tabular(region, page):
            continue
        x0, top, x1, bottom = region.bbox
        crop = page.crop((max(x0 - 2, 0), max(top - 2, 0),
                          min(x1 + 2, page.width), min(bottom + 2, page.height)))
        inner = crop.find_tables(
            {"vertical_strategy": "text", "horizontal_strategy": "text",
             "intersection_tolerance": 5}
        )
        # Prefer the finer-grained split if it recovered more rows.
        best = max(inner, key=lambda t: len(t.extract()), default=None)
        if best is not None and len(best.extract()) > len(region.extract()):
            good.append(best)
        else:
            good.append(region)
    return good


def _looks_tabular(table, page):
    rows = table.extract()
    if len(rows) < 2:
        return False
    widths = [len(r) for r in rows]
    if max(widths) < 2:
        return False
    # A "table" covering most of the page is almost certainly misdetected prose.
    x0, top, x1, bottom = table.bbox
    if (bottom - top) > page.height * 0.9 and (x1 - x0) > page.width * 0.9:
        return False
    cells = [c for r in rows for c in r]
    filled = [str(c) for c in cells if c and str(c).strip()]
    if not filled:
        return False
    # Real tables are mostly full and hold short values, not paragraphs.
    if len(filled) / len(cells) < 0.5:
        return False
    if max(len(c) for c in filled) > 80:
        return False
    return True


def _strip_page_furniture(lines, page_height, body_size):
    """Remove running heads, footers and page numbers.

    Matching repeated strings fails as soon as the header interpolates the
    section name, and a fixed margin band either misses headers or eats real
    headings near a page edge. Page furniture is instead identified
    structurally: it is the first/last line, it is short, it sits in the outer
    margin, it is separated from the text block by an unusually large gap, and
    it is not set in a display font (which would make it a title).

    `lines` is a list of (top, bottom, text, size, bold), sorted by top.
    """
    if len(lines) < 3:
        return lines

    gaps = [lines[i + 1][0] - lines[i][1] for i in range(len(lines) - 1)]
    positive = [g for g in gaps if g > 0]
    if not positive:
        return lines
    typical_gap = statistics.median(positive)

    def is_furniture(idx, gap):
        top, bottom, text, size, _bold = lines[idx]
        if len(text.split()) > 12:
            return False
        if size > body_size + 0.5:  # a title, not a running head
            return False
        in_margin = top < page_height * 0.15 or bottom > page_height * 0.85
        return in_margin and gap > max(typical_gap * 1.8, 6)

    keep = list(lines)
    if is_furniture(0, gaps[0]):
        keep[0] = None
    if is_furniture(len(lines) - 1, gaps[-1]):
        keep[-1] = None
    return [l for l in keep if l is not None]


def convert_plumber(path, pages, want_images, asset_dir, keep_heads=False):
    import pdfplumber

    out = []
    with pdfplumber.open(str(path)) as pdf:
        selected = (
            [pdf.pages[p - 1] for p in pages if 0 < p <= len(pdf.pages)]
            if pages
            else pdf.pages
        )

        # Pass 1: find the dominant (body) font size across the document.
        sizes = []
        for page in selected:
            for ch in page.chars:
                sizes.append(round(ch["size"], 1))
        if not sizes:
            return ""
        body_size = statistics.mode(sizes)
        size_ranks = sorted({s for s in sizes if sizes.count(s) > 2}, reverse=True)

        for pno, page in enumerate(selected, 1):
            # Tables first: record their bounding boxes so we can skip that text.
            table_objs = _find_tables(page)
            table_bboxes = [t.bbox for t in table_objs]

            def in_table(obj):
                x0, top, x1, bottom = obj["x0"], obj["top"], obj["x1"], obj["bottom"]
                for bx0, btop, bx1, bbottom in table_bboxes:
                    if x0 >= bx0 - 1 and x1 <= bx1 + 1 and top >= btop - 1 and bottom <= bbottom + 1:
                        return True
                return False

            words = [w for w in page.extract_words(extra_attrs=["size", "fontname"])
                     if not in_table(w)]

            # Group words into lines by their vertical position.
            lines = {}
            for w in words:
                key = round(w["top"] / 3)
                lines.setdefault(key, []).append(w)

            page_lines = []  # (top, bottom, text, size, bold)
            for key in sorted(lines):
                ws = sorted(lines[key], key=lambda w: w["x0"])
                text = " ".join(w["text"] for w in ws).strip()
                if not text:
                    continue
                size = round(statistics.median([w["size"] for w in ws]), 1)
                bold = all("bold" in w.get("fontname", "").lower() for w in ws)
                page_lines.append(
                    (
                        min(w["top"] for w in ws),
                        max(w["bottom"] for w in ws),
                        text,
                        size,
                        bold,
                    )
                )

            if not keep_heads:
                page_lines = _strip_page_furniture(page_lines, page.height, body_size)

            blocks = [
                (top, "line", (text, size, bold))
                for top, _bottom, text, size, bold in page_lines
            ]

            for t in table_objs:
                md = _table_to_md(t.extract())
                if md:
                    blocks.append((t.bbox[1], "table", md))

            blocks.sort(key=lambda b: b[0])

            para = []

            def flush():
                if para:
                    out.append(" ".join(para))
                    out.append("")
                    para.clear()

            for _, kind, payload in blocks:
                if kind == "table":
                    flush()
                    out.append(payload)
                    out.append("")
                    continue

                text, size, bold = payload
                level = _heading_level(size, body_size, size_ranks)
                if level is None and bold and len(text) < 90 and not text.endswith("."):
                    level = 3  # bold short line = subheading

                if level:
                    flush()
                    if out and out[-1] != "":
                        out.append("")  # CommonMark needs a blank line first
                    out.append("#" * level + " " + text)
                    out.append("")
                elif BULLET.match(text):
                    flush()
                    out.append("- " + BULLET.sub("", text))
                elif NUMBERED.match(text):
                    flush()
                    m = NUMBERED.match(text)
                    out.append(f"{m.group(1)}. " + NUMBERED.sub("", text))
                else:
                    # A bare number near the bottom of the page is a page number.
                    if text.isdigit() and len(text) <= 4:
                        continue
                    para.append(_md_escape(text))
            flush()

            if want_images and page.images:
                asset_dir.mkdir(parents=True, exist_ok=True)
                for i, im in enumerate(page.images, 1):
                    name = f"page{pno}_img{i}.png"
                    try:
                        bbox = (
                            max(im["x0"], 0),
                            max(im["top"], 0),
                            min(im["x1"], page.width),
                            min(im["bottom"], page.height),
                        )
                        page.crop(bbox).to_image(resolution=150).save(
                            str(asset_dir / name)
                        )
                        out.append(f"![{name}]({asset_dir.name}/{name})")
                        out.append("")
                    except Exception:
                        pass

            if pno != len(selected):
                out.append("---")
                out.append("")

    md = "\n".join(out)
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md.strip() + "\n"


# --------------------------------------------------------------------------
# cleanup: repeated headers/footers, hyphenation
# --------------------------------------------------------------------------


def strip_running_heads(md, page_count):
    """Drop short lines that repeat on most pages (headers/footers/page numbers)."""
    if page_count < 3:
        return md
    lines = md.split("\n")
    counts = {}
    for ln in lines:
        s = ln.strip()
        if 0 < len(s) < 60:
            counts[s] = counts.get(s, 0) + 1
    threshold = max(3, int(page_count * 0.6))
    junk = {
        s
        for s, c in counts.items()
        if c >= threshold and (s.isdigit() or len(s.split()) <= 8)
    }
    if not junk:
        return md
    return "\n".join(ln for ln in lines if ln.strip() not in junk)


def dehyphenate(md):
    return re.sub(r"(\w)-\n(\w)", r"\1\2", md)


def parse_pages(spec):
    if not spec:
        return None
    pages = set()
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            pages.update(range(int(a), int(b) + 1))
        elif part:
            pages.add(int(part))
    return sorted(pages)


def convert(path, out_path, engine, pages, want_images, keep_heads):
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError("no such file")
    if path.suffix.lower() != ".pdf":
        raise ValueError("not a .pdf file")

    asset_dir = out_path.parent / f"{out_path.stem}_assets"

    if engine == "pymupdf4llm":
        md = convert_pymupdf4llm(path, pages, want_images, asset_dir)
    else:
        md = convert_plumber(path, pages, want_images, asset_dir, keep_heads)

    md = dehyphenate(md)
    # The plumber engine already removes furniture positionally, which is more
    # reliable; this only backstops pymupdf4llm, which keeps headers.
    if not keep_heads and engine == "pymupdf4llm":
        try:
            import pdfplumber

            with pdfplumber.open(str(path)) as pdf:
                n = len(pages) if pages else len(pdf.pages)
        except Exception:
            n = 0
        md = strip_running_heads(md, n)

    md = re.sub(r"\n{3,}", "\n\n", md).strip() + "\n"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(md, encoding="utf-8")
    return md


def main():
    ap = argparse.ArgumentParser(
        description="Convert PDF files to Markdown.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("pdfs", nargs="+", help="input PDF file(s)")
    ap.add_argument("-o", "--output", help="output .md path (single input only)")
    ap.add_argument("-d", "--outdir", help="output directory (default: alongside input)")
    ap.add_argument("--pages", help="page range, e.g. 1-5 or 1,3,7-9")
    ap.add_argument("--images", action="store_true", help="extract images")
    ap.add_argument(
        "--engine",
        choices=["auto", "pymupdf4llm", "plumber"],
        default="auto",
        help="conversion engine (default: auto)",
    )
    ap.add_argument(
        "--keep-headers",
        action="store_true",
        help="keep repeated page headers/footers",
    )
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args()

    engines = available_engines()
    if not engines:
        sys.exit(
            "No PDF engine found. Install one:\n"
            "  pip install pymupdf4llm     (recommended)\n"
            "  pip install pdfplumber      (fallback)"
        )
    engine = args.engine
    if engine == "auto":
        engine = engines[0]
    elif engine not in engines:
        sys.exit(f"Engine '{engine}' not installed. Available: {', '.join(engines)}")

    if args.output and len(args.pdfs) > 1:
        sys.exit("-o works with a single input; use -d for batches.")

    pages = parse_pages(args.pages)
    failures = 0

    for p in args.pdfs:
        src = Path(p)
        if args.output:
            dst = Path(args.output)
        else:
            base = Path(args.outdir) if args.outdir else src.parent
            dst = base / (src.stem + ".md")
        try:
            md = convert(src, dst, engine, pages, args.images, args.keep_headers)
        except Exception as e:
            failures += 1
            print(f"FAIL  {src.name}: {e}", file=sys.stderr)
            continue
        if not args.quiet:
            words = len(md.split())
            note = "  (little text found - may be a scanned PDF; try OCR)" if words < 20 else ""
            print(f"OK    {src.name} -> {dst}  [{engine}, {words} words]{note}")

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
