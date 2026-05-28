import AppKit
import Foundation

final class AnimationStore {
    private(set) var manifest: PetManifest
    private var cache: [String: LoadedAnimation] = [:]

    init() throws {
        manifest = Self.codexManifest()

        // Load the CodexPet spritesheet for movement/idle animations (original character).
        // Then fill in any IDs not in the atlas (concerned, nod, eat, dance, headpat,
        // shrug, peek, worried) from the bundled NomiAssets PNG frames.
        if try loadCodexPetAtlas() {
            try? supplementFromNomiAssets()
            return
        }

        // No spritesheet found — load everything from NomiAssets.
        try loadLegacyFramePack()
    }

    func animation(id: String) -> LoadedAnimation? {
        cache[id]
    }

    private func loadCodexPetAtlas() throws -> Bool {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex")
                .appendingPathComponent("pets")
                .appendingPathComponent("nomi"),
            Bundle.module.resourceURL?
                .appendingPathComponent("CodexPet")
                .appendingPathComponent("nomi"),
            Bundle.module.resourceURL?
                .appendingPathComponent("Resources")
                .appendingPathComponent("CodexPet")
                .appendingPathComponent("nomi"),
            Bundle.module.bundleURL
                .appendingPathComponent("Resources")
                .appendingPathComponent("CodexPet")
                .appendingPathComponent("nomi")
        ].compactMap { $0 }

        guard let petRoot = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("pet.json").path)
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent("spritesheet.webp").path)
        }) else {
            return false
        }

        let sheetURL = petRoot.appendingPathComponent("spritesheet.webp")
        guard let sheet = NSImage(contentsOf: sheetURL),
              let cgSheet = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let columns = 8
        let rows = 9
        let cellWidth = cgSheet.width / columns
        let cellHeight = cgSheet.height / rows

        for mapping in Self.codexMappings {
            var frames: [NSImage] = []
            for column in 0..<columns {
                let cropRect = CGRect(
                    x: column * cellWidth,
                    y: mapping.row * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                guard let frame = cgSheet.cropping(to: cropRect), Self.hasVisiblePixels(frame) else {
                    continue
                }
                frames.append(NSImage(cgImage: frame, size: NSSize(width: cellWidth, height: cellHeight)))
            }

            if frames.isEmpty == false {
                let spec = PetAnimation(
                    id: mapping.id,
                    name: mapping.state,
                    category: mapping.category,
                    fps: mapping.fps,
                    loop: mapping.loop,
                    frames: []
                )
                cache[mapping.id] = LoadedAnimation(spec: spec, frames: frames)
            }
        }

        return cache["idle_breathe"] != nil
    }

    private func loadLegacyFramePack() throws {
        let candidates = [
            Bundle.module.resourceURL?.appendingPathComponent("NomiAssets"),
            Bundle.module.resourceURL?.appendingPathComponent("Resources").appendingPathComponent("NomiAssets"),
            Bundle.module.bundleURL.appendingPathComponent("Resources").appendingPathComponent("NomiAssets")
        ].compactMap { $0 }

        guard let resourceRoot = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
        }) else {
            throw NSError(domain: "NomiPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing CodexPet/nomi or bundled NomiAssets/manifest.json"])
        }

        let rootURL = resourceRoot
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        manifest = try JSONDecoder().decode(PetManifest.self, from: data)

        for spec in manifest.animations {
            let frames = spec.frames.compactMap { relativePath -> NSImage? in
                let url = rootURL.appendingPathComponent(relativePath)
                return NSImage(contentsOf: url)
            }
            if frames.isEmpty == false {
                cache[spec.id] = LoadedAnimation(spec: spec, frames: frames)
            }
        }
    }

    /// Loads animations from NomiAssets for any IDs **not already in the cache**.
    /// Used to supplement the CodexPet atlas with new emotion/interaction animations.
    private func supplementFromNomiAssets() throws {
        let candidates = [
            Bundle.module.resourceURL?.appendingPathComponent("NomiAssets"),
            Bundle.module.resourceURL?.appendingPathComponent("Resources").appendingPathComponent("NomiAssets"),
            Bundle.module.bundleURL.appendingPathComponent("Resources").appendingPathComponent("NomiAssets")
        ].compactMap { $0 }

        guard let resourceRoot = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
        }) else { return }

        let data = try Data(contentsOf: resourceRoot.appendingPathComponent("manifest.json"))
        let nomiManifest = try JSONDecoder().decode(PetManifest.self, from: data)

        for spec in nomiManifest.animations where cache[spec.id] == nil {
            let frames = spec.frames.compactMap { relativePath -> NSImage? in
                NSImage(contentsOf: resourceRoot.appendingPathComponent(relativePath))
            }
            if frames.isEmpty == false {
                cache[spec.id] = LoadedAnimation(spec: spec, frames: frames)
            }
        }
    }

    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: bytesPerPixel).contains { pixels[$0] > 8 }
    }

    private static func codexManifest() -> PetManifest {
        PetManifest(
            name: "Nomi",
            version: "codex-pet",
            format: PetFormat(frameSize: [192, 208]),
            animations: codexMappings.map {
                PetAnimation(
                    id: $0.id,
                    name: $0.state,
                    category: $0.category,
                    fps: $0.fps,
                    loop: $0.loop,
                    frames: []
                )
            }
        )
    }

    private static let codexMappings: [CodexMapping] = [
        CodexMapping(id: "idle_breathe", state: "idle", row: 0, fps: 3, loop: true, category: "idle"),
        CodexMapping(id: "walk_right", state: "running-right", row: 1, fps: 8, loop: true, category: "movement"),
        CodexMapping(id: "run_right", state: "running-right", row: 1, fps: 10, loop: true, category: "movement"),
        CodexMapping(id: "walk_left", state: "running-left", row: 2, fps: 8, loop: true, category: "movement"),
        CodexMapping(id: "run_left", state: "running-left", row: 2, fps: 10, loop: true, category: "movement"),
        CodexMapping(id: "wave", state: "waving", row: 3, fps: 5, loop: true, category: "social"),
        CodexMapping(id: "happy", state: "waving", row: 3, fps: 5, loop: true, category: "social"),
        CodexMapping(id: "jump", state: "jumping", row: 4, fps: 8, loop: false, category: "movement"),
        CodexMapping(id: "pout", state: "failed", row: 5, fps: 5, loop: true, category: "emotion"),
        CodexMapping(id: "sleep", state: "failed", row: 5, fps: 3, loop: true, category: "rest"),
        CodexMapping(id: "waiting", state: "waiting", row: 6, fps: 5, loop: true, category: "system"),
        CodexMapping(id: "working", state: "running", row: 7, fps: 6, loop: true, category: "work"),
        CodexMapping(id: "thinking", state: "review", row: 8, fps: 5, loop: true, category: "work"),
        CodexMapping(id: "look_around", state: "review", row: 8, fps: 5, loop: true, category: "work"),
        CodexMapping(id: "wake_up", state: "jumping", row: 4, fps: 7, loop: false, category: "rest"),
        CodexMapping(id: "stretch", state: "jumping", row: 4, fps: 7, loop: false, category: "rest")
    ]
}

private struct CodexMapping {
    let id: String
    let state: String
    let row: Int
    let fps: Int
    let loop: Bool
    let category: String
}
