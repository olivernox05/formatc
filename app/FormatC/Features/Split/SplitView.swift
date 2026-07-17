import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PDFKit

struct SplitView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case perPage = "One file per page"
        case range = "Extract page range"
        var id: String { rawValue }
    }

    @State private var pdf: URL?
    @State private var pageCount: Int = 0
    @State private var mode: Mode = .perPage
    @State private var fromPage: Int = 1
    @State private var toPage: Int = 1
    @State private var isSplitting = false
    @State private var errorMessage: String?
    @State private var results: [URL] = []

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
            DropZone(kinds: [.pdf]) { urls in
                loadPDF(urls.first)
            } label: {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 26, weight: .light))
                    Text(pdf == nil ? "Drop a PDF" : "\(pageCount) pages")
                        .font(Tokens.Font.title)
                    if let pdf {
                        Text(pdf.lastPathComponent)
                            .font(Tokens.Font.caption)
                            .foregroundStyle(Tokens.Color.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding()
            }

            if pdf != nil {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if mode == .range {
                    HStack(spacing: Tokens.Space.sm) {
                        Stepper("From \(fromPage)", value: $fromPage, in: 1...pageCount)
                            .labelsHidden()
                        Text("\(fromPage)")
                            .font(Tokens.Font.mono)
                            .frame(width: 32)
                        Text("→").foregroundStyle(Tokens.Color.textDim)
                        Stepper("To \(toPage)", value: $toPage, in: fromPage...pageCount)
                            .labelsHidden()
                        Text("\(toPage)")
                            .font(Tokens.Font.mono)
                            .frame(width: 32)
                    }
                    .font(Tokens.Font.caption)
                }
            }

            Button(action: split) {
                HStack {
                    Spacer()
                    Text(buttonLabel).font(Tokens.Font.title)
                    Spacer()
                }
                .padding(.vertical, Tokens.Space.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pdf == nil || isSplitting)

            if let msg = errorMessage {
                Text(msg)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.err)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("Output").font(Tokens.Font.title)
                Spacer()
                if !results.isEmpty {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(results)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tokens.Color.accent)
                }
            }
            if results.isEmpty {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(Tokens.Color.textFaint)
                    Text(pdf == nil
                         ? "Drop a PDF on the left."
                         : "Ready — hit \(buttonLabel).")
                        .font(Tokens.Font.body)
                        .foregroundStyle(Tokens.Color.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(results, id: \.self) { url in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Tokens.Color.ok)
                                Text(url.lastPathComponent)
                                    .font(Tokens.Font.mono)
                                    .foregroundStyle(Tokens.Color.text)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var buttonLabel: String {
        switch mode {
        case .perPage: return isSplitting ? "Splitting…" : "Split all pages"
        case .range:   return isSplitting ? "Extracting…" : "Extract pages"
        }
    }

    private func loadPDF(_ url: URL?) {
        guard let url, let doc = PDFDocument(url: url) else {
            errorMessage = "Cannot open that PDF"
            return
        }
        pdf = url
        pageCount = doc.pageCount
        fromPage = 1
        toPage = max(1, doc.pageCount)
        results = []
        errorMessage = nil
    }

    private func split() {
        guard let pdf else { return }
        errorMessage = nil

        switch mode {
        case .perPage:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Save Here"
            panel.directoryURL = pdf.deletingLastPathComponent()
            panel.message = "Choose a folder to save the split pages"
            panel.begin { response in
                guard response == .OK, let dir = panel.url else { return }
                runOnBackground {
                    try PDFOps.split(pdf, into: dir)
                }
            }

        case .range:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let stem = pdf.deletingPathExtension().lastPathComponent
            panel.nameFieldStringValue = "\(stem) p\(fromPage)-\(toPage).pdf"
            panel.directoryURL = pdf.deletingLastPathComponent()
            let from = fromPage, to = toPage
            panel.begin { response in
                guard response == .OK, let outURL = panel.url else { return }
                runOnBackground {
                    try [PDFOps.extractRange(pdf, pages: from...to, into: outURL)]
                }
            }
        }
    }

    private func runOnBackground(_ work: @escaping () throws -> [URL]) {
        isSplitting = true
        Task.detached(priority: .userInitiated) {
            do {
                let out = try work()
                await MainActor.run {
                    isSplitting = false
                    results = out
                }
            } catch {
                await MainActor.run {
                    isSplitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
