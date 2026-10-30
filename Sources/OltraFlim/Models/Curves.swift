import Foundation

enum CurveChannel: String, CaseIterable, Identifiable {
    case luma
    case red
    case green
    case blue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .luma: return T("明暗", "Luma")
        case .red: return "R"
        case .green: return "G"
        case .blue: return "B"
        }
    }
}

struct CurvePoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

struct ChannelCurve: Codable, Equatable {
    var points: [CurvePoint]

    static let identity = ChannelCurve(points: [
        CurvePoint(0.0, 0.0),
        CurvePoint(0.25, 0.25),
        CurvePoint(0.5, 0.5),
        CurvePoint(0.75, 0.75),
        CurvePoint(1.0, 1.0)
    ])

    init(points: [CurvePoint]) {
        self.points = points.sorted { $0.x < $1.x }
    }

    var isIdentity: Bool {
        abs(CurveMath.values(points: points)[128] - 0.5) < 0.004
            && abs(CurveMath.values(points: points)[255] - 1.0) < 0.004
    }
}

struct CurveSet: Codable, Equatable {
    var luma: ChannelCurve = .identity
    var red: ChannelCurve = .identity
    var green: ChannelCurve = .identity
    var blue: ChannelCurve = .identity

    static let identity = CurveSet()

    func curve(_ channel: CurveChannel) -> ChannelCurve {
        switch channel {
        case .luma: return luma
        case .red: return red
        case .green: return green
        case .blue: return blue
        }
    }

    mutating func set(_ curve: ChannelCurve, for channel: CurveChannel) {
        switch channel {
        case .luma: luma = curve
        case .red: red = curve
        case .green: green = curve
        case .blue: blue = curve
        }
    }

    var isIdentity: Bool {
        luma.isIdentity && red.isIdentity && green.isIdentity && blue.isIdentity
    }
}

enum CurveMath {
    /// PCHIP (monotone cubic) evaluation, sampled to `count` evenly spaced x
    /// values in 0…1. This keeps tone curves smooth without the overshoot of
    /// a plain Catmull-Rom spline.
    static func values(points input: [CurvePoint], count: Int = 256) -> [Double] {
        let points = input.sorted { $0.x < $1.x }
        guard points.count >= 2, count > 1 else {
            return (0..<count).map { Double($0) / Double(max(count - 1, 1)) }
        }

        let xs = points.map { min(1, max(0, $0.x)) }
        let ys = points.map { min(1, max(0, $0.y)) }
        let n = points.count

        var h = [Double](repeating: 0, count: n - 1)
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            h[i] = max(1e-6, xs[i + 1] - xs[i])
            delta[i] = (ys[i + 1] - ys[i]) / h[i]
        }

        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                if delta[i - 1] * delta[i] <= 0 {
                    m[i] = 0
                } else {
                    let w1 = 2 * h[i] + h[i - 1]
                    let w2 = h[i] + 2 * h[i - 1]
                    m[i] = (w1 + w2) / (w1 / delta[i - 1] + w2 / delta[i])
                }
            }
        }

        var output = [Double](repeating: 0, count: count)
        for k in 0..<count {
            let x = Double(k) / Double(count - 1)
            if x <= xs[0] {
                output[k] = ys[0]
                continue
            }
            if x >= xs[n - 1] {
                output[k] = ys[n - 1]
                continue
            }
            var seg = 0
            while seg < n - 2 && x > xs[seg + 1] { seg += 1 }
            let t = (x - xs[seg]) / h[seg]
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2 * t3 - 3 * t2 + 1
            let h10 = t3 - 2 * t2 + t
            let h01 = -2 * t3 + 3 * t2
            let h11 = t3 - t2
            let value = h00 * ys[seg] + h10 * h[seg] * m[seg]
                + h01 * ys[seg + 1] + h11 * h[seg] * m[seg + 1]
            output[k] = min(1, max(0, value))
        }
        return output
    }
}
