import Foundation
import AppKit

/// Persists a single reusable signature PNG in Application Support so the
/// user only draws it once. Bundle-id-scoped path so it doesn't collide
/// with anyone else's signature blobs.
enum SignatureStore {
    static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FormatC")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("signature.png")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: storageURL.path)
    }

    static func load() -> NSImage? {
        guard exists else { return nil }
        return NSImage(contentsOf: storageURL)
    }

    static func save(_ image: NSImage) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SignatureStore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot encode signature as PNG"])
        }
        try png.write(to: storageURL)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: storageURL)
    }
}
