import CoreGraphics
import PDFKit
import UIKit

enum PDFTextSource: String, Equatable {
    case content
    case replacement
    case ocr
}

enum PDFTextAlignment: String, Equatable, CaseIterable {
    case left
    case center
    case right

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

struct PDFColor: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let white = PDFColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = PDFColor(red: 0, green: 0, blue: 0, alpha: 1)

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var luminance: CGFloat {
        (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(red: red, green: green, blue: blue, alpha: alpha)
            return
        }
        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            self.init(red: white, green: white, blue: white, alpha: alpha)
            return
        }
        self = .black
    }

    func distance(to other: PDFColor) -> CGFloat {
        let dr = red - other.red
        let dg = green - other.green
        let db = blue - other.blue
        return sqrt((dr * dr) + (dg * dg) + (db * db))
    }
}

struct PDFTextStyle: Equatable {
    var fontName: String?
    var fontSize: CGFloat
    var color: PDFColor
    var alignment: PDFTextAlignment
    var isBold: Bool
    var isItalic: Bool

    static let fallback = PDFTextStyle(
        fontName: nil,
        fontSize: 16,
        color: .black,
        alignment: .left,
        isBold: false,
        isItalic: false
    )

    func with(fontSize: CGFloat) -> PDFTextStyle {
        var copy = self
        copy.fontSize = fontSize
        return copy
    }
}

struct PDFTextElement: Identifiable, Equatable {
    var id: UUID
    var pageIndex: Int
    var text: String
    var bounds: CGRect
    var style: PDFTextStyle
    var backgroundColor: PDFColor
    var backgroundIsUniform: Bool
    var source: PDFTextSource
    var lineCount: Int

    var canEditDirectly: Bool {
        if source == .ocr { return true }
        return backgroundIsUniform
    }

    func duplicated(id: UUID, pageIndex: Int) -> PDFTextElement {
        var copy = self
        copy.id = id
        copy.pageIndex = pageIndex
        return copy
    }
}

struct PDFTextReplacement: Identifiable, Equatable {
    var id: UUID
    var elementID: UUID
    var pageIndex: Int
    var originalBounds: CGRect
    var visibleBounds: CGRect
    var coverBounds: CGRect
    var text: String
    var style: PDFTextStyle
    var backgroundColor: PDFColor
    var lineCount: Int

    var displayElement: PDFTextElement {
        PDFTextElement(
            id: elementID,
            pageIndex: pageIndex,
            text: text,
            bounds: visibleBounds,
            style: style,
            backgroundColor: backgroundColor,
            backgroundIsUniform: true,
            source: .replacement,
            lineCount: max(1, lineCount)
        )
    }
}

enum PDFPageContentKind: String, Equatable {
    case text
    case scanned
    case mixed
}

enum PDFDocumentContentKind: String, Equatable {
    case textBased
    case scanned
    case mixed
    case empty
}

enum PDFEditingRestriction: Equatable {
    case locked
    case permissionDenied

    var message: String {
        "This PDF is protected and can't be edited."
    }
}

enum PDFTextEditError: LocalizedError, Equatable {
    case unsupportedBackground
    case failedToRebuild
    case missingPage

    var errorDescription: String? {
        switch self {
        case .unsupportedBackground, .failedToRebuild, .missingPage:
            "This text can't be edited directly in this PDF."
        }
    }
}

enum PDFTextLayout {
    static let minimumFontSize: CGFloat = 8
    static let minimumScale: CGFloat = 0.6
    static let coverPadding: CGFloat = 2.2
    static let pageMargin: CGFloat = 28
}

struct PDFTextEngineState {
    var masters: [Int: PDFPage]
    var rotationDeltas: [Int: Int]
    var replacements: [PDFTextReplacement]
    var extracted: [Int: [PDFTextElement]]
    var ocrElements: [Int: [PDFTextElement]]

    static let empty = PDFTextEngineState(
        masters: [:],
        rotationDeltas: [:],
        replacements: [],
        extracted: [:],
        ocrElements: [:]
    )
}
