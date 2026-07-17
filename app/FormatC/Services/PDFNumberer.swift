import Foundation
import CoreGraphics
import CoreText
import AppKit
import PDFKit

enum PDFNumbererError: LocalizedError {
    case cannotOpen(URL)
    case cannotWrite(URL)
    case cannotCreateContext
    case noPages

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let u): return "Cannot open \(u.lastPathComponent)"
        case .cannotWrite(let u): return "Cannot write \(u.path)"
        case .cannotCreateContext: return "Cannot create PDF context"
        case .noPages: return "PDF has no pages"
        }
    }
}

/// Draws page numbers on each page of a PDF. The original page content is
/// preserved untouched; the number is drawn on top via a CGContext text
/// draw. Format uses printf-style tokens: `%d` for the number, `%t` for
/// the total (e.g. `"%d / %t"` → "3 / 12").
enum PDFNumberer {
    enum Position: String, CaseIterable, Identifiable {
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

    static func addPageNumbers(
        to input: URL,
        output: URL,
        startAt start: Int,
        position: Position,
        format: String,
        fontSize: CGFloat = 10,
        margin: CGFloat = 24
    ) throws {
        guard let source = CGPDFDocument(input as CFURL), source.numberOfPages > 0 else {
            throw PDFNumbererError.cannotOpen(input)
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let firstPage = source.page(at: 1) else {
            throw PDFNumbererError.noPages
        }
        var firstBox = firstPage.getBoxRect(.mediaBox)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            throw PDFNumbererError.cannotCreateContext
        }

        let total = source.numberOfPages
        for i in 1...total {
            guard let page = source.page(at: i) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)

            ctx.beginPDFPage([
                kCGPDFContextMediaBox: NSValue(rect: NSRectFromCGRect(mediaBox))
            ] as CFDictionary)
            // Re-draw original content untouched.
            ctx.drawPDFPage(page)

            // Compose the label — %d → page number, %t → total.
            let number = start + (i - 1)
            let label = format
                .replacingOccurrences(of: "%d", with: "\(number)")
                .replacingOccurrences(of: "%t", with: "\(total)")

            drawText(label, in: ctx,
                     box: mediaBox, position: position,
                     fontSize: fontSize, margin: margin)

            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    private static func drawText(
        _ text: String, in ctx: CGContext,
        box: CGRect, position: Position,
        fontSize: CGFloat, margin: CGFloat
    ) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black.cgColor
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        let textBounds = CTLineGetImageBounds(line, ctx)

        // PDF coordinate space: origin is bottom-left of the media box.
        let x: CGFloat = {
            switch position {
            case .topLeft, .bottomLeft:
                return box.minX + margin
            case .topCenter, .bottomCenter:
                return box.midX - textBounds.width / 2
            case .topRight, .bottomRight:
                return box.maxX - margin - textBounds.width
            }
        }()
        let y: CGFloat = {
            switch position {
            case .topLeft, .topCenter, .topRight:
                return box.maxY - margin - textBounds.height
            case .bottomLeft, .bottomCenter, .bottomRight:
                return box.minY + margin
            }
        }()

        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}
