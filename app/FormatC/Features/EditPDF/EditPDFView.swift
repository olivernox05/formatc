import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PDFKit

/// One tab that gathers the "modify a PDF in place" tools: Compress,
/// Number, Crop, Sign, and Add text. Sub-picker at the top switches
/// between them; each shares the same drop zone on the left and result
/// panel on the right.
struct EditPDFView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case compress = "Compress"
        case number   = "Number"
        case crop     = "Crop"
        case sign     = "Sign"
        case addText  = "Add text"
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

    // Sign
    @State private var signPage: Int = 1
    @State private var signAnchor: PDFAnchor = .bottomRight
    @State private var signScale: Double = 0.25
    @State private var hasSignature: Bool = SignatureStore.exists
    @State private var showingSignatureCapture = false

    // Add text
    @State private var textPage: Int = 1
    @State private var textContent: String = ""
    @State private var textAnchor: PDFAnchor = .topCenter
    @State private var textFontSize: Double = 14
    @State private var textWhiteCover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider().overlay(Tokens.Color.border)
            HStack(alignment: .top, spacing: 0) {
                leftPane
                    .frame(width: 340)
                    .padding(Tokens.Space.lg)
                    .background(Tokens.Color.surface)
                Divider().overlay(Tokens.Color.border)
                rightPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Tokens.Space.lg)
            }
        }
        .sheet(isPresented: $showingSignatureCapture) {
            SignatureCaptureView(onSaved: {
                hasSignature = true
            })
        }
    }

    private var modePicker: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(width: 460)
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
        case .sign:     return "signature"
        case .addText:  return "text.cursor"
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch mode {
        case .compress: compressControls
        case .number:   numberControls
        case .crop:     cropControls
        case .sign:     signControls
        case .addText:  addTextControls
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

    private var signControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            signaturePreview
            HStack {
                Text("Page").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Stepper("\(signPage)", value: $signPage, in: 1...max(1, pageCount)).labelsHidden()
                Text("\(signPage) / \(pageCount)").font(Tokens.Font.mono).frame(width: 60)
            }
            HStack {
                Text("Corner").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Spacer()
                Picker("", selection: $signAnchor) {
                    ForEach(PDFAnchor.allCases) { a in Text(a.displayName).tag(a) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 150)
            }
            HStack {
                Text("Size").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Slider(value: $signScale, in: 0.10...0.50, step: 0.05)
                Text("\(Int(signScale * 100))%").font(Tokens.Font.mono).frame(width: 40)
            }
        }
    }

    private var signaturePreview: some View {
        HStack(spacing: Tokens.Space.sm) {
            if hasSignature, let img = SignatureStore.load() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 44)
                    .padding(4)
                    .background(Color.white)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.Color.border))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signature saved")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.text)
                    Button("Redraw…") { showingSignatureCapture = true }
                        .buttonStyle(.borderless)
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.accent)
                }
                Spacer()
            } else {
                Button {
                    showingSignatureCapture = true
                } label: {
                    HStack {
                        Image(systemName: "signature")
                        Text("Draw your signature…")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tokens.Space.sm)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var addTextControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text("Text")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
            TextField("Text to add", text: $textContent, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Text("Page").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Stepper("\(textPage)", value: $textPage, in: 1...max(1, pageCount)).labelsHidden()
                Text("\(textPage) / \(pageCount)").font(Tokens.Font.mono).frame(width: 60)
            }
            HStack {
                Text("Position").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Spacer()
                Picker("", selection: $textAnchor) {
                    ForEach(PDFAnchor.allCases) { a in Text(a.displayName).tag(a) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 150)
            }
            HStack {
                Text("Size").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Slider(value: $textFontSize, in: 8...48, step: 1)
                Text("\(Int(textFontSize))pt").font(Tokens.Font.mono).frame(width: 40)
            }
            Toggle(isOn: $textWhiteCover) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cover underneath with a white box")
                        .font(Tokens.Font.caption)
                    Text("Use this to \"replace\" existing text — paints white, then overlays yours.")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.textFaint)
                }
            }
            .toggleStyle(.checkbox)
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
        case .sign:     return "Sign PDF"
        case .addText:  return "Add text"
        }
    }

    private var canRun: Bool {
        guard pdf != nil, !isRunning else { return false }
        switch mode {
        case .sign:    return hasSignature
        case .addText: return !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:       return true
        }
    }

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
        // Default signatures to the last page (typical) and added text to
        // the first page. User can override.
        signPage = doc.pageCount
        textPage = 1
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
        let sigPage = self.signPage
        let sigAnchorLocal = self.signAnchor
        let sigScaleLocal = CGFloat(self.signScale)
        let sigURL = SignatureStore.storageURL
        let txtPage = self.textPage
        let txtContent = self.textContent
        let txtAnchorLocal = self.textAnchor
        let txtFontSize = CGFloat(self.textFontSize)
        let txtCover = self.textWhiteCover
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
                case .sign:
                    try PDFOverlay.addSignature(
                        to: srcURL, output: out,
                        page: sigPage, signature: sigURL,
                        anchor: sigAnchorLocal, scale: sigScaleLocal
                    )
                    detail = nil
                case .addText:
                    try PDFOverlay.addText(
                        to: srcURL, output: out,
                        page: txtPage, text: txtContent,
                        anchor: txtAnchorLocal, fontSize: txtFontSize,
                        whiteCover: txtCover
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
        case .sign:     return "signed"
        case .addText:  return "edited"
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
