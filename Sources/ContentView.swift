import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            header
            dropZone
            if let error = model.dropError {
                banner(error, systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
            if model.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
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
            authControl
        }
    }

    @ViewBuilder
    private var authControl: some View {
        if model.isSignedIn {
            Menu {
                Button("Se déconnecter", role: .destructive) { model.signOut() }
            } label: {
                Label("Connecté", systemImage: "person.crop.circle.fill.badge.checkmark")
                    .foregroundStyle(.green)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if model.isAuthenticating {
            ProgressView().controlSize(.small)
        } else {
            Button {
                model.signIn()
            } label: {
                Label("Se connecter avec Google", systemImage: "person.crop.circle.badge.plus")
            }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
            )
            .frame(height: 110)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Dépose un ou plusieurs .aab ici")
                        .font(.headline)
                    Text("Ils seront envoyés en Test interne sur l'app correspondante")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.handleDroppedFile(url) }
            }
        }
        return handled
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Aucun build pour l'instant")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.items) { item in
                    row(item)
                    Divider()
                }
            }
        }
    }

    private func row(_ item: BuildItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "shippingbox").foregroundStyle(.secondary))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.packageName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.versionLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                statusLine(item)
            }

            Spacer(minLength: 8)

            trailing(item)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func statusLine(_ item: BuildItem) -> some View {
        switch item.status {
        case .ready:
            Label("Prêt", systemImage: "circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.blue)
        case .uploading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.progressByID[item.id] ?? "Envoi…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .sent:
            Label("Envoyé le \(formatted(item.date)) · Test interne", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Label(item.detail ?? "Échec", systemImage: "xmark.octagon.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func trailing(_ item: BuildItem) -> some View {
        HStack(spacing: 8) {
            if item.status == .ready || item.status == .failed {
                Button(item.status == .failed ? "Réessayer" : "Envoyer") {
                    model.send(item)
                }
                .disabled(!model.isSignedIn)
                .help(model.isSignedIn ? "" : "Connecte-toi à Google d'abord")
            }
            Menu {
                Button("Afficher dans le Finder") { model.revealInFinder(item) }
                    .disabled(!item.fileExists)
                Button("Retirer de la liste", role: .destructive) { model.remove(item) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Bits

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
