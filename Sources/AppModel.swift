import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @Published var pendingUpdate: Updater.Manifest?
    @Published var isUpdating = false
    /// Filter the list to a single package (nil = all apps).
    @Published var filterPackage: String?

    var userEmail: String? { GoogleAuth.shared.userEmail }

    /// Distinct packages present in the list, for the filter menu.
    var packages: [String] {
        Array(Set(items.map { $0.packageName })).sorted()
    }

    var filteredItems: [BuildItem] {
        guard let filterPackage else { return items }
        return items.filter { $0.packageName == filterPackage }
    }

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
        checkForUpdates(silent: true)
    }

    // MARK: - Auto-update

    func checkForUpdates(silent: Bool) {
        Task {
            do {
                let manifest = try await Updater.fetchManifest()
                if Updater.isNewer(manifest.version) {
                    self.pendingUpdate = manifest
                } else if !silent {
                    self.dropError = "Playporter est à jour (v\(Updater.currentVersion()))."
                }
            } catch {
                if !silent { self.dropError = "Vérification des mises à jour impossible." }
            }
        }
    }

    func installUpdate() {
        guard let manifest = pendingUpdate, !isUpdating else { return }
        isUpdating = true
        Task {
            do {
                try await Updater.performUpdate(manifest)
            } catch {
                self.isUpdating = false
                self.dropError = "Mise à jour échouée : \(error.localizedDescription)"
            }
        }
    }

    func dismissUpdate() { pendingUpdate = nil }

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

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let aabType = UTType(filenameExtension: "aab") {
            panel.allowedContentTypes = [aabType]
        }
        panel.prompt = "Ajouter"
        if panel.runModal() == .OK {
            for url in panel.urls { handleDroppedFile(url) }
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
                let result = try await publisher.publishInternal(
                    aab: target.fileURL,
                    packageName: target.packageName
                ) { status in
                    Task { @MainActor in self.progressByID[target.id] = status }
                }
                self.update(target.id) {
                    $0.status = .sent
                    $0.date = Date()
                    $0.versionCode = result.versionCode
                    if let name = result.appName { $0.appName = name }
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
