import AppKit
import Compression
import CoreGraphics
import SwiftUI

/// 从 SwiftPM Bundle.module 加载像素风 PNG 资源与 Sprite Sheet 切片
/// 使用纯 Swift + Compression(zlib) 解码 8-bit RGBA PNG 并直接构造 CGImage，完全绕过 ImageIO 插件初始化
enum PixelAssetLoader {
    private static let lock = NSLock()
    private static var cache: [String: NSImage] = [:]
    private static var frameCache: [String: NSImage] = [:]

    private static let pixelBundle: Bundle = {
        if let resURL = Bundle.main.url(forResource: "TerrariumMenuBar_TerrariumMenuBar", withExtension: "bundle"),
           let bundle = Bundle(url: resURL) {
            return bundle
        }
        return Bundle.module
    }()

    static func nsImage(named name: String) -> NSImage? {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let cleanName = name.replacingOccurrences(of: ".png", with: "")
        guard let url = pixelBundle.url(forResource: cleanName, withExtension: "png", subdirectory: "Pixel"),
              let data = try? Data(contentsOf: url),
              let cgImage = decodePNGToCGImage(data: data) else {
            return nil
        }
        let pixelSize = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: pixelSize)
        lock.lock()
        cache[name] = image
        lock.unlock()
        return image
    }

    /// 从水平拼接的 Sprite Sheet 切出指定帧并缓存（零运行时重复裁剪）
    static func spriteSheetFrame(named sheetName: String, frameIndex: Int, frameSize: CGSize) -> NSImage? {
        let key = "\(sheetName)#\(frameIndex)_\(Int(frameSize.width))x\(Int(frameSize.height))"
        lock.lock()
        if let cached = frameCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let sheetNS = nsImage(named: sheetName),
              let fullCG = sheetNS.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let fw = Int(frameSize.width)
        let fh = Int(frameSize.height)
        let maxFrames = max(1, fullCG.width / fw)
        let safeIndex = max(0, min(maxFrames - 1, frameIndex))
        let cropRect = CGRect(x: safeIndex * fw, y: 0, width: fw, height: fh)

        guard let cropped = fullCG.cropping(to: cropRect) else {
            return nil
        }
        let frameImg = NSImage(cgImage: cropped, size: frameSize)
        lock.lock()
        frameCache[key] = frameImg
        lock.unlock()
        return frameImg
    }

    static func swiftUIImage(named name: String) -> Image {
        if let img = nsImage(named: name) {
            return Image(nsImage: img)
                .interpolation(.none)
        }
        return Image(systemName: "leaf")
    }

    /// 用于造景列表缩略图：若资源是 Sprite Sheet 则自动截取第 0 帧展示
    static func previewSwiftUIImage(named name: String, frameSize: CGSize? = nil) -> Image {
        if let size = frameSize, let frame = spriteSheetFrame(named: name, frameIndex: 0, frameSize: size) {
            return Image(nsImage: frame).interpolation(.none)
        }
        return swiftUIImage(named: name)
    }

    enum MenuBarVisualState: String, CaseIterable {
        case normal = "menubar_icon_normal"
        case event = "menubar_icon_event"
        case dry = "menubar_icon_dry"
        case hungry = "menubar_icon_hungry"
        case night = "menubar_icon_night"
        case sleep = "menubar_icon_sleep"
    }

    private static let menuBarCache: [MenuBarVisualState: NSImage] = {
        var dict: [MenuBarVisualState: NSImage] = [:]
        for st in MenuBarVisualState.allCases {
            dict[st] = makeMenuBarImage(assetName: st.rawValue)
        }
        return dict
    }()

    /// 专门用于顶部菜单栏图标（18x18 点阵），直接返回模板缓存实例避免高频重绘创建副本
    static func menuBarNSImage(state visualState: MenuBarVisualState) -> NSImage {
        menuBarCache[visualState] ?? makeMenuBarImage(assetName: MenuBarVisualState.normal.rawValue)
    }

    private static func makeMenuBarImage(assetName: String) -> NSImage {
        if let img = nsImage(named: assetName)?.copy() as? NSImage {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false
            return img
        }
        return NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Terrarium") ?? NSImage()
    }

    // MARK: - 纯 Swift 8-bit RGBA PNG 解码器（不调用 ImageIO）

    private static func decodePNGToCGImage(data: Data) -> CGImage? {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count > 24, Array(bytes[0..<8]) == signature else { return nil }

        var offset = 8
        var width = 0
        var height = 0
        var bitDepth: UInt8 = 0
        var colorType: UInt8 = 0
        var idatData = Data()

        while offset + 12 <= bytes.count {
            let length = Int(readUInt32BE(bytes, at: offset))
            let typeBytes = bytes[(offset + 4)..<(offset + 8)]
            let chunkType = String(bytes: typeBytes, encoding: .ascii) ?? ""
            let dataStart = offset + 8
            let dataEnd = dataStart + length
            guard dataEnd + 4 <= bytes.count else { break }

            if chunkType == "IHDR" && length >= 13 {
                width = Int(readUInt32BE(bytes, at: dataStart))
                height = Int(readUInt32BE(bytes, at: dataStart + 4))
                bitDepth = bytes[dataStart + 8]
                colorType = bytes[dataStart + 9]
            } else if chunkType == "IDAT" {
                idatData.append(contentsOf: bytes[dataStart..<dataEnd])
            } else if chunkType == "IEND" {
                break
            }
            offset = dataEnd + 4
        }

        guard width > 0, height > 0, bitDepth == 8, colorType == 6, idatData.count > 6 else {
            return nil
        }

        // 跳过 2 字节 zlib header，保留 raw deflate 流给 COMPRESSION_ZLIB
        let deflateBytes = [UInt8](idatData.dropFirst(2))
        let stride = width * 4
        let expectedRawSize = height * (1 + stride)
        var raw = [UInt8](repeating: 0, count: expectedRawSize)

        let decodedCount = deflateBytes.withUnsafeBufferPointer { srcPtr in
            raw.withUnsafeMutableBufferPointer { dstPtr in
                compression_decode_buffer(
                    dstPtr.baseAddress!,
                    expectedRawSize,
                    srcPtr.baseAddress!,
                    deflateBytes.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == expectedRawSize else { return nil }

        var rgba = [UInt8](repeating: 0, count: height * stride)
        for y in 0..<height {
            let rowStart = y * (1 + stride)
            let filterType = raw[rowStart]
            let outStart = y * stride
            let prevStart = (y - 1) * stride

            for x in 0..<stride {
                let rawVal = raw[rowStart + 1 + x]
                let a: UInt8 = x >= 4 ? rgba[outStart + x - 4] : 0
                let b: UInt8 = y > 0 ? rgba[prevStart + x] : 0
                let c: UInt8 = (x >= 4 && y > 0) ? rgba[prevStart + x - 4] : 0

                let recon: UInt8
                switch filterType {
                case 0: recon = rawVal
                case 1: recon = rawVal &+ a
                case 2: recon = rawVal &+ b
                case 3: recon = rawVal &+ UInt8((Int(a) + Int(b)) / 2)
                case 4: recon = rawVal &+ paethPredictor(a, b, c)
                default: recon = rawVal
                }
                rgba[outStart + x] = recon
            }
        }

        let rgbaData = Data(rgba)
        guard let provider = CGDataProvider(data: rgbaData as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func readUInt32BE(_ bytes: [UInt8], at idx: Int) -> UInt32 {
        (UInt32(bytes[idx]) << 24)
            | (UInt32(bytes[idx + 1]) << 16)
            | (UInt32(bytes[idx + 2]) << 8)
            | UInt32(bytes[idx + 3])
    }

    private static func paethPredictor(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
        let ia = Int(a), ib = Int(b), ic = Int(c)
        let p = ia + ib - ic
        let pa = abs(p - ia)
        let pb = abs(p - ib)
        let pc = abs(p - ic)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }
}
