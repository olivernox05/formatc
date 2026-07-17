import Foundation
import UniformTypeIdentifiers

enum FileFormat: String, CaseIterable, Identifiable, Hashable {
    // Documents
    case pdf
    case markdown
    case html
    case docx
    case rtf
    case odt
    case epub
    case txt
    case tex     // LaTeX
    // Images
    case png
    case jpeg
    case webp
    case heic
    case tiff
    case gif
    case bmp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf:      return "PDF"
        case .markdown: return "Markdown"
        case .html:     return "HTML"
        case .docx:     return "Word (.docx)"
        case .rtf:      return "Rich Text (.rtf)"
        case .odt:      return "OpenDocument (.odt)"
        case .epub:     return "EPUB"
        case .txt:      return "Plain Text"
        case .tex:      return "LaTeX"
        case .png:      return "PNG"
        case .jpeg:     return "JPEG"
        case .webp:     return "WebP"
        case .heic:     return "HEIC"
        case .tiff:     return "TIFF"
        case .gif:      return "GIF"
        case .bmp:      return "BMP"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf:      return "pdf"
        case .markdown: return "md"
        case .html:     return "html"
        case .docx:     return "docx"
        case .rtf:      return "rtf"
        case .odt:      return "odt"
        case .epub:     return "epub"
        case .txt:      return "txt"
        case .tex:      return "tex"
        case .png:      return "png"
        case .jpeg:     return "jpg"
        case .webp:     return "webp"
        case .heic:     return "heic"
        case .tiff:     return "tiff"
        case .gif:      return "gif"
        case .bmp:      return "bmp"
        }
    }

    var utType: UTType {
        switch self {
        case .pdf:      return .pdf
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .html:     return .html
        case .docx:     return UTType(filenameExtension: "docx") ?? .data
        case .rtf:      return .rtf
        case .odt:      return UTType(filenameExtension: "odt") ?? .data
        case .epub:     return UTType(filenameExtension: "epub") ?? .data
        case .txt:      return .plainText
        case .tex:      return UTType(filenameExtension: "tex") ?? .plainText
        case .png:      return .png
        case .jpeg:     return .jpeg
        case .webp:     return .webP
        case .heic:     return .heic
        case .tiff:     return .tiff
        case .gif:      return .gif
        case .bmp:      return .bmp
        }
    }

    static func from(url: URL) -> FileFormat? {
        switch url.pathExtension.lowercased() {
        case "pdf":                          return .pdf
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm":                  return .html
        case "docx":                         return .docx
        case "rtf":                          return .rtf
        case "odt":                          return .odt
        case "epub":                         return .epub
        case "txt", "text":                  return .txt
        case "tex", "latex":                 return .tex
        case "png":                          return .png
        case "jpg", "jpeg":                  return .jpeg
        case "webp":                         return .webp
        case "heic", "heif":                 return .heic
        case "tif", "tiff":                  return .tiff
        case "gif":                          return .gif
        case "bmp":                          return .bmp
        default:                             return nil
        }
    }

    /// Categorical grouping used by the routing tables below.
    var isText: Bool {
        switch self {
        case .markdown, .html, .docx, .rtf, .odt, .epub, .txt, .tex: return true
        default: return false
        }
    }

    var isImage: Bool {
        switch self {
        case .png, .jpeg, .webp, .heic, .tiff, .gif, .bmp: return true
        default: return false
        }
    }

    /// Formats we let the user *convert into* for a given source. The
    /// dispatcher rejects any pair it can't actually service; this is only
    /// the UI whitelist.
    func supportedTargets() -> [FileFormat] {
        let allTexts: [FileFormat] = [.pdf, .markdown, .html, .docx, .rtf, .odt, .epub, .txt, .tex]
        let allImages: [FileFormat] = [.png, .jpeg, .webp, .heic, .tiff, .gif, .bmp]

        if self == .pdf {
            // PDF is both — text (via pdf2md/pandoc) and rasterizable to PNG.
            return [.markdown, .docx, .html, .txt, .png]
        }
        if isText {
            return allTexts.filter { $0 != self }
        }
        if isImage {
            return allImages.filter { $0 != self } + [.pdf]
        }
        return []
    }
}
