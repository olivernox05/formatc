import Foundation

enum ConversionEngineError: LocalizedError {
    case unsupportedPair(from: FileFormat, to: FileFormat)
    case pandocRequired
    case pythonEngineRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedPair(let f, let t):
            return "No route from \(f.displayName) to \(t.displayName)."
        case .pandocRequired:
            return "This conversion needs pandoc. Install with:  brew install pandoc"
        case .pythonEngineRequired:
            return "PDF→Markdown needs a PDF engine:\n  python3 -m pip install --user pymupdf4llm"
        }
    }
}

/// Central router that picks the right underlying engine for a (from, to)
/// pair and decides on the output URL.
struct ConversionEngine {
    let tools: ToolCheck

    /// Whether the pair is deliverable given currently-installed tools.
    /// Used by the UI to grey out unavailable targets and explain why.
    func availability(from src: FileFormat, to dst: FileFormat) -> Availability {
        if src == dst { return .unavailable("Source and target are the same") }

        // Route table for the router below. Kept in sync manually — if
        // `route` grows a case, add it here so the UI stays honest.
        switch (src, dst) {
        case (.pdf, .markdown):
            return tools.pdf2mdEngine != nil
                ? .available
                : .unavailable("Install a Python PDF engine (see README)")
        case (.pdf, .png):
            return .available
        case (.pdf, .docx), (.markdown, .html), (.html, .markdown),
             (.markdown, .pdf), (.html, .pdf), (.markdown, .docx),
             (.html, .docx), (.docx, .markdown), (.docx, .html),
             (.docx, .pdf), (.pdf, .html):
            return tools.pandoc.isAvailable
                ? .available
                : .unavailable("Install pandoc:  brew install pandoc")
        case (.png, .pdf), (.jpeg, .pdf):
            return .available
        default:
            return .unavailable("Not supported")
        }
    }

    enum Availability: Equatable {
        case available
        case unavailable(String)

        var isAvailable: Bool { self == .available }
        var reason: String? {
            if case .unavailable(let s) = self { return s }
            return nil
        }
    }

    /// Perform a single conversion. Blocks the calling thread; call from a
    /// Task { } off the main actor.
    func convert(_ job: ConversionJob) throws -> URL {
        let src = job.source
        let dst = defaultOutput(for: src, target: job.target)

        switch (job.sourceFormat, job.target) {
        case (.pdf, .markdown):
            guard let py = tools.python3.path else {
                throw ConversionEngineError.pythonEngineRequired
            }
            let engine = PythonScriptEngine(pythonPath: py, pdf2mdEngine: tools.pdf2mdEngine)
            try engine.pdfToMarkdown(from: src, to: dst)

        case (.pdf, .png):
            _ = try PDFOps.rasterize(src, to: dst)

        case (.png, .pdf), (.jpeg, .pdf):
            try ImagePDFOps.imagesToPDF([src], into: dst)

        default:
            guard let pandoc = tools.pandoc.path else {
                throw ConversionEngineError.pandocRequired
            }
            guard PandocEngine.canConvert(from: job.sourceFormat, to: job.target) else {
                throw ConversionEngineError.unsupportedPair(from: job.sourceFormat, to: job.target)
            }
            let engine = PandocEngine(executablePath: pandoc)
            try engine.convert(from: src, to: dst,
                               srcFormat: job.sourceFormat, dstFormat: job.target)
        }
        return dst
    }

    /// Where a conversion writes by default: same directory as the source,
    /// same stem, target extension. Collision-safe: appends " 2", " 3"...
    func defaultOutput(for src: URL, target: FileFormat) -> URL {
        let dir = src.deletingLastPathComponent()
        let stem = src.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem).\(target.fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(n).\(target.fileExtension)")
            n += 1
        }
        return candidate
    }
}
