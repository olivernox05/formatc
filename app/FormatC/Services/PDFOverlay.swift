import Foundation
import CoreGraphics
import CoreText
import AppKit
import PDFKit

enum PDFOverlayError: LocalizedError {
    case cannotOpen(URL)
    case cannotWrite(URL)
    case cannotCreateContext
    case pageOutOfRange(Int, total: Int)
    case cannotDecodeSignature(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let u): return "Cannot open \(u.lastPathComponent)"
        case .cannotWrite(let u): return "Cannot write \(u.path)"
        case .cannotCreateContext: return "Cannot create PDF context"
        case .pageOutOfRange(let p, let t): return "Page \(p) doesn't exist — the PDF has \(t) pages"
        case .cannotDecodeSignature(let u): return "Cannot read the signature at \(u.path)"
        }
    }
}

enum PDFAnchor: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft:      return "Top left"
        case .topCenter:    return "Top center"
        case .topRight:     return "Top right"
        case .bottomLeft:   return "Bottom left"
        case .bottomCenter: return "Bottom center"
        case .bottomRight:  return "Bottom right"
        }
    }
}

/// Overlay content on top of an existing PDF page. Signatures come in as
/// image URLs and are scaled proportionally; text comes in as a string
/// with font size. Optionally paints a white rectangle underneath the
/// text bounding box first — the "cover and retype" workflow that lets
/// you effectively replace visible text without a real PDF text editor.
enum PDFOverlay {
    /// Add a signature image to a single page. `scale` is the fraction of
    /// the page width the signature will occupy (0.15–0.5 typical).
    static func addSignature(
        to input: URL, output: URL,
        page targetPage: Int,
        signature signatureURL: URL,
        anchor: PDFAnchor,
        scale: CGFloat,
        margin: CGFloat = 36
    ) throws {
        guard let signatureImage = NSImage(contentsOf: signatureURL) else {
            throw PDFOverlayError.cannotDecodeSignature(signatureURL)
        }
        var rect = NSRect.zero
        guard let sigCG = signatureImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw PDFOverlayError.cannotDecodeSignature(signatureURL)
        }
        try modify(input: input, output: output, targetPage: targetPage) { ctx, mediaBox, isTarget in
            guard isTarget else { return }
            let sigW = mediaBox.width * scale
            let sigH = sigW * CGFloat(sigCG.height) / CGFloat(sigCG.width)
            let rect = frame(width: sigW, height: sigH, in: mediaBox, anchor: anchor, margin: margin)
            ctx.draw(sigCG, in: rect)
        }
    }

    /// Add plain text at a fixed anchor. If `whiteCover` is true, a white
    /// rectangle 8 points larger than the text bounds is drawn under it —
    /// the "erase" step of the erase-then-retype workflow.
    static func addText(
        to input: URL, output: URL,
        page targetPage: Int,
        text: String,
        anchor: PDFAnchor,
        fontSize: CGFloat,
        margin: CGFloat = 36,
        whiteCover: Bool = false
    ) throws {
        try modify(input: input, output: output, targetPage: targetPage) { ctx, mediaBox, isTarget in
            guard isTarget else { return }
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black.cgColor
            ]
            let attr = NSAttributedString(string: text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
            let textBounds = CTLineGetImageBounds(line, ctx)

            let rect = frame(
                width: textBounds.width, height: textBounds.height,
                in: mediaBox, anchor: anchor, margin: margin
            )

            if whiteCover {
                let pad: CGFloat = 4
                let cover = rect.insetBy(dx: -pad, dy: -pad)
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fill(cover)
            }
            ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY)
            CTLineDraw(line, ctx)
        }
    }

    // MARK: - Shared plumbing

    /// Rewrite the PDF page by page, invoking `draw` after redrawing the
    /// original content for each page. `isTarget` is true only on the
    /// page the caller cares about.
    private static func modify(
        input: URL, output: URL, targetPage: Int,
        draw: (CGContext, CGRect, Bool) -> Void
    ) throws {
        guard let source = CGPDFDocument(input as CFURL), source.numberOfPages > 0 else {
            throw PDFOverlayError.cannotOpen(input)
        }
        guard targetPage >= 1, targetPage <= source.numberOfPages else {
            throw PDFOverlayError.pageOutOfRange(targetPage, total: source.numberOfPages)
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var firstBox = source.page(at: 1)!.getBoxRect(.mediaBox)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            throw PDFOverlayError.cannotCreateContext
        }

        for i in 1...source.numberOfPages {
            guard let page = source.page(at: i) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)
            ctx.beginPDFPage([
                kCGPDFContextMediaBox: NSValue(rect: NSRectFromCGRect(mediaBox))
            ] as CFDictionary)
            ctx.drawPDFPage(page)
            draw(ctx, mediaBox, i == targetPage)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// Where to place a content box of `width` × `height` inside `box`
    /// given an anchor and a margin. PDF coord space: origin is bottom-left.
    private static func frame(
        width: CGFloat, height: CGFloat,
        in box: CGRect, anchor: PDFAnchor, margin: CGFloat
    ) -> CGRect {
        let x: CGFloat = {
            switch anchor {
            case .topLeft, .bottomLeft:     return box.minX + margin
            case .topCenter, .bottomCenter: return box.midX - width / 2
            case .topRight, .bottomRight:   return box.maxX - margin - width
            }
        }()
        let y: CGFloat = {
            switch anchor {
            case .topLeft, .topCenter, .topRight:
                return box.maxY - margin - height
            case .bottomLeft, .bottomCenter, .bottomRight:
                return box.minY + margin
            }
        }()
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
