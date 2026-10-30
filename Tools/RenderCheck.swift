import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Headless render check for the Metal engine. Not shipped in the app.
// Usage: render-check <input> <output> [lookID] [exposure] [contrast] [grain] [halation] [vignette]
//        [strength] [grainSize] [clarity] [sharpen] [halationThreshold]
//        [halationRadius] [halationWarmth] [grainChroma] [grainShadow] [fade]

@main
struct RenderCheck {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: render-check <input> <output> [lookID] [exposure] [contrast] [grain] [halation] [vignette]")
            exit(2)
        }
        let input = URL(fileURLWithPath: args[1])
        let output = URL(fileURLWithPath: args[2])

        guard let data = try? Data(contentsOf: ResourceLocator.resourceURL("catalog.json")),
              let catalog = try? JSONDecoder().decode(FilmCatalog.self, from: data) else {
            print("catalog missing")
            exit(3)
        }
        let lookID = args.count > 3 ? args[3] : (catalog.stocks.first(where: { $0.id == "kodak-portra-400" })?.defaultLook ?? "")
        guard let look = catalog.stocks.flatMap({ $0.variants }).first(where: { $0.id == lookID }) else {
            print("look not found: \(lookID)")
            exit(3)
        }

        let library = LUTLibrary(size: catalog.lutSize)
        guard let renderer = Renderer(lutLibrary: library) else {
            print("renderer failed")
            exit(4)
        }
        do {
            try library.load(device: renderer.device, catalog: catalog) { _ in }
            let loaded = try ImageLoader.shared.loadFull(url: input)
            var edit = PhotoEdit(lookID: look.id, strength: 1, adjustments: .neutral)
            if args.count > 4 { edit.adjustments.exposure = Double(args[4]) ?? 0 }
            if args.count > 5 { edit.adjustments.contrast = Double(args[5]) ?? 0 }
            if args.count > 6 { edit.adjustments.grain = Double(args[6]) ?? 0 }
            if args.count > 7 { edit.adjustments.halation = Double(args[7]) ?? 0 }
            if args.count > 8 { edit.adjustments.vignette = Double(args[8]) ?? 0 }
            if args.count > 9 { edit.strength = Double(args[9]) ?? 1 }
            if args.count > 10 { edit.adjustments.grainSize = Double(args[10]) ?? 38 }
            if args.count > 11 { edit.adjustments.clarity = Double(args[11]) ?? 0 }
            if args.count > 12 { edit.adjustments.sharpen = Double(args[12]) ?? 0 }
            if args.count > 13 { edit.adjustments.halationThreshold = Double(args[13]) ?? 55 }
            if args.count > 14 { edit.adjustments.halationRadius = Double(args[14]) ?? 50 }
            if args.count > 15 { edit.adjustments.halationWarmth = Double(args[15]) ?? 75 }
            if args.count > 16 { edit.adjustments.grainChroma = Double(args[16]) ?? 0 }
            if args.count > 17 { edit.adjustments.grainShadow = Double(args[17]) ?? 0 }
            if args.count > 18 { edit.adjustments.fade = Double(args[18]) ?? 0 }
            guard let result = renderer.renderFull(loaded, edit: edit, look: look) else {
                print("render failed")
                exit(5)
            }
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                print("destination failed")
                exit(6)
            }
            CGImageDestinationAddImage(dest, result, nil)
            guard CGImageDestinationFinalize(dest) else { exit(7) }
            print("wrote \(output.path) \(result.width)x\(result.height) look=\(look.id)")
        } catch {
            print("error: \(error)")
            exit(8)
        }
    }
}
