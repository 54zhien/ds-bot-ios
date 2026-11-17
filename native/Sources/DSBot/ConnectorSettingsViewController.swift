import UIKit

final class ConnectorSettingsViewController: UITableViewController {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let session: LinkSession
    private var connectors: [JSONValue] = []

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Connectors")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let state = try await BotAPI.call("state", on: session)
            if case .array(let values)? = state["connectors"] { connectors = values } else { connectors = [] }
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, connectors.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "connector")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "connector")
        cell.accessoryView = nil
        if connectors.isEmpty {
            cell.textLabel?.text = tr("No connectors")
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
        } else {
            let item = connectors[indexPath.row]
            cell.textLabel?.text = item["name"]?.stringValue ?? item["id"]?.stringValue
            let status = item["state"]?.stringValue ?? "off"
            switch status {
            case "ready": cell.detailTextLabel?.text = item["account"]?.stringValue.map {
                NativeLanguage.text("Connected as {name}", ["name": $0])
            } ?? tr("Connected")
            case "connecting": cell.detailTextLabel?.text = tr("Connecting…")
            case "error": cell.detailTextLabel?.text = item["error"]?.stringValue ?? tr("Could not connect")
            default: cell.detailTextLabel?.text = tr("Not connected")
            }
            cell.selectionStyle = .default
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !connectors.isEmpty, let id = connectors[indexPath.row]["id"]?.stringValue else { return }
        let item = connectors[indexPath.row]
        let status = item["state"]?.stringValue ?? "off"
        let sheet = UIAlertController(title: item["name"]?.stringValue ?? id,
                                      message: item["error"]?.stringValue, preferredStyle: .actionSheet)
        if status == "off" {
            sheet.addAction(UIAlertAction(title: tr("Connect"), style: .default) { [weak self] _ in
                self?.askToken(for: id, name: item["name"]?.stringValue ?? id)
            })
        } else {
            if status == "error" {
                sheet.addAction(UIAlertAction(title: tr("Try again"), style: .default) { [weak self] _ in
                    self?.run("connector-retry", id: id)
                })
            }
            sheet.addAction(UIAlertAction(title: tr("Disconnect"), style: .destructive) { [weak self] _ in
                self?.run("connector-disconnect", id: id)
            })
        }
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(sheet, animated: true)
    }

    private func askToken(for id: String, name: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Connect {name}", ["name": name]),
                                      message: NativeLanguage.text("Paste a token from {name}.", ["name": name]),
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = self.tr("Token")
            field.isSecureTextEntry = true
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Connect"), style: .default) { [weak self, weak alert] _ in
            guard let token = alert?.textFields?.first?.text, !token.isEmpty else { return }
            self?.run("connector-connect", id: id, token: token)
        })
        present(alert, animated: true)
    }

    private func run(_ endpoint: String, id: String, token: String? = nil) {
        var payload: [String: JSONValue] = ["id": .string(id)]
        if let token { payload["token"] = .string(token) }
        Task {
            do {
                _ = try await BotAPI.call(endpoint, payload: .object(payload), on: session)
                await load()
            } catch { showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: tr("Connector action failed"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("OK"), style: .default))
        present(alert, animated: true)
    }
}
