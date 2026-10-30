import Foundation
import Metal

/// Persists user-imported LUTs as compact RGBA16F binaries plus a small JSON
/// registry. The original .cube is not copied; it can always be re-imported.
final class ImportedLUTStore {
    let root: URL
    private let registryURL: URL
    private(set) var entries: [ImportedLUT] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("OltraFlim", isDirectory: true)
        root = folder.appendingPathComponent("LUTs", isDirectory: true)
        registryURL = folder.appendingPathComponent("importedLUTs.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: registryURL),
           let decoded = try? JSONDecoder().decode([ImportedLUT].self, from: data) {
            // Self-heal: drop registry rows whose binary vanished, so the LUT
            // browser never shows an unusable entry after a failed write.
            let existing = decoded.filter {
                FileManager.default.fileExists(atPath: root.appendingPathComponent($0.fileName).path)
            }
            entries = existing.sorted { $0.createdAt > $1.createdAt }
            if existing.count != decoded.count { save() }
        }
    }

    /// The version-independent Application Support folder that holds edits,
    /// library metadata and imported LUT binaries. App updates replace the
    /// bundle, never this folder.
    var dataFolder: URL { root.deletingLastPathComponent() }

    func binaryURL(for entry: ImportedLUT) -> URL {
        root.appendingPathComponent(entry.fileName)
    }

    func add(_ entry: ImportedLUT) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        save()
    }

    func remove(_ entry: ImportedLUT) {
        entries.removeAll { $0.id == entry.id }
        try? FileManager.default.removeItem(at: binaryURL(for: entry))
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }

    func importCube(from url: URL, device: MTLDevice) throws -> (entry: ImportedLUT, texture: MTLTexture) {
        let lut = try LUTImporter.parse(url: url)
        let id = UUID().uuidString
        let fileName = "\(id).bin"
        let binaryURL = root.appendingPathComponent(fileName)
        try LUTImporter.writeBinary(lut, to: binaryURL)
        let texture = try LUTImporter.makeTexture(lut, device: device)
        let entry = ImportedLUT(
            id: id,
            name: lut.title,
            size: lut.size,
            fileName: fileName,
            originalFileName: url.lastPathComponent,
            createdAt: Date(),
            swatch: LUTImporter.swatch(for: lut)
        )
        add(entry)
        return (entry, texture)
    }
}
