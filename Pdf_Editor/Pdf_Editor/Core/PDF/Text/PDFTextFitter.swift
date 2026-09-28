import CoreGraphics
import UIKit

struct PDFTextFit: Equatable {
    var style: PDFTextStyle
    var visibleBounds: CGRect
    var coverBounds: CGRect
}

enum PDFTextFitter {
    static func fit(
        text: String,
        style: PDFTextStyle,
        originalBounds: CGRect,
        pageBounds: CGRect,
        obstacles: [CGRect],
        lineCount: Int
    ) -> PDFTextFit {
        let multiline = text.contains("\n") || lineCount > 1
        let floor = max(PDFTextLayout.minimumFontSize, (style.fontSize * PDFTextLayout.minimumScale).rounded(.down))
        var size = max(floor, style.fontSize)
        var fittedSize = size

        while true {
            let measured = measure(text, font: PDFFontMatcher.font(for: style.with(fontSize: size)), wrapping: multiline ? originalBounds.width : .greatestFiniteMagnitude)
            if measured.width <= originalBounds.width + 1.5 && measured.height <= originalBounds.height + 2 {
                fittedSize = size
                break
            }
            if size <= floor + 0.01 {
                fittedSize = floor
                break
            }
            size = max(floor, size - 0.5)
        }

        var fittedStyle = style
        fittedStyle.fontSize = fittedSize
        let font = PDFFontMatcher.font(for: fittedStyle)
        let measured = measure(
            text,
            font: font,
            wrapping: multiline ? max(originalBounds.width, 24) : .greatestFiniteMagnitude
        )

        var visible = originalBounds
        if measured.width > visible.width + 1 {
            visible.size.width = measured.width + 2
        }
        if measured.height > visible.height + 1 {
            let growth = measured.height + 2 - visible.height
            visible.origin.y -= growth
            visible.size.height += growth
        }
        visible = clamped(visible, original: originalBounds, pageBounds: pageBounds, obstacles: obstacles)

        var cover = originalBounds.union(visible)
        let padded = cover.insetBy(dx: -PDFTextLayout.coverPadding, dy: -PDFTextLayout.coverPadding)
        let paddingHitsObstacle = obstacles.contains { obstacle in
            padded.intersects(obstacle) && !originalBounds.insetBy(dx: -0.5, dy: -0.5).intersects(obstacle)
        }
        cover = paddingHitsObstacle ? cover : padded
        cover = insetAroundNeighbors(cover, original: originalBounds, obstacles: obstacles)
        cover = cover.intersection(pageBounds.insetBy(dx: 0.5, dy: 0.5))
        if cover.isNull || cover.width < 1 || cover.height < 1 {
            cover = originalBounds.intersection(pageBounds)
        }
        if visible.intersection(cover).isNull {
            visible = originalBounds
        }

        return PDFTextFit(style: fittedStyle, visibleBounds: visible, coverBounds: cover)
    }

    static func measure(_ text: String, font: UIFont, wrapping maxWidth: CGFloat) -> CGSize {
        let content = text.isEmpty ? " " : text
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = maxWidth < 50_000 ? .byWordWrapping : .byClipping
        let rect = (content as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private static func clamped(_ rect: CGRect, original: CGRect, pageBounds: CGRect, obstacles: [CGRect]) -> CGRect {
        var rect = rect
        let minX = pageBounds.minX + PDFTextLayout.pageMargin
        let maxX = pageBounds.maxX - PDFTextLayout.pageMargin
        let minY = pageBounds.minY + PDFTextLayout.pageMargin
        let maxY = pageBounds.maxY - PDFTextLayout.pageMargin

        if rect.maxX > maxX {
            rect.size.width -= rect.maxX - maxX
        }
        if rect.minX < minX {
            let shift = minX - rect.minX
            rect.origin.x += shift
            rect.size.width -= shift
        }
        if rect.maxY > maxY {
            let overflow = rect.maxY - maxY
            rect.size.height -= overflow
        }
        if rect.minY < minY {
            let shift = minY - rect.minY
            rect.origin.y += shift
            rect.size.height -= shift
        }

        for obstacle in obstacles where rect.intersects(obstacle) && !original.intersects(obstacle) {
            if original.maxX <= obstacle.minX + 1 && rect.maxX > obstacle.minX {
                rect.size.width = max(original.width, obstacle.minX - rect.minX - 2)
            }
            if original.minY >= obstacle.maxY - 1 && rect.minY < obstacle.maxY {
                let shift = obstacle.maxY + 2 - rect.minY
                rect.origin.y += shift
                rect.size.height = max(original.height, rect.height - shift)
            }
        }

        if rect.width < 4 { rect.size.width = max(4, original.width) }
        if rect.height < 4 { rect.size.height = max(4, original.height) }
        return original.union(rect)
    }

    /// Keeps the opaque cover off neighboring text when lines sit close together.
    /// A shorter line above must not be treated as a left-side obstacle.
    private static func insetAroundNeighbors(_ cover: CGRect, original: CGRect, obstacles: [CGRect]) -> CGRect {
        var cover = cover
        for obstacle in obstacles {
            let horizontalOverlap = min(original.maxX, obstacle.maxX) - max(original.minX, obstacle.minX)
            let verticalOverlap = min(original.maxY, obstacle.maxY) - max(original.minY, obstacle.minY)
            let sameColumn = horizontalOverlap > min(original.width, obstacle.width) * 0.25
            let sameRow = verticalOverlap > min(original.height, obstacle.height) * 0.25

            if sameColumn, obstacle.minY >= original.midY, cover.maxY > obstacle.minY - 0.5 {
                let limit = obstacle.minY - 0.75
                if cover.maxY > limit {
                    cover.size.height -= cover.maxY - limit
                }
            }
            if sameColumn, obstacle.maxY <= original.midY, cover.minY < obstacle.maxY + 0.5 {
                let limit = obstacle.maxY + 0.75
                if cover.minY < limit {
                    let shift = limit - cover.minY
                    cover.origin.y += shift
                    cover.size.height -= shift
                }
            }
            if sameRow, obstacle.minX >= original.midX, cover.maxX > obstacle.minX - 0.5 {
                let limit = obstacle.minX - 0.75
                if cover.maxX > limit {
                    cover.size.width -= cover.maxX - limit
                }
            }
            if sameRow, obstacle.maxX <= original.midX, cover.minX < obstacle.maxX + 0.5 {
                let limit = obstacle.maxX + 0.75
                if cover.minX < limit {
                    let shift = limit - cover.minX
                    cover.origin.x += shift
                    cover.size.width -= shift
                }
            }
        }
        if cover.width < 2 || cover.height < 2 || cover.isNull {
            return original
        }
        return cover
    }
}
