import AppKit
import ImageIO

/// A downsampled image plus what the UI reports about the original: pixel size (read from
/// the file header, not a full decode) and, for previews only, file size.
final class LoadedImage {
    let image: NSImage
    let pixelWidth: Int
    let pixelHeight: Int
    let byteSize: Int64?

    init(image: NSImage, pixelWidth: Int, pixelHeight: Int, byteSize: Int64?) {
        self.image = image
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
    }
}

/// Lazy, cached image blobs for the list thumbnails and the preview pane. Decoding happens
/// off the main queue; completions land on main. Cached by size + path.
enum ImageLoader {
    // Row thumbnails are tiny, so all are kept (as before); previews are big, so only a few.
    private static let thumbnails = NSCache<NSString, LoadedImage>()
    private static let previews: NSCache<NSString, LoadedImage> = {
        let cache = NSCache<NSString, LoadedImage>()
        cache.countLimit = 16
        return cache
    }()
    /// The row thumbnail size; anything larger counts as a preview.
    static let thumbnailPixels = 48

    static func cached(path: String, maxPixel: Int) -> LoadedImage? {
        cache(for: maxPixel).object(forKey: key(path, maxPixel))
    }

    static func load(path: String, maxPixel: Int, completion: @escaping (LoadedImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = Self.decode(path: path, maxPixel: maxPixel)
            DispatchQueue.main.async {
                if let loaded { Self.cache(for: maxPixel).setObject(loaded, forKey: Self.key(path, maxPixel)) }
                completion(loaded)
            }
        }
    }

    private static func cache(for maxPixel: Int) -> NSCache<NSString, LoadedImage> {
        maxPixel > thumbnailPixels ? previews : thumbnails
    }

    private static func key(_ path: String, _ maxPixel: Int) -> NSString {
        "\(maxPixel)|\(path)" as NSString
    }

    private static func decode(path: String, maxPixel: Int) -> LoadedImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        var byteSize: Int64?
        if maxPixel > thumbnailPixels {   // only the preview's meta line shows the file size
            byteSize = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
        }
        return LoadedImage(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
                           pixelWidth: props?[kCGImagePropertyPixelWidth] as? Int ?? cg.width,
                           pixelHeight: props?[kCGImagePropertyPixelHeight] as? Int ?? cg.height,
                           byteSize: byteSize)
    }
}
