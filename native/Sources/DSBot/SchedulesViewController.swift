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
        title = "Scheduled tasks"
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
            cell.textLabel?.text = "No scheduled tasks yet"
            cell.detailTextLabel?.text = "Tap + to add one"
        } else {
            let task = tasks[indexPath.row]
            cell.textLabel?.text = task["title"]?.stringValue ?? "Task"
            let kind = task["kind"]?.stringValue ?? ""
            let status = task["status"]?.stringValue ?? ""
            cell.detailTextLabel?.text = [kind, status].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return cell
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard tasks.indices.contains(indexPath.row), let id = tasks[indexPath.row]["id"]?.stringValue else { return nil }
        let task = tasks[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
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
        let alert = UIAlertController(title: "Delete this task?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
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
        let alert = UIAlertController(title: "Schedule unavailable", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
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
    private let kind = UISegmentedControl(items: ["Once", "Daily", "Weekly", "Repeat"])
    private let date = UITextField()
    private let time = UITextField()
    private let weekdays = UITextField()
    private let interval = UITextField()

    init(botID: String, session: LinkSession) {
        self.botID = botID
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New task"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Create", style: .done,
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
        name.placeholder = "Morning briefing"
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
        weekdays.text = "1,2,3,4,5"
        weekdays.placeholder = "Weekdays: 1=Mon, 7=Sun"
        interval.text = "60"
        interval.placeholder = "Minutes between runs"
        for field in [date, time, weekdays, interval] {
            field.borderStyle = .roundedRect
            field.autocapitalizationType = .none
            field.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(field)
        }
        updateFields()
    }

    @objc private func updateFields() {
        date.isHidden = kind.selectedSegmentIndex != 0
        time.isHidden = kind.selectedSegmentIndex == 3
        weekdays.isHidden = kind.selectedSegmentIndex != 2
        interval.isHidden = kind.selectedSegmentIndex != 3
    }

    @objc private func create() {
        let title = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let task = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !task.isEmpty else { showError("Enter a title and instructions."); return }
        let when: [String: JSONValue]
        switch kind.selectedSegmentIndex {
        case 0:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let at = formatter.date(from: "\(date.text ?? "") \(time.text ?? "")") else {
                showError("Enter a date and time in YYYY-MM-DD and HH:mm format.")
                return
            }
            when = ["kind": .string("at"), "at": .string(ISO8601DateFormatter().string(from: at))]
        case 2:
            let days = (weekdays.text ?? "").split(separator: ",").compactMap {
                Int(String($0).trimmingCharacters(in: .whitespaces))
            }
            guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
                showError("Choose weekdays from 1 to 7.")
                return
            }
            when = ["kind": .string("weekly"), "time": .string(time.text ?? "09:00"),
                    "timeZone": .string(TimeZone.current.identifier),
                    "weekdays": .array(days.map { .number(Double($0)) })]
        case 3:
            guard let minutes = Int(interval.text ?? ""), minutes > 0 else {
                showError("Enter a positive number of minutes.")
                return
            }
            when = ["kind": .string("every"), "minutes": .number(Double(minutes))]
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
        let alert = UIAlertController(title: "Could not create task", message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
