import UIKit

enum ChatMarkdownBlock: Equatable {
    case text(String)
    case code(String)
    case table([[String]])

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
            paragraph.append(lines[index])
            index += 1
        }
        flush()
        return blocks
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func hasWideBlock(_ text: String) -> Bool {
        ChatMarkdownBlock.parse(text).contains {
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
                let label = UILabel()
                label.numberOfLines = 0
                label.font = .preferredFont(forTextStyle: .body)
                if let markdown = try? AttributedString(markdown: value) {
                    label.attributedText = NSAttributedString(markdown)
                } else { label.text = value }
                addArrangedSubview(label)
            case .code(let value): addArrangedSubview(codeView(value))
            case .table(let rows): addArrangedSubview(tableView(rows))
            }
        }
    }

    private func codeView(_ code: String) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        scroll.layer.cornerRadius = 10
        scroll.layer.borderWidth = 0.5
        scroll.layer.borderColor = UIColor.separator.cgColor
        scroll.backgroundColor = UIColor.label.withAlphaComponent(0.06)
        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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
        scroll.layer.cornerRadius = 10
        scroll.layer.borderWidth = 0.5
        scroll.layer.borderColor = UIColor.separator.cgColor
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        scroll.addSubview(content)
        for (rowIndex, values) in rows.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.backgroundColor = rowIndex == 0 ? UIColor.label.withAlphaComponent(0.06) : .clear
            for value in values {
                let label = UILabel()
                label.text = value
                label.font = .systemFont(ofSize: 14, weight: rowIndex == 0 ? .semibold : .regular)
                label.numberOfLines = 2
                label.textAlignment = .left
                label.widthAnchor.constraint(equalToConstant: 150).isActive = true
                row.addArrangedSubview(label)
            }
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            content.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: CGFloat(max(1, rows.count) * 44)),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        ])
        return scroll
    }
}
