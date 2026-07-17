import Foundation
import PDFKit

enum PDFCropperError: LocalizedError {
    case cannotOpen(URL)
    case cannotWrite(URL)
    case invalidMargins

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let u): return "Cannot open \(u.lastPathComponent)"
        case .cannotWrite(let u): return "Cannot write \(u.path)"
        case .invalidMargins: return "Margins are larger than the page — nothing would be visible."
        }
    }
}

/// Trim uniform margins off every page by shrinking the crop box (the
/// region viewers actually render). The underlying content is left in the
/// PDF, so a viewer that ignores the crop box (or the user, if they open
/// the doc and reset the crop) would see the original. That matches how
/// Preview and most PDF tools handle "crop pages."
///
/// Margins are in **points** (1/72 inch). US Letter is 612 × 792 points;
/// A4 is 595 × 842. So a 36pt margin = ½ inch = ~1.27 cm.
enum PDFCropper {
    static func crop(
        _ input: URL, to output: URL,
        top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat
    ) throws {
        guard let source = PDFDocument(url: input), source.pageCount > 0 else {
            throw PDFCropperError.cannotOpen(input)
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        for i in 0..<source.pageCount {
            guard let page = source.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let newWidth = box.width - left - right
            let newHeight = box.height - top - bottom
            guard newWidth > 0, newHeight > 0 else {
                throw PDFCropperError.invalidMargins
            }
            let newBox = CGRect(
                x: box.minX + left,
                y: box.minY + bottom,
                width: newWidth,
                height: newHeight
            )
            page.setBounds(newBox, for: .cropBox)
        }

        guard source.write(to: output) else {
            throw PDFCropperError.cannotWrite(output)
        }
    }
}
