import UIKit

struct DeepViewNumberRule {
    let min: Double?
    let max: Double?
    let step: Double

    init(node: JSONValue) {
        if case .number(let value)? = node["min"] { min = value } else { min = nil }
        if case .number(let value)? = node["max"] { max = value } else { max = nil }
        if case .number(let value)? = node["step"] { step = value > 0 ? value : 1 } else { step = 1 }
    }

    func normalize(_ value: Double) -> Double {
        let base = min ?? 0
        let stepped = base + ((value - base) / step).rounded() * step
        return Swift.min(max ?? .infinity, Swift.max(min ?? -.infinity, stepped))
    }
}

/// Native controls for the common Deep View card nodes exposed by the mobile API.
final class PendingViewController: UIViewController {
    var onChanged: (() -> Void)?

    private let sessionID: String
    private let record: JSONValue
    private let session: LinkSession
    private let readOnly: Bool
    private let scroll = UIScrollView()
    private let body = UIStackView()
    private var inputs: [String: JSONValue] = [:]
    private var fields: [String: UITextField] = [:]
    private var textAreas: [String: UITextView] = [:]
    private var numericFields = Set<String>()
    private var numericRules: [String: DeepViewNumberRule] = [:]
    private var selections: [String: Set<String>] = [:]
    private var formula: DeepViewFormula?
    private var computedLabels: [(UILabel, JSONValue)] = []
    private var computedProgress: [(UIProgressView, JSONValue)] = []
    private var computedProgressLabels: [(UILabel, JSONValue)] = []
    private var computedData: [(UIStackView, JSONValue)] = []
    private var busy = false

    init(sessionID: String, record: JSONValue, session: LinkSession, readOnly: Bool = false) {
        self.sessionID = sessionID
        self.record = record
        self.session = session
        self.readOnly = readOnly
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = record["title"]?.stringValue ?? "Card"
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                                target: self, action: #selector(close))
        }
        view.backgroundColor = .systemBackground
        scroll.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        body.axis = .vertical
        body.spacing = 12
        body.isLayoutMarginsRelativeArrangement = true
        body.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 30, trailing: 18)
        view.addSubview(scroll)
        scroll.addSubview(body)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        if let root = record["view"] {
            formula = DeepViewFormula(root: root)
            DeepViewFormula.collectInputs(root, into: &inputs)
            if let content = render(root) { body.addArrangedSubview(content) }
        }
        if !readOnly {
            let dismiss = button("Dismiss", prominent: false) { [weak self] in self?.dismissCard() }
            body.addArrangedSubview(dismiss)
        }
    }

    @objc private func close() { dismiss(animated: true) }

    private func label(_ text: String, emphasis: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: emphasis ? .headline : .body)
        label.numberOfLines = 0
        return label
    }

    private func boundLabel(_ value: JSONValue?, emphasis: Bool = false) -> UILabel {
        let text = label(scalar(value), emphasis: emphasis)
        if let value, DeepViewFormula.isFormula(value) { computedLabels.append((text, value)) }
        return text
    }

    private func refreshFormulas() {
        for (label, source) in computedLabels { label.text = scalar(source) }
        for (progress, node) in computedProgress {
            let percent = progressPercent(node)
            progress.progress = Float(max(0, min(100, percent))) / 100
        }
        for (label, node) in computedProgressLabels {
            label.text = node["valueLabel"].map { scalar($0) } ?? "\(Int(progressPercent(node).rounded()))%"
        }
        for (container, node) in computedData {
            for view in container.arrangedSubviews {
                container.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            container.addArrangedSubview(dataContent(node))
        }
    }

    private func numeric(_ value: JSONValue?) -> Double? {
        guard case .number(let number)? = value else { return nil }
        return number
    }

    private func progressPercent(_ node: JSONValue) -> Double {
        func value(_ key: String) -> Double? {
            numeric(formula?.resolve(node[key], inputs: inputs) ?? node[key])
        }
        if let percent = value("percent") { return percent }
        return (value("value") ?? 0) / max(1, value("max") ?? 1) * 100
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.layer.cornerRadius = 16
        button.backgroundColor = prominent ? view.tintColor.withAlphaComponent(0.18) : .tertiarySystemBackground
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func column(_ views: [UIView], horizontal: Bool = false) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = horizontal ? .horizontal : .vertical
        stack.distribution = horizontal ? .fillEqually : .fill
        stack.spacing = 8
        return stack
    }

    private func scalar(_ value: JSONValue?) -> String {
        guard let source = value else { return "" }
        let evaluated = formula?.resolve(source, inputs: inputs)
        if DeepViewFormula.isFormula(source), evaluated == nil { return "…" }
        let value = evaluated ?? source
        switch value {
        case .string(let text): return text
        case .number(let number): return number.formatted()
        case .bool(let bool): return bool ? "Yes" : "No"
        default: return "…"
        }
    }

    private func children(_ node: JSONValue) -> [UIView] {
        guard case .array(let values)? = node["children"] else { return [] }
        return values.compactMap(render)
    }

    private func table(_ node: JSONValue) -> UIView? {
        guard case .array(let columns)? = formula?.resolve(node["columns"], inputs: inputs) ?? node["columns"],
              case .array(let rows)? = formula?.resolve(node["rows"], inputs: inputs) ?? node["rows"] else { return nil }
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = true
        let content = UIStackView()
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
        ])
        func row(_ values: [JSONValue], heading: Bool) -> UIStackView {
            let cells = values.map { value -> UILabel in
                let cell = label(scalar(value))
                cell.font = .preferredFont(forTextStyle: heading ? .caption1 : .subheadline)
                cell.textColor = heading ? .secondaryLabel : .label
                cell.numberOfLines = 0
                cell.widthAnchor.constraint(equalToConstant: 100).isActive = true
                return cell
            }
            let line = UIStackView(arrangedSubviews: cells)
            line.axis = .horizontal
            line.alignment = .top
            line.spacing = 10
            line.isLayoutMarginsRelativeArrangement = true
            line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 8,
                                                                    bottom: 7, trailing: 8)
            if heading { line.backgroundColor = .tertiarySystemBackground }
            return line
        }
        let headers = columns.map { $0["label"] ?? $0["key"] ?? $0 }
        content.addArrangedSubview(row(headers, heading: true))
        for entry in rows {
            guard case .array(let cells) = entry else { continue }
            content.addArrangedSubview(row(cells, heading: false))
        }
        let visibleRows = min(6, rows.count + 1)
        scroller.heightAnchor.constraint(equalToConstant: CGFloat(visibleRows * 48)).isActive = true
        return scroller
    }

    private func dataContent(_ node: JSONValue) -> UIView {
        switch node["type"]?.stringValue {
        case "table": return table(node) ?? label("…")
        case "chart":
            guard case .object(var resolved) = node else { return label("…") }
            for key in ["categories", "series", "kind", "unit", "caption"] {
                if let source = node[key] {
                    let evaluated = formula?.resolve(source, inputs: inputs)
                    guard let value = evaluated ?? (DeepViewFormula.isFormula(source) ? nil : source) else {
                        return label("…")
                    }
                    resolved[key] = value
                }
            }
            guard case .array? = resolved["categories"], case .array? = resolved["series"] else {
                return label("…")
            }
            return DeepViewChartView(node: .object(resolved))
        default: return label("…")
        }
    }

    private func dataView(_ node: JSONValue) -> UIView {
        let container = column([dataContent(node)])
        computedData.append((container, node))
        return container
    }

    private func render(_ node: JSONValue) -> UIView? {
        guard let type = node["type"]?.stringValue else { return nil }
        let id = node["id"]?.stringValue ?? ""
        switch type {
        case "stack": return column(children(node))
        case "row": return column(children(node))
        case "text": return boundLabel(node["text"])
        case "metric":
            var parts: [UIView] = [boundLabel(node["label"]), boundLabel(node["value"], emphasis: true)]
            if let caption = node["caption"] { parts.append(boundLabel(caption)) }
            return column(parts)
        case "callout": return boundLabel(node["text"])
        case "html": return column([boundLabel(node["summary"]), label("Open it on the computer")])
        case "progress":
            let title = boundLabel(node["label"])
            let value = label(node["valueLabel"].map { scalar($0) }
                              ?? "\(Int(progressPercent(node).rounded()))%")
            value.font = .preferredFont(forTextStyle: .caption1)
            value.textColor = .tertiaryLabel
            let heading = UIStackView(arrangedSubviews: [title, value])
            heading.axis = .horizontal
            heading.alignment = .top
            heading.spacing = 8
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let progress = UIProgressView(progressViewStyle: .default)
            let percent = progressPercent(node)
            progress.progress = Float(max(0, min(100, percent))) / 100
            if ["percent", "value", "max"].contains(where: { DeepViewFormula.isFormula(node[$0]) }) {
                computedProgress.append((progress, node))
            }
            if DeepViewFormula.isFormula(node["valueLabel"])
                || ["percent", "value", "max"].contains(where: { DeepViewFormula.isFormula(node[$0]) }) {
                computedProgressLabels.append((value, node))
            }
            return column([heading, progress])
        case "sources":
            guard case .array(let sources)? = node["items"] else { return nil }
            return column(sources.compactMap { source -> UIView? in
                guard let link = source["url"]?.stringValue, let url = URL(string: link),
                      url.scheme == "https" || url.scheme == "http" else { return nil }
                return button(source["label"]?.stringValue ?? source["title"]?.stringValue ?? link,
                              prominent: false) { UIApplication.shared.open(url) }
            })
        case "table", "chart": return dataView(node)
        case "choice":
            guard case .array(let options)? = node["options"] else { return nil }
            let labels = options.map { $0["label"]?.stringValue ?? $0.stringValue ?? scalar($0["value"]) }
            let choice = UISegmentedControl(items: labels)
            choice.isEnabled = !readOnly
            if let selected = options.firstIndex(where: { scalar($0["value"] ?? $0) == scalar(node["value"]) }) {
                choice.selectedSegmentIndex = selected
            }
            inputs[id] = node["value"] ?? .null
            choice.addAction(UIAction { [weak self] _ in
                guard let self, choice.selectedSegmentIndex >= 0 else { return }
                let picked = options[choice.selectedSegmentIndex]
                self.inputs[id] = picked["value"] ?? picked
                self.refreshFormulas()
            }, for: .valueChanged)
            return column([boundLabel(node["label"]), choice])
        case "toggle":
            let toggle = UISwitch()
            toggle.isEnabled = !readOnly
            toggle.isOn = node["value"] == .bool(true)
            inputs[id] = .bool(toggle.isOn)
            toggle.addAction(UIAction { [weak self] _ in
                self?.inputs[id] = .bool(toggle.isOn)
                self?.refreshFormulas()
            }, for: .valueChanged)
            return column([boundLabel(node["label"]), toggle], horizontal: true)
        case "slider":
            let slider = UISlider()
            slider.isEnabled = !readOnly
            slider.minimumValue = Float(node["min"]?.intValue ?? 0)
            slider.maximumValue = Float(node["max"]?.intValue ?? 100)
            slider.value = Float(node["value"]?.intValue ?? Int(slider.minimumValue))
            inputs[id] = .number(Double(slider.value))
            slider.addAction(UIAction { [weak self] _ in
                let step = Float(max(1, node["step"]?.intValue ?? 1))
                self?.inputs[id] = .number(Double((slider.value / step).rounded() * step))
                self?.refreshFormulas()
            }, for: .valueChanged)
            return column([boundLabel(node["label"]), slider])
        case "number":
            let field = UITextField()
            field.isEnabled = !readOnly
            field.borderStyle = .roundedRect
            field.keyboardType = .decimalPad
            if case .number(let value)? = node["value"] {
                field.text = value.rounded() == value && value.magnitude < Double(Int.max)
                    ? String(Int(value)) : String(value)
            } else { field.text = scalar(node["value"]) }
            fields[id] = field
            numericFields.insert(id)
            let rule = DeepViewNumberRule(node: node)
            numericRules[id] = rule
            field.addAction(UIAction { [weak self] _ in
                if let number = Double(field.text ?? "") { self?.inputs[id] = .number(rule.normalize(number)) }
                self?.refreshFormulas()
            }, for: .editingChanged)
            if let unit = node["unit"] {
                let row = UIStackView(arrangedSubviews: [field, boundLabel(unit)])
                row.axis = .horizontal
                row.alignment = .center
                row.spacing = 8
                field.setContentHuggingPriority(.defaultLow, for: .horizontal)
                return column([boundLabel(node["label"]), row])
            }
            return column([boundLabel(node["label"]), field])
        case "options":
            guard case .array(let options)? = node["options"] else { return nil }
            let multi = node["multi"] == .bool(true)
            var controls: [UIView] = options.map { option in
                let choice = option["value"]?.stringValue ?? option["label"]?.stringValue
                    ?? option.stringValue ?? ""
                let control = button(choice, prominent: false) { [weak self] in
                    guard let self else { return }
                    if multi {
                        var selected = self.selections[id] ?? []
                        if !selected.insert(choice).inserted { selected.remove(choice) }
                        self.selections[id] = selected
                    } else {
                        self.submit(action: id, values: ["selected": .array([.string(choice)])])
                    }
                }
                control.isEnabled = !readOnly
                return control
            }
            if multi {
                let submit = button("Submit", prominent: true) { [weak self] in
                    guard let self else { return }
                    let selected = self.selections[id] ?? []
                    let ordered = options.compactMap {
                        $0["value"]?.stringValue ?? $0["label"]?.stringValue ?? $0.stringValue
                    }.filter { selected.contains($0) }
                    self.submit(action: id, values: ["selected": .array(ordered.map(JSONValue.string))])
                }
                submit.isEnabled = !readOnly
                controls.append(submit)
            }
            return column(controls)
        case "confirm":
            let cancel = button(node["cancelLabel"]?.stringValue ?? "Cancel", prominent: false) { [weak self] in
                self?.submit(action: id, values: ["confirmed": .bool(false)])
            }
            let confirm = button(node["confirmLabel"]?.stringValue ?? "Confirm", prominent: true) { [weak self] in
                self?.submit(action: id, values: ["confirmed": .bool(true)])
            }
            cancel.isEnabled = !readOnly
            confirm.isEnabled = !readOnly
            return column([cancel, confirm], horizontal: true)
        case "form":
            guard case .array(let definitions)? = node["fields"] else { return nil }
            var controls: [UIView] = definitions.enumerated().map { index, field in
                let key = field["id"]?.stringValue ?? String(index)
                if field["kind"]?.stringValue == "multiline" {
                    let input = UITextView()
                    input.isEditable = !readOnly
                    input.font = .preferredFont(forTextStyle: .body)
                    input.layer.cornerRadius = 10
                    input.layer.borderWidth = 1
                    input.layer.borderColor = UIColor.separator.cgColor
                    input.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
                    textAreas[key] = input
                    return column([label(field["label"]?.stringValue ?? key), input])
                }
                let input = UITextField()
                input.isEnabled = !readOnly
                input.borderStyle = .roundedRect
                input.placeholder = field["placeholder"]?.stringValue
                fields[key] = input
                return column([label(field["label"]?.stringValue ?? key), input])
            }
            let submit = button(node["submitLabel"]?.stringValue ?? "Submit", prominent: true) { [weak self] in
                guard let self else { return }
                var answers: [String: JSONValue] = [:]
                for (index, definition) in definitions.enumerated() {
                    let key = definition["id"]?.stringValue ?? String(index)
                    answers[key] = .string(self.textAreas[key]?.text ?? self.fields[key]?.text ?? "")
                }
                self.submit(action: id, values: ["fields": .object(answers)])
            }
            submit.isEnabled = !readOnly
            controls.append(submit)
            return column(controls)
        case "submit":
            let submit = button(node["label"]?.stringValue ?? "Submit", prominent: true) { [weak self] in
                self?.submit(action: id, values: [:])
            }
            submit.isEnabled = !readOnly
            return submit
        default: return nil
        }
    }

    private func submit(action: String, values: [String: JSONValue]) {
        guard !readOnly, !busy, let viewID = record["id"]?.stringValue else { return }
        busy = true
        var sent = values
        for key in numericFields {
            if let number = Double(fields[key]?.text ?? "") {
                inputs[key] = .number(numericRules[key]?.normalize(number) ?? number)
            }
        }
        if !inputs.isEmpty { sent["inputs"] = .object(inputs) }
        Task {
            do {
                _ = try await BotAPI.call("view-reply", payload: .object([
                    "sessionId": .string(sessionID), "viewId": .string(viewID),
                    "action": .string(action), "values": .object(sent),
                ]), on: session)
                onChanged?()
                navigationController?.dismiss(animated: true)
            } catch {
                busy = false
                showError(error.localizedDescription)
            }
        }
    }

    private func dismissCard() {
        guard !readOnly, !busy else { return }
        busy = true
        Task {
            do {
                _ = try await BotAPI.call("dismiss-view", payload: .object([
                    "sessionId": .string(sessionID),
                ]), on: session)
                onChanged?()
                navigationController?.dismiss(animated: true)
            } catch {
                busy = false
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Card action failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
