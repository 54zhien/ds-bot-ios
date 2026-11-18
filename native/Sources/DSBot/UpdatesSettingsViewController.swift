import UIKit

final class UpdatesSettingsViewController: UITableViewController {
    private let session: LinkSession
    private var update: JSONValue?
    private var dsh: JSONValue?
    private var diagnostics: JSONValue?
    private var latestDump: URL?
    private var busy = false
    private var hasNotes: Bool { !(update?["notes"]?.stringValue ?? "").isEmpty }
    private var lastEntry: String? {
        guard case .array(let entries)? = diagnostics?["entries"] else { return nil }
        return entries.last?["text"]?.stringValue
    }

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
        SettingsStyle.prepare(tableView)
        Task { await load() }
    }

    private var palette: Palette { SettingsStyle.palette(of: traitCollection) }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        if let result = try? await BotAPI.call("update-check", on: session) {
            update = result["update"] ?? result
            dsh = result["dsh"]
        }
        diagnostics = try? await BotAPI.call("diagnostics", on: session)
        // Taken from the folder, so a dump the user deleted in Files.app stops being shown.
        latestDump = DiagnosticsStore.latest()
        tableView.reloadData()
        refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        SettingsStyle.headerHeight
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        SettingsStyle.headerView(title: NativeLanguage.text(["DS Bot", "DSH", "Diagnostics", "Phone diagnostics"][section]),
                                 palette: palette)
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2 + (hasNotes ? 1 : 0) + (update?["available"] == .bool(true) ? 1 : 0)
        case 1: return dsh?["available"] == .bool(true) ? 2 : 1
        case 3: return 2
        default: return lastEntry == nil ? 3 : 4
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
        case (0, 1): pair = (NativeLanguage.text(busy ? "Checking…" : "Check for updates"), nil)
        case (0, 2) where hasNotes: pair = (NativeLanguage.text("What is new"), update?["notes"]?.stringValue)
        case (0, _): pair = (NativeLanguage.text("Install DS Bot update"), update?["latest"]?.stringValue)
        case (1, 0): pair = ("DSH \(dsh?["current"]?.stringValue ?? "")", status(dsh))
        case (1, 1): pair = (NativeLanguage.text("Install DSH update"), dsh?["verified"]?.stringValue ?? dsh?["latest"]?.stringValue)
        case (2, 0): pair = (NativeLanguage.text("Log entries"), diagnostics?["total"]?.intValue.map(String.init) ?? "—")
        case (2, 1) where lastEntry != nil: pair = (NativeLanguage.text("Last entry"), lastEntry)
        case (2, let row) where row == (lastEntry == nil ? 1 : 2):
            pair = (NativeLanguage.text("Diagnostics log"), NativeLanguage.text("View"))
        case (3, 0):
            pair = (NativeLanguage.text("Latest dump"), latestDump?.lastPathComponent ?? NativeLanguage.text("None yet"))
        case (3, _):
            pair = (NativeLanguage.text("Diagnostics folder"), "Documents/" + DiagnosticsStore.folder.lastPathComponent)
        default: pair = (NativeLanguage.text("Clear diagnostics"), nil)
        }
        cell.textLabel?.text = pair.0
        cell.detailTextLabel?.text = pair.1
        SettingsStyle.styleSubtitle(cell, palette: palette)
        // The one destructive row reads as destructive.
        if indexPath.section == 2, indexPath.row == (lastEntry == nil ? 2 : 3) {
            cell.textLabel?.textColor = palette.danger
        }
        if indexPath == IndexPath(row: 1, section: 0)
            || indexPath.section == 0 && indexPath.row == (hasNotes ? 3 : 2) && update?["available"] == .bool(true)
            || indexPath == IndexPath(row: 1, section: 1)
            || indexPath.section == 2 && indexPath.row >= (lastEntry == nil ? 1 : 2)
            || indexPath.section == 3 {
            cell.selectionStyle = .default
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return cell
    }

    private func status(_ value: JSONValue?) -> String {
        guard let value else { return "—" }
        switch value["phase"]?.stringValue {
        case "installing": return NativeLanguage.text("Installing…")
        case "installed": return NativeLanguage.text("Installed · restart DSH")
        case "failed": return value["error"]?.stringValue ?? NativeLanguage.text("Update failed")
        default: break
        }
        if value["available"] == .bool(true) {
            return NativeLanguage.text("Version {version} available", ["version": value["latest"]?.stringValue ?? value["verified"]?.stringValue ?? ""])
        }
        if value["enabled"] == .bool(false) { return NativeLanguage.text("Update checks are off") }
        if value["source"]?.stringValue == "path" { return NativeLanguage.text("Update from the local folder") }
        return NativeLanguage.text("Up to date")
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 1): Task { await load() }
        case (0, 2) where !hasNotes: confirm("Install DS Bot update?", endpoint: "update-install")
        case (0, 3) where hasNotes: confirm("Install DS Bot update?", endpoint: "update-install")
        case (1, 1): confirm("Install DSH update?", endpoint: "dsh-update-install")
        case (2, let row) where row == (lastEntry == nil ? 1 : 2): Task { await showLog() }
        case (2, let row) where row == (lastEntry == nil ? 2 : 3):
            confirm("Clear diagnostics?", endpoint: "diagnostics-clear")
        case (3, 0):
            showDump()
        case (3, 1):
            UIPasteboard.general.string = DiagnosticsStore.folder.path
        default: break
        }
    }

    private func confirm(_ title: String, endpoint: String) {
        let alert = UIAlertController(title: NativeLanguage.text(title), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NativeLanguage.text(endpoint == "diagnostics-clear" ? "Clear" : "Install"),
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

    /// The dump is on this phone, not on the computer, so it opens from the file itself.
    private func showDump() {
        guard let latestDump, let text = try? String(contentsOf: latestDump, encoding: .utf8) else {
            showError(NativeLanguage.text("There is no dump yet. Long-press the chat title to save one."))
            return
        }
        navigationController?.pushViewController(DiagnosticsLogViewController(content: text), animated: true)
    }

    private func showLog() async {
        do {
            let result = try await BotAPI.call("diagnostics-log", on: session)
            let viewer = DiagnosticsLogViewController(content: result.stringValue ?? "")
            navigationController?.pushViewController(viewer, animated: true)
        } catch { showError(error.localizedDescription) }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Could not load diagnostics"), message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
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
        title = NativeLanguage.text("Diagnostics log")
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NativeLanguage.text("Copy"), style: .plain,
                                                            target: self, action: #selector(copyLog))
    }

    @objc private func copyLog() { UIPasteboard.general.string = content }
}
