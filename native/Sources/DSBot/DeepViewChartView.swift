import UIKit

final class DeepViewChartView: UIView {
    struct Series {
        let name: String
        let values: [CGFloat]
        let color: UIColor
    }

    private let kind: String
    private let categories: [String]
    private let series: [Series]
    private let unit: String
    private var pinned: Int?
    private var hidden = Set<Int>()
    private var legendButtons: [UIButton] = []
    private let detail = UILabel()
    private let plot = PlotView()
    private let chartContent = UIStackView()
    private let tableContent = UIStackView()
    private let menuActions = UIStackView()

    init(node: JSONValue) {
        kind = node["kind"]?.stringValue ?? "bar"
        if case .array(let values)? = node["categories"] {
            categories = values.map { $0.stringValue ?? $0.intValue.map { String($0) } ?? "" }
        } else { categories = [] }
        unit = node["unit"]?.stringValue ?? ""
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPink, .systemPurple,
                                  .systemTeal, .systemOrange]
        if case .array(let values)? = node["series"] {
            series = values.enumerated().map { index, item in
                let raw = item["values"] ?? item["data"]
                let points: [CGFloat]
                if case .array(let entries)? = raw {
                    points = entries.map(Self.numeric)
                } else { points = [] }
                return Series(name: item["name"]?.stringValue ?? String(index + 1),
                              values: points, color: colors[index % colors.count])
            }
        } else { series = [] }
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        chartContent.axis = .vertical
        chartContent.spacing = 6
        tableContent.axis = .vertical
        tableContent.spacing = 6
        tableContent.isHidden = true
        stack.addArrangedSubview(chartContent)
        stack.addArrangedSubview(tableContent)
        plot.kind = kind
        plot.categories = categories
        plot.series = series
        plot.backgroundColor = .clear
        plot.heightAnchor.constraint(equalToConstant: 165).isActive = true
        chartContent.addArrangedSubview(plot)
        if kind != "donut" && kind != "hbar", !categories.isEmpty {
            let captions = UIStackView(arrangedSubviews: categories.map { category in
                let label = UILabel()
                label.text = category
                label.textColor = .secondaryLabel
                label.font = .preferredFont(forTextStyle: .caption2)
                label.textAlignment = .center
                label.lineBreakMode = .byTruncatingTail
                return label
            })
            captions.distribution = .fillEqually
            chartContent.addArrangedSubview(captions)
        }
        detail.font = .preferredFont(forTextStyle: .caption1)
        detail.numberOfLines = 0
        detail.isHidden = true
        chartContent.addArrangedSubview(detail)
        let legend = UIStackView()
        legend.axis = .horizontal
        legend.spacing = 10
        let legendItems: [(String, UIColor)] = kind == "donut"
            ? categories.enumerated().map { index, category in
                let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPink,
                                          .systemPurple, .systemTeal, .systemOrange]
                return (category, colors[index % colors.count])
            } : series.map { ($0.name, $0.color) }
        if legendItems.count > 3 { legend.axis = .vertical }
        for (index, item) in legendItems.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle("● \(item.0)", for: .normal)
            button.setTitleColor(item.1, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption2)
            button.accessibilityLabel = item.0
            button.addAction(UIAction { [weak self] _ in self?.toggleSeries(index) }, for: .touchUpInside)
            legendButtons.append(button)
            legend.addArrangedSubview(button)
        }
        let menu = UIButton(type: .system)
        menu.setTitle("⋯", for: .normal)
        menu.accessibilityLabel = NativeLanguage.text("Chart options")
        menu.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.menuActions.isHidden.toggle()
        }, for: .touchUpInside)
        let legendRow = UIStackView(arrangedSubviews: [legend, menu])
        legendRow.axis = .horizontal
        legendRow.spacing = 8
        chartContent.addArrangedSubview(legendRow)
        if let caption = node["caption"]?.stringValue, !caption.isEmpty {
            let label = UILabel()
            label.text = caption
            label.textColor = .secondaryLabel
            label.font = .preferredFont(forTextStyle: .caption1)
            label.numberOfLines = 0
            chartContent.addArrangedSubview(label)
        }
        menuActions.axis = .horizontal
        menuActions.spacing = 16
        menuActions.isHidden = true
        let asTable = UIButton(type: .system)
        asTable.setTitle(NativeLanguage.text("View as table"), for: .normal)
        asTable.accessibilityLabel = NativeLanguage.text("View as table")
        asTable.addAction(UIAction { [weak self] _ in self?.showTable(true) }, for: .touchUpInside)
        let copy = UIButton(type: .system)
        copy.setTitle(NativeLanguage.text("Copy data (CSV)"), for: .normal)
        copy.accessibilityLabel = NativeLanguage.text("Copy data (CSV)")
        copy.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = self.csv()
            self.menuActions.isHidden = true
        }, for: .touchUpInside)
        menuActions.addArrangedSubview(asTable)
        menuActions.addArrangedSubview(copy)
        chartContent.addArrangedSubview(menuActions)
        buildTable()
        let tap = UITapGestureRecognizer(target: self, action: #selector(pick(_:)))
        plot.addGestureRecognizer(tap)
        plot.isAccessibilityElement = true
        plot.accessibilityLabel = NativeLanguage.text("Chart")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func toggleSeries(_ index: Int) {
        if hidden.contains(index) { hidden.remove(index) }
        else { hidden.insert(index) }
        legendButtons[index].alpha = hidden.contains(index) ? 0.35 : 1
        legendButtons[index].accessibilityValue = NativeLanguage.text(hidden.contains(index) ? "Hidden" : "Visible")
        plot.hiddenSeries = hidden
        pinned = nil
        plot.pinned = nil
        detail.isHidden = true
        plot.accessibilityValue = nil
        plot.setNeedsDisplay()
    }

    private func showTable(_ visible: Bool) {
        chartContent.isHidden = visible
        tableContent.isHidden = !visible
        menuActions.isHidden = true
    }

    private func tableRows(includeUnit: Bool) -> [[String]] {
        let names = kind == "donut" ? [series.first?.name ?? ""] : series.map(\.name)
        let heading = [""] + names
        let rows = categories.enumerated().map { index, category in
            let values = kind == "donut" ? Array(series.prefix(1)) : series
            return [category] + values.map { item in
                guard item.values.indices.contains(index) else { return includeUnit ? "—" : "" }
                let value = Double(item.values[index])
                return includeUnit ? "\(value.formatted())\(unit)" : String(value)
            }
        }
        return [heading] + rows
    }

    private func csv() -> String {
        tableRows(includeUnit: false).map { row in
            row.map { cell in
                guard cell.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return cell }
                return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    private func buildTable() {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        let rows = UIStackView()
        rows.axis = .vertical
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        ])
        for (index, values) in tableRows(includeUnit: true).enumerated() {
            let cells = values.map { value -> UILabel in
                let label = UILabel()
                label.text = value
                label.font = .preferredFont(forTextStyle: index == 0 ? .caption1 : .subheadline)
                label.textColor = index == 0 ? .secondaryLabel : .label
                label.numberOfLines = 0
                label.widthAnchor.constraint(equalToConstant: 110).isActive = true
                return label
            }
            let row = UIStackView(arrangedSubviews: cells)
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 8
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 8,
                                                                  bottom: 6, trailing: 8)
            if index == 0 { row.backgroundColor = .tertiarySystemBackground }
            rows.addArrangedSubview(row)
        }
        scroll.heightAnchor.constraint(equalToConstant: CGFloat(min(6, categories.count + 1) * 40)).isActive = true
        tableContent.addArrangedSubview(scroll)
        let back = UIButton(type: .system)
        back.setTitle(NativeLanguage.text("View as chart"), for: .normal)
        back.accessibilityLabel = NativeLanguage.text("View as chart")
        back.addAction(UIAction { [weak self] _ in self?.showTable(false) }, for: .touchUpInside)
        tableContent.addArrangedSubview(back)
    }

    private static func numeric(_ value: JSONValue) -> CGFloat {
        switch value {
        case .number(let number): return CGFloat(number)
        case .string(let text): return CGFloat(Double(text) ?? 0)
        default: return 0
        }
    }

    @objc private func pick(_ gesture: UITapGestureRecognizer) {
        guard !categories.isEmpty else { return }
        let point = gesture.location(in: plot)
        let index: Int
        if kind == "donut", let first = series.first {
            let center = CGPoint(x: plot.bounds.midX, y: plot.bounds.midY)
            var angle = atan2(point.y - center.y, point.x - center.x) + .pi / 2
            if angle < 0 { angle += 2 * .pi }
            let values = categories.indices.map { item in
                max(0, hidden.contains(item) ? 0 : first.values.indices.contains(item) ? first.values[item] : 0)
            }
            let total = max(0.000001, values.reduce(0, +))
            var running: CGFloat = 0
            var found = categories.count - 1
            for (item, value) in values.enumerated() {
                running += value / total * 2 * .pi
                if angle <= running { found = item; break }
            }
            index = found
        } else {
            index = min(categories.count - 1, max(0, Int(point.x / max(1, plot.bounds.width)
                * CGFloat(categories.count))))
        }
        pinned = pinned == index ? nil : index
        plot.pinned = pinned
        if let pinned {
            let values = series.enumerated().compactMap { index, item -> String? in
                guard !hidden.contains(index) else { return nil }
                let value = item.values.indices.contains(pinned)
                    ? Double(item.values[pinned]).formatted() : "—"
                return "\(item.name) \(value)\(unit)"
            }
            detail.text = "\(categories[pinned]): " + values.joined(separator: " · ")
            detail.isHidden = false
            plot.accessibilityValue = detail.text
        } else {
            detail.isHidden = true
            plot.accessibilityValue = nil
        }
    }

    private final class PlotView: UIView {
        var kind = "bar"
        var categories: [String] = []
        var series: [Series] = []
        var hiddenSeries = Set<Int>()
        var pinned: Int? { didSet { setNeedsDisplay() } }

        override func draw(_ rect: CGRect) {
            guard !categories.isEmpty, !series.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }
            let width = rect.width
            let height = rect.height
            let pad: CGFloat = 8
            let maxValue = max(1, series.enumerated().filter { !hiddenSeries.contains($0.offset) }
                .flatMap { $0.element.values }.max() ?? 1)
            if kind == "donut" {
                let values = categories.indices.map { index in
                    max(0, hiddenSeries.contains(index) ? 0
                        : series[0].values.indices.contains(index) ? series[0].values[index] : 0)
                }
                let total = max(0.000001, values.reduce(0, +))
                var start = -CGFloat.pi / 2
                let center = CGPoint(x: width / 2, y: height / 2)
                let outer = min(width, height) * 0.43
                let inner = outer * 0.53
                let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPink,
                                          .systemPurple, .systemTeal, .systemOrange]
                for (index, value) in values.enumerated() where value > 0 {
                    let end = start + value / total * 2 * .pi
                    let path = UIBezierPath()
                    path.addArc(withCenter: center, radius: outer, startAngle: start,
                                endAngle: end, clockwise: true)
                    path.addArc(withCenter: center, radius: inner, startAngle: end,
                                endAngle: start, clockwise: false)
                    path.close()
                    let color = colors[index % colors.count]
                    color.withAlphaComponent(pinned == nil || pinned == index ? 1 : 0.25).setFill()
                    path.fill()
                    start = end
                }
                return
            }
            let count = CGFloat(categories.count)
            let groupWidth = (width - pad * 2) / count
            for (seriesIndex, item) in series.enumerated() {
                if hiddenSeries.contains(seriesIndex) { continue }
                let color = item.color
                if kind == "line" || kind == "area" {
                    let path = UIBezierPath()
                    for (index, value) in item.values.prefix(categories.count).enumerated() {
                        let x = pad + (CGFloat(index) + 0.5) * groupWidth
                        let y = height - pad - max(0, value) / maxValue * (height - pad * 2)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    if kind == "area", !item.values.isEmpty {
                        path.addLine(to: CGPoint(x: pad + (CGFloat(min(item.values.count, categories.count)) - 0.5)
                                                       * groupWidth, y: height - pad))
                        path.addLine(to: CGPoint(x: pad + 0.5 * groupWidth, y: height - pad))
                        path.close()
                        color.withAlphaComponent(0.22).setFill()
                        path.fill()
                    }
                    color.setStroke()
                    path.lineWidth = 2
                    path.stroke()
                } else {
                    for (index, value) in item.values.prefix(categories.count).enumerated() {
                        let fraction = max(0, value) / maxValue
                        let bar = UIBezierPath()
                        if kind == "hbar" {
                            let rowHeight = (height - pad * 2) / count
                            let markHeight = max(2, (rowHeight - 5) / CGFloat(series.count))
                            let y = pad + CGFloat(index) * rowHeight
                                + CGFloat(seriesIndex) * markHeight
                            bar.append(UIBezierPath(roundedRect: CGRect(x: pad, y: y,
                                width: fraction * (width - pad * 2), height: markHeight - 2), cornerRadius: 2))
                        } else {
                            let markWidth = max(2, (groupWidth - 6) / CGFloat(series.count))
                            let x = pad + CGFloat(index) * groupWidth + CGFloat(seriesIndex) * markWidth + 3
                            let barHeight = fraction * (height - pad * 2)
                            bar.append(UIBezierPath(roundedRect: CGRect(x: x, y: height - pad - barHeight,
                                width: markWidth - 2, height: barHeight), cornerRadius: 2))
                        }
                        color.withAlphaComponent(pinned == nil || pinned == index ? 1 : 0.25).setFill()
                        bar.fill()
                    }
                }
            }
            context.flush()
        }
    }
}
