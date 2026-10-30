import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Eigenes Menüleisten-Symbol. Hochgeladene Dateien werden nie ausgeführt oder als HTML/PDF/SVG
/// geöffnet: nur Rasterbilder, Größe begrenzt, auf 64 px neu gezeichnet und als PNG unter festem Namen gespeichert.
enum IconStore {
    static let maxBytes = 5 * 1024 * 1024
    static let types: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
    private static let allowed = Set(types.map(\.identifier))

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SoundController", isDirectory: true)
            .appendingPathComponent("menu-icon.png")
    }

    /// Prüft und verkleinert ein Bild. nil = abgelehnt.
    static func sanitize(_ src: URL) -> CGImage? {
        guard let v = try? src.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true,
              let size = v.fileSize, size > 0, size <= maxBytes,
              let data = try? Data(contentsOf: src, options: .uncached), data.count <= maxBytes,
              let s = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(s) as String?, allowed.contains(type),
              CGImageSourceGetCount(s) >= 1,
              let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 10_000, h <= 10_000 else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 64,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary)
    }

    static func importIcon(from src: URL) -> Bool {
        guard let img = sanitize(src), let url else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".menu-icon.tmp.png")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return false }
        _ = try? FileManager.default.removeItem(at: url)
        return (try? FileManager.default.moveItem(at: tmp, to: url)) != nil
    }

    /// Menüleisten-Bild (18 pt hoch). Auch die eigene Datei wird erneut geprüft.
    static func load(template: Bool) -> NSImage? {
        guard let url, let img = sanitize(url) else { return nil }
        let h: CGFloat = 18
        let w = min(h * CGFloat(img.width) / CGFloat(max(img.height, 1)), 36)
        let ns = NSImage(cgImage: img, size: NSSize(width: w, height: h))
        ns.isTemplate = template
        return ns
    }

    static func remove() { if let url { try? FileManager.default.removeItem(at: url) } }
}
