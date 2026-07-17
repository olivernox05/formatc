import Foundation

struct ConversionJob: Identifiable, Hashable {
    enum Status: Hashable {
        case queued
        case running
        case done(URL)
        case failed(String)
    }

    let id = UUID()
    let source: URL
    let sourceFormat: FileFormat
    let target: FileFormat
    var status: Status = .queued

    var displayName: String { source.lastPathComponent }
}
