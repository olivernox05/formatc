import Foundation

enum PythonScriptEngineError: LocalizedError {
    case pythonMissing
    case scriptMissing
    case engineMissing
    case failed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing: return "python3 is not available."
        case .scriptMissing: return "Bundled pdf2md.py is missing from the app."
        case .engineMissing:
            return "Install a PDF engine:\n  python3 -m pip install --user pymupdf4llm"
        case .failed(let status, let stderr):
            return "pdf2md failed (exit \(status)):\n\(stderr)"
        }
    }
}

/// Wraps the bundled `pdf2md.py` for PDF → Markdown. The pandoc PDF reader
/// is far worse at this specifically (loses tables, mangles code blocks) so
/// PDF→MD always goes through pdf2md, never pandoc.
struct PythonScriptEngine {
    let pythonPath: String
    let pdf2mdEngine: String? // "pymupdf4llm" / "plumber" / nil if none installed

    func pdfToMarkdown(from src: URL, to dst: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw PythonScriptEngineError.pythonMissing
        }
        guard let script = Bundle.main.url(forResource: "pdf2md", withExtension: "py") else {
            throw PythonScriptEngineError.scriptMissing
        }
        guard let engine = pdf2mdEngine else {
            throw PythonScriptEngineError.engineMissing
        }
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments = [
            script.path,
            src.path,
            "-o", dst.path,
            "--engine", engine,
            "-q",
        ]
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            throw PythonScriptEngineError.failed(status: p.terminationStatus, stderr: stderr)
        }
    }
}
