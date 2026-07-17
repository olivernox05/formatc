import SwiftUI
import UniformTypeIdentifiers

/// Drop target that accepts files of the given UTTypes (folders too — it
/// walks one level in) and calls back with the resolved URLs. Ignores
/// content types it wasn't asked to accept.
struct DropZone<Label: View>: View {
    let kinds: [UTType]
    let onDrop: ([URL]) -> Void
    let label: () -> Label

    @State private var isTargeted = false

    var body: some View {
        label()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .fill(isTargeted ? Tokens.Color.surfaceRaised : Tokens.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(
                        isTargeted ? Tokens.Color.accent : Tokens.Color.border,
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [4, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .onTapGesture { pickFiles() }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            .foregroundStyle(Tokens.Color.textDim)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var collected: [URL] = []
        let queue = DispatchQueue(label: "app.toolsai.formatc.drop")

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                queue.sync { collected.append(contentsOf: expand(url)) }
            }
        }
        group.notify(queue: .main) {
            let accepted = collected.filter(accepts)
            if !accepted.isEmpty { onDrop(accepted) }
        }
        return true
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = kinds
        if panel.runModal() == .OK {
            onDrop(panel.urls)
        }
    }

    private func expand(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return []
        }
        if !isDir.boolValue { return [url] }
        // Shallow: don't recurse deep dirs by accident. Users can always
        // drag the specific children they want.
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter { u in
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &d)
            return !d.boolValue
        }
    }

    private func accepts(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return kinds.contains(where: { type.conforms(to: $0) || type == $0 })
    }
}
