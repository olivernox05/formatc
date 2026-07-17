import SwiftUI
import PDFKit
import AppKit

/// Interactive PDF preview. Wraps PDFKit's `PDFView` in a
/// `NSViewRepresentable`, adds a click-recognizer that reports back
/// (pageIndex, pointInPageCoords) so the caller can place a signature,
/// drop a text box, or look up what text lives under the click.
///
/// Coordinate system exposed to the caller is **PDF page space** — origin
/// at bottom-left, in points. That's what `CGPDFContext` and
/// `PDFAnnotation` also use, so nothing has to be flipped downstream.
struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument
    var onPageClick: (_ pageIndex: Int, _ pagePoint: CGPoint) -> Void = { _, _ in }
    var onTextClick: (_ pageIndex: Int, _ selection: PDFSelection, _ bounds: CGRect) -> Void = { _, _, _ in }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(white: 0.92, alpha: 1)
        view.document = document

        // Attach the click gesture recognizer to PDFView. Some PDFView
        // interactions (link clicks, annotation editing) may consume the
        // click first; that's fine — we only care about clicks on the
        // page background.
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        view.addGestureRecognizer(click)
        context.coordinator.pdfView = view
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        context.coordinator.onPageClick = onPageClick
        context.coordinator.onTextClick = onTextClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageClick: onPageClick, onTextClick: onTextClick)
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var onPageClick: (Int, CGPoint) -> Void
        var onTextClick: (Int, PDFSelection, CGRect) -> Void

        init(
            onPageClick: @escaping (Int, CGPoint) -> Void,
            onTextClick: @escaping (Int, PDFSelection, CGRect) -> Void
        ) {
            self.onPageClick = onPageClick
            self.onTextClick = onTextClick
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let view = pdfView, let doc = view.document else { return }
            let locInView = recognizer.location(in: view)
            guard let page = view.page(for: locInView, nearest: true) else { return }
            let pageIndex = doc.index(for: page)
            let pagePoint = view.convert(locInView, to: page)

            // If there's text at this point, prefer the text-click callback.
            // Grow the selection to a full word so single-glyph clicks still
            // pick up something usable.
            if let selection = page.selectionForWord(at: pagePoint) {
                let bounds = selection.bounds(for: page)
                if !bounds.isEmpty {
                    onTextClick(pageIndex, selection, bounds)
                    return
                }
            }
            onPageClick(pageIndex, pagePoint)
        }
    }
}
