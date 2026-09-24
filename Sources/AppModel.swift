import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {

    /// The unified list: queued, uploading, sent and failed builds.
    @Published var items: [BuildItem] = []
    /// Live progress text per in-flight item (not persisted).
    @Published var progressByID: [UUID: String] = [:]
    /// Transient error shown when a dropped file can't be read.
    @Published var dropError: String?

    @Published var isSignedIn: Bool = GoogleAuth.shared.isAuthorized
    @Published var isAuthenticating = false

    init() {
        // Restore the list; any build left "uploading" from a previous run
        // (app quit mid-flight) is downgraded so it can be retried.
        items = Storage.load().map { item in
            guard item.status == .uploading else { return item }
            var recovered = item
            recovered.status = .failed
            recovered.detail = "Envoi interrompu"
            return recovered
        }
    }

    // MARK: - Drop

    func handleDroppedFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "aab" else {
            dropError = "Ce fichier n'est pas un .aab"
            return
        }
        dropError = nil
        Task {
            do {
                let info = try await Task.detached(priority: .userInitiated) {
                    try AABInspector.inspect(url)
                }.value
                self.items.insert(BuildItem(info: info), at: 0)
                self.persist()
            } catch {
                self.dropError = error.localizedDescription
            }
        }
    }

    // MARK: - Upload

    func send(_ item: BuildItem) {
        guard isSignedIn else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .uploading
        progressByID[item.id] = "Préparation…"
        let target = items[index]

        Task {
            do {
                let token = try await GoogleAuth.shared.accessToken()
                let publisher = PlayPublisher(accessToken: token)
                let versionCode = try await publisher.publishInternal(
                    aab: target.fileURL,
                    packageName: target.packageName
                ) { status in
                    Task { @MainActor in self.progressByID[target.id] = status }
                }
                self.update(target.id) {
                    $0.status = .sent
                    $0.date = Date()
                    $0.versionCode = versionCode
                    $0.detail = nil
                }
            } catch {
                self.update(target.id) {
                    $0.status = .failed
                    $0.detail = error.localizedDescription
                }
            }
            self.progressByID[target.id] = nil
        }
    }

    // MARK: - Row actions

    func remove(_ item: BuildItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func revealInFinder(_ item: BuildItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    // MARK: - Auth

    func signIn() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            defer { self.isAuthenticating = false }
            do {
                try await GoogleAuth.shared.signIn()
                self.isSignedIn = true
            } catch {
                self.dropError = "Connexion échouée : \(error.localizedDescription)"
            }
        }
    }

    func signOut() {
        GoogleAuth.shared.signOut()
        isSignedIn = false
    }

    // MARK: - Helpers

    private func update(_ id: UUID, _ change: (inout BuildItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        persist()
    }

    private func persist() {
        Storage.save(items)
    }
}
