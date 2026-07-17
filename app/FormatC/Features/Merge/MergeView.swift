import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MergeView: View {
    @State private var pdfs: [URL] = []
    @State private var isMerging = false
    @State private var lastResult: URL?
    @State private var errorMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftPane
                .frame(width: 320)
                .padding(Tokens.Space.lg)
                .background(Tokens.Color.surface)
            Divider().overlay(Tokens.Color.border)
            rightPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Tokens.Space.lg)
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            DropZone(kinds: [.pdf]) { urls in
                pdfs.append(contentsOf: urls.filter { $0.pathExtension.lowercased() == "pdf" })
            } label: {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 26, weight: .light))
                    Text(pdfs.isEmpty ? "Drop PDFs to merge" : "\(pdfs.count) PDF\(pdfs.count == 1 ? "" : "s") queued")
                        .font(Tokens.Font.title)
                    Text("Drag to reorder in the list →")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.textDim)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding()
            }

            Button(action: merge) {
                HStack {
                    Spacer()
                    Text(isMerging ? "Merging…" : "Merge \(pdfs.count) → 1")
                        .font(Tokens.Font.title)
                    Spacer()
                }
                .padding(.vertical, Tokens.Space.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pdfs.count < 2 || isMerging)

            if let msg = errorMessage {
                Text(msg)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.err)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let out = lastResult {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.Color.accent)
            }

            Spacer()
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("Order").font(Tokens.Font.title)
                Spacer()
                if !pdfs.isEmpty {
                    Button("Clear") { pdfs.removeAll(); lastResult = nil; errorMessage = nil }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Tokens.Color.textDim)
                }
            }

            if pdfs.isEmpty {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(Tokens.Color.textFaint)
                    Text("Drop 2 or more PDFs to combine them.")
                        .font(Tokens.Font.body)
                        .foregroundStyle(Tokens.Color.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(pdfs, id: \.self) { url in
                        HStack {
                            Text("\((pdfs.firstIndex(of: url) ?? 0) + 1).")
                                .font(Tokens.Font.mono)
                                .foregroundStyle(Tokens.Color.textDim)
                                .frame(width: 24, alignment: .trailing)
                            Text(url.lastPathComponent)
                                .font(Tokens.Font.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                pdfs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Tokens.Color.textFaint)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { indices, newOffset in
                        pdfs.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func merge() {
        guard pdfs.count >= 2 else { return }
        isMerging = true
        errorMessage = nil
        lastResult = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Combined.pdf"
        panel.canCreateDirectories = true
        panel.directoryURL = pdfs.first?.deletingLastPathComponent()

        panel.begin { response in
            guard response == .OK, let outputURL = panel.url else {
                isMerging = false
                return
            }
            let inputs = pdfs
            Task.detached(priority: .userInitiated) {
                do {
                    try PDFOps.merge(inputs, into: outputURL)
                    await MainActor.run {
                        isMerging = false
                        lastResult = outputURL
                    }
                } catch {
                    await MainActor.run {
                        isMerging = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
