import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageConverterError: LocalizedError {
    case cannotDecode(URL)
    case cannotEncode(FileFormat)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let u): return "Cannot decode \(u.lastPathComponent)"
        case .cannotEncode(let f): return "Cannot encode as \(f.displayName) on this macOS"
        case .cannotWrite(let u):  return "Cannot write \(u.path)"
        }
    }
}

/// Image ↔ image conversion via Core Graphics / ImageIO. Every macOS
/// image codec (PNG/JPEG/WebP/HEIC/TIFF/GIF/BMP) is available here
/// without any external tool.
enum ImageConverter {
    /// The UTType most codecs expect. WebP encoding was added in macOS 11
    /// via com.google.webp; on older systems we return nil and the caller
    /// bails.
    static func encodingUTI(for format: FileFormat) -> UTType? {
        switch format {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .webp: return .webP
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif:  return .gif
        case .bmp:  return .bmp
        default:    return nil
        }
    }

    /// Convert a single image file to `target` format. JPEG uses 90%
    /// quality — high enough to be visually lossless for photos, small
    /// enough to be materially smaller than PNG.
    static func convert(from src: URL, to dst: URL, target: FileFormat) throws {
        guard let uti = encodingUTI(for: target) else {
            throw ImageConverterError.cannotEncode(target)
        }
        // ImageIO source: decodes anything Core Graphics knows how to
        // read (PNG/JPEG/WebP/HEIC/TIFF/GIF/BMP/RAW/…).
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageConverterError.cannotDecode(src)
        }
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            dst as CFURL, uti.identifier as CFString, 1, nil
        ) else {
            throw ImageConverterError.cannotWrite(dst)
        }
        // Codec-specific properties: JPEG/HEIC quality, WebP quality.
        // GIF/PNG/TIFF/BMP take image data as-is.
        var props: [CFString: Any] = [:]
        if target == .jpeg || target == .heic || target == .webp {
            props[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw ImageConverterError.cannotWrite(dst)
        }
    }
}
