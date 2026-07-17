import Foundation
import PDFKit
import AppKit

enum PDFOpsError: LocalizedError {
    case cannotOpen(URL)
    case cannotWrite(URL)
    case noPages

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url): return "Cannot open \(url.lastPathComponent)"
        case .cannotWrite(let url): return "Cannot write to \(url.path)"
        case .noPages: return "PDF has no pages"
        }
    }
}

enum PDFOps {
    /// Combine PDFs in the given order. Pages are shallow-copied from the
    /// source docs; PDFKit does not deep-copy embedded resources here, so the
    /// output stays roughly (source sizes summed) rather than ballooning.
    static func merge(_ inputs: [URL], into output: URL) throws {
        let combined = PDFDocument()
        var insertIndex = 0
        for url in inputs {
            guard let doc = PDFDocument(url: url) else {
                throw PDFOpsError.cannotOpen(url)
            }
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                combined.insert(page, at: insertIndex)
                insertIndex += 1
            }
        }
        guard combined.pageCount > 0 else { throw PDFOpsError.noPages }
        guard combined.write(to: output) else {
            throw PDFOpsError.cannotWrite(output)
        }
    }

    /// Emit one PDF per page, named `<stem>_p<N>.pdf` in `directory`.
    static func split(_ input: URL, into directory: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else {
            throw PDFOpsError.cannotOpen(input)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = input.deletingPathExtension().lastPathComponent
        var results: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let out = directory.appendingPathComponent("\(stem)_p\(i + 1).pdf")
            guard single.write(to: out) else { throw PDFOpsError.cannotWrite(out) }
            results.append(out)
        }
        return results
    }

    /// Render each page as a PNG at the given DPI. Returns the written URLs.
    /// If the PDF has one page, writes `output` directly; otherwise writes
    /// `<output stem>_p<N>.png` in `output`'s directory.
    static func rasterize(_ input: URL, to output: URL, dpi: CGFloat = 200) throws -> [URL] {
        guard let doc = PDFDocument(url: input) else {
            throw PDFOpsError.cannotOpen(input)
        }
        let scale = dpi / 72.0
        let directory = output.deletingLastPathComponent()
        let stem = output.deletingPathExtension().lastPathComponent
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var results: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

            let image = NSImage(size: pixelSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: pixelSize).fill()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
                page.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            image.unlockFocus()

            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw PDFOpsError.cannotWrite(output)
            }
            let target: URL = doc.pageCount == 1
                ? output
                : directory.appendingPathComponent("\(stem)_p\(i + 1).png")
            try png.write(to: target)
            results.append(target)
        }
        if results.isEmpty { throw PDFOpsError.noPages }
        return results
    }
}
