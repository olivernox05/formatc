import Foundation
import AppKit
import CoreImage
import Vision

enum BackgroundRemoverError: LocalizedError {
    case cannotDecode(URL)
    case noSubjectDetected
    case cannotEncode
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let u):
            return "Cannot decode \(u.lastPathComponent)"
        case .noSubjectDetected:
            return "No subject detected — the image doesn't have a clear foreground the model can isolate. Try a shot with a distinct subject against a background."
        case .cannotEncode:
            return "Cannot encode the output"
        case .cannotWrite(let u):
            return "Cannot write \(u.path)"
        }
    }
}

/// Wraps VNGenerateForegroundInstanceMaskRequest (macOS 14+): Apple's
/// on-device subject-isolation model. No network, no external tool.
///
/// The output is always PNG — the whole point is transparency and the
/// alpha channel needs a lossless container. If the user later wants
/// WebP-with-alpha they can convert the result again via the Convert tab.
enum BackgroundRemover {
    /// Remove the background from `input` and write a transparent PNG to `output`.
    static func removeBackground(from input: URL, to output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BackgroundRemoverError.cannotDecode(input)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw BackgroundRemoverError.noSubjectDetected
        }
        let maskedPixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        // Convert the CVPixelBuffer to a CGImage via CIImage, then encode
        // as PNG. Preserving the alpha channel needs the color space we
        // pass here — sRGB with alpha keeps transparency.
        let ciImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
        let ctx = CIContext(options: nil)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let outCG = ctx.createCGImage(ciImage, from: ciImage.extent,
                                            format: .RGBA8, colorSpace: colorSpace) else {
            throw BackgroundRemoverError.cannotEncode
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            output as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw BackgroundRemoverError.cannotWrite(output)
        }
        CGImageDestinationAddImage(dest, outCG, nil)
        if !CGImageDestinationFinalize(dest) {
            throw BackgroundRemoverError.cannotWrite(output)
        }
    }
}
