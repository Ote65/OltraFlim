import Foundation

/// A LUT header can spell its input space in several ways ("ACEScc",
/// "ACEScc (AP1)", "acescc"); the domain check is shared by the importer and
/// the stored record.
enum LUTInputSpace {
    static func isACEScc(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.lowercased().contains("acescc")
    }
}

struct ImportedLUT: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var size: Int
    var fileName: String
    var originalFileName: String
    var createdAt: Date
    var swatch: [String]
    /// Input space declared by the LUT header, e.g. "ACEScc".
    var inputSpace: String? = nil
    /// Exposure the LUT expects at its input, in stops.
    var exposureEV: Double? = nil

    var isACESccLMT: Bool {
        LUTInputSpace.isACEScc(inputSpace)
    }

    var subtitle: String {
        if isACESccLMT {
            return "\(size)³ · ACEScc LMT"
        }
        return "\(size)³ · \(T("自定义 LUT", "Custom LUT"))"
    }
}
