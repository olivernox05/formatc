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

    /// pandoc's reader (-f) token. Asymmetric with the writer because
    /// pandoc has no "plain text" reader — plain-text files are just
    /// read as markdown, which is a safe superset.
    static func pandocReader(_ format: FileFormat) -> String? {
        switch format {
        case .markdown, .txt: return "markdown"
        case .html:  return "html"
        case .docx:  return "docx"
        case .rtf:   return "rtf"
        case .odt:   return "odt"
        case .epub:  return "epub"
        case .tex:   return "latex"
        default:     return nil       // PDF and images have no pandoc reader
        }
    }

    /// pandoc's writer (-t) token. "plain" writes flat text with markdown
    /// stripped, which is what a TXT target should produce.
    static func pandocWriter(_ format: FileFormat) -> String? {
        switch format {
        case .markdown: return "markdown"
        case .txt:      return "plain"
        case .html:     return "html"
        case .docx:     return "docx"
        case .rtf:      return "rtf"
        case .odt:      return "odt"
        case .epub:     return "epub"
        case .tex:      return "latex"
        case .pdf:      return "pdf"
        default:        return nil     // images can't be a pandoc target
        }
    }

    static func canConvert(from: FileFormat, to: FileFormat) -> Bool {
        // Route PDF→text through pdf2md, not pandoc — pandoc's PDF reader
        // loses tables and mangles code blocks. Keep only PDF→DOCX here for
        // the rare DOCX-only need.
        if from == .pdf && to != .docx { return false }
        if !from.isText && from != .pdf { return false }
        if !to.isText && to != .pdf { return false }
        // TXT is output-only in this wrapper (pandoc reads txt as-is but
        // it's usually more useful to route txt→pdf via a real doc format).
        // Actually — pandoc handles txt fine. Allow.
        return true
    }

    func convert(from src: URL, to dst: URL, srcFormat: FileFormat, dstFormat: FileFormat) throws {
        guard let inFmt = Self.pandocReader(srcFormat),
              let outFmt = Self.pandocWriter(dstFormat) else {
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
        // GUI-launched apps get a minimal PATH that omits everywhere TeX
        // Live installs its binaries. Pandoc then can't find xelatex even
        // when it's installed. Extend PATH so the common install
        // locations (MacTeX/BasicTeX at /Library/TeX/texbin, Homebrew,
        // custom TeX Live) are all searchable.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/Library/TeX/texbin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        env["PATH"] = ([env["PATH"] ?? ""] + extraPaths)
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        p.environment = env

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
