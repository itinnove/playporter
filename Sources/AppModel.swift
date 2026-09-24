import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case inspecting
        case ready(AABInfo)
        case uploading(String)
        case success(String)
        case failure(String)
    }

    @Published var phase: Phase = .idle
    /// Wired up in the OAuth step; false for now.
    @Published var isSignedIn: Bool = false

    func handleDroppedFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "aab" else {
            phase = .failure("Ce fichier n'est pas un .aab")
            return
        }
        phase = .inspecting
        Task {
            do {
                let info = try await Task.detached(priority: .userInitiated) {
                    try AABInspector.inspect(url)
                }.value
                self.phase = .ready(info)
            } catch {
                self.phase = .failure(error.localizedDescription)
            }
        }
    }

    func reset() {
        phase = .idle
    }

    /// Placeholder — implemented in the upload step.
    func upload(_ info: AABInfo) {
        phase = .uploading("Upload à venir (étape API)…")
    }
}
