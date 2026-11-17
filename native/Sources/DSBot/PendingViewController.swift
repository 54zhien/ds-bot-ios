import UIKit

/// Native controls for the common Deep View card nodes exposed by the mobile API.
final class PendingViewController: UIViewController {
    var onChanged: (() -> Void)?

    private let sessionID: String
    private let record: JSONValue
    private let session: LinkSession
    private let scroll = UIScrollView()
    private let body = UIStackView()
    private var inputs: [String: JSONValue] = [:]
    private var fields: [String: UITextField] = [:]
    private var numericFields = Set<String>()
    private var selections: [String: Set<String>] = [:]
    private var busy = false

    init(sessionID: String, record: JSONValue, session: LinkSession) {
        self.sessionID = sessionID
        self.record = record
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = record["title"]?.stringValue ?? "Card"
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
        if let root = record["view"], let content = render(root) { body.addArrangedSubview(content) }
        let dismiss = button("Dismiss", prominent: false) { [weak self] in self?.dismissCard() }
        body.addArrangedSubview(dismiss)
    }

    private func label(_ text: String, emphasis: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: emphasis ? .headline : .body)
        label.numberOfLines = 0
        return label
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
        guard let value else { return "" }
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
        guard case .array(let columns)? = node["columns"],
              case .array(let rows)? = node["rows"] else { return nil }
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
        func row(_ values: [String], heading: Bool) -> UIStackView {
            let cells = values.map { text -> UILabel in
                let cell = label(text)
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
        let headers = columns.map { $0["label"]?.stringValue ?? $0["key"]?.stringValue ?? scalar($0) }
        content.addArrangedSubview(row(headers, heading: true))
        for entry in rows {
            guard case .array(let cells) = entry else { continue }
            content.addArrangedSubview(row(cells.map { scalar($0) }, heading: false))
        }
        let visibleRows = min(6, rows.count + 1)
        scroller.heightAnchor.constraint(equalToConstant: CGFloat(visibleRows * 48)).isActive = true
        return scroller
    }

    private func render(_ node: JSONValue) -> UIView? {
        guard let type = node["type"]?.stringValue else { return nil }
        let id = node["id"]?.stringValue ?? ""
        switch type {
        case "stack": return column(children(node))
        case "row": return column(children(node), horizontal: true)
        case "text": return label(scalar(node["text"]))
        case "metric":
            return column([label(scalar(node["label"])), label(scalar(node["value"]), emphasis: true)])
        case "callout": return label(scalar(node["text"]))
        case "html": return label([scalar(node["summary"]), "Open it on the computer"].filter { !$0.isEmpty }.joined(separator: "\n"))
        case "progress":
            let title = label(scalar(node["label"]))
            let progress = UIProgressView(progressViewStyle: .default)
            let percent = node["percent"]?.intValue ?? 0
            progress.progress = Float(max(0, min(100, percent))) / 100
            return column([title, progress])
        case "sources":
            guard case .array(let sources)? = node["items"] else { return nil }
            return column(sources.compactMap { source -> UIView? in
                guard let link = source["url"]?.stringValue, let url = URL(string: link),
                      url.scheme == "https" || url.scheme == "http" else { return nil }
                return button(source["label"]?.stringValue ?? source["title"]?.stringValue ?? link,
                              prominent: false) { UIApplication.shared.open(url) }
            })
        case "table": return table(node)
        case "chart": return DeepViewChartView(node: node)
        case "choice":
            guard case .array(let options)? = node["options"] else { return nil }
            let labels = options.map { $0["label"]?.stringValue ?? $0.stringValue ?? scalar($0["value"]) }
            let choice = UISegmentedControl(items: labels)
            if let selected = options.firstIndex(where: { scalar($0["value"] ?? $0) == scalar(node["value"]) }) {
                choice.selectedSegmentIndex = selected
            }
            inputs[id] = node["value"] ?? .null
            choice.addAction(UIAction { [weak self] _ in
                guard let self, choice.selectedSegmentIndex >= 0 else { return }
                let picked = options[choice.selectedSegmentIndex]
                self.inputs[id] = picked["value"] ?? picked
            }, for: .valueChanged)
            return column([label(scalar(node["label"])), choice])
        case "toggle":
            let toggle = UISwitch()
            toggle.isOn = node["value"] == .bool(true)
            inputs[id] = .bool(toggle.isOn)
            toggle.addAction(UIAction { [weak self] _ in self?.inputs[id] = .bool(toggle.isOn) }, for: .valueChanged)
            return column([label(scalar(node["label"])), toggle], horizontal: true)
        case "slider":
            let slider = UISlider()
            slider.minimumValue = Float(node["min"]?.intValue ?? 0)
            slider.maximumValue = Float(node["max"]?.intValue ?? 100)
            slider.value = Float(node["value"]?.intValue ?? Int(slider.minimumValue))
            inputs[id] = .number(Double(slider.value))
            slider.addAction(UIAction { [weak self] _ in
                let step = Float(max(1, node["step"]?.intValue ?? 1))
                self?.inputs[id] = .number(Double((slider.value / step).rounded() * step))
            }, for: .valueChanged)
            return column([label(scalar(node["label"])), slider])
        case "number":
            let field = UITextField()
            field.borderStyle = .roundedRect
            field.keyboardType = .decimalPad
            field.text = scalar(node["value"])
            fields[id] = field
            numericFields.insert(id)
            return column([label(scalar(node["label"])), field])
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
                return control
            }
            if multi {
                controls.append(button("Submit", prominent: true) { [weak self] in
                    guard let self else { return }
                    let selected = self.selections[id] ?? []
                    let ordered = options.compactMap {
                        $0["value"]?.stringValue ?? $0["label"]?.stringValue ?? $0.stringValue
                    }.filter { selected.contains($0) }
                    self.submit(action: id, values: ["selected": .array(ordered.map(JSONValue.string))])
                })
            }
            return column(controls)
        case "confirm":
            let cancel = button(node["cancelLabel"]?.stringValue ?? "Cancel", prominent: false) { [weak self] in
                self?.submit(action: id, values: ["confirmed": .bool(false)])
            }
            let confirm = button(node["confirmLabel"]?.stringValue ?? "Confirm", prominent: true) { [weak self] in
                self?.submit(action: id, values: ["confirmed": .bool(true)])
            }
            return column([cancel, confirm], horizontal: true)
        case "form":
            guard case .array(let definitions)? = node["fields"] else { return nil }
            var controls: [UIView] = definitions.enumerated().map { index, field in
                let key = field["id"]?.stringValue ?? String(index)
                let input = UITextField()
                input.borderStyle = .roundedRect
                input.placeholder = field["placeholder"]?.stringValue
                fields[key] = input
                return column([label(field["label"]?.stringValue ?? key), input])
            }
            controls.append(button(node["submitLabel"]?.stringValue ?? "Submit", prominent: true) { [weak self] in
                guard let self else { return }
                var answers: [String: JSONValue] = [:]
                for (index, definition) in definitions.enumerated() {
                    let key = definition["id"]?.stringValue ?? String(index)
                    answers[key] = .string(self.fields[key]?.text ?? "")
                }
                self.submit(action: id, values: ["fields": .object(answers)])
            })
            return column(controls)
        case "submit": return button(node["label"]?.stringValue ?? "Submit", prominent: true) { [weak self] in
            self?.submit(action: id, values: [:])
        }
        default: return nil
        }
    }

    private func submit(action: String, values: [String: JSONValue]) {
        guard !busy, let viewID = record["id"]?.stringValue else { return }
        busy = true
        var sent = values
        for key in numericFields {
            if let number = Double(fields[key]?.text ?? "") { inputs[key] = .number(number) }
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
        guard !busy else { return }
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
