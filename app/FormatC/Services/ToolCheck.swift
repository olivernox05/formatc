import Foundation
import Observation

/// Runtime probe for the CLIs FormatC shells out to. Detects at launch so
/// the UI can show which conversion pairs work and which need install.
///
/// Homebrew binaries are not on the GUI-launched app's default PATH, so we
/// probe explicit absolute paths rather than trusting `which`.
@Observable
final class ToolCheck {
    struct Tool: Hashable {
        var name: String
        var path: String?
        var version: String?
        var isAvailable: Bool { path != nil }
    }

    var pandoc = Tool(name: "pandoc")
    var python3 = Tool(name: "python3")
    var pdf2mdEngine: String? // "pymupdf4llm" / "plumber" / nil

    private static let candidatePaths: [String: [String]] = [
        "pandoc": [
            "/opt/homebrew/bin/pandoc",
            "/usr/local/bin/pandoc",
            "/usr/bin/pandoc",
        ],
        "python3": [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ],
    ]

    func refresh() {
        pandoc = probe("pandoc")
        python3 = probe("python3")
        pdf2mdEngine = probePdf2mdEngine()
    }

    private func probe(_ name: String) -> Tool {
        for candidate in Self.candidatePaths[name] ?? [] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                let version = runCapture(candidate, ["--version"])?
                    .split(separator: "\n").first.map(String.init)
                return Tool(name: name, path: candidate, version: version)
            }
        }
        return Tool(name: name)
    }

    private func probePdf2mdEngine() -> String? {
        guard let py = python3.path,
              let script = Bundle.main.url(forResource: "pdf2md", withExtension: "py") else {
            return nil
        }
        // Ask the script's helper via a one-liner. It's cheaper than the
        // full script and avoids the "no PDF given" exit branch.
        let code = """
        import importlib
        for name in ("pymupdf4llm", "pdfplumber"):
            if importlib.util.find_spec(name):
                print("pymupdf4llm" if name == "pymupdf4llm" else "plumber"); break
        """
        _ = script
        return runCapture(py, ["-c", code])?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func runCapture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
