import Foundation

struct ImportedLUT: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var size: Int
    var fileName: String
    var originalFileName: String
    var createdAt: Date
    var swatch: [String]

    var subtitle: String {
        "\(size)³ · \(T("自定义 LUT", "Custom LUT"))"
    }
}
