import SwiftUI

struct ContentView: View {
    enum Tab: Hashable { case convert, merge, split, backgroundRemove }
    @State private var tab: Tab = .convert
    @Environment(ToolCheck.self) private var tools

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Tokens.Color.border)

            Group {
                switch tab {
                case .convert:          ConvertView()
                case .merge:            MergeView()
                case .split:            SplitView()
                case .backgroundRemove: BackgroundRemoveView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Tokens.Color.border)
            statusBar
        }
        .background(Tokens.Color.bg)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.md) {
            Text("FormatC")
                .font(Tokens.Font.display)
                .foregroundStyle(Tokens.Color.text)

            Spacer()

            Picker("", selection: $tab) {
                Text("Convert").tag(Tab.convert)
                Text("Merge").tag(Tab.merge)
                Text("Split").tag(Tab.split)
                Text("Remove BG").tag(Tab.backgroundRemove)
            }
            .pickerStyle(.segmented)
            .frame(width: 380)
        }
        .padding(.horizontal, Tokens.Space.lg)
        .padding(.vertical, Tokens.Space.md)
    }

    private var statusBar: some View {
        HStack(spacing: Tokens.Space.md) {
            statusChip("pandoc", ok: tools.pandoc.isAvailable, detail: tools.pandoc.version)
            statusChip("python3", ok: tools.python3.isAvailable, detail: tools.python3.version)
            statusChip("pdf2md", ok: tools.pdf2mdEngine != nil, detail: tools.pdf2mdEngine)
            Spacer()
            Button("Refresh") { tools.refresh() }
                .buttonStyle(.borderless)
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.textDim)
        }
        .padding(.horizontal, Tokens.Space.lg)
        .padding(.vertical, Tokens.Space.sm)
        .background(Tokens.Color.surface)
    }

    private func statusChip(_ label: String, ok: Bool, detail: String?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Tokens.Color.ok : Tokens.Color.textFaint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.text)
            if let detail, !detail.isEmpty {
                Text("· \(detail)")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textDim)
                    .lineLimit(1)
            }
        }
    }
}
