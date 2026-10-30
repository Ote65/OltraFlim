import Foundation
import AppKit
import CoreImage
import Observation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Metal

// MARK: - Supporting types

enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case jpeg
    case png
    case tiff
    case heic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .heic: return "HEIC"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .heic: return .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tif"
        case .heic: return "heic"
        }
    }

    var isLossy: Bool { self == .jpeg || self == .heic }
}

struct ExportOptions: Codable {
    var format: ExportFormat = .jpeg
    var quality: Double = 0.92
    var longEdge: Int? = nil
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var detail: String?
    var symbol: String
}

enum LibraryMode: String, CaseIterable, Identifiable {
    case films
    case luts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .films: return T("胶片", "Films")
        case .luts: return T("LUT", "LUTs")
        }
    }
}

enum AppScreen: String {
    case library
    case editor
}

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
    var title: String {
        switch self {
        case .grid: return T("网格", "Grid")
        case .list: return T("列表", "List")
        }
    }
    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

enum LibraryGrouping: String, CaseIterable, Identifiable {
    case none
    case film
    case favorite
    case color

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return T("不群组", "None")
        case .film: return T("胶片", "Film")
        case .favorite: return T("收藏", "Favorites")
        case .color: return T("颜色标签", "Color label")
        }
    }
    var symbol: String {
        switch self {
        case .none: return "rectangle.3.group"
        case .film: return "film"
        case .favorite: return "star"
        case .color: return "tag"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case edited
    case red
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return T("全部", "All")
        case .favorites: return T("收藏", "Favorites")
        case .edited: return T("已调整", "Edited")
        case .red: return PhotoColorLabel.red.title
        case .yellow: return PhotoColorLabel.yellow.title
        case .green: return PhotoColorLabel.green.title
        case .blue: return PhotoColorLabel.blue.title
        case .purple: return PhotoColorLabel.purple.title
        }
    }

    var colorLabel: PhotoColorLabel? {
        switch self {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        default: return nil
        }
    }

    var symbol: String? {
        switch self {
        case .all: return nil
        case .favorites: return "star"
        case .edited: return "slider.horizontal.3"
        default: return nil
        }
    }
}

struct LibraryPhotoGroup: Identifiable {
    let id: String
    let title: String?
    let photos: [Photo]
}

struct StorageUsage: Equatable {
    var cacheBytes: Int64 = 0
    var dataBytes: Int64 = 0
}

enum LibraryState: Equatable {
    case idle
    case loading(progress: Double, phase: String)
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - App model

@Observable
final class AppModel {
    static let shared = AppModel()

    let catalog: FilmCatalog
    let index: CatalogIndex
    let lutLibrary: LUTLibrary
    let renderer: Renderer?
    let importedStore = ImportedLUTStore()

    var language: AppLanguage = .chinese {
        didSet {
            L10n.current = language
            UserDefaults.standard.set(language.rawValue, forKey: "language")
        }
    }

    // MARK: In-app settings

    var textScale: Double = 1.0 {
        didSet {
            DS.textScale = CGFloat(textScale)
            UserDefaults.standard.set(textScale, forKey: "uiTextScale")
        }
    }

    var reduceMotion: Bool = false {
        didSet {
            DS.reduceMotion = reduceMotion
            UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion")
        }
    }

    /// Baseline auto exposure: the scene's center-weighted mean is normalised
    /// to 18% grey before the film LUT, mirroring spektrafilm. Turning it off
    /// keeps the RAW's absolute exposure.
    var autoExposure: Bool = true {
        didSet {
            UserDefaults.standard.set(autoExposure, forKey: "autoExposure")
            renderer?.autoExposureEnabled = autoExposure
            if currentPhoto != nil { reapplyCurrentLook() }
        }
    }

    var defaultExportDirectoryPath: String? {
        didSet {
            if let path = defaultExportDirectoryPath {
                UserDefaults.standard.set(path, forKey: "defaultExportDirectory")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultExportDirectory")
            }
        }
    }

    /// Resolved only when the folder still exists, so a deleted directory
    /// silently falls back to the system save panel default.
    var defaultExportDirectory: URL? {
        guard let path = defaultExportDirectoryPath else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var thumbnailCacheCount: Int {
        photos.reduce(0) { $0 + ($1.thumbnail == nil ? 0 : 1) }
            + lookThumbs.count + importedThumbs.count + sampleImportedThumbs.count
    }

    var importedLUTs: [ImportedLUT] = []
    var libraryMode: LibraryMode = .films
    var inspectorTab: InspectorTab = .light
    var isImportingLUT = false

    var photos: [Photo] = []
    var selectedPhotoID: UUID?
    var screen: AppScreen = .library
    var folders: [LibraryFolder] = []
    var folderTrail: [URL] = []
    var subfolderEntries: [LibraryFolder] = []
    var libraryDisplay: LibraryDisplayMode = .grid {
        didSet { UserDefaults.standard.set(libraryDisplay.rawValue, forKey: "libraryDisplay") }
    }
    var libraryGrouping: LibraryGrouping = .none {
        didSet { UserDefaults.standard.set(libraryGrouping.rawValue, forKey: "libraryGrouping") }
    }
    var libraryFilter: LibraryFilter = .all
    var librarySearch = ""
    var browseStockID: String
    var favorites: Set<String> = []
    var recentStocks: [String] = []

    var searchText = ""
    var brandFilter: String?
    var typeFilter: FilmType?
    var engineFilter: String?
    var favoritesOnly = false

    var libraryState: LibraryState = .idle
    var startupError: String?
    var lookThumbs: [String: CGImage] = [:]
    var importedThumbs: [String: CGImage] = [:]
    var samplePreviewImage: CGImage?
    var isGeneratingThumbs = false
    var histogram = HistogramData.empty
    var toneStats = ToneStats.empty
    var showOriginal = false
    var compareSplit: Double = 0.5
    var toast: ToastMessage?
    var alertMessage: String?
    var isExporting = false
    var exportStatus = ""
    var exportPresented = false
    var exportOptions: ExportOptions
    var isDropTarget = false
    var storageUsage = StorageUsage()
    var isClearingCache = false

    private var thumbCache: [UUID: [String: CGImage]] = [:]
    private var importedThumbCache: [UUID: [String: CGImage]] = [:]
    private var pendingThumbnails: Set<UUID> = []
    private var pendingPreviews: Set<UUID> = []
    private var sampleThumbs: [String: CGImage] = [:]
    private var sampleImportedThumbs: [String: CGImage] = [:]
    private var previewAccess: [UUID] = []
    private var lookThumbAccess: [UUID] = []
    private var libraryThumbAccess: [UUID] = []
    private var previewGeneration = 0
    private let previewLock = NSLock()
    private let previewQueue = DispatchQueue(label: "studio.oltra.oltraflim.previews", qos: .userInitiated)
    private let thumbnailCache = ThumbnailCache.shared
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var histogramWork: DispatchWorkItem?
    private var toastTask: Task<Void, Never>?
    private var thumbGeneration = 0
    private var pendingExportURL: URL?
    private var pendingLookID: String?
    private var pendingBefore = false
    private let editStore = EditStore()
    private let libraryMetaStore = LibraryMetaStore()
    private let libraryDefaultsKey = "libraryPhotoPaths"
    private let libraryFolderDefaultsKey = "libraryFolderPaths"
    private let thumbnailQueue = DispatchQueue(label: "studio.oltra.oltraflim.thumbnails", qos: .userInitiated)
    private var pendingFolderCovers: Set<String> = []
    private var editSaveWork: DispatchWorkItem?
    private var needsToneAnalysis = true
    private var pendingTonal: Double?
    private var pendingColor: Double?
    private var pendingImportLUT: URL?
    private var pendingCurveDemo = false
    private var pendingColorDemo = false

    // MARK: Init

    private init() {
        let defaults = UserDefaults.standard
        let selectedLanguage = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .chinese
        language = selectedLanguage
        L10n.current = selectedLanguage

        let savedScale = defaults.double(forKey: "uiTextScale")
        let scale = savedScale > 0 ? min(1.2, max(0.85, savedScale)) : 1.0
        textScale = scale
        DS.textScale = CGFloat(scale)
        let motion = defaults.bool(forKey: "reduceMotion")
        reduceMotion = motion
        DS.reduceMotion = motion
        defaultExportDirectoryPath = defaults.string(forKey: "defaultExportDirectory")
        let catalog: FilmCatalog
        let catalogURL = ResourceLocator.resourceURL("catalog.json")
        if let data = try? Data(contentsOf: catalogURL) {
            do {
                catalog = try JSONDecoder().decode(FilmCatalog.self, from: data)
            } catch {
                catalog = .empty
                startupError = T("胶片目录解析失败：\(error)", "The film catalog could not be decoded: \(error)")
                NSLog("OltraFlim catalog decode error: %@", String(describing: error))
            }
        } else {
            catalog = .empty
            startupError = T("应用内的胶片目录缺失。", "The film catalog is missing from the app bundle.")
            NSLog("OltraFlim catalog missing at %@", catalogURL.path)
        }
        self.catalog = catalog
        self.index = CatalogIndex(catalog: catalog)
        self.lutLibrary = LUTLibrary(size: catalog.lutSize)
        self.renderer = Renderer(lutLibrary: lutLibrary)
        if renderer == nil {
            startupError = T("OltraFlim 无法启动 Metal 胶片引擎。", "OltraFlim could not start the Metal film engine.")
        }
        let autoExposureDefault = defaults.object(forKey: "autoExposure") as? Bool ?? true
        autoExposure = autoExposureDefault
        renderer?.autoExposureEnabled = autoExposureDefault

        libraryDisplay = LibraryDisplayMode(rawValue: defaults.string(forKey: "libraryDisplay") ?? "") ?? .grid
        libraryGrouping = LibraryGrouping(rawValue: defaults.string(forKey: "libraryGrouping") ?? "") ?? .none

        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        let recent = defaults.stringArray(forKey: "recentStocks") ?? []
        recentStocks = recent.filter { id in catalog.stocks.contains(where: { $0.id == id }) }
        let savedStock = defaults.string(forKey: "browseStock")
        browseStockID = catalog.stocks.contains(where: { $0.id == savedStock }) ? (savedStock ?? catalog.defaultStock) : catalog.defaultStock
        importedLUTs = importedStore.entries
        if let data = defaults.data(forKey: "exportOptions"),
           let options = try? JSONDecoder().decode(ExportOptions.self, from: data) {
            exportOptions = options
        } else {
            exportOptions = ExportOptions()
        }

        renderer?.onHistogram = { [weak self] data, stats in
            self?.handleHistogram(data, stats)
        }
        renderer?.onError = { [weak self] message in
            self?.alertMessage = message
        }

        prepareLibrary()
        loadSamplePreview()
        restoreLibrary()
        restoreFolders()
        observeMemoryPressure()
        refreshStorageUsage()
        DispatchQueue.global(qos: .utility).async {
            ThumbnailCache.shared.prune()
        }
        DispatchQueue.main.async { [weak self] in
            self?.importLaunchArguments()
        }
    }

    // MARK: Library

    private func prepareLibrary() {
        guard let renderer else { return }
        libraryState = .loading(progress: 0, phase: T("正在准备胶片库", "Preparing film stock"))
        let library = lutLibrary
        let catalog = self.catalog
        let entries = importedLUTs
        let store = importedStore
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try library.load(device: renderer.device, catalog: catalog) { progress in
                    let fraction = Double(progress.loaded) / Double(max(progress.total, 1))
                    DispatchQueue.main.async { [weak self] in
                        self?.libraryState = .loading(progress: fraction, phase: T("正在准备胶片库", "Preparing film stock"))
                    }
                }
                for entry in entries {
                    if let texture = try? LUTImporter.makeTexture(
                        fromBinary: store.binaryURL(for: entry),
                        size: entry.size,
                        device: renderer.device
                    ) {
                        library.registerUserLUT(
                            id: entry.id,
                            texture: texture,
                            info: LUTInfo(isACEScc: entry.isACESccLMT,
                                          exposureEV: Float(entry.exposureEV ?? 0))
                        )
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.libraryState = .ready
                    self.reapplyCurrentLook()
                    self.generateThumbsIfNeeded()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.libraryState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func reapplyCurrentLook() {
        guard let renderer else { return }
        renderer.update(edit: currentEdit, look: currentLook)
    }

    private func loadSamplePreview() {
        let url = ResourceLocator.resourceURL("Sample/sample_preview.jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = try? ImageLoader.shared.loadPreview(url: url, maxPixel: 2200)
            DispatchQueue.main.async { [weak self] in
                guard let self, let image = loaded?.image else { return }
                self.samplePreviewImage = image
                if self.currentPhoto == nil {
                    self.lookThumbs = self.sampleThumbs
                    self.importedThumbs = self.sampleImportedThumbs
                    self.generateThumbsIfNeeded()
                }
            }
        }
    }

    // MARK: Photo library

    private func makePhoto(url: URL, folder: URL?) -> Photo {
        let stock = index.stock(browseStockID) ?? index.stock(catalog.defaultStock)
        let stored = editStore.edit(for: url)
        let validStored = stored.flatMap { candidate in
            index.look(candidate.lookID) == nil ? nil : candidate
        }
        let meta = libraryMetaStore.meta(for: url)
        var photo = Photo(
            id: UUID(),
            url: url.standardizedFileURL,
            name: url.lastPathComponent,
            metadata: PhotoMetadata(),
            pixelSize: .zero,
            edit: validStored ?? PhotoEdit(
                lookID: stock?.defaultLook, strength: 1, adjustments: .neutral
            ),
            thumbnail: nil
        )
        photo.folder = folder?.standardizedFileURL
        photo.isFavorite = meta.isFavorite
        photo.colorLabel = meta.colorLabel
        return photo
    }

    /// Restores loose photographs imported in previous sessions. Folder
    /// contents are scanned on demand when the folder is opened.
    private func restoreLibrary() {
        guard let paths = UserDefaults.standard.stringArray(forKey: libraryDefaultsKey) else { return }
        var seen = Set<String>()
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(url.path).inserted,
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            photos.append(makePhoto(url: url, folder: nil))
        }
        saveLibrary()
    }

    private func saveLibrary() {
        UserDefaults.standard.set(
            photos.filter { $0.folder == nil }.map { $0.url.standardizedFileURL.path },
            forKey: libraryDefaultsKey
        )
    }

    private func restoreFolders() {
        let paths = UserDefaults.standard.stringArray(forKey: libraryFolderDefaultsKey) ?? []
        var seen = Set<String>()
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(url.path).inserted,
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            folders.append(makeFolderRecord(for: url))
        }
        saveFolders()
    }

    private func saveFolders() {
        UserDefaults.standard.set(
            folders.map { $0.url.standardizedFileURL.path },
            forKey: libraryFolderDefaultsKey
        )
    }

    /// Home cards only need the small thumbnail. The full preview is decoded
    /// when the photograph is opened in the editor. Thumbnails are persisted to
    /// a bounded disk cache and capped in memory so large folders stay light.
    func requestThumbnail(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        if photos[index].thumbnail != nil {
            touchLibraryThumbnail(id)
            return
        }
        guard !pendingThumbnails.contains(id) else { return }
        pendingThumbnails.insert(id)
        let url = photos[index].url
        thumbnailQueue.async { [weak self] in
            let thumb = ThumbnailCache.shared.thumbnail(for: url, maxPixel: 480)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingThumbnails.remove(id)
                guard let index = self.photos.firstIndex(where: { $0.id == id }) else { return }
                self.photos[index].thumbnail = thumb
                if thumb != nil { self.touchLibraryThumbnail(id) }
            }
        }
    }

    func requestFolderCover(_ folder: LibraryFolder) {
        guard folder.cover == nil, let coverURL = folder.coverURL,
              !pendingFolderCovers.contains(folder.id) else { return }
        pendingFolderCovers.insert(folder.id)
        let id = folder.id
        thumbnailQueue.async { [weak self] in
            let thumb = ThumbnailCache.shared.thumbnail(for: coverURL, maxPixel: 480)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingFolderCovers.remove(id)
                if let index = self.folders.firstIndex(where: { $0.id == id }) {
                    self.folders[index].cover = thumb
                }
                if let index = self.subfolderEntries.firstIndex(where: { $0.id == id }) {
                    self.subfolderEntries[index].cover = thumb
                }
            }
        }
    }

    private func touchLibraryThumbnail(_ id: UUID) {
        libraryThumbAccess.removeAll { $0 == id }
        libraryThumbAccess.append(id)
        evictLibraryThumbnails(libraryThumbAccess.count - 200)
    }

    private func evictLibraryThumbnails(_ overflow: Int) {
        guard overflow > 0 else { return }
        var evicted = 0
        var kept: [UUID] = []
        for candidate in libraryThumbAccess {
            if evicted < overflow, candidate != selectedPhotoID,
               let index = photos.firstIndex(where: { $0.id == candidate }) {
                photos[index].thumbnail = nil
                evicted += 1
            } else {
                kept.append(candidate)
            }
        }
        libraryThumbAccess = kept
    }

    func openPhoto(_ id: UUID) {
        guard photos.contains(where: { $0.id == id }) else { return }
        screen = .editor
        selectPhoto(id)
    }

    func showLibrary() {
        screen = .library
        showOriginal = false
        renderer?.setCompare(enabled: false, split: compareSplit)
    }

    // MARK: Folders

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = T("导入文件夹", "Import folders")
        panel.prompt = T("导入", "Import")
        panel.message = T("文件夹中的照片会保留在原位置，点击文件夹即可浏览。",
                           "Photographs stay where they are; open the folder to browse them.")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }
        importFolders(panel.urls)
    }

    func importFolders(_ urls: [URL]) {
        var added: [LibraryFolder] = []
        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            guard !folders.contains(where: { $0.url.standardizedFileURL.path == url.path }) else { continue }
            added.append(makeFolderRecord(for: url))
        }
        guard !added.isEmpty else {
            alertMessage = T("这些文件夹已经在照片库里了。", "Those folders are already in the library.")
            return
        }
        folders.append(contentsOf: added)
        saveFolders()
        folderTrail = []
        subfolderEntries = []
        screen = .library
        showToast(
            T("已添加 \(added.count) 个文件夹", "Added \(added.count) folder\(added.count == 1 ? "" : "s")"),
            symbol: "folder"
        )
    }

    func importDroppedURLs(_ urls: [URL]) {
        var folderURLs: [URL] = []
        var photoURLs: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                folderURLs.append(url)
            } else if Self.isSupportedImage(url) {
                photoURLs.append(url)
            }
        }
        if !folderURLs.isEmpty { importFolders(folderURLs) }
        if !photoURLs.isEmpty {
            importURLs(photoURLs, openFirst: false)
        }
    }

    func enterFolder(_ folder: LibraryFolder) {
        enterFolder(folder.url)
    }

    func enterFolder(_ url: URL) {
        let target = url.standardizedFileURL
        screen = .library
        if let current = folderTrail.last,
           target.path.hasPrefix(current.standardizedFileURL.path + "/") {
            folderTrail.append(target)
        } else if let index = folderTrail.firstIndex(where: { $0.standardizedFileURL.path == target.path }) {
            folderTrail = Array(folderTrail.prefix(index + 1))
        } else {
            folderTrail = [target]
        }
        loadCurrentFolder()
    }

    func goUpFolder() {
        guard !folderTrail.isEmpty else { return }
        folderTrail.removeLast()
        if folderTrail.isEmpty {
            subfolderEntries = []
        } else {
            loadCurrentFolder()
        }
    }

    func goToLibraryRoot() {
        folderTrail = []
        subfolderEntries = []
    }

    func navigateToTrail(_ index: Int) {
        guard index >= 0, index < folderTrail.count else { return }
        folderTrail = Array(folderTrail.prefix(index + 1))
        loadCurrentFolder()
    }

    private func loadCurrentFolder() {
        guard let folder = currentFolderURL else {
            subfolderEntries = []
            return
        }
        let scan = scanFolder(folder)
        subfolderEntries = scan.folders
        let known = Set(photos.map { $0.url.standardizedFileURL.path })
        let newPhotos = scan.photos.filter { !known.contains($0.url.standardizedFileURL.path) }
        photos.append(contentsOf: newPhotos)
        if let index = folders.firstIndex(where: { $0.url.standardizedFileURL.path == folder.path }) {
            folders[index].count = scan.photos.count
            folders[index].subfolderCount = scan.folderCount
            folders[index].coverURL = scan.photos.first?.url
        }
        saveFolders()
    }

    func refreshFolder(_ folder: LibraryFolder) {
        let record = makeFolderRecord(for: folder.url)
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = record
        }
        if let index = subfolderEntries.firstIndex(where: { $0.id == folder.id }) {
            subfolderEntries[index] = record
        }
        requestFolderCover(record)
        if currentFolderURL?.path == folder.url.standardizedFileURL.path {
            loadCurrentFolder()
        }
    }

    func removeFolder(_ folder: LibraryFolder) {
        folders.removeAll { $0.id == folder.id }
        let root = folder.url.standardizedFileURL.path
        photos.removeAll { photo in
            guard let parent = photo.folder?.standardizedFileURL.path else { return false }
            return parent == root || parent.hasPrefix(root + "/")
        }
        if let current = currentFolderURL,
           current.path == root || current.path.hasPrefix(root + "/") {
            folderTrail = []
            subfolderEntries = []
        }
        if let selected = selectedPhotoID, !photos.contains(where: { $0.id == selected }) {
            selectedPhotoID = nil
            renderer?.clearImage()
        }
        saveFolders()
        saveLibrary()
        showToast(T("已从照片库移除文件夹", "Removed folder from library"),
                  detail: folder.name, symbol: "folder.badge.minus")
    }

    private func makeFolderRecord(for url: URL) -> LibraryFolder {
        let scan = scanFolder(url, includePhotos: false, includeSubfolders: false)
        return LibraryFolder(
            url: url.standardizedFileURL,
            count: scan.imageCount,
            subfolderCount: scan.folderCount,
            coverURL: scan.coverURL,
            cover: nil
        )
    }

    private struct FolderScan {
        var photos: [Photo]
        var folders: [LibraryFolder]
        var imageCount: Int
        var folderCount: Int
        var coverURL: URL?
    }

    private func scanFolder(
        _ url: URL,
        includePhotos: Bool = true,
        includeSubfolders: Bool = true
    ) -> FolderScan {
        let directory = url.standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        var subfolders: [LibraryFolder] = []
        var folderCount = 0
        var imageURLs: [URL] = []
        for item in contents {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if !item.lastPathComponent.hasPrefix(".") {
                    folderCount += 1
                    if includeSubfolders {
                        subfolders.append(makeFolderRecord(for: item))
                    }
                }
            } else if Self.isSupportedImage(item) {
                imageURLs.append(item)
            }
        }
        imageURLs.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        subfolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let newPhotos = includePhotos ? imageURLs.map { makePhoto(url: $0, folder: directory) } : []
        return FolderScan(
            photos: newPhotos,
            folders: subfolders,
            imageCount: imageURLs.count,
            folderCount: folderCount,
            coverURL: imageURLs.first
        )
    }

    // MARK: Library metadata

    func toggleFavorite(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].isFavorite.toggle()
        libraryMetaStore.setFavorite(photos[index].isFavorite, for: photos[index].url)
    }

    func setColorLabel(_ label: PhotoColorLabel?, for id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].colorLabel = label
        libraryMetaStore.setColorLabel(label, for: photos[index].url)
    }

    // MARK: Derived state

    func localized(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }

    var currentPhoto: Photo? {
        guard let selectedPhotoID else { return nil }
        return photos.first(where: { $0.id == selectedPhotoID })
    }

    var currentPhotoIndex: Int? {
        guard let selectedPhotoID else { return nil }
        return photos.firstIndex(where: { $0.id == selectedPhotoID })
    }

    // MARK: Library state

    var currentFolderURL: URL? {
        folderTrail.last?.standardizedFileURL
    }

    var currentFolderName: String? {
        currentFolderURL?.lastPathComponent
    }

    var libraryTitle: String {
        currentFolderName ?? T("照片库", "Library")
    }

    var libraryParentTitle: String {
        guard folderTrail.count > 1 else { return T("照片库", "Library") }
        return folderTrail[folderTrail.count - 2].lastPathComponent
    }

    var loosePhotos: [Photo] {
        photos.filter { $0.folder == nil }
    }

    var folderPhotos: [Photo] {
        guard let folder = currentFolderURL else { return [] }
        return photos.filter {
            $0.folder?.standardizedFileURL.path == folder.path
        }
    }

    /// Photographs shown in the current library location. Folder photographs
    /// are hidden from the root, so the root stays a clean index of folders and
    /// directly imported files.
    var libraryPhotos: [Photo] {
        currentFolderURL == nil ? loosePhotos : folderPhotos
    }

    /// The photographs the editor should offer for next / previous and in the
    /// filmstrip: the selected photograph's folder, or the root library for a
    /// loose photograph.
    var collectionPhotos: [Photo] {
        if let folder = currentPhoto?.folder?.standardizedFileURL {
            return photos.filter { $0.folder?.standardizedFileURL.path == folder.path }
        }
        return loosePhotos
    }

    var visibleFolders: [LibraryFolder] {
        currentFolderURL == nil ? folders : subfolderEntries
    }

    var filteredLibraryPhotos: [Photo] {
        var result = libraryPhotos
        switch libraryFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .edited:
            result = result.filter { photo in
                photo.edit.adjustments.activeCount > 0
                    || !photo.edit.curves.isIdentity
                    || abs(photo.edit.strength - 1) > 0.001
                    || photo.edit.lutID != nil
            }
        case .red, .yellow, .green, .blue, .purple:
            if let label = libraryFilter.colorLabel {
                result = result.filter { $0.colorLabel == label }
            }
        }

        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        let needle = query.lowercased()
        return result.filter { photo in
            let stock = stockLabel(for: photo)
            let color = photo.colorLabel?.title ?? ""
            let haystack = "\(photo.name) \(stock) \(color)".lowercased()
            return haystack.contains(needle)
        }
    }

    var libraryGroups: [LibraryPhotoGroup] {
        let source = filteredLibraryPhotos
        guard !source.isEmpty else { return [] }

        switch libraryGrouping {
        case .none:
            return [LibraryPhotoGroup(id: "all", title: nil, photos: source)]

        case .film:
            let buckets = Dictionary(grouping: source) { stockLabel(for: $0) }
            return buckets.keys
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { key in
                    LibraryPhotoGroup(id: "film-\(key)", title: key, photos: buckets[key] ?? [])
                }

        case .favorite:
            var groups: [LibraryPhotoGroup] = []
            let favorites = source.filter(\.isFavorite)
            let others = source.filter { !$0.isFavorite }
            if !favorites.isEmpty {
                groups.append(LibraryPhotoGroup(
                    id: "fav-yes", title: T("收藏", "Favorites"), photos: favorites
                ))
            }
            if !others.isEmpty {
                groups.append(LibraryPhotoGroup(
                    id: "fav-no", title: T("未收藏", "Not favorites"), photos: others
                ))
            }
            return groups

        case .color:
            var groups: [LibraryPhotoGroup] = []
            for label in PhotoColorLabel.allCases {
                let photos = source.filter { $0.colorLabel == label }
                if !photos.isEmpty {
                    groups.append(LibraryPhotoGroup(
                        id: "color-\(label.rawValue)", title: label.title, photos: photos
                    ))
                }
            }
            let unlabeled = source.filter { $0.colorLabel == nil }
            if !unlabeled.isEmpty {
                groups.append(LibraryPhotoGroup(
                    id: "color-none", title: T("未标记", "Unlabeled"), photos: unlabeled
                ))
            }
            return groups
        }
    }

    func libraryFilterCount(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .all:
            return libraryPhotos.count
        case .favorites:
            return libraryPhotos.filter(\.isFavorite).count
        case .edited:
            return libraryPhotos.filter { photo in
                photo.edit.adjustments.activeCount > 0
                    || !photo.edit.curves.isIdentity
                    || abs(photo.edit.strength - 1) > 0.001
                    || photo.edit.lutID != nil
            }.count
        case .red, .yellow, .green, .blue, .purple:
            guard let label = filter.colorLabel else { return 0 }
            return libraryPhotos.filter { $0.colorLabel == label }.count
        }
    }

    var libraryStatusText: String {
        if currentFolderURL != nil {
            return T("\(folderPhotos.count) 张照片 · \(subfolderEntries.count) 个文件夹",
                     "\(folderPhotos.count) photographs · \(subfolderEntries.count) folders")
        }
        return T("\(folders.count) 个文件夹 · \(loosePhotos.count) 张照片",
                 "\(folders.count) folders · \(loosePhotos.count) photographs")
    }

    func stockLabel(for photo: Photo) -> String {
        if let id = photo.edit.lutID,
           let lut = importedLUTs.first(where: { $0.id == id }) {
            return lut.name
        }
        if let lookID = photo.edit.lookID,
           let stockID = index.stockID(forLook: lookID),
           let stock = index.stock(stockID) {
            return stock.name
        }
        return T("未选胶片", "No film")
    }

    var currentEdit: PhotoEdit {
        currentPhoto?.edit ?? PhotoEdit(lookID: defaultLookID(for: browseStockID))
    }

    var currentAdjustments: Adjustments { currentEdit.adjustments }
    var currentCurves: CurveSet { currentEdit.curves }

    var currentLook: FilmVariant? {
        index.look(currentPhoto?.edit.lookID) ?? index.look(defaultLookID(for: browseStockID))
    }

    var currentStock: FilmStock? {
        index.stock(index.stockID(forLook: currentPhoto?.edit.lookID) ?? browseStockID)
            ?? index.stock(catalog.defaultStock)
    }

    var currentStockID: String? { currentStock?.id }

    var currentImportedLUT: ImportedLUT? {
        guard let id = currentPhoto?.edit.lutID else { return nil }
        return importedLUTs.first(where: { $0.id == id })
    }

    var filteredLUTs: [ImportedLUT] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return importedLUTs }
        return importedLUTs.filter {
            "\($0.name) \($0.originalFileName)".lowercased().contains(query)
        }
    }

    var defaultStock: FilmStock? { index.stock(catalog.defaultStock) }

    var libraryIsLoading: Bool {
        switch libraryState {
        case .idle, .loading: return true
        case .ready, .failed: return false
        }
    }

    var brands: [String] {
        Array(Set(catalog.stocks.map(\.brand))).sorted { lhs, rhs in
            let a = ["Kodak", "Fujifilm", "Agfa"].firstIndex(of: lhs) ?? 99
            let b = ["Kodak", "Fujifilm", "Agfa"].firstIndex(of: rhs) ?? 99
            return a == b ? lhs < rhs : a < b
        }
    }

    var engines: [String] {
        ["SpektraFilm", "Spectral Film"]
    }

    var filteredStocks: [FilmStock] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalog.stocks.filter { stock in
            if favoritesOnly && !favorites.contains(stock.id) { return false }
            if let brandFilter, stock.brand != brandFilter { return false }
            if let typeFilter, stock.type != typeFilter { return false }
            if let engineFilter, !stock.variants.contains(where: { $0.engine == engineFilter }) { return false }
            if !query.isEmpty {
                let haystack = "\(stock.brand) \(stock.name) \(stock.type.label) \(stock.type.localizedLabel) \(stock.iso.map(String.init) ?? "")".lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }

    var activeFilterCount: Int {
        var count = 0
        if typeFilter != nil { count += 1 }
        if engineFilter != nil { count += 1 }
        if favoritesOnly { count += 1 }
        return count
    }

    func defaultLookID(for stockID: String?) -> String? {
        index.stock(stockID)?.defaultLook ?? index.stock(catalog.defaultStock)?.defaultLook
    }

    func thumbnail(for stock: FilmStock) -> CGImage? {
        if stock.id == currentStockID, let look = currentLook {
            return lookThumbs[look.id] ?? lookThumbs[stock.defaultLook]
        }
        return lookThumbs[stock.defaultLook]
    }

    func variant(for lookID: String?) -> FilmVariant? { index.look(lookID) }

    func stock(for lookID: String?) -> FilmStock? {
        index.stock(index.stockID(forLook: lookID))
    }

    // MARK: Imported LUTs

    func chooseLUTFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let cube = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cube]
        }
        panel.prompt = T("导入", "Import")
        panel.message = T("选择 .cube 3D LUT。文件头声明 ACEScc 的按 ACES LMT 流程处理，其余按 Rec.709 显示 LUT。",
                           "Choose a .cube 3D LUT. Header metadata decides the domain: ACEScc LMTs run through ACES, everything else is a Rec.709 display LUT.")
        guard panel.runModal() == .OK else { return }
        importLUTURLs(panel.urls)
    }

    func importLUTURLs(_ urls: [URL]) {
        guard let renderer else { return }
        guard !urls.isEmpty else { return }
        let remaining = 50 - importedStore.entries.count
        guard remaining > 0 else {
            alertMessage = T("自定义 LUT 已达 50 个上限，请先删除一些。", "The custom LUT library is full (50). Delete some first.")
            return
        }
        let acceptedURLs = Array(urls.prefix(remaining))
        if acceptedURLs.count < urls.count {
            alertMessage = T("一次最多保留 50 个自定义 LUT，本次只导入前 \(acceptedURLs.count) 个。",
                             "The library keeps at most 50 custom LUTs; only the first \(acceptedURLs.count) were imported.")
        }
        isImportingLUT = true
        let store = importedStore
        let device = renderer.device
        let library = lutLibrary
        let urlsToImport = acceptedURLs
        DispatchQueue.global(qos: .userInitiated).async {
            var imported: [(ImportedLUT, MTLTexture)] = []
            var failures: [String] = []
            for url in urlsToImport {
                do {
                    let pair = try store.importCube(from: url, device: device)
                    imported.append(pair)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isImportingLUT = false
                for (entry, texture) in imported {
                    library.registerUserLUT(
                        id: entry.id,
                        texture: texture,
                        info: LUTInfo(isACEScc: entry.isACESccLMT,
                                      exposureEV: Float(entry.exposureEV ?? 0))
                    )
                }
                self.importedLUTs = store.entries
                self.invalidateImportedThumbs()
                if !imported.isEmpty {
                    self.libraryMode = .luts
                    if self.currentPhoto != nil {
                        self.selectImportedLUT(imported[0].0)
                    }
                    self.showToast(
                        T("已导入 \(imported.count) 个 LUT", "Imported \(imported.count) LUT\(imported.count == 1 ? "" : "s")"),
                        symbol: "square.stack.3d.up"
                    )
                }
                if !failures.isEmpty {
                    self.alertMessage = failures.joined(separator: "\n")
                }
            }
        }
    }

    func selectImportedLUT(_ lut: ImportedLUT) {
        libraryMode = .luts
        guard let photoIndex = currentPhotoIndex else {
            showToast(T("先导入一张照片，再选择 LUT", "Import a photograph before applying a LUT"),
                      symbol: "photo")
            return
        }
        photos[photoIndex].edit.lutID = lut.id
        photos[photoIndex].edit.lutStrength = 1
        beginToneAnalysis()
        applyCurrentEdit()
    }

    func clearLUT() {
        guard let photoIndex = currentPhotoIndex, photos[photoIndex].edit.lutID != nil else { return }
        photos[photoIndex].edit.lutID = nil
        beginToneAnalysis()
        applyCurrentEdit()
    }

    func setLUTStrength(_ value: Double) {
        guard let photoIndex = currentPhotoIndex else { return }
        photos[photoIndex].edit.lutStrength = value.clamped(to: 0...1)
        applyCurrentEdit()
    }

    func deleteImportedLUT(_ lut: ImportedLUT) {
        importedStore.remove(lut)
        importedLUTs = importedStore.entries
        lutLibrary.removeUserLUT(id: lut.id)
        invalidateImportedThumbs()
        if let photoIndex = currentPhotoIndex, photos[photoIndex].edit.lutID == lut.id {
            photos[photoIndex].edit.lutID = nil
            beginToneAnalysis()
            applyCurrentEdit()
        }
    }

    // MARK: Import

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.prompt = T("导入", "Import")
        panel.message = T("选择要用 OltraFlim 显影的照片。", "Choose photographs to develop with OltraFlim.")
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }

    func importURLs(_ urls: [URL], openFirst: Bool? = nil) {
        let supported = urls.filter(Self.isSupportedImage)
        guard !supported.isEmpty else {
            alertMessage = T("没有可导入的照片格式。", "No supported image files were selected.")
            return
        }
        let shouldOpen = openFirst ?? (screen == .editor)
        var newPhotos: [Photo] = []
        for url in supported {
            if photos.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { continue }
            newPhotos.append(makePhoto(url: url, folder: nil))
        }
        guard !newPhotos.isEmpty else {
            if let first = urls.first {
                alertMessage = T("\(first.lastPathComponent) 已经在照片库里。",
                                 "\(first.lastPathComponent) is already in the library.")
            }
            return
        }
        photos.append(contentsOf: newPhotos)
        saveLibrary()
        if !shouldOpen, screen == .library, currentFolderURL != nil {
            // Imported files are not copied into the folder being browsed;
            // return to the root so the new loose photographs are visible.
            folderTrail = []
            subfolderEntries = []
        }
        if shouldOpen, let first = newPhotos.first {
            openPhoto(first.id)
        }
        showToast(T("已导入 \(newPhotos.count) 张照片", "Imported \(newPhotos.count) photo\(newPhotos.count == 1 ? "" : "s")"), symbol: "photo.on.rectangle")
    }

    private func importLaunchArguments() {
        let args = CommandLine.arguments
        if let lookIndex = args.firstIndex(of: "--look"), args.count > lookIndex + 1 {
            pendingLookID = args[lookIndex + 1]
        }
        if args.contains("--before") {
            pendingBefore = true
        }
        if let tonalIndex = args.firstIndex(of: "--tonal"), args.count > tonalIndex + 1 {
            pendingTonal = Double(args[tonalIndex + 1])
        }
        if let colorIndex = args.firstIndex(of: "--color"), args.count > colorIndex + 1 {
            pendingColor = Double(args[colorIndex + 1])
        }
        if let libraryIndex = args.firstIndex(of: "--library"), args.count > libraryIndex + 1 {
            libraryMode = args[libraryIndex + 1].lowercased() == "luts" ? .luts : .films
        }
        if args.contains("--curve-demo") { pendingCurveDemo = true }
        if args.contains("--color-demo") { pendingColorDemo = true }
        if let tabIndex = args.firstIndex(of: "--tab"), args.count > tabIndex + 1 {
            switch args[tabIndex + 1].lowercased() {
            case "color": inspectorTab = .color
            case "curves": inspectorTab = .curves
            default: inspectorTab = .light
            }
        }
        if let lutIndex = args.firstIndex(of: "--import-lut"), args.count > lutIndex + 1 {
            let url = URL(fileURLWithPath: args[lutIndex + 1])
            if FileManager.default.fileExists(atPath: url.path) { pendingImportLUT = url }
        }
        if args.contains("--export-sheet") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.exportPresented = true
            }
        }
        if let exportIndex = args.firstIndex(of: "--export"), args.count > exportIndex + 1 {
            let url = URL(fileURLWithPath: args[exportIndex + 1])
            if url.pathExtension.lowercased() == "png" { exportOptions.format = .png }
            if url.pathExtension.lowercased() == "tiff" || url.pathExtension.lowercased() == "tif" { exportOptions.format = .tiff }
            pendingExportURL = url
        }
        guard let flagIndex = args.firstIndex(of: "--open"), args.count > flagIndex + 1 else { return }
        let paths = args[(flagIndex + 1)...].filter { !$0.hasPrefix("-") }
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty { importURLs(urls, openFirst: true) }
        if let lut = pendingImportLUT {
            pendingImportLUT = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.importLUTURLs([lut])
            }
        }
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Previews are decoded one at a time on a dedicated queue. A newer
    /// selection supersedes queued work, so rapid next/previous browsing never
    /// leaves several full-size previews resident at once.
    private func loadPreview(for photoID: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == photoID }) else { return }
        pendingPreviews.insert(photoID)
        previewLock.lock()
        previewGeneration += 1
        let generation = previewGeneration
        previewLock.unlock()
        let id = photos[index].id
        let url = photos[index].url
        let needsThumbnail = photos[index].thumbnail == nil
        previewQueue.async { [weak self] in
            guard let self else { return }
            guard self.currentPreviewGeneration() == generation else {
                DispatchQueue.main.async { self.pendingPreviews.remove(id) }
                return
            }
            do {
                let loaded = try ImageLoader.shared.loadPreview(url: url)
                guard self.currentPreviewGeneration() == generation else {
                    DispatchQueue.main.async { self.pendingPreviews.remove(id) }
                    return
                }
                let thumb = needsThumbnail
                    ? ThumbnailCache.shared.thumbnail(for: url, maxPixel: 480)
                    : nil
                DispatchQueue.main.async {
                    self.pendingPreviews.remove(id)
                    guard self.currentPreviewGeneration() == generation,
                          let index = self.photos.firstIndex(where: { $0.id == id }) else { return }
                    self.photos[index].previewImage = loaded.image
                    self.photos[index].linearImage = loaded.linearImage
                    self.photos[index].autoExposureEV = loaded.autoExposureEV
                    self.photos[index].pixelSize = loaded.pixelSize
                    self.photos[index].metadata = loaded.metadata
                    self.photos[index].sourceStats = loaded.stats
                    if self.photos[index].thumbnail == nil, let thumb {
                        self.photos[index].thumbnail = thumb
                        self.touchLibraryThumbnail(id)
                    }
                    self.photos[index].previewLoaded = true
                    self.touchPreview(id)
                    if self.selectedPhotoID == id {
                        self.installPreview(for: id)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.pendingPreviews.remove(id)
                    if let index = self.photos.firstIndex(where: { $0.id == id }) {
                        self.photos[index].previewError = error.localizedDescription
                    }
                    guard self.selectedPhotoID == id else { return }
                    self.alertMessage = error.localizedDescription
                    self.removePhoto(id)
                }
            }
        }
    }

    private func currentPreviewGeneration() -> Int {
        previewLock.lock()
        defer { previewLock.unlock() }
        return previewGeneration
    }

    private func touchPreview(_ id: UUID) {
        previewAccess.removeAll { $0 == id }
        previewAccess.append(id)
        while previewAccess.count > 3 {
            guard let candidate = previewAccess.first(where: { $0 != selectedPhotoID }),
                  let index = photos.firstIndex(where: { $0.id == candidate }) else { break }
            photos[index].previewImage = nil
            photos[index].linearImage = nil
            photos[index].previewLoaded = false
            previewAccess.removeAll { $0 == candidate }
            dropLookThumbs(for: candidate)
        }
    }

    private func dropLookThumbs(for id: UUID) {
        thumbCache[id] = nil
        importedThumbCache[id] = nil
        lookThumbAccess.removeAll { $0 == id }
    }

    private func installPreview(for photoID: UUID) {
        guard var photo = photos.first(where: { $0.id == photoID }),
              let image = photo.previewImage, let renderer else { return }
        do {
            try renderer.setImage(image: image, linear: photo.linearImage,
                                  autoExposureEV: photo.autoExposureEV)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        if let tonal = pendingTonal, let index = photos.firstIndex(where: { $0.id == photoID }) {
            photos[index].edit.adjustments.tonalTransparency = tonal
            photo.edit.adjustments.tonalTransparency = tonal
            pendingTonal = nil
        }
        if let color = pendingColor, let index = photos.firstIndex(where: { $0.id == photoID }) {
            photos[index].edit.adjustments.colorTransparency = color
            photo.edit.adjustments.colorTransparency = color
            pendingColor = nil
        }
        if pendingCurveDemo, let index = photos.firstIndex(where: { $0.id == photoID }) {
            let luma = ChannelCurve(points: [
                CurvePoint(0, 0), CurvePoint(0.25, 0.18), CurvePoint(0.5, 0.52),
                CurvePoint(0.75, 0.83), CurvePoint(1, 1)
            ])
            let red = ChannelCurve(points: [
                CurvePoint(0, 0.06), CurvePoint(0.25, 0.28), CurvePoint(0.5, 0.52),
                CurvePoint(0.75, 0.78), CurvePoint(1, 1)
            ])
            var curves = CurveSet.identity
            curves.luma = luma
            curves.red = red
            photos[index].edit.curves = curves
            photo.edit.curves = curves
            pendingCurveDemo = false
        }
        if pendingColorDemo, let index = photos.firstIndex(where: { $0.id == photoID }) {
            photos[index].edit.adjustments.hueShift = 8
            photos[index].edit.adjustments.colorDensity = 18
            photos[index].edit.adjustments.skinSaturation = 22
            photos[index].edit.adjustments.greenSaturation = -18
            photos[index].edit.adjustments.blueSaturation = 20
            photos[index].edit.adjustments.highlightWarmth = 35
            photos[index].edit.adjustments.shadowCoolness = 30
            photo.edit.adjustments.hueShift = 8
            photo.edit.adjustments.colorDensity = 18
            photo.edit.adjustments.skinSaturation = 22
            photo.edit.adjustments.greenSaturation = -18
            photo.edit.adjustments.blueSaturation = 20
            photo.edit.adjustments.highlightWarmth = 35
            photo.edit.adjustments.shadowCoolness = 30
            pendingColorDemo = false
        }
        libraryMode = photo.edit.usesLUT ? .luts : .films
        toneStats = .empty
        needsToneAnalysis = true
        renderer.setToneStats(.empty)
        renderer.setCompare(enabled: showOriginal, split: compareSplit)
        renderer.update(edit: photo.edit, look: index.look(photo.edit.lookID))
        renderer.requestHistogram()
        generateThumbsIfNeeded()
        if let stockID = pendingLookID, let stock = index.stock(stockID) {
            pendingLookID = nil
            selectStock(stock)
        }
        if pendingBefore {
            pendingBefore = false
            showOriginal = true
            renderer.setCompare(enabled: true, split: compareSplit)
        }
        if let exportURL = pendingExportURL {
            pendingExportURL = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.performExport(photo: photo, to: exportURL)
            }
        }
    }

    func selectPhoto(_ id: UUID) {
        guard photos.contains(where: { $0.id == id }) else { return }
        selectedPhotoID = id
        if let photo = photos.first(where: { $0.id == id }) {
            if let stockID = index.stockID(forLook: photo.edit.lookID) {
                browseStockID = stockID
            }
            lookThumbs = cachedLookThumbs(for: id) ?? [:]
            importedThumbs = cachedImportedThumbs(for: id) ?? [:]
            libraryMode = photo.edit.usesLUT ? .luts : .films
            if photo.previewLoaded, photo.previewImage != nil {
                touchPreview(id)
                installPreview(for: id)
            } else {
                renderer?.clearImage()
                loadPreview(for: id)
            }
        }
        showOriginal = false
        renderer?.setCompare(enabled: false, split: compareSplit)
    }

    func removePhoto(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let folder = photos[index].folder
        photos.remove(at: index)
        if let folder, let folderIndex = folders.firstIndex(where: {
            $0.url.standardizedFileURL.path == folder.standardizedFileURL.path
        }) {
            folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
        }
        thumbCache[id] = nil
        importedThumbCache[id] = nil
        previewAccess.removeAll { $0 == id }
        lookThumbAccess.removeAll { $0 == id }
        libraryThumbAccess.removeAll { $0 == id }
        pendingThumbnails.remove(id)
        pendingPreviews.remove(id)
        saveLibrary()
        if selectedPhotoID == id {
            if screen == .editor, let next = photos[safe: index] ?? photos.last {
                selectPhoto(next.id)
            } else {
                selectedPhotoID = nil
                renderer?.clearImage()
                lookThumbs = sampleThumbs
                importedThumbs = sampleImportedThumbs
                generateThumbsIfNeeded()
            }
        }
        if photos.isEmpty {
            screen = .library
        }
    }

    func nextPhoto() {
        let list = collectionPhotos
        guard let index = list.firstIndex(where: { $0.id == selectedPhotoID }), !list.isEmpty else { return }
        selectPhoto(list[(index + 1) % list.count].id)
    }

    func previousPhoto() {
        let list = collectionPhotos
        guard let index = list.firstIndex(where: { $0.id == selectedPhotoID }), !list.isEmpty else { return }
        selectPhoto(list[(index - 1 + list.count) % list.count].id)
    }

    // MARK: Films

    func selectStock(_ stock: FilmStock) {
        browseStockID = stock.id
        UserDefaults.standard.set(stock.id, forKey: "browseStock")
        pushRecent(stock.id)
        libraryMode = .films
        if let photoIndex = currentPhotoIndex {
            photos[photoIndex].edit.lookID = stock.defaultLook
            photos[photoIndex].edit.lutID = nil
            beginToneAnalysis()
            applyCurrentEdit()
        } else {
            rendererUpdatePreviewOnly()
        }
    }

    func selectVariant(_ variant: FilmVariant) {
        guard let photoIndex = currentPhotoIndex else { return }
        photos[photoIndex].edit.lookID = variant.id
        photos[photoIndex].edit.lutID = nil
        libraryMode = .films
        if let stockID = index.stockID(forLook: variant.id) {
            browseStockID = stockID
            UserDefaults.standard.set(stockID, forKey: "browseStock")
            pushRecent(stockID)
        }
        beginToneAnalysis()
        applyCurrentEdit()
    }

    func setStrength(_ value: Double) {
        guard let photoIndex = currentPhotoIndex else { return }
        photos[photoIndex].edit.strength = value.clamped(to: 0...1)
        applyCurrentEdit()
    }

    func updateCurve(_ channel: CurveChannel, points: [CurvePoint]) {
        guard let photoIndex = currentPhotoIndex else { return }
        var curve = photos[photoIndex].edit.curves.curve(channel)
        curve.points = points.sorted { $0.x < $1.x }
        photos[photoIndex].edit.curves.set(curve, for: channel)
        applyCurrentEdit()
    }

    func resetCurve(_ channel: CurveChannel) {
        guard let photoIndex = currentPhotoIndex else { return }
        photos[photoIndex].edit.curves.set(.identity, for: channel)
        applyCurrentEdit()
    }

    func resetAllCurves() {
        guard let photoIndex = currentPhotoIndex else { return }
        photos[photoIndex].edit.curves = .identity
        applyCurrentEdit()
    }

    func updateAdjustments(_ mutate: (inout Adjustments) -> Void) {
        guard let photoIndex = currentPhotoIndex else { return }
        mutate(&photos[photoIndex].edit.adjustments)
        applyCurrentEdit()
    }

    func resetAdjustment(_ keyPath: WritableKeyPath<Adjustments, Double>) {
        let fallback: Double
        switch keyPath {
        case \Adjustments.grainSize: fallback = 38
        case \Adjustments.grainRoughness: fallback = 50
        case \Adjustments.halationThreshold: fallback = 55
        case \Adjustments.halationRadius: fallback = 50
        case \Adjustments.halationWarmth: fallback = 75
        case \Adjustments.vignetteMidpoint: fallback = 50
        case \Adjustments.vignetteFeather: fallback = 50
        default: fallback = 0
        }
        updateAdjustments { $0[keyPath: keyPath] = fallback }
    }

    func resetAdjustments() {
        guard let photoIndex = currentPhotoIndex else { return }
        photos[photoIndex].edit.adjustments = .neutral
        applyCurrentEdit()
    }

    func resetAll() {
        guard let photoIndex = currentPhotoIndex else { return }
        let stock = index.stock(index.stockID(forLook: photos[photoIndex].edit.lookID)) ?? index.stock(browseStockID)
        photos[photoIndex].edit = PhotoEdit(lookID: stock?.defaultLook ?? defaultLookID(for: browseStockID),
                                           strength: 1, adjustments: .neutral)
        libraryMode = .films
        beginToneAnalysis()
        applyCurrentEdit()
        showToast(T("已重置为 \(stock?.name ?? "默认胶片")", "Reset to \(stock?.name ?? "the default film")"),
                  symbol: "arrow.uturn.backward")
    }

    func autoTone() {
        guard let photo = currentPhoto else { return }
        let stats = photo.sourceStats
        let target = 0.455
        let ev = log2(target / max(stats.p50, 0.02)).clamped(to: -1.4...1.4)
        if currentAdjustments.tonalTransparency > 0 || currentAdjustments.colorTransparency > 0 {
            beginToneAnalysis()
        }
        updateAdjustments { adjust in
            adjust.exposure = (ev * 10).rounded() / 10
            adjust.contrast = 8
            adjust.highlights = stats.p95 > 0.9 ? -22 : 0
            adjust.shadows = stats.p05 < 0.05 ? 18 : 2
            adjust.whites = stats.p95 > 0.95 ? -8 : 5
            adjust.blacks = stats.p05 < 0.03 ? 5 : -2
            adjust.vibrance = 8
        }
    }

    private func applyCurrentEdit() {
        guard let photo = currentPhoto else { return }
        editStore.set(photo.edit, for: photo.url)
        scheduleEditSave()
        guard let renderer, photo.previewLoaded else { return }
        renderer.setToneStats(toneStats)
        renderer.update(edit: photo.edit, look: index.look(photo.edit.lookID))
        scheduleHistogram()
    }

    private func beginToneAnalysis() {
        toneStats = .empty
        needsToneAnalysis = true
        renderer?.setToneStats(.empty)
    }

    func analyzeTone() {
        guard currentPhoto != nil else { return }
        beginToneAnalysis()
        applyCurrentEdit()
        renderer?.requestHistogram()
    }

    private func handleHistogram(_ data: HistogramData, _ incoming: ToneStats) {
        histogram = data
        var updated = toneStats
        if needsToneAnalysis {
            updated = incoming
            needsToneAnalysis = false
        } else {
            if currentAdjustments.tonalTransparency <= 0.001 {
                updated.blackPoint = incoming.blackPoint
                updated.whitePoint = incoming.whitePoint
            }
            if currentAdjustments.colorTransparency <= 0.001 {
                updated.whiteDeltaR = incoming.whiteDeltaR
                updated.whiteDeltaG = incoming.whiteDeltaG
                updated.whiteDeltaB = incoming.whiteDeltaB
                updated.blackDeltaR = incoming.blackDeltaR
                updated.blackDeltaG = incoming.blackDeltaG
                updated.blackDeltaB = incoming.blackDeltaB
                updated.whiteCount = incoming.whiteCount
                updated.blackCount = incoming.blackCount
                updated.whiteAverageR = incoming.whiteAverageR
                updated.whiteAverageG = incoming.whiteAverageG
                updated.whiteAverageB = incoming.whiteAverageB
                updated.blackAverageR = incoming.blackAverageR
                updated.blackAverageG = incoming.blackAverageG
                updated.blackAverageB = incoming.blackAverageB
            }
        }
        if updated != toneStats {
            toneStats = updated
            if currentAdjustments.tonalTransparency > 0 || currentAdjustments.colorTransparency > 0 {
                renderer?.setToneStats(updated)
            }
        }
    }

    private func scheduleEditSave() {
        editSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.editStore.save()
        }
        editSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveEditsNow() {
        editSaveWork?.cancel()
        editStore.save()
    }

    private func rendererUpdatePreviewOnly() {
        renderer?.update(edit: currentEdit, look: currentLook)
    }

    private func scheduleHistogram() {
        histogramWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.renderer?.requestHistogram()
        }
        histogramWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func toggleShowOriginal() {
        showOriginal.toggle()
        renderer?.setCompare(enabled: showOriginal, split: compareSplit)
    }

    func setCompareSplit(_ value: Double) {
        compareSplit = value.clamped(to: 0...1)
        if showOriginal {
            renderer?.setCompare(enabled: true, split: compareSplit)
        }
    }

    // MARK: Favorites

    func isFavorite(_ stock: FilmStock) -> Bool { favorites.contains(stock.id) }

    func toggleFavorite(_ stock: FilmStock) {
        if favorites.contains(stock.id) {
            favorites.remove(stock.id)
        } else {
            favorites.insert(stock.id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    private func pushRecent(_ id: String) {
        recentStocks.removeAll { $0 == id }
        recentStocks.insert(id, at: 0)
        if recentStocks.count > 8 { recentStocks.removeLast(recentStocks.count - 8) }
        UserDefaults.standard.set(recentStocks, forKey: "recentStocks")
    }

    // MARK: Thumbnails

    private func thumbnailSource() -> (image: CGImage, linear: CIImage?, autoEV: Double, key: String, photoID: UUID?)? {
        if let photo = currentPhoto, let image = photo.previewImage {
            return (image, photo.linearImage, photo.autoExposureEV, "photo:\(photo.id.uuidString)", photo.id)
        }
        if let image = samplePreviewImage {
            return (image, nil, 0, "sample", nil)
        }
        return nil
    }

    private func cachedLookThumbs(for photoID: UUID?) -> [String: CGImage]? {
        guard let photoID else { return sampleThumbs }
        let cached = thumbCache[photoID]
        if cached?.isEmpty == false { touchLookThumbCache(photoID) }
        return cached
    }

    private func cachedImportedThumbs(for photoID: UUID?) -> [String: CGImage]? {
        guard let photoID else { return sampleImportedThumbs }
        let cached = importedThumbCache[photoID]
        if cached?.isEmpty == false { touchLookThumbCache(photoID) }
        return cached
    }

    private func storeLookThumbs(_ images: [String: CGImage], for photoID: UUID) {
        thumbCache[photoID] = images
        touchLookThumbCache(photoID)
    }

    private func storeImportedThumbs(_ images: [String: CGImage], for photoID: UUID) {
        importedThumbCache[photoID] = images
        touchLookThumbCache(photoID)
    }

    /// The 113-look atlas is a few megabytes per photograph. Only the most
    /// recently used photographs keep it so multi-photo editing stays bounded.
    private func touchLookThumbCache(_ id: UUID) {
        lookThumbAccess.removeAll { $0 == id }
        lookThumbAccess.append(id)
        while lookThumbAccess.count > 3 {
            guard let candidate = lookThumbAccess.first(where: { $0 != selectedPhotoID }) else { break }
            lookThumbAccess.removeAll { $0 == candidate }
            thumbCache[candidate] = nil
            importedThumbCache[candidate] = nil
        }
    }

    private func generateThumbsIfNeeded() {
        guard let renderer, lutLibrary.neutral0 != nil else { return }
        guard let source = thumbnailSource() else { return }
        if isGeneratingThumbs { return }

        let lookCache = cachedLookThumbs(for: source.photoID)
        let importedCache = cachedImportedThumbs(for: source.photoID)
        lookThumbs = lookCache ?? [:]
        importedThumbs = importedCache ?? [:]

        let needsFilm = lookCache?.isEmpty ?? true
        let needsImported = !importedLUTs.isEmpty && (importedCache?.isEmpty ?? true)
        guard needsFilm || needsImported else { return }

        thumbGeneration += 1
        let generation = thumbGeneration
        isGeneratingThumbs = true
        let variants = catalog.stocks.flatMap(\.variants)

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.isGeneratingThumbs = false
            if self.thumbnailSource()?.key != source.key {
                self.generateThumbsIfNeeded()
            }
        }

        let importStep: () -> Void = { [weak self] in
            guard let self else { return }
            guard generation == self.thumbGeneration else { return }
            guard !self.importedLUTs.isEmpty else {
                self.importedThumbs = [:]
                finish()
                return
            }
            if let cached = self.cachedImportedThumbs(for: source.photoID), !cached.isEmpty {
                self.importedThumbs = cached
                finish()
                return
            }
            renderer.generateImportedLUTThumbnails(source: source.linear ?? CIImage(cgImage: source.image),
                                                   autoExposureEV: autoExposure ? Float(source.autoEV) : 0,
                                                   luts: self.importedLUTs) { [weak self] images in
                guard let self else { return }
                if generation == self.thumbGeneration {
                    if let photoID = source.photoID {
                        self.storeImportedThumbs(images, for: photoID)
                    } else {
                        self.sampleImportedThumbs = images
                    }
                    if self.thumbnailSource()?.key == source.key {
                        self.importedThumbs = images
                    }
                } else {
                    return
                }
                finish()
            }
        }

        if needsFilm {
            renderer.generateLookThumbnails(source: source.linear ?? CIImage(cgImage: source.image),
                                            autoExposureEV: autoExposure ? Float(source.autoEV) : 0,
                                            looks: variants) { [weak self] images in
                guard let self else { return }
                if generation == self.thumbGeneration {
                    if let photoID = source.photoID {
                        self.storeLookThumbs(images, for: photoID)
                    } else {
                        self.sampleThumbs = images
                    }
                    if self.thumbnailSource()?.key == source.key {
                        self.lookThumbs = images
                        if self.importedThumbs.isEmpty { self.importedThumbs = self.cachedImportedThumbs(for: source.photoID) ?? [:] }
                    }
                    importStep()
                } else {
                    return
                }
            }
        } else {
            importStep()
        }
    }

    private func invalidateImportedThumbs() {
        if let id = selectedPhotoID {
            importedThumbCache[id] = nil
        }
        sampleImportedThumbs = [:]
        importedThumbs = [:]
        thumbGeneration += 1
        isGeneratingThumbs = false
        generateThumbsIfNeeded()
    }

    // MARK: Export

    func beginExport() {
        guard let photo = currentPhoto else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportOptions.format.utType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFileName(for: photo)
        panel.message = T("导出显影后的照片。", "Export the developed photograph.")
        if let directory = defaultExportDirectory {
            panel.directoryURL = directory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performExport(photo: photo, to: url)
    }

    func chooseDefaultExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = T("选择", "Choose")
        panel.message = T("选择导出时的默认保存位置。",
                          "Choose where exported photographs are saved by default.")
        if let directory = defaultExportDirectory {
            panel.directoryURL = directory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaultExportDirectoryPath = url.path
        showToast(T("默认保存位置已更新", "Default export folder updated"),
                  detail: url.lastPathComponent,
                  symbol: "folder")
    }

    /// Clears derived image caches only: memory thumbnails, decoded previews
    /// and the on-disk thumbnail cache. Library indexes, edits, favourites,
    /// imported LUTs and the original files on disk are never touched.
    func clearThumbnailCache() {
        guard !isClearingCache else { return }
        isClearingCache = true
        let selected = selectedPhotoID
        previewLock.lock()
        previewGeneration += 1
        previewLock.unlock()
        thumbGeneration += 1
        isGeneratingThumbs = false
        previewAccess.removeAll()
        lookThumbAccess.removeAll()
        libraryThumbAccess.removeAll()
        thumbCache.removeAll()
        importedThumbCache.removeAll()
        sampleThumbs.removeAll()
        sampleImportedThumbs.removeAll()
        lookThumbs.removeAll()
        importedThumbs.removeAll()
        pendingThumbnails.removeAll()
        pendingFolderCovers.removeAll()
        let cache = thumbnailCache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            cache.clear()
            DispatchQueue.main.async {
                guard let self else { return }
                // Release the in-memory copies only after the disk cache is
                // gone, so visible cards re-request from an empty cache instead
                // of repopulating it while the sweep is still running.
                for index in self.photos.indices {
                    self.photos[index].thumbnail = nil
                    self.photos[index].previewImage = nil
                    self.photos[index].linearImage = nil
                    self.photos[index].previewLoaded = false
                }
                for index in self.folders.indices {
                    self.folders[index].cover = nil
                }
                for index in self.subfolderEntries.indices {
                    self.subfolderEntries[index].cover = nil
                }
                self.renderer?.clearImage()
                self.isClearingCache = false
                self.storageUsage.cacheBytes = 0
                if let selected, self.photos.contains(where: { $0.id == selected }) {
                    self.selectPhoto(selected)
                } else {
                    self.loadSamplePreview()
                }
                self.refreshStorageUsage()
                self.showToast(T("已清理图片缓存", "Image cache cleared"),
                              detail: T("原照片、编辑记录与导入的 LUT 均未改动",
                                         "Originals, edits and imported LUTs were left untouched"),
                              symbol: "trash")
            }
        }
    }

    var dataFolderURL: URL {
        importedStore.dataFolder
    }

    func refreshStorageUsage() {
        let cacheRoot = thumbnailCache.root
        let dataURL = dataFolderURL
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cacheBytes = StorageInspector.size(of: cacheRoot)
            let dataBytes = StorageInspector.size(of: dataURL)
            DispatchQueue.main.async {
                self?.storageUsage = StorageUsage(cacheBytes: cacheBytes, dataBytes: dataBytes)
            }
        }
    }

    func revealDataFolder() {
        NSWorkspace.shared.open(dataFolderURL)
    }

    // MARK: Memory pressure

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.memoryPressureSource else { return }
            self.handleMemoryPressure(critical: source.data.contains(.critical))
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure(critical: Bool) {
        let selected = selectedPhotoID
        for index in photos.indices where photos[index].id != selected {
            photos[index].previewImage = nil
            photos[index].linearImage = nil
            photos[index].previewLoaded = false
        }
        previewAccess = selected.map { [$0] } ?? []
        if let selected {
            thumbCache = thumbCache[selected].map { [selected: $0] } ?? [:]
            importedThumbCache = importedThumbCache[selected].map { [selected: $0] } ?? [:]
        } else {
            thumbCache.removeAll()
            importedThumbCache.removeAll()
        }
        lookThumbAccess = selected.map { [$0] } ?? []
        if critical {
            for index in photos.indices where photos[index].id != selected {
                photos[index].thumbnail = nil
            }
            libraryThumbAccess = selected.map { [$0] } ?? []
        } else {
            evictLibraryThumbnails(libraryThumbAccess.count - 100)
        }
    }

    private func suggestedFileName(for photo: Photo) -> String {
        let base = (photo.name as NSString).deletingPathExtension
        let stock = index.stock(index.stockID(forLook: photo.edit.lookID))
        let film = stock.map { "\($0.brand)_\($0.name)" } ?? "OltraFlim"
        let safe = film.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "-")
        return "\(base)_\(safe).\(exportOptions.format.fileExtension)"
    }

    private func performExport(photo: Photo, to url: URL) {
        guard let renderer else { return }
        isExporting = true
        exportStatus = T("正在显影完整分辨率…", "Developing full resolution…")
        let options = exportOptions
        let edit = photo.edit
        let look = index.look(photo.edit.lookID)
        let sourceURL = photo.url
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                do {
                    let loaded = try ImageLoader.shared.loadFull(url: sourceURL)
                    guard let rendered = renderer.renderFull(loaded, edit: edit, look: look,
                                                            longEdge: options.longEdge) else {
                        throw RendererError.exportFailed
                    }
                    try Self.write(rendered, to: url, format: options.format, quality: options.quality)
                    DispatchQueue.main.async { [weak self] in
                        self?.isExporting = false
                        self?.showToast(T("已导出 \(url.lastPathComponent)", "Exported \(url.lastPathComponent)"), symbol: "checkmark")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.isExporting = false
                        self?.alertMessage = T("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    nonisolated private static func write(_ image: CGImage, to url: URL, format: ExportFormat, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil
        ) else { throw RendererError.exportFailed }
        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RendererError.exportFailed }
    }

    func saveExportOptions() {
        if let data = try? JSONEncoder().encode(exportOptions) {
            UserDefaults.standard.set(data, forKey: "exportOptions")
        }
    }

    // MARK: Toast

    func showToast(_ text: String, detail: String? = nil, symbol: String = "checkmark") {
        toastTask?.cancel()
        withAnimation(DS.spring) {
            toast = ToastMessage(text: text, detail: detail, symbol: symbol)
        }
        let id = toast?.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.toast?.id == id else { return }
                withAnimation(DS.easeOutExpo) { self.toast = nil }
            }
        }
    }

    func revealCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        NSWorkspace.shared.activateFileViewerSelecting([photo.url])
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
