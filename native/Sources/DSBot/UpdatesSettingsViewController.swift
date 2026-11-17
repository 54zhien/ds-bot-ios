import UIKit

final class UpdatesSettingsViewController: UITableViewController {
    private let session: LinkSession
    private var update: JSONValue?
    private var dsh: JSONValue?
    private var diagnostics: JSONValue?
    private var busy = false

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Updates & diagnostics")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        if let result = try? await BotAPI.call("update-check", on: session) {
            update = result["update"] ?? result
            dsh = result["dsh"]
        }
        diagnostics = try? await BotAPI.call("diagnostics", on: session)
        tableView.reloadData()
        refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["DS Bot", "DSH", "Diagnostics"][section]
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return update?["available"] == .bool(true) ? 3 : 2
        case 1: return dsh?["available"] == .bool(true) ? 2 : 1
        default: return 3
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "update")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "update")
        cell.accessoryView = nil
        cell.selectionStyle = .none
        let pair: (String, String?)
        switch (indexPath.section, indexPath.row) {
        case (0, 0): pair = ("DS Bot \(update?["current"]?.stringValue ?? "")", status(update))
        case (0, 1): pair = (busy ? "Checking…" : "Check for updates", nil)
        case (0, 2): pair = ("Install DS Bot update", update?["latest"]?.stringValue)
        case (1, 0): pair = ("DSH \(dsh?["current"]?.stringValue ?? "")", status(dsh))
        case (1, 1): pair = ("Install DSH update", dsh?["verified"]?.stringValue ?? dsh?["latest"]?.stringValue)
        case (2, 0): pair = ("Log entries", diagnostics?["total"]?.intValue.map(String.init) ?? "—")
        case (2, 1): pair = ("Diagnostics log", "View")
        default: pair = ("Clear diagnostics", nil)
        }
        cell.textLabel?.text = pair.0
        cell.detailTextLabel?.text = pair.1
        if indexPath == IndexPath(row: 1, section: 0) || indexPath.row == 2 && indexPath.section == 0
            || indexPath == IndexPath(row: 1, section: 1) || indexPath.section == 2 && indexPath.row > 0 {
            cell.selectionStyle = .default
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return cell
    }

    private func status(_ value: JSONValue?) -> String {
        guard let value else { return "—" }
        switch value["phase"]?.stringValue {
        case "installing": return "Installing…"
        case "installed": return "Installed · restart DSH"
        case "failed": return value["error"]?.stringValue ?? "Update failed"
        default: break
        }
        if value["available"] == .bool(true) {
            return "Version \(value["latest"]?.stringValue ?? value["verified"]?.stringValue ?? "") available"
        }
        if value["enabled"] == .bool(false) { return "Update checks are off" }
        if value["source"]?.stringValue == "path" { return "Update from the local folder" }
        return "Up to date"
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 1): Task { await load() }
        case (0, 2): confirm("Install DS Bot update?", endpoint: "update-install")
        case (1, 1): confirm("Install DSH update?", endpoint: "dsh-update-install")
        case (2, 1): Task { await showLog() }
        case (2, 2): confirm("Clear diagnostics?", endpoint: "diagnostics-clear")
        default: break
        }
    }

    private func confirm(_ title: String, endpoint: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: endpoint == "diagnostics-clear" ? "Clear" : "Install",
                                      style: endpoint == "diagnostics-clear" ? .destructive : .default) { [weak self] _ in
            self?.run(endpoint)
        })
        present(alert, animated: true)
    }

    private func run(_ endpoint: String) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                _ = try await BotAPI.call(endpoint, on: session)
                await load()
            } catch { showError(error.localizedDescription) }
            busy = false
        }
    }

    private func showLog() async {
        do {
            let result = try await BotAPI.call("diagnostics-log", on: session)
            let viewer = DiagnosticsLogViewController(content: result.stringValue ?? "")
            navigationController?.pushViewController(viewer, animated: true)
        } catch { showError(error.localizedDescription) }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Could not load diagnostics", message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private final class DiagnosticsLogViewController: UIViewController {
    private let content: String

    init(content: String) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Diagnostics log"
        view.backgroundColor = .systemBackground
        let editor = UITextView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.isEditable = false
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.text = content
        view.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            editor.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy", style: .plain,
                                                            target: self, action: #selector(copyLog))
    }

    @objc private func copyLog() { UIPasteboard.general.string = content }
}
