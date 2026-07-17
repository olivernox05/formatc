import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct BackgroundRemoveView: View {
    struct Result: Identifiable, Hashable {
        let id = UUID()
        let source: URL
        let output: URL
    }

    @State private var pending: [URL] = []
    @State private var results: [Result] = []
    @State private var failed: [(URL, String)] = []
    @State private var isRunning = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftPane
                .frame(width: 320, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(Tokens.Space.lg)
                .background(Tokens.Color.surface)
            Divider().overlay(Tokens.Color.border)
            rightPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(Tokens.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DropZone(kinds: [.png, .jpeg, .heic, .webP, .tiff, .gif, .bmp]) { urls in
                pending = urls
            } label: {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "person.and.background.dotted")
                        .font(.system(size: 26, weight: .light))
                    Text(pending.isEmpty
                         ? "Drop image(s)"
                         : "\(pending.count) image\(pending.count == 1 ? "" : "s") ready")
                        .font(Tokens.Font.title)
                    Text("Uses Apple's on-device subject isolation")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.textDim)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding()
            }

            Button(action: run) {
                HStack {
                    Spacer()
                    Text(isRunning ? "Working…" : "Remove background")
                        .font(Tokens.Font.title)
                    Spacer()
                }
                .padding(.vertical, Tokens.Space.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pending.isEmpty || isRunning)

            Text("Output is always a transparent PNG next to the source.")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("Results").font(Tokens.Font.title)
                Spacer()
                if !results.isEmpty {
                    Button("Show all in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(results.map(\.output))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tokens.Color.accent)
                }
            }

            if results.isEmpty && failed.isEmpty {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(Tokens.Color.textFaint)
                    Text("Drop images on the left, hit Remove background.")
                        .font(Tokens.Font.body)
                        .foregroundStyle(Tokens.Color.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.sm) {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                        ForEach(failed, id: \.0) { url, msg in
                            failureRow(url, msg)
                        }
                    }
                }
            }
        }
    }

    private func resultRow(_ result: Result) -> some View {
        HStack(spacing: Tokens.Space.md) {
            thumbnail(result.output)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.source.lastPathComponent)
                    .font(Tokens.Font.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.output.lastPathComponent)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textDim)
            }
            Spacer()
            Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([result.output]) }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.Color.accent)
        }
        .padding(Tokens.Space.sm)
        .background(Tokens.Color.surfaceRaised)
        .cornerRadius(Tokens.Radius.md)
    }

    private func failureRow(_ url: URL, _ msg: String) -> some View {
        HStack(spacing: Tokens.Space.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tokens.Color.err)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(Tokens.Font.body)
                    .lineLimit(1)
                Text(msg)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.err)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(Tokens.Space.sm)
        .background(Tokens.Color.surfaceRaised)
        .cornerRadius(Tokens.Radius.md)
    }

    @ViewBuilder
    private func thumbnail(_ url: URL) -> some View {
        if let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .background(
                    // Chessboard so the transparency is visible.
                    Image(systemName: "checkerboard.shield")
                        .resizable().opacity(0.05)
                )
                .cornerRadius(4)
        } else {
            Rectangle().frame(width: 48, height: 48).foregroundStyle(Tokens.Color.border)
        }
    }

    private func run() {
        guard !pending.isEmpty else { return }
        let jobs = pending
        pending = []
        results.removeAll()
        failed.removeAll()
        isRunning = true

        Task.detached(priority: .userInitiated) {
            var ok: [Result] = []
            var bad: [(URL, String)] = []
            for src in jobs {
                let dst = Self.outputURL(for: src)
                do {
                    try BackgroundRemover.removeBackground(from: src, to: dst)
                    ok.append(Result(source: src, output: dst))
                } catch {
                    bad.append((src, error.localizedDescription))
                }
            }
            let finalOk = ok
            let finalBad = bad
            await MainActor.run {
                results = finalOk
                failed = finalBad
                isRunning = false
            }
        }
    }

    private nonisolated static func outputURL(for src: URL) -> URL {
        let dir = src.deletingLastPathComponent()
        let stem = src.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem)_nobg.png")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)_nobg \(n).png")
            n += 1
        }
        return candidate
    }
}
