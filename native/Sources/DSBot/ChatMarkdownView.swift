import UIKit

struct ChatMarkdownListItem: Equatable {
    let text: String
    let marker: String
    let depth: Int
}

enum ChatMarkdownBlock: Equatable {
    case text(String)
    case code(String)
    case table([[String]])
    case heading(Int, String)
    case list([ChatMarkdownListItem])
    case quote(String)
    case rule

    static func parse(_ source: String) -> [ChatMarkdownBlock] {
        let lines = source.components(separatedBy: "\n")
        var blocks: [ChatMarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0
        func flush() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { blocks.append(.text(text)) }
            paragraph.removeAll()
        }
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                let fence = String(line.prefix(3))
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                if index < lines.count { index += 1 }
                continue
            }
            if index + 1 < lines.count, line.contains("|"), isDivider(lines[index + 1]) {
                flush()
                var rows = [cells(lines[index])]
                index += 2
                while index < lines.count, lines[index].contains("|"),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[index]))
                    index += 1
                }
                blocks.append(.table(rows))
                continue
            }
            if isRule(line) {
                flush()
                blocks.append(.rule)
                index += 1
                continue
            }
            if let heading = heading(line) {
                flush()
                blocks.append(.heading(heading.0, heading.1))
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quoted.append(String(current.dropFirst()).replacingOccurrences(of: "^ ?", with: "",
                                                                               options: .regularExpression))
                    index += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }
            if let first = listItem(lines[index]) {
                flush()
                var items: [ChatMarkdownListItem] = []
                var indents = [first.indent]
                while index < lines.count {
                    if let last = items.last, unclosedFence(in: last.text) != nil {
                        let removed = min(leadingSpaces(lines[index]), first.indent + 2)
                        items[items.count - 1] = ChatMarkdownListItem(
                            text: last.text + "\n" + String(lines[index].dropFirst(removed)),
                            marker: last.marker, depth: last.depth)
                        index += 1
                    } else if let item = listItem(lines[index]) {
                        if item.indent > indents.last! { indents.append(item.indent) }
                        else {
                            while indents.count > 1 && item.indent < indents.last! { indents.removeLast() }
                        }
                        items.append(ChatMarkdownListItem(text: item.text, marker: item.marker,
                                                          depth: indents.count - 1))
                        index += 1
                    } else if lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                              index + 1 < lines.count,
                              listItem(lines[index + 1]) != nil
                                || leadingSpaces(lines[index + 1]) > indents.first! {
                        if let last = items.last, listItem(lines[index + 1]) == nil {
                            items[items.count - 1] = ChatMarkdownListItem(
                                text: last.text + "\n", marker: last.marker, depth: last.depth)
                        }
                        index += 1
                    } else if let last = items.last, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                              leadingSpaces(lines[index]) > indents.first! {
                        items[items.count - 1] = ChatMarkdownListItem(
                            text: last.text + "\n" + lines[index].trimmingCharacters(in: .whitespaces),
                            marker: last.marker, depth: last.depth)
                        index += 1
                    } else { break }
                }
                blocks.append(.list(items))
                continue
            }
            paragraph.append(lines[index])
            index += 1
        }
        flush()
        return blocks
    }

    private static func isRule(_ line: String) -> Bool {
        line.range(of: "^([-*_]\\s*){3,}$", options: .regularExpression) != nil
    }

    private static func unclosedFence(in text: String) -> String? {
        var opened: String?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let current = opened {
                if trimmed.hasPrefix(current) { opened = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                opened = String(trimmed.prefix(3))
            }
        }
        return opened
    }

    private static func heading(_ line: String) -> (Int, String)? {
        guard let prefix = line.range(of: "^#{1,6} ", options: .regularExpression) else { return nil }
        let depth = line[prefix].filter { $0 == "#" }.count
        let title = line[prefix.upperBound...].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (depth, title)
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func listItem(_ line: String) -> (text: String, marker: String, indent: Int)? {
        let indent = leadingSpaces(line)
        let body = line.drop { $0 == " " || $0 == "\t" }
        for marker in ["- ", "+ ", "* "] where body.hasPrefix(marker) {
            return (String(body.dropFirst(marker.count)), "•", indent)
        }
        guard let prefix = body.range(of: "^[0-9]+[.)] ", options: .regularExpression),
              let start = Int(body[prefix].dropLast(2)) else { return nil }
        return (String(body[prefix.upperBound...]), "\(start).", indent)
    }

    private static func isDivider(_ line: String) -> Bool {
        let parts = cells(line)
        return !parts.isEmpty && parts.allSatisfy {
            $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil
        }
    }

    private static func cells(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "|" { parts.append(current); current = "" }
            else { current.append(character) }
        }
        parts.append(current)
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") { parts.removeFirst() }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|") { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Scrollable fenced code and GFM tables inside a self-sizing chat bubble.
final class ChatMarkdownView: UIStackView {
    private var source = ""

    /// mobile/src/screens/chat/markdown.tsx draws every block on the bubble type and
    /// tints from the palette, so the same values are read here instead of copied.
    private var palette: Palette { ThemeStore.palette(trait: traitCollection) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = Glass.gap
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func hasWideBlock(_ text: String) -> Bool {
        return ChatMarkdownBlock.parse(text).contains {
            if case .text = $0 { return false }
            return true
        }
    }

    func configure(_ text: String) {
        guard source != text else { return }
        source = text
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        for block in ChatMarkdownBlock.parse(text) {
            switch block {
            case .text(let value):
                addArrangedSubview(markdownLabel(value))
            case .code(let value): addArrangedSubview(codeView(value))
            case .table(let rows): addArrangedSubview(tableView(rows))
            case .heading(let depth, let value):
                let scale = depth == 1 ? TypeScale.largeTitle : TypeScale.headerTitle
                let label = markdownLabel(value, font: scale.font, lineHeight: scale.lineHeight)
                addArrangedSubview(label)
            case .list(let items): addArrangedSubview(listView(items))
            case .quote(let value): addArrangedSubview(quoteView(value))
            case .rule:
                let separator = UIView()
                separator.backgroundColor = palette.line
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                addArrangedSubview(separator)
            }
        }
    }

    private func markdownLabel(_ value: String, font: UIFont? = nil, lineHeight: CGFloat? = nil) -> UILabel {
        let label = MarkdownLinkLabel()
        label.numberOfLines = 0
        let ink = palette.ink
        let type = font ?? TypeScale.bubble.font
        let lead = lineHeight ?? TypeScale.bubble.lineHeight
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lead
        paragraph.maximumLineHeight = lead
        if let markdown = try? AttributedString(markdown: value) {
            let rendered = NSMutableAttributedString(attributedString: NSAttributedString(markdown))
            rendered.addAttributes([.font: type, .foregroundColor: ink, .paragraphStyle: paragraph],
                                   range: NSRange(location: 0, length: rendered.length))
            // Links read as links: the accent, underlined, like markdown.tsx.
            let text = rendered.string as NSString
            for match in matches(in: text, pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") {
                rendered.addAttributes([.foregroundColor: palette.accent, .underlineStyle: NSUnderlineStyle.single.rawValue],
                                       range: match)
            }
            label.attributedText = rendered
        } else {
            label.attributedText = NSAttributedString(string: value, attributes: [
                .font: type, .foregroundColor: ink, .paragraphStyle: paragraph,
            ])
        }
        return label
    }

    private func matches(in text: NSString, pattern: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).map(\.range)
    }

    private func listView(_ items: [ChatMarkdownListItem]) -> UIView {
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 6
        for item in items {
            let marker = UILabel()
            marker.text = item.marker
            marker.textColor = palette.ink3
            marker.font = TypeScale.bubble.font
            marker.textAlignment = .right
            marker.widthAnchor.constraint(equalToConstant: item.marker == "•" ? 18 : 30).isActive = true
            let body = ChatMarkdownView()
            body.configure(item.text)
            let row = UIStackView(arrangedSubviews: [marker, body])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 6
            if item.depth == 0 { list.addArrangedSubview(row) }
            else {
                let inset = UIView()
                inset.widthAnchor.constraint(equalToConstant: CGFloat(item.depth * 14)).isActive = true
                let nested = UIStackView(arrangedSubviews: [inset, row])
                nested.axis = .horizontal
                list.addArrangedSubview(nested)
            }
        }
        return list
    }

    private func quoteView(_ value: String) -> UIView {
        let stripe = UIView()
        stripe.backgroundColor = palette.line
        stripe.widthAnchor.constraint(equalToConstant: 3).isActive = true
        let body = ChatMarkdownView()
        body.configure(value)
        let quote = UIStackView(arrangedSubviews: [stripe, body])
        quote.axis = .horizontal
        quote.spacing = 10
        return quote
    }

    private func codeView(_ code: String) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        scroll.layer.cornerRadius = Radius.input
        scroll.layer.borderWidth = 1
        scroll.layer.borderColor = palette.line.cgColor
        scroll.backgroundColor = palette.hover
        let font = TypeScale.mono(13)
        let width = code.components(separatedBy: "\n").map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let height = CGFloat(max(1, code.components(separatedBy: "\n").count)) * 19 + 18
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = code
        label.font = font
        label.numberOfLines = 0
        label.lineBreakMode = .byClipping
        scroll.addSubview(label)
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: height),
            label.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -9),
            label.widthAnchor.constraint(equalToConstant: max(1, width)),
        ])
        return scroll
    }

    private func tableView(_ rows: [[String]]) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        scroll.layer.cornerRadius = Radius.input
        scroll.layer.borderWidth = 1
        scroll.layer.borderColor = palette.line.cgColor
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        scroll.addSubview(content)
        let columnCount = rows.map(\.count).max() ?? 0
        for (rowIndex, values) in rows.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.backgroundColor = rowIndex == 0 ? palette.hover : .clear
            for index in 0..<columnCount {
                let value = index < values.count ? values[index] : ""
                let label = UILabel()
                if let markdown = try? AttributedString(markdown: value) {
                    label.attributedText = NSAttributedString(markdown)
                } else { label.text = value }
                label.font = .systemFont(ofSize: TypeScale.bubble.size - 1, weight: rowIndex == 0 ? .semibold : .regular)
                label.textColor = palette.ink
                label.numberOfLines = 2
                label.textAlignment = .left
                label.widthAnchor.constraint(equalToConstant: 150).isActive = true
                row.addArrangedSubview(label)
            }
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
            content.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: CGFloat(max(1, rows.count) * 54)),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        ])
        return scroll
    }
}
