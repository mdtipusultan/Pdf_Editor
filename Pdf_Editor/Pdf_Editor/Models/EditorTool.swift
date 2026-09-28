import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case text
    case draw
    case highlight
    case signature
    case shape
    case image
    case pages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .draw: "Draw"
        case .highlight: "Highlight"
        case .signature: "Sign"
        case .shape: "Shape"
        case .image: "Image"
        case .pages: "Pages"
        }
    }

    var icon: String {
        switch self {
        case .text: "textformat"
        case .draw: "pencil.tip"
        case .highlight: "highlighter"
        case .signature: "signature"
        case .shape: "square.on.circle"
        case .image: "photo"
        case .pages: "square.grid.2x2"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .pages, .shape, .image: true
        default: false
        }
    }
}

enum DrawSubTool: String, CaseIterable, Identifiable {
    case pen
    case highlighter
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        }
    }

    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        }
    }
}

enum ShapeType: String, CaseIterable, Identifiable {
    case rectangle
    case circle
    case checkmark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        case .checkmark: "Checkmark"
        }
    }
}

enum MarkupStyle: String, CaseIterable, Identifiable {
    case highlight
    case underline
    case strikethrough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        }
    }

    var pdfSubtype: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikethrough: "StrikeOut"
        }
    }
}
