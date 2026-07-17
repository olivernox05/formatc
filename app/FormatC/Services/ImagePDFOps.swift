import Foundation
import PDFKit
import AppKit

enum ImagePDFOpsError: LocalizedError {
    case cannotDecode(URL)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let url): return "Cannot decode image \(url.lastPathComponent)"
        case .cannotWrite(let url): return "Cannot write \(url.path)"
        }
    }
}

enum ImagePDFOps {
    /// Bundle each image as one page. Page size follows the image's pixel
    /// dimensions (72dpi assumed) so nothing is upscaled. The user rarely
    /// wants a fixed A4 canvas for a screenshot dump.
    static func imagesToPDF(_ images: [URL], into output: URL) throws {
        let pdf = PDFDocument()
        for (i, url) in images.enumerated() {
            guard let image = NSImage(contentsOf: url) else {
                throw ImagePDFOpsError.cannotDecode(url)
            }
            guard let page = PDFPage(image: image) else {
                throw ImagePDFOpsError.cannotDecode(url)
            }
            pdf.insert(page, at: i)
        }
        guard pdf.write(to: output) else {
            throw ImagePDFOpsError.cannotWrite(output)
        }
    }
}
