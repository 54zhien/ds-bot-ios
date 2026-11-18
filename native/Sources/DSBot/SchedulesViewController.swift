import UIKit

final class SchedulesViewController: UITableViewController {
    private let botID: String
    private let sessionID: String
    private let session: LinkSession
    private var tasks: [JSONValue] = []

    init(botID: String, sessionID: String, session: LinkSession) {
        self.botID = botID
        self.sessionID = sessionID
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Scheduled tasks")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self, action: #selector(add))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let result = try await BotAPI.call("schedules", on: session)
            if case .array(let values)? = result["tasks"] {
                tasks = values.filter { $0["botId"]?.stringValue == botID || $0["botId"] == nil }
            } else { tasks = [] }
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, tasks.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "schedule")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "schedule")
        cell.selectionStyle = .none
        if tasks.isEmpty {
            cell.textLabel?.text = NativeLanguage.text("No scheduled tasks yet. Add one")
            cell.detailTextLabel?.text = nil
        } else {
            let task = tasks[indexPath.row]
            cell.textLabel?.text = task["title"]?.stringValue ?? NativeLanguage.text("Task")
            cell.detailTextLabel?.text = Self.whenText(task)
        }
        return cell
    }

    private static func whenText(_ task: JSONValue) -> String {
        let time = task["time"]?.stringValue ?? ""
        switch task["kind"]?.stringValue {
        case "at":
            let timestamp = Double(task["scheduledAt"]?.intValue ?? 0) / 1000
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return NativeLanguage.text("Once, {time}", ["time": formatter.string(from: Date(timeIntervalSince1970: timestamp))])
        case "every":
            let seconds = task["everySeconds"]?.intValue ?? (task["minutes"]?.intValue ?? 0) * 60
            if seconds > 0, seconds % 86400 == 0 {
                let count = seconds / 86400
                return count == 1 ? NativeLanguage.text("Every day")
                    : NativeLanguage.text("Every {count} days", ["count": String(count)])
            }
            if seconds > 0, seconds % 3600 == 0 {
                let count = seconds / 3600
                return count == 1 ? NativeLanguage.text("Every hour")
                    : NativeLanguage.text("Every {count} hours", ["count": String(count)])
            }
            return NativeLanguage.text("Every {count} minutes", ["count": String((seconds + 30) / 60)])
        case "daily":
            return NativeLanguage.text("Every day at {time}", ["time": time])
        case "weekly":
            guard case .array(let values)? = task["weekdays"] else { return "" }
            let days = values.compactMap(\.intValue).sorted()
            if days == [1, 2, 3, 4, 5] {
                return NativeLanguage.text("Every weekday at {time}", ["time": time])
            }
            if days == [6, 7] {
                return NativeLanguage.text("Every weekend at {time}", ["time": time])
            }
            if days == [1, 2, 3, 4, 5, 6, 7] {
                return NativeLanguage.text("Every day at {time}", ["time": time])
            }
            let labels = days.map { ScheduleEditorViewController.weekdayLabel($0, withPrefix: true) }
            return NativeLanguage.text("Every {days} at {time}", [
                "days": labels.joined(separator: NativeLanguage.isChinese ? "、" : ", "), "time": time,
            ])
        case "cron":
            return NativeLanguage.text("On the schedule {expression}", ["expression": task["expression"]?.stringValue ?? ""])
        default: return ""
        }
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard tasks.indices.contains(indexPath.row), let id = tasks[indexPath.row]["id"]?.stringValue else { return nil }
        let task = tasks[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: NativeLanguage.text("Delete")) { [weak self] _, _, done in
            self?.confirmDelete(id: id, sessionID: task["sessionId"]?.stringValue ?? self?.sessionID ?? "")
            done(false)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func add() {
        let editor = ScheduleEditorViewController(botID: botID, session: session)
        editor.onSaved = { [weak self] in Task { await self?.load() } }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func confirmDelete(id: String, sessionID: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Delete this task?"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Keep"), style: .cancel))
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    _ = try await BotAPI.call("schedule-delete", payload: .object([
                        "sessionId": .string(sessionID), "id": .string(id),
                    ]), on: self.session)
                    await self.load()
                } catch { self.showError(error.localizedDescription) }
            }
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Schedule unavailable"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
        present(alert, animated: true)
    }
}

private final class ScheduleEditorViewController: UIViewController {
    var onSaved: (() -> Void)?
    private let botID: String
    private let session: LinkSession
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let name = UITextField()
    private let prompt = UITextView()
    private let kind = UISegmentedControl(items: ["Once", "Every day", "Every week", "Repeat"].map { NativeLanguage.text($0) })
    private let date = UITextField()
    private let time = UITextField()
    private let weekdayRow = UIStackView()
    private var weekdayButtons: [UIButton] = []
    private var selectedWeekdays: Set<Int> = [1, 2, 3, 4, 5]
    private let interval = UITextField()
    private let repeatUnit = UISegmentedControl(items: ["minutes", "hours", "days"].map { NativeLanguage.text($0) })

    static func weekdayLabel(_ day: Int, withPrefix: Bool = false) -> String {
        let chinese = ["", "一", "二", "三", "四", "五", "六", "日"]
        let english = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard (1...7).contains(day) else { return String(day) }
        return NativeLanguage.isChinese ? (withPrefix ? "周" : "") + chinese[day] : english[day]
    }

    init(botID: String, session: LinkSession) {
        self.botID = botID
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("New task")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NativeLanguage.text("Create task"), style: .done,
                                                            target: self, action: #selector(create))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 24, trailing: 18)
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        name.placeholder = NativeLanguage.text("Morning briefing")
        name.borderStyle = .roundedRect
        name.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(name)
        prompt.font = .preferredFont(forTextStyle: .body)
        prompt.layer.borderWidth = 1
        prompt.layer.borderColor = UIColor.separator.cgColor
        prompt.layer.cornerRadius = 10
        prompt.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(prompt)
        kind.selectedSegmentIndex = 1
        kind.addTarget(self, action: #selector(updateFields), for: .valueChanged)
        stack.addArrangedSubview(kind)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        date.text = formatter.string(from: Date())
        date.placeholder = "YYYY-MM-DD"
        time.text = "09:00"
        time.placeholder = "09:00"
        weekdayRow.axis = .horizontal
        weekdayRow.distribution = .fillEqually
        weekdayRow.spacing = 4
        for day in 1...7 {
            let button = UIButton(type: .system)
            button.setTitle(Self.weekdayLabel(day), for: .normal)
            button.layer.cornerRadius = 12
            button.accessibilityLabel = Self.weekdayLabel(day, withPrefix: true)
            button.addAction(UIAction { [weak self] _ in self?.toggleWeekday(day) }, for: .touchUpInside)
            weekdayButtons.append(button)
            weekdayRow.addArrangedSubview(button)
        }
        weekdayRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(weekdayRow)
        updateWeekdayButtons()
        interval.text = "1"
        interval.keyboardType = .numberPad
        repeatUnit.selectedSegmentIndex = 1
        for field in [date, time, interval] {
            field.borderStyle = .roundedRect
            field.autocapitalizationType = .none
            field.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(field)
        }
        stack.addArrangedSubview(repeatUnit)
        updateFields()
    }

    private func toggleWeekday(_ day: Int) {
        if selectedWeekdays.contains(day) { selectedWeekdays.remove(day) }
        else { selectedWeekdays.insert(day) }
        updateWeekdayButtons()
    }

    private func updateWeekdayButtons() {
        for (index, button) in weekdayButtons.enumerated() {
            let selected = selectedWeekdays.contains(index + 1)
            button.backgroundColor = selected ? view.tintColor : .tertiarySystemBackground
            button.setTitleColor(selected ? .white : .label, for: .normal)
            button.accessibilityValue = NativeLanguage.text(selected ? "Selected" : "Not selected")
        }
    }

    @objc private func updateFields() {
        date.isHidden = kind.selectedSegmentIndex != 0
        time.isHidden = kind.selectedSegmentIndex == 3
        weekdayRow.isHidden = kind.selectedSegmentIndex != 2
        interval.isHidden = kind.selectedSegmentIndex != 3
        repeatUnit.isHidden = kind.selectedSegmentIndex != 3
    }

    @objc private func create() {
        let title = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let task = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !task.isEmpty else {
            showError(NativeLanguage.text("Enter a title and instructions."))
            return
        }
        let when: [String: JSONValue]
        switch kind.selectedSegmentIndex {
        case 0:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let at = formatter.date(from: "\(date.text ?? "") \(time.text ?? "")") else {
                showError(NativeLanguage.text("Enter a date and time in YYYY-MM-DD and HH:mm format."))
                return
            }
            when = ["kind": .string("at"), "at": .string(ISO8601DateFormatter().string(from: at))]
        case 2:
            let days = selectedWeekdays.sorted()
            guard !days.isEmpty else {
                showError(NativeLanguage.text("Choose at least one weekday."))
                return
            }
            when = ["kind": .string("weekly"), "time": .string(time.text ?? "09:00"),
                    "timeZone": .string(TimeZone.current.identifier),
                    "weekdays": .array(days.map { .number(Double($0)) })]
        case 3:
            let multiplier = [1, 60, 1440][repeatUnit.selectedSegmentIndex]
            guard let count = Int(interval.text ?? ""), count > 0,
                  count <= Int.max / multiplier else {
                showError(NativeLanguage.text("Enter a positive repeat interval."))
                return
            }
            when = ["kind": .string("every"), "minutes": .number(Double(count * multiplier))]
        default:
            when = ["kind": .string("daily"), "time": .string(time.text ?? "09:00"),
                    "timeZone": .string(TimeZone.current.identifier)]
        }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            do {
                _ = try await BotAPI.call("schedule-create", payload: .object([
                    "target": .string(botID), "title": .string(title), "prompt": .string(task),
                    "when": .object(when),
                ]), on: session)
                onSaved?()
                navigationController?.popViewController(animated: true)
            } catch {
                navigationItem.rightBarButtonItem?.isEnabled = true
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Could not create task"), message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
        present(alert, animated: true)
    }
}
