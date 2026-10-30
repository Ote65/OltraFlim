import Foundation

/// Session-independent edit memory keyed by the photograph's canonical path.
/// This is deliberately not a catalogue: it only lets a re-imported file come
/// back with the look and adjustments it had, without inventing library state.
final class EditStore {
    private var edits: [String: PhotoEdit] = [:]
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("OltraFlim", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("edits.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: PhotoEdit].self, from: data) {
            edits = decoded
        }
    }

    private func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    func edit(for url: URL) -> PhotoEdit? {
        edits[key(for: url)]
    }

    func set(_ edit: PhotoEdit, for url: URL) {
        edits[key(for: url)] = edit
    }

    func remove(for url: URL) {
        edits[key(for: url)] = nil
    }

    func save() {
        guard let data = try? JSONEncoder().encode(edits) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
