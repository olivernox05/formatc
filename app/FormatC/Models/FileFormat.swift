import Foundation
import UniformTypeIdentifiers

enum FileFormat: String, CaseIterable, Identifiable, Hashable {
    case pdf
    case markdown
    case html
    case docx
    case png
    case jpeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .docx: return "Word (.docx)"
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .html: return "html"
        case .docx: return "docx"
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: return .pdf
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .html: return .html
        case .docx: return UTType(filenameExtension: "docx") ?? .data
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    static func from(url: URL) -> FileFormat? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm": return .html
        case "docx": return .docx
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        default: return nil
        }
    }

    /// Formats we let the user *convert into* for a given source.
    /// The dispatcher rejects any pair it can't actually service; this is
    /// only the UI whitelist.
    func supportedTargets() -> [FileFormat] {
        switch self {
        case .pdf:
            return [.markdown, .docx, .png, .html]
        case .markdown:
            return [.html, .pdf, .docx]
        case .html:
            return [.markdown, .pdf, .docx]
        case .docx:
            return [.pdf, .markdown, .html]
        case .png, .jpeg:
            return [.pdf]
        }
    }
}
