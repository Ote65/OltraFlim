import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var shortLabel: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        }
    }
}

/// OltraFlim ships two inline string tables. The current language is a process-
/// wide value; views rebuild when the language changes (see ContentView/Settings
/// `.id`), so every literal re-evaluates without threading a localizer through
/// forty view structs.
enum L10n {
    static var current: AppLanguage = .chinese

    static func t(_ chinese: String, _ english: String) -> String {
        current == .chinese ? chinese : english
    }
}

func T(_ chinese: String, _ english: String) -> String {
    L10n.t(chinese, english)
}

extension FilmType {
    var localizedLabel: String {
        switch self {
        case .negative: return T("负片", "Negative")
        case .slide: return T("反转片", "Slide")
        case .cinema: return T("电影片", "Cinema")
        case .instant: return T("即时成像", "Instant")
        case .special: return T("特种胶片", "Special")
        case .lut: return T("LUT", "LUT")
        }
    }

    var localizedShortLabel: String {
        switch self {
        case .negative: return T("负", "NEG")
        case .slide: return T("反", "SLIDE")
        case .cinema: return T("影", "CINE")
        case .instant: return T("即", "INST")
        case .special: return T("特", "SPEC")
        case .lut: return T("LUT", "LUT")
        }
    }
}

extension FilmVariant {
    var localizedLabel: String {
        switch label {
        case "Slide": return T("反转片", "Slide")
        case "Print": return T("相纸", "Print")
        case "Infrared": return T("红外", "Infrared")
        case "ADX density": return T("ADX 密度", "ADX density")
        default: return label
        }
    }
}
