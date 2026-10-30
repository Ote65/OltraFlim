import Foundation

struct LibraryMeta: Codable, Equatable {
    var isFavorite = false
    var colorLabel: PhotoColorLabel? = nil
}

/// Favourites and colour labels are library metadata, independent from the
/// per-file develop settings. They are keyed by the original file path so the
/// same photograph keeps its tags when re-opened from a folder.
final class LibraryMetaStore {
    private let registryURL: URL
    private var values: [String: LibraryMeta] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("OltraFlim", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        registryURL = folder.appendingPathComponent("libraryMeta.json")
        if let data = try? Data(contentsOf: registryURL),
           let decoded = try? JSONDecoder().decode([String: LibraryMeta].self, from: data) {
            values = decoded
        }
    }

    func meta(for url: URL) -> LibraryMeta {
        values[url.standardizedFileURL.path] ?? LibraryMeta()
    }

    func setFavorite(_ favorite: Bool, for url: URL) {
        let key = url.standardizedFileURL.path
        var meta = values[key] ?? LibraryMeta()
        meta.isFavorite = favorite
        values[key] = meta
        save()
    }

    func setColorLabel(_ label: PhotoColorLabel?, for url: URL) {
        let key = url.standardizedFileURL.path
        var meta = values[key] ?? LibraryMeta()
        meta.colorLabel = label
        values[key] = meta
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }
}
