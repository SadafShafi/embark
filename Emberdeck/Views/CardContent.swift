//
//  CardContent.swift
//  Emberdeck
//
//  Anki stores fields as HTML. Emberdeck doesn't run Anki's card templates, so
//  a field is flattened into text runs and images that SwiftUI can draw.
//

import Foundation
import SwiftUI

enum CardSegment: Identifiable {
    case text(AttributedString)
    case image(String)

    var id: String {
        switch self {
        case .text(let a): return "t" + String(a.characters.prefix(24))
        case .image(let n): return "i" + n
        }
    }
}

enum CardContent {

    static func segments(from html: String) -> [CardSegment] {
        let cleaned = stripNoise(html)
        var result: [CardSegment] = []
        var cursor = cleaned.startIndex

        let pattern = #"<img\b[^>]*\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return [.text(attributed(from: cleaned))]
        }

        let ns = cleaned as NSString
        let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))

        for match in matches {
            guard let range = Range(match.range, in: cleaned) else { continue }

            let before = String(cleaned[cursor..<range.lowerBound])
            if !plainText(before).isEmpty { result.append(.text(attributed(from: before))) }

            var source = ""
            for group in 1...3 where match.range(at: group).location != NSNotFound {
                source = ns.substring(with: match.range(at: group))
                break
            }
            let name = source.removingPercentEncoding ?? source
            if !name.isEmpty, MediaStore.exists(name) { result.append(.image(name)) }

            cursor = range.upperBound
        }

        let tail = String(cleaned[cursor...])
        if !plainText(tail).isEmpty || result.isEmpty {
            result.append(.text(attributed(from: tail)))
        }
        return result
    }

    /// Filenames referenced by `[sound:…]` tags, in order.
    static func audioNames(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[sound:([^\]]+)\]"#, options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
    }

    /// What text-to-speech should read: the text with markup, sound tags and
    /// any bracketed hints like "(m.)" removed.
    static func speechText(_ html: String) -> String {
        var text = plainText(html)
        text = replace(text, pattern: #"\([^)]*\)"#, with: "")
        text = replace(text, pattern: #"\s+"#, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A one-line version for list rows and search.
    static func plainText(_ html: String) -> String {
        stripTags(stripNoise(html))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    private static func stripNoise(_ html: String) -> String {
        var s = html
        s = replace(s, pattern: #"\[sound:[^\]]*\]"#, with: "")
        s = replace(s, pattern: #"<script[\s\S]*?</script>"#, with: "")
        s = replace(s, pattern: #"<style[\s\S]*?</style>"#, with: "")
        // Show cloze deletions rather than hiding them: this app has no cloze
        // card type, so the answer stays visible and is marked instead.
        s = replace(s, pattern: #"\{\{c\d+::(.*?)(?:::.*?)?\}\}"#, with: "<b>$1</b>")
        return s
    }

    private static func attributed(from html: String) -> AttributedString {
        var markdown = html
        markdown = replace(markdown, pattern: #"<\s*br\s*/?>"#, with: "\n")
        markdown = replace(markdown, pattern: #"</\s*(div|p|li|tr)\s*>"#, with: "\n")
        markdown = replace(markdown, pattern: #"<\s*(b|strong)\s*>"#, with: "**")
        markdown = replace(markdown, pattern: #"</\s*(b|strong)\s*>"#, with: "**")
        markdown = replace(markdown, pattern: #"<\s*(i|em)\s*>"#, with: "_")
        markdown = replace(markdown, pattern: #"</\s*(i|em)\s*>"#, with: "_")
        markdown = stripTags(markdown)
        markdown = decodeEntities(markdown)
        markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(markdown)
    }

    private static func stripTags(_ s: String) -> String {
        decodeEntities(replace(s, pattern: #"<[^>]+>"#, with: ""))
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&hellip;", "…"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&rsquo;", "'"), ("&lsquo;", "'"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ]
        for (entity, replacement) in map {
            out = out.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        // Numeric entities, e.g. &#12354;
        out = replaceMatches(out, pattern: #"&#(\d+);"#) { groups in
            guard let code = UInt32(groups[0]), let scalar = Unicode.Scalar(code) else { return "" }
            return String(Character(scalar))
        }
        return out
    }

    private static func replace(_ s: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return s }
        return regex.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    private static func replaceMatches(_ s: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            var groups: [String] = []
            for i in 1..<match.numberOfRanges where match.range(at: i).location != NSNotFound {
                groups.append(ns.substring(with: match.range(at: i)))
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}

/// Draws a parsed field: text runs interleaved with any images it referenced.
struct CardFieldView: View {
    let html: String
    var font: Font
    var color: Color

    var body: some View {
        VStack(spacing: 10) {
            ForEach(CardContent.segments(from: html)) { segment in
                switch segment {
                case .text(let attributed):
                    Text(attributed)
                        .font(font)
                        .foregroundStyle(color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                case .image(let name):
                    if let image = UIImage(contentsOfFile: MediaStore.url(for: name).path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }
}
