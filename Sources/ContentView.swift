import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            header
            dropZone
            statusArea
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Playporter")
                .font(.title2.weight(.semibold))
            Spacer()
            Label(model.isSignedIn ? "Connecté" : "Non connecté",
                  systemImage: model.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.xmark")
                .font(.caption)
                .foregroundStyle(model.isSignedIn ? .green : .secondary)
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
            )
            .frame(height: 150)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Dépose un fichier .aab ici")
                        .font(.headline)
                    Text("Il sera envoyé en Test interne sur l'app correspondante")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in model.handleDroppedFile(url) }
        }
        return true
    }

    // MARK: - Status

    @ViewBuilder
    private var statusArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .inspecting:
            ProgressView("Lecture de l'AAB…")

        case .ready(let info):
            VStack(spacing: 12) {
                infoCard(info)
                Button {
                    model.upload(info)
                } label: {
                    Label("Envoyer en Test interne", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

        case .uploading(let text):
            ProgressView(text)

        case .success(let text):
            statusBanner(text, systemImage: "checkmark.circle.fill", color: .green)

        case .failure(let text):
            statusBanner(text, systemImage: "xmark.octagon.fill", color: .red)
        }
    }

    private func infoCard(_ info: AABInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Fichier", info.fileName)
            row("Package", info.applicationId)
            if let vc = info.versionCode { row("versionCode", String(vc)) }
            if let vn = info.versionName { row("versionName", vn) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func statusBanner(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.callout)
            Spacer(minLength: 0)
            Button("OK") { model.reset() }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
    }
}
