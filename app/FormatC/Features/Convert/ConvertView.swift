import SwiftUI
import UniformTypeIdentifiers

struct ConvertView: View {
    @Environment(ToolCheck.self) private var tools
    @State private var sources: [URL] = []
    @State private var target: FileFormat = .markdown
    @State private var jobs: [ConversionJob] = []
    @State private var isRunning = false

    private var sourceFormat: FileFormat? {
        // If all sources share a format we can pick a target; otherwise the
        // user has to sort out the mixed batch first.
        guard let first = sources.first.flatMap(FileFormat.from(url:)) else { return nil }
        for url in sources.dropFirst() {
            guard FileFormat.from(url: url) == first else { return nil }
        }
        return first
    }

    private var engine: ConversionEngine { ConversionEngine(tools: tools) }

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

    // MARK: - Left: drop zone + target picker

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            dropZone
            targetPicker
            Button(action: run) {
                HStack {
                    Spacer()
                    Text(isRunning ? "Converting…" : "Convert \(sources.count) file\(sources.count == 1 ? "" : "s")")
                        .font(Tokens.Font.title)
                    Spacer()
                }
                .padding(.vertical, Tokens.Space.md)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRun)

            if let reason = unavailableReason {
                Text(reason)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var dropZone: some View {
        DropZone(kinds: [.pdf, .png, .jpeg, .html, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "docx") ?? .data]) { urls in
            sources = urls
            // Reset to a viable target for the new source type.
            if let src = sourceFormat, !src.supportedTargets().contains(target) {
                target = src.supportedTargets().first ?? .markdown
            }
        } label: {
            VStack(spacing: Tokens.Space.sm) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 26, weight: .light))
                Text(sources.isEmpty ? "Drop files here" : "\(sources.count) file\(sources.count == 1 ? "" : "s") ready")
                    .font(Tokens.Font.title)
                if !sources.isEmpty, let f = sourceFormat {
                    Text("All \(f.displayName)")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.textDim)
                } else if !sources.isEmpty {
                    Text("Mixed formats — pick one type at a time")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.warn)
                } else {
                    Text("PDF · Markdown · HTML · DOCX · PNG · JPEG")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.textDim)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding()
        }
    }

    @ViewBuilder
    private var targetPicker: some View {
        if let src = sourceFormat {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("Convert to")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.textDim)
                Picker("Target format", selection: $target) {
                    ForEach(src.supportedTargets(), id: \.self) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var canRun: Bool {
        guard let src = sourceFormat, !isRunning else { return false }
        return engine.availability(from: src, to: target).isAvailable
    }

    private var unavailableReason: String? {
        guard let src = sourceFormat else { return nil }
        return engine.availability(from: src, to: target).reason
    }

    // MARK: - Right: job list

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack {
                Text("Results").font(Tokens.Font.title)
                Spacer()
                if !jobs.isEmpty {
                    Button("Clear") { jobs.removeAll() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Tokens.Color.textDim)
                }
            }
            if jobs.isEmpty {
                emptyState
            } else {
                ScrollView { jobRows }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Space.sm) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Tokens.Color.textFaint)
            Text("Drop files, pick a target, hit Convert.")
                .font(Tokens.Font.body)
                .foregroundStyle(Tokens.Color.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobRows: some View {
        VStack(spacing: Tokens.Space.sm) {
            ForEach(jobs) { job in
                JobRow(job: job)
            }
        }
    }

    // MARK: - Run

    private func run() {
        guard let src = sourceFormat else { return }
        let newJobs = sources.map { url in
            ConversionJob(source: url, sourceFormat: src, target: target)
        }
        jobs.append(contentsOf: newJobs)
        sources.removeAll()
        isRunning = true

        Task.detached(priority: .userInitiated) {
            let engineCopy = engine
            for job in newJobs {
                await MainActor.run { setStatus(job.id, .running) }
                do {
                    let out = try engineCopy.convert(job)
                    await MainActor.run { setStatus(job.id, .done(out)) }
                } catch {
                    await MainActor.run { setStatus(job.id, .failed(error.localizedDescription)) }
                }
            }
            await MainActor.run { isRunning = false }
        }
    }

    private func setStatus(_ id: UUID, _ status: ConversionJob.Status) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = status
    }
}

private struct JobRow: View {
    let job: ConversionJob

    var body: some View {
        HStack(spacing: Tokens.Space.md) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(Tokens.Font.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
            }
            Spacer()
            if case .done(let url) = job.status {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Tokens.Color.accent)
            }
        }
        .padding(Tokens.Space.sm)
        .background(Tokens.Color.surfaceRaised)
        .cornerRadius(Tokens.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Color.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .queued:
            Image(systemName: "circle.dotted")
                .foregroundStyle(Tokens.Color.textFaint)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tokens.Color.ok)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tokens.Color.err)
        }
    }

    private var subtitle: String {
        switch job.status {
        case .queued: return "Queued · \(job.sourceFormat.displayName) → \(job.target.displayName)"
        case .running: return "Converting to \(job.target.displayName)…"
        case .done(let url): return url.path
        case .failed(let msg): return msg
        }
    }

    private var subtitleColor: SwiftUI.Color {
        if case .failed = job.status { return Tokens.Color.err }
        return Tokens.Color.textDim
    }
}
