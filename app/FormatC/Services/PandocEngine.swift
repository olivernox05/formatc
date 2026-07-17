import Foundation

enum PandocEngineError: LocalizedError {
    case notInstalled
    case failed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "pandoc is not installed. Run: brew install pandoc"
        case .failed(let status, let stderr):
            return "pandoc failed (exit \(status)):\n\(stderr)"
        }
    }
}

/// pandoc subprocess wrapper. All conversions go input→output as files;
/// stdin/stdout piping would let us avoid the temp write but tables the size
/// of a Word doc chew through a pipe buffer, so we stick with files.
struct PandocEngine {
    let executablePath: String

    /// pandoc format tokens for its `-f` / `-t` flags.
    static func pandocFormat(_ format: FileFormat) -> String? {
        switch format {
        case .markdown: return "markdown"
        case .html: return "html"
        case .docx: return "docx"
        case .pdf: return "pdf"       // only valid as output target
        case .png, .jpeg: return nil  // not text; pandoc doesn't handle these
        }
    }

    static func canConvert(from: FileFormat, to: FileFormat) -> Bool {
        // PDF is output-only for pandoc; images are not text.
        if from == .pdf && to != .docx { return false }
        // pandoc technically reads PDF via a wrapper, but the round-trip
        // quality is bad. Route PDF→text conversions through pdf2md
        // instead. Keep just PDF→DOCX here for the rare DOCX-only need.
        if from == .png || from == .jpeg { return false }
        if to == .png || to == .jpeg { return false }
        return true
    }

    func convert(from src: URL, to dst: URL, srcFormat: FileFormat, dstFormat: FileFormat) throws {
        guard let inFmt = Self.pandocFormat(srcFormat),
              let outFmt = Self.pandocFormat(dstFormat) else {
            throw PandocEngineError.failed(status: -1, stderr: "unsupported format pair")
        }
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var args: [String] = [
            "-f", inFmt,
            "-t", outFmt,
            src.path,
            "-o", dst.path,
        ]

        // MD → HTML defaults to a fragment; standalone HTML with a <head> is
        // more useful when the user double-clicks the output.
        if dstFormat == .html {
            args.insert("--standalone", at: 0)
        }
        // MD/HTML → PDF requires a LaTeX engine. Prefer xelatex where
        // available; pandoc's default is pdflatex, which chokes on unicode.
        if dstFormat == .pdf {
            args.insert(contentsOf: ["--pdf-engine=xelatex"], at: 0)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            throw PandocEngineError.failed(status: p.terminationStatus, stderr: stderr)
        }
    }
}
