import CoreGraphics
import PDFKit
import UIKit

struct PDFBackgroundSample: Equatable {
    var background: PDFColor
    var foreground: PDFColor
    var isUniform: Bool
}

enum PDFPageImage {
    static func thumbnail(of page: PDFPage, maxDimension: CGFloat = 1400) -> (image: UIImage, pageBounds: CGRect)? {
        let pageBounds = page.bounds(for: .mediaBox)
        let longest = max(pageBounds.width, pageBounds.height)
        guard longest > 1 else { return nil }
        let scale = min(2, maxDimension / longest)
        let size = CGSize(width: max(1, pageBounds.width * scale), height: max(1, pageBounds.height * scale))
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard image.size.width > 1, image.size.height > 1 else { return nil }
        return (image, pageBounds)
    }
}

enum PDFBackgroundSampler {
    static func sample(page: PDFPage, rect: CGRect) -> PDFBackgroundSample? {
        guard let rendered = PDFPageImage.thumbnail(of: page) else { return nil }
        return sample(image: rendered.image, pageBounds: rendered.pageBounds, pdfRect: rect)
    }

    static func sample(image: UIImage, pageBounds: CGRect, pdfRect: CGRect) -> PDFBackgroundSample? {
        guard let buffer = PixelBuffer(image: image) else { return nil }
        let uiRect = PDFCoordinateConverter.uiKitRect(fromPDF: pdfRect, pageBounds: pageBounds)
        let scaleX = CGFloat(buffer.width) / max(pageBounds.width, 1)
        let scaleY = CGFloat(buffer.height) / max(pageBounds.height, 1)
        let pixelRect = CGRect(
            x: uiRect.minX * scaleX,
            y: uiRect.minY * scaleY,
            width: max(1, uiRect.width * scaleX),
            height: max(1, uiRect.height * scaleY)
        )

        let backgroundPixels = ringPixels(in: buffer, around: pixelRect)
        let backgroundSource = backgroundPixels.isEmpty ? interiorPixels(in: buffer, rect: pixelRect) : backgroundPixels
        guard !backgroundSource.isEmpty else { return nil }
        let background = median(backgroundSource)
        let spread = meanDistance(backgroundSource, from: background)
        let isUniform = backgroundPixels.count >= 8 && spread < 0.12

        let interior = interiorPixels(in: buffer, rect: pixelRect)
        let ink = interior.filter { $0.distance(to: background) > 0.22 }
        let foreground = ink.isEmpty ? contrastingFallback(for: background) : median(ink)
        return PDFBackgroundSample(background: background, foreground: foreground, isUniform: isUniform)
    }

    private static func contrastingFallback(for background: PDFColor) -> PDFColor {
        background.luminance > 0.62 ? .black : .white
    }

    private static func ringPixels(in buffer: PixelBuffer, around rect: CGRect) -> [PDFColor] {
        let outer = rect.insetBy(dx: -7, dy: -7)
        let inner = rect.insetBy(dx: 1, dy: 1)
        var colors: [PDFColor] = []
        let minX = max(0, Int(outer.minX))
        let maxX = min(buffer.width - 1, Int(outer.maxX))
        let minY = max(0, Int(outer.minY))
        let maxY = min(buffer.height - 1, Int(outer.maxY))
        guard minX <= maxX, minY <= maxY else { return [] }
        let strideX = max(1, (maxX - minX) / 24)
        let strideY = max(1, (maxY - minY) / 24)
        for y in Swift.stride(from: minY, through: maxY, by: strideY) {
            for x in Swift.stride(from: minX, through: maxX, by: strideX) {
                let point = CGPoint(x: x, y: y)
                if inner.contains(point) { continue }
                if let color = buffer.color(x: x, y: y) {
                    colors.append(color)
                }
            }
        }
        return colors
    }

    private static func interiorPixels(in buffer: PixelBuffer, rect: CGRect) -> [PDFColor] {
        let minX = max(0, Int(rect.minX))
        let maxX = min(buffer.width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(buffer.height - 1, Int(rect.maxY))
        guard minX <= maxX, minY <= maxY else { return [] }
        var colors: [PDFColor] = []
        let strideX = max(1, min(2, (maxX - minX) / 16))
        let strideY = max(1, min(2, (maxY - minY) / 16))
        for y in Swift.stride(from: minY, through: maxY, by: strideY) {
            for x in Swift.stride(from: minX, through: maxX, by: strideX) {
                if let color = buffer.color(x: x, y: y) {
                    colors.append(color)
                }
            }
        }
        return colors
    }

    private static func median(_ colors: [PDFColor]) -> PDFColor {
        func mid(_ values: [CGFloat]) -> CGFloat {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        return PDFColor(
            red: mid(colors.map(\.red)),
            green: mid(colors.map(\.green)),
            blue: mid(colors.map(\.blue)),
            alpha: 1
        )
    }

    private static func meanDistance(_ colors: [PDFColor], from reference: PDFColor) -> CGFloat {
        guard !colors.isEmpty else { return 1 }
        let total = colors.reduce(CGFloat(0)) { $0 + $1.distance(to: reference) }
        return total / CGFloat(colors.count)
    }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        width = cgImage.width
        height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.data = data
    }

    func color(x: Int, y: Int) -> PDFColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = ((y * width) + x) * 4
        let alpha = CGFloat(data[offset + 3]) / 255
        guard alpha > 0.4 else { return nil }
        let red = (CGFloat(data[offset]) / 255) / alpha
        let green = (CGFloat(data[offset + 1]) / 255) / alpha
        let blue = (CGFloat(data[offset + 2]) / 255) / alpha
        return PDFColor(red: min(1, red), green: min(1, green), blue: min(1, blue), alpha: 1)
    }
}
