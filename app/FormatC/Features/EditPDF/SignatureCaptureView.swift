import SwiftUI
import AppKit

/// Modal sheet where the user draws a signature with mouse or trackpad.
/// The result is a transparent-background PNG stored via SignatureStore
/// so subsequent PDFs can reuse it. Tapping "Clear" resets the strokes;
/// "Save" persists and calls `onSaved`.
struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void = {}

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    private let canvasSize = CGSize(width: 560, height: 200)

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("Draw your signature")
                    .font(Tokens.Font.title)
                Spacer()
                Button("Clear") { strokes = []; currentStroke = [] }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tokens.Color.textDim)
                    .disabled(strokes.isEmpty && currentStroke.isEmpty)
            }

            Canvas { context, _ in
                for stroke in strokes { drawStroke(stroke, in: context) }
                drawStroke(currentStroke, in: context)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(Tokens.Color.border, lineWidth: 1)
            )
            .cornerRadius(Tokens.Radius.md)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        if !currentStroke.isEmpty {
                            strokes.append(currentStroke)
                            currentStroke = []
                        }
                    }
            )

            Text("Draw with your trackpad or mouse. Transparent background is preserved when placed on a PDF.")
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(strokes.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.lg)
        .frame(width: canvasSize.width + Tokens.Space.lg * 2)
    }

    private func drawStroke(_ stroke: [CGPoint], in context: GraphicsContext) {
        guard stroke.count > 1 else { return }
        var path = Path()
        path.addLines(stroke)
        context.stroke(path, with: .color(.black),
                       style: StrokeStyle(lineWidth: 2.2,
                                          lineCap: .round,
                                          lineJoin: .round))
    }

    private func save() {
        let image = renderToImage()
        do {
            try SignatureStore.save(image)
            onSaved()
            dismiss()
        } catch {
            NSSound.beep()
        }
    }

    /// Render the strokes to a transparent-background PNG at 3× scale so
    /// it stays crisp when placed on a large PDF.
    private func renderToImage() -> NSImage {
        let scale: CGFloat = 3
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.2 * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            // Flip Y — SwiftUI canvas has top-left origin, NSImage focus
            // is bottom-left.
            path.move(to: NSPoint(
                x: first.x * scale,
                y: size.height - first.y * scale
            ))
            for point in stroke.dropFirst() {
                path.line(to: NSPoint(
                    x: point.x * scale,
                    y: size.height - point.y * scale
                ))
            }
        }
        path.stroke()
        image.unlockFocus()
        return image
    }
}
