import Foundation
import CoreGraphics
import ImageIO
import AppKit
import PDFKit

enum PDFCompressorError: LocalizedError {
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

/// Compress a PDF by re-rendering each page at a chosen resolution and
/// re-encoding as JPEG. Vector content is lost — this is a raster-only
/// compressor. For most scanned or image-heavy PDFs it drops file size by
/// 3–10×; for text-only PDFs it can *increase* size (because text as
/// vectors compresses smaller than text as JPEG), so warn users on that
/// case in the UI.
enum PDFCompressor {
    enum Quality: String, CaseIterable, Identifiable {
        case high, medium, low
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .high:   return "High (200 DPI, 90%)"
            case .medium: return "Medium (150 DPI, 75%)"
            case .low:    return "Low (100 DPI, 50%)"
            }
        }

        var dpi: CGFloat {
            switch self { case .high: 200; case .medium: 150; case .low: 100 }
        }

        var jpegQuality: CGFloat {
            switch self { case .high: 0.9; case .medium: 0.75; case .low: 0.5 }
        }
    }

    static func compress(_ input: URL, to output: URL, quality: Quality) throws {
        guard let source = CGPDFDocument(input as CFURL), source.numberOfPages > 0 else {
            throw PDFCompressorError.cannotOpen(input)
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let firstPage = source.page(at: 1) else {
            throw PDFCompressorError.noPages
        }
        var firstBox = firstPage.getBoxRect(.mediaBox)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            throw PDFCompressorError.cannotCreateContext
        }

        for i in 1...source.numberOfPages {
            guard let page = source.page(at: i) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)
            let scale = quality.dpi / 72.0
            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let bitmap = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { continue }

            bitmap.setFillColor(gray: 1, alpha: 1)
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.saveGState()
            bitmap.scaleBy(x: scale, y: scale)
            bitmap.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
            bitmap.drawPDFPage(page)
            bitmap.restoreGState()

            guard let pageImage = bitmap.makeImage() else { continue }

            // Round-trip through JPEG encoder so the compressed bytes are
            // what actually lands in the PDF, not the raw bitmap.
            let jpegData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                jpegData, "public.jpeg" as CFString, 1, nil
            ) else { continue }
            CGImageDestinationAddImage(dest, pageImage, [
                kCGImageDestinationLossyCompressionQuality: quality.jpegQuality
            ] as CFDictionary)
            CGImageDestinationFinalize(dest)

            guard let jpegSource = CGImageSourceCreateWithData(jpegData, nil),
                  let compressed = CGImageSourceCreateImageAtIndex(jpegSource, 0, nil) else {
                continue
            }

            ctx.beginPDFPage([
                kCGPDFContextMediaBox: NSValue(rect: NSRectFromCGRect(mediaBox))
            ] as CFDictionary)
            ctx.draw(compressed, in: mediaBox)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    static func fileSize(_ url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }
}
