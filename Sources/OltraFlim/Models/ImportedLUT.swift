import Foundation

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
        inputSpace?.lowercased() == "acescc"
    }

    var subtitle: String {
        if isACESccLMT {
            return "\(size)³ · ACEScc LMT"
        }
        return "\(size)³ · \(T("自定义 LUT", "Custom LUT"))"
    }
}
