import CoreGraphics
import PDFKit
import UIKit

struct PDFFontSample: Equatable {
    var name: String
    var size: CGFloat
}

enum PDFFontMatcher {
    static func style(
        estimatedSize: CGFloat,
        samples: [PDFFontSample],
        color: PDFColor
    ) -> PDFTextStyle {
        let estimated = max(PDFTextLayout.minimumFontSize, estimatedSize)
        let closest = samples
            .filter { $0.size > 0.5 }
            .min { abs($0.size - estimated) < abs($1.size - estimated) }

        var fontName = closest?.name
        var size = estimated
        if let closest {
            let delta = abs(closest.size - estimated)
            let allowed = max(2, estimated * 0.4)
            if delta <= allowed {
                size = closest.size
            }
            fontName = closest.name
        }

        let traits = traits(from: fontName)
        return PDFTextStyle(
            fontName: fontName,
            fontSize: size,
            color: color,
            alignment: .left,
            isBold: traits.bold,
            isItalic: traits.italic
        )
    }

    static func font(for style: PDFTextStyle) -> UIFont {
        let size = max(PDFTextLayout.minimumFontSize, style.fontSize)
        if let name = style.fontName {
            let cleaned = normalized(name)
            if let matched = resolve(cleaned, size: size, bold: style.isBold, italic: style.isItalic) {
                return matched
            }
        }
        return systemFont(size: size, bold: style.isBold, italic: style.isItalic, mono: false, serif: false)
    }

    static func samples(on page: PDFPage) -> [PDFFontSample] {
        PDFFontProbe.rawSamples(on: page).map { PDFFontSample(name: $0.0, size: $0.1) }
    }

    static func normalized(_ name: String) -> String {
        guard let plus = name.firstIndex(of: "+") else { return name }
        let prefix = name[..<plus]
        guard prefix.count == 6 else { return name }
        return String(name[name.index(after: plus)...])
    }

    static func traits(from name: String?) -> (bold: Bool, italic: Bool) {
        guard let name else { return (false, false) }
        let lower = normalized(name).lowercased()
        let bold = lower.contains("bold") || lower.contains("black") || lower.contains("heavy") || lower.contains("semibold")
        let italic = lower.contains("italic") || lower.contains("oblique")
        return (bold, italic)
    }

    private static func resolve(_ name: String, size: CGFloat, bold: Bool, italic: Bool) -> UIFont? {
        let candidates = [name, substitutions[name]].compactMap { $0 }
        for candidate in candidates {
            if let font = UIFont(name: candidate, size: size) {
                return font
            }
        }
        let lower = name.lowercased()
        let mono = lower.contains("courier") || lower.contains("mono")
        let serif = lower.contains("times") || lower.contains("georgia") || lower.contains("roman") || lower.contains("serif")
        if mono || serif {
            return systemFont(size: size, bold: bold, italic: italic, mono: mono, serif: serif)
        }
        return nil
    }

    private static func systemFont(size: CGFloat, bold: Bool, italic: Bool, mono: Bool, serif: Bool) -> UIFont {
        let base: UIFont
        if mono {
            base = UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        } else if serif, let serifFont = serifFont(size: size, bold: bold, italic: italic) {
            return serifFont
        } else {
            base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        guard italic, let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func serifFont(size: CGFloat, bold: Bool, italic: Bool) -> UIFont? {
        let name: String
        switch (bold, italic) {
        case (true, true): name = "TimesNewRomanPS-BoldItalicMT"
        case (true, false): name = "TimesNewRomanPS-BoldMT"
        case (false, true): name = "TimesNewRomanPS-ItalicMT"
        case (false, false): name = "TimesNewRomanPSMT"
        }
        return UIFont(name: name, size: size)
    }

    private static let substitutions: [String: String] = [
        "Times-Roman": "TimesNewRomanPSMT",
        "Times-Bold": "TimesNewRomanPS-BoldMT",
        "Times-Italic": "TimesNewRomanPS-ItalicMT",
        "Times-BoldItalic": "TimesNewRomanPS-BoldItalicMT",
        "TimesNewRoman": "TimesNewRomanPSMT",
        "Arial": "ArialMT",
        "Arial-Bold": "Arial-BoldMT",
        "Arial-Italic": "Arial-ItalicMT",
        "Arial-BoldItalic": "Arial-BoldItalicMT"
    ]
}

nonisolated private enum PDFFontProbe {
    static func rawSamples(on page: PDFPage) -> [(String, CGFloat)] {
        guard let pageRef = page.pageRef else { return [] }
        let stream = CGPDFContentStreamCreateWithPage(pageRef)
        defer { CGPDFContentStreamRelease(stream) }

        guard let table = CGPDFOperatorTableCreate() else {
            return []
        }
        defer { CGPDFOperatorTableRelease(table) }

        let box = FontProbeBox()
        let info = Unmanaged.passUnretained(box).toOpaque()
        CGPDFOperatorTableSetCallback(table, "Tf", tfCallback)
        let scanner = CGPDFScannerCreate(stream, table, info)
        defer { CGPDFScannerRelease(scanner) }
        CGPDFScannerScan(scanner)
        return box.samples
    }

    private static let tfCallback: CGPDFOperatorCallback = { scanner, info in
        guard let info else { return }
        var size: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &size), size > 0.5, size < 400 else { return }
        var namePointer: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &namePointer), let namePointer else { return }
        let name = String(cString: namePointer)
        guard !name.isEmpty else { return }
        let box = Unmanaged<FontProbeBox>.fromOpaque(info).takeUnretainedValue()
        box.samples.append((name, CGFloat(size)))
    }
}

nonisolated private final class FontProbeBox {
    var samples: [(String, CGFloat)] = []
}
