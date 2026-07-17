import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PDFKit

/// Batch PDF tools: Compress, Number, Crop. Sub-picker at the top switches
/// between them; each shares the same drop zone on the left and result
/// panel on the right. Interactive editing (sign / add text / edit text)
/// lives in InteractiveEditorView on its own tab because it needs the whole
/// right pane for the PDF preview.
struct EditPDFView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case compress = "Compress"
        case number   = "Number"
        case crop     = "Crop"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .compress
    @State private var pdf: URL?
    @State private var pageCount: Int = 0
    @State private var lastResult: URL?
    @State private var lastResultDetail: String?
    @State private var errorMessage: String?
    @State private var isRunning = false

    // Compress
    @State private var quality: PDFCompressor.Quality = .medium

    // Number
    @State private var startPage: Int = 1
    @State private var format: String = "%d"
    @State private var position: PDFNumberer.Position = .bottomCenter

    // Crop (in points)
    @State private var marginTop: Double = 36
    @State private var marginRight: Double = 36
    @State private var marginBottom: Double = 36
    @State private var marginLeft: Double = 36

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider().overlay(Tokens.Color.border)
            // maxHeight: .infinity here is what stops the mode picker
            // from shifting when controls below grow or shrink — without
            // it, the HStack collapses to intrinsic height and the whole
            // VStack repacks each time.
            HStack(alignment: .top, spacing: 0) {
                leftPane
                    .frame(width: 340, alignment: .top)
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
    }

    private var modePicker: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            Spacer()
        }
        .padding(.horizontal, Tokens.Space.lg)
        .padding(.vertical, Tokens.Space.sm)
    }

    // MARK: - Left pane: drop + controls + run

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            dropZone
            controls
            runButton
            if let msg = errorMessage {
                Text(msg)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.err)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var dropZone: some View {
        DropZone(kinds: [.pdf]) { urls in
            loadPDF(urls.first)
        } label: {
            VStack(spacing: Tokens.Space.sm) {
                Image(systemName: iconForMode)
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
    }

    private var iconForMode: String {
        switch mode {
        case .compress: return "arrow.down.to.line.compact"
        case .number:   return "number.square"
        case .crop:     return "crop"
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch mode {
        case .compress: compressControls
        case .number:   numberControls
        case .crop:     cropControls
        }
    }

    private var compressControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Quality")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
            Picker("Quality", selection: $quality) {
                ForEach(PDFCompressor.Quality.allCases) { q in
                    Text(q.displayName).tag(q)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text("Re-renders each page at the chosen DPI. Great for scanned/image-heavy PDFs — text-only PDFs can grow.")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var numberControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            HStack {
                Text("Position").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Spacer()
                Picker("", selection: $position) {
                    ForEach(PDFNumberer.Position.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
            }
            HStack {
                Text("Start at").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Stepper("\(startPage)", value: $startPage, in: 1...9999).labelsHidden()
                Text("\(startPage)").font(Tokens.Font.mono).frame(width: 40)
            }
            HStack {
                Text("Format").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                TextField("%d", text: $format)
                    .font(Tokens.Font.mono)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Tokens: %d = number, %t = total. e.g. \"%d of %t\" → \"3 of 12\".")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cropControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Trim margins (points; 72 pt ≈ 1 inch)")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
            marginField("Top",    value: $marginTop)
            marginField("Bottom", value: $marginBottom)
            marginField("Left",   value: $marginLeft)
            marginField("Right",  value: $marginRight)
        }
    }

    private func marginField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.text)
                .frame(width: 50, alignment: .leading)
            Slider(value: value, in: 0...144, step: 6)
            Text("\(Int(value.wrappedValue))")
                .font(Tokens.Font.mono)
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(Tokens.Color.textDim)
        }
    }

    private var runButton: some View {
        Button(action: run) {
            HStack {
                Spacer()
                Text(runLabel).font(Tokens.Font.title)
                Spacer()
            }
            .padding(.vertical, Tokens.Space.md)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canRun)
    }

    private var runLabel: String {
        if isRunning { return "Working…" }
        switch mode {
        case .compress: return "Compress"
        case .number:   return "Number pages"
        case .crop:     return "Crop pages"
        }
    }

    private var canRun: Bool { pdf != nil && !isRunning }

    // MARK: - Right pane: results

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("Output").font(Tokens.Font.title)
                Spacer()
                if let out = lastResult {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([out])
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tokens.Color.accent)
                }
            }

            if let out = lastResult {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Tokens.Color.ok)
                        Text(out.lastPathComponent)
                            .font(Tokens.Font.body)
                    }
                    if let detail = lastResultDetail {
                        Text(detail)
                            .font(Tokens.Font.caption)
                            .foregroundStyle(Tokens.Color.textDim)
                    }
                    Text(out.path)
                        .font(Tokens.Font.mono)
                        .foregroundStyle(Tokens.Color.textFaint)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(Tokens.Space.md)
                .background(Tokens.Color.surfaceRaised)
                .cornerRadius(Tokens.Radius.md)
                Spacer()
            } else {
                VStack(spacing: Tokens.Space.sm) {
                    Image(systemName: "doc")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(Tokens.Color.textFaint)
                    Text(pdf == nil ? "Drop a PDF on the left." : "Ready — hit \(runLabel).")
                        .font(Tokens.Font.body)
                        .foregroundStyle(Tokens.Color.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func loadPDF(_ url: URL?) {
        guard let url, let doc = PDFDocument(url: url) else {
            errorMessage = "Cannot open that PDF"
            return
        }
        pdf = url
        pageCount = doc.pageCount
        lastResult = nil
        lastResultDetail = nil
        errorMessage = nil
    }

    private func run() {
        guard let pdf else { return }
        errorMessage = nil
        lastResult = nil
        lastResultDetail = nil

        let out = defaultOutputURL(for: pdf, suffix: suffixForMode)
        let mode = self.mode
        let quality = self.quality
        let start = self.startPage
        let position = self.position
        let format = self.format
        let top = CGFloat(marginTop)
        let right = CGFloat(marginRight)
        let bottom = CGFloat(marginBottom)
        let left = CGFloat(marginLeft)
        let srcURL = pdf
        isRunning = true

        Task.detached(priority: .userInitiated) {
            do {
                let detail: String?
                switch mode {
                case .compress:
                    let before = PDFCompressor.fileSize(srcURL)
                    try PDFCompressor.compress(srcURL, to: out, quality: quality)
                    let after = PDFCompressor.fileSize(out)
                    detail = formatSize(before: before, after: after)
                case .number:
                    try PDFNumberer.addPageNumbers(
                        to: srcURL, output: out,
                        startAt: start, position: position, format: format
                    )
                    detail = nil
                case .crop:
                    try PDFCropper.crop(
                        srcURL, to: out,
                        top: top, right: right, bottom: bottom, left: left
                    )
                    detail = nil
                }
                let finalDetail = detail
                await MainActor.run {
                    isRunning = false
                    lastResult = out
                    lastResultDetail = finalDetail
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var suffixForMode: String {
        switch mode {
        case .compress: return "compressed"
        case .number:   return "numbered"
        case .crop:     return "cropped"
        }
    }

    private func defaultOutputURL(for src: URL, suffix: String) -> URL {
        let dir = src.deletingLastPathComponent()
        let stem = src.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem)_\(suffix).pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)_\(suffix) \(n).pdf")
            n += 1
        }
        return candidate
    }
}

/// Human-readable "before → after (Δ%)" size line for the compress result.
private func formatSize(before: UInt64, after: UInt64) -> String {
    let fmt = ByteCountFormatter()
    fmt.countStyle = .file
    let b = fmt.string(fromByteCount: Int64(before))
    let a = fmt.string(fromByteCount: Int64(after))
    guard before > 0 else { return "\(b) → \(a)" }
    let delta = Double(after) / Double(before) - 1.0
    let pct = Int(delta * 100)
    let sign = pct >= 0 ? "+" : ""
    return "\(b) → \(a) (\(sign)\(pct)%)"
}
