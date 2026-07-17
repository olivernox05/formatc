import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PDFKit

/// Click-to-place PDF editor: sign, add text, edit existing text — all
/// via an interactive PDFView preview on the right. Each mode maintains
/// its own pending list; hitting Save flattens everything to a new PDF.
struct InteractiveEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case sign     = "Sign"
        case addText  = "Add text"
        case editText = "Edit text"
        var id: String { rawValue }
    }

    // Loaded PDF
    @State private var pdfURL: URL?
    @State private var document: PDFDocument?
    @State private var isRunning = false
    @State private var lastResult: URL?
    @State private var errorMessage: String?

    // Mode
    @State private var mode: Mode = .sign
    @State private var showingSignatureCapture = false
    @State private var hasSignature: Bool = SignatureStore.exists

    // Add-text inputs
    @State private var textInput: String = ""
    @State private var addTextFontSize: Double = 14
    @State private var whiteCoverForNew: Bool = false

    // Edit-text state (populated when the user clicks existing text)
    @State private var selectedEditText: PendingEdit?
    @State private var editedFontSize: Double = 12

    // Accumulated placements
    @State private var placements: [PDFPlacement] = []

    // For redraw the annotations on document mutation
    @State private var annotationRefreshID = UUID()

    // Sign scale
    @State private var signScale: Double = 0.25

    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(width: 340, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(Tokens.Space.lg)
                .background(Tokens.Color.surface)
            Divider().overlay(Tokens.Color.border)
            rightPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSignatureCapture) {
            SignatureCaptureView(onSaved: { hasSignature = true })
        }
    }

    // MARK: - Left pane

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            modePicker
            dropZone
            Group {
                switch mode {
                case .sign:     signControls
                case .addText:  addTextControls
                case .editText: editTextControls
                }
            }
            Spacer()
            saveButton
            if let msg = errorMessage {
                Text(msg)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.err)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let out = lastResult {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Tokens.Color.ok)
                        Text("Saved — show in Finder")
                            .font(Tokens.Font.caption)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.Color.accent)
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: mode) { _, _ in
            selectedEditText = nil
        }
    }

    private var dropZone: some View {
        DropZone(kinds: [.pdf]) { urls in
            loadPDF(urls.first)
        } label: {
            VStack(spacing: Tokens.Space.sm) {
                Image(systemName: pdfURL == nil ? "square.and.arrow.down" : "doc.text")
                    .font(.system(size: 22, weight: .light))
                Text(pdfURL?.lastPathComponent ?? "Drop a PDF")
                    .font(Tokens.Font.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Tokens.Color.text)
                if let doc = document {
                    Text("\(doc.pageCount) pages · \(placements.count) placement\(placements.count == 1 ? "" : "s")")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.textDim)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding()
        }
    }

    @ViewBuilder
    private var signControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            if hasSignature, let img = SignatureStore.load() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 44)
                    .padding(4)
                    .background(Color.white)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tokens.Color.border))
                Button("Redraw signature…") { showingSignatureCapture = true }
                    .buttonStyle(.borderless)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.accent)
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

            HStack {
                Text("Size").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Slider(value: $signScale, in: 0.10...0.50, step: 0.05)
                Text("\(Int(signScale * 100))%").font(Tokens.Font.mono).frame(width: 40)
            }

            Text(hasSignature
                 ? "Click anywhere on the preview to place. Click again to move."
                 : "Draw your signature first.")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var addTextControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text("Text")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
            TextField("Type here…", text: $textInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Text("Size").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                Slider(value: $addTextFontSize, in: 8...48, step: 1)
                Text("\(Int(addTextFontSize))pt").font(Tokens.Font.mono).frame(width: 40)
            }
            Toggle("Cover underneath with a white box", isOn: $whiteCoverForNew)
                .toggleStyle(.checkbox)
                .font(Tokens.Font.caption)
            Text("Type your text, then click the preview to place it. Repeat to add more.")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var editTextControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text("Edit existing text")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
            if let edit = selectedEditText {
                Text("Original")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textFaint)
                Text(edit.originalText)
                    .font(Tokens.Font.mono)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.Color.surfaceRaised)
                    .cornerRadius(4)
                Text("Replacement")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textFaint)
                TextField("Type replacement…", text: Binding(
                    get: { selectedEditText?.replacement ?? "" },
                    set: { newValue in
                        selectedEditText?.replacement = newValue
                    }
                ))
                .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Size").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.textDim)
                    Slider(value: $editedFontSize, in: 6...36, step: 1)
                    Text("\(Int(editedFontSize))pt").font(Tokens.Font.mono).frame(width: 40)
                }
                HStack {
                    Button("Commit") { commitEdit() }
                        .buttonStyle(.borderedProminent)
                        .disabled((selectedEditText?.replacement ?? "").isEmpty)
                    Button("Cancel") { selectedEditText = nil }
                }
            } else {
                Text("Click any word in the preview to select it, then type a replacement.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Font is substituted with Helvetica — the app can't know what the original was set in.")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            if !placements.isEmpty {
                Button {
                    placements.removeLast()
                    refreshAnnotations()
                } label: {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo last placement")
                    }
                    .font(Tokens.Font.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.Color.textDim)
            }
            Button(action: save) {
                HStack {
                    Spacer()
                    Text(isRunning ? "Saving…" : "Save PDF")
                        .font(Tokens.Font.title)
                    Spacer()
                }
                .padding(.vertical, Tokens.Space.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pdfURL == nil || placements.isEmpty || isRunning)
        }
    }

    // MARK: - Right pane: preview

    @ViewBuilder
    private var rightPane: some View {
        if let doc = document {
            PDFPreviewView(
                document: doc,
                onPageClick: { pageIndex, point in
                    handlePageClick(pageIndex: pageIndex, point: point)
                },
                onTextClick: { pageIndex, selection, bounds in
                    handleTextClick(pageIndex: pageIndex, selection: selection, bounds: bounds)
                }
            )
            .id(annotationRefreshID)
        } else {
            VStack(spacing: Tokens.Space.md) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Tokens.Color.textFaint)
                Text("Drop a PDF on the left to start editing.")
                    .font(Tokens.Font.body)
                    .foregroundStyle(Tokens.Color.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Color.surface)
        }
    }

    // MARK: - Loading

    private func loadPDF(_ url: URL?) {
        guard let url, let doc = PDFDocument(url: url) else {
            errorMessage = "Cannot open that PDF"
            return
        }
        pdfURL = url
        document = doc
        placements = []
        selectedEditText = nil
        lastResult = nil
        errorMessage = nil
        annotationRefreshID = UUID()
    }

    // MARK: - Click handling

    private func handlePageClick(pageIndex: Int, point: CGPoint) {
        errorMessage = nil
        lastResult = nil

        switch mode {
        case .sign:
            guard hasSignature, let doc = document, let page = doc.page(at: pageIndex) else { return }
            let mediaBox = page.bounds(for: .mediaBox)
            let sigImage = SignatureStore.load()
            let aspect: CGFloat
            if let img = sigImage, img.size.height > 0 {
                aspect = img.size.height / img.size.width
            } else {
                aspect = 0.35
            }
            let width = mediaBox.width * CGFloat(signScale)
            let height = width * aspect
            let rect = CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width, height: height
            )
            // "Click again to move" semantics — keep only the latest sig
            // placement per session, per this design.
            placements.removeAll(where: { if case .signature = $0 { return true } else { return false } })
            placements.append(.signature(
                id: UUID(), pageIndex: pageIndex, bounds: rect,
                imageURL: SignatureStore.storageURL
            ))
            refreshAnnotations()

        case .addText:
            let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "Type some text on the left first."
                return
            }
            let size = CGFloat(addTextFontSize)
            let coverRect: CGRect? = whiteCoverForNew
                ? approximateTextRect(text: trimmed, fontSize: size, anchor: point)
                : nil
            placements.append(.text(
                id: UUID(), pageIndex: pageIndex, anchor: point,
                text: trimmed, fontSize: size,
                whiteCover: whiteCoverForNew, coverRect: coverRect
            ))
            refreshAnnotations()

        case .editText:
            // No text was under the click — fall through: create a fresh
            // placement here as if this were Add text with existing selection.
            break
        }
    }

    private func handleTextClick(pageIndex: Int, selection: PDFSelection, bounds: CGRect) {
        switch mode {
        case .editText:
            let text = selection.string ?? ""
            guard !text.isEmpty else { return }
            selectedEditText = PendingEdit(
                pageIndex: pageIndex,
                originalText: text,
                originalBounds: bounds,
                replacement: text
            )
            editedFontSize = Double(bounds.height)
        default:
            handlePageClick(pageIndex: pageIndex, point: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    private func commitEdit() {
        guard let edit = selectedEditText, !edit.replacement.isEmpty else { return }
        placements.append(.editedText(
            id: UUID(),
            pageIndex: edit.pageIndex,
            originalBounds: edit.originalBounds,
            newText: edit.replacement,
            fontSize: CGFloat(editedFontSize)
        ))
        selectedEditText = nil
        refreshAnnotations()
    }

    /// Rough helper — Helvetica is roughly 0.5em wide per char at most sizes.
    /// Only used to size the white-cover rect for new text; the actual text
    /// draw uses real CoreText metrics.
    private func approximateTextRect(text: String, fontSize: CGFloat, anchor: CGPoint) -> CGRect {
        let width = CGFloat(text.count) * fontSize * 0.55
        let height = fontSize * 1.2
        return CGRect(
            x: anchor.x - 2, y: anchor.y - 2,
            width: width + 4, height: height + 4
        )
    }

    // MARK: - Annotation refresh — visual placeholders on the preview

    /// Redraw preview markers so the user can see WHERE their placements
    /// will land. Uses PDFAnnotation `.square` shapes as lightweight
    /// visual proxies; the actual signature/text is drawn at save time
    /// via PDFOverlay. Fresh UUID forces PDFPreviewView to re-init so the
    /// annotation set matches state.
    private func refreshAnnotations() {
        guard let doc = document else { return }
        // Wipe our annotations (leave anything the user might have added
        // elsewhere alone — we tag ours with a custom userName).
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for ann in page.annotations where ann.userName == "formatc-marker" {
                page.removeAnnotation(ann)
            }
        }
        for placement in placements {
            guard let page = doc.page(at: placement.pageIndex) else { continue }
            let bounds: CGRect
            switch placement {
            case .signature(_, _, let b, _):
                bounds = b
            case .text(_, _, let a, let text, let fs, _, _):
                bounds = approximateTextRect(text: text, fontSize: fs, anchor: a)
            case .editedText(_, _, let b, _, _):
                bounds = b
            }
            let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
            annotation.userName = "formatc-marker"
            annotation.color = NSColor.systemBlue.withAlphaComponent(0.15)
            annotation.border = PDFBorder()
            annotation.border?.lineWidth = 1
            annotation.border?.style = .dashed
            page.addAnnotation(annotation)
        }
        annotationRefreshID = UUID()
    }

    // MARK: - Save

    private func save() {
        guard let src = pdfURL else { return }
        let placementsCopy = placements
        let out = defaultOutputURL(for: src)
        isRunning = true
        Task.detached(priority: .userInitiated) {
            do {
                try PDFOverlay.apply(placements: placementsCopy, input: src, output: out)
                await MainActor.run {
                    isRunning = false
                    lastResult = out
                    // Reset the working set — user starts over on the source.
                    placements = []
                    if let doc = PDFDocument(url: src) {
                        document = doc
                    }
                    annotationRefreshID = UUID()
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func defaultOutputURL(for src: URL) -> URL {
        let dir = src.deletingLastPathComponent()
        let stem = src.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(stem)_edited.pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)_edited \(n).pdf")
            n += 1
        }
        return candidate
    }
}

// Working buffer for an edit-in-progress before it gets committed to
// `placements`. Kept separate so the user can back out with Cancel.
private struct PendingEdit {
    let pageIndex: Int
    let originalText: String
    let originalBounds: CGRect
    var replacement: String
}
