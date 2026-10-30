import Foundation
import CoreGraphics

// MARK: - Catalog

struct FilmCatalog: Decodable {
    let version: Int
    let lutSize: Int
    let defaultStock: String
    let attribution: String
    let stocks: [FilmStock]
}

enum FilmType: String, Decodable, CaseIterable, Hashable {
    case negative
    case slide
    case cinema
    case instant
    case special
    case lut

    var label: String {
        switch self {
        case .negative: return "Negative"
        case .slide: return "Slide"
        case .cinema: return "Cinema"
        case .instant: return "Instant"
        case .special: return "Special"
        case .lut: return "LUT"
        }
    }

    var shortLabel: String {
        switch self {
        case .negative: return "NEG"
        case .slide: return "SLIDE"
        case .cinema: return "CINE"
        case .instant: return "INST"
        case .special: return "SPEC"
        case .lut: return "LUT"
        }
    }

    var symbol: String {
        switch self {
        case .negative: return "circle.lefthalf.filled"
        case .slide: return "sun.max"
        case .cinema: return "film"
        case .instant: return "square.on.square"
        case .special: return "sparkles"
        case .lut: return "square.stack.3d.up"
        }
    }
}

struct FilmStock: Identifiable, Decodable, Hashable {
    let id: String
    let brand: String
    let name: String
    let type: FilmType
    let iso: Int?
    let push: Int
    let defaultLook: String
    let swatch: [String]
    let luminance: Double
    let variants: [FilmVariant]

    var displayName: String { name }
    var subtitle: String {
        var parts: [String] = [brand]
        if let iso { parts.append("ISO \(iso)") }
        if push > 0 { parts.append("Push \(push)") }
        return parts.joined(separator: " · ")
    }

    var typeLine: String {
        var parts: [String] = [type.localizedLabel]
        if let iso { parts.append("ISO \(iso)") }
        if push > 0 { parts.append("Push \(push)") }
        return parts.joined(separator: " · ")
    }
}

struct FilmVariant: Identifiable, Decodable, Hashable {
    let id: String
    let label: String
    let engine: String
    let source: String
    let print: String?
    let variant: String?
    let exposureEV: Double
    let note: String?
    let displayRequirement: String?
    let lut: String

    var engineShort: String { engine == "SpektraFilm" ? "SPK" : "SPC" }
}

// MARK: - Lookup helpers

struct CatalogIndex {
    private let stockByID: [String: FilmStock]
    private let lookByID: [String: FilmVariant]
    private let stockIDByLook: [String: String]

    init(catalog: FilmCatalog) {
        var stocks: [String: FilmStock] = [:]
        var looks: [String: FilmVariant] = [:]
        var owners: [String: String] = [:]
        for stock in catalog.stocks {
            stocks[stock.id] = stock
            for variant in stock.variants {
                looks[variant.id] = variant
                owners[variant.id] = stock.id
            }
        }
        stockByID = stocks
        lookByID = looks
        stockIDByLook = owners
    }

    func stockID(forLook id: String?) -> String? {
        guard let id else { return nil }
        return stockIDByLook[id]
    }

    func stock(_ id: String?) -> FilmStock? {
        guard let id else { return nil }
        return stockByID[id]
    }

    func look(_ id: String?) -> FilmVariant? {
        guard let id else { return nil }
        return lookByID[id]
    }
}


extension FilmCatalog {
    static let empty = FilmCatalog(
        version: 0,
        lutSize: 33,
        defaultStock: "kodak-portra-400",
        attribution: "",
        stocks: []
    )
}
