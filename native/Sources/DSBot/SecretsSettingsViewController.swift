import UIKit

final class SecretsSettingsViewController: UITableViewController {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let session: LinkSession
    private var secrets: [JSONValue] = []

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Secrets")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self, action: #selector(add))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let state = try await BotAPI.call("state", on: session)
            if case .array(let values)? = state["secrets"] { secrets = values } else { secrets = [] }
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, secrets.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "secret")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "secret")
        cell.selectionStyle = .none
        if secrets.isEmpty {
            cell.textLabel?.text = tr("Nothing saved yet")
            cell.detailTextLabel?.text = tr("Tap + to add a secret")
        } else {
            let secret = secrets[indexPath.row]
            cell.textLabel?.text = secret["name"]?.stringValue
            if case .array(let scope)? = secret["scope"] {
                cell.detailTextLabel?.text = scope.compactMap(\.stringValue).joined(separator: ", ")
            } else {
                cell.detailTextLabel?.text = secret["scope"]?.stringValue == "all"
                    ? tr("All Bots") : secret["scope"]?.stringValue
            }
        }
        return cell
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard secrets.indices.contains(indexPath.row), let name = secrets[indexPath.row]["name"]?.stringValue else {
            return nil
        }
        let action = UIContextualAction(style: .destructive, title: tr("Delete")) { [weak self] _, _, done in
            self?.confirmDelete(name)
            done(false)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func add() {
        let alert = UIAlertController(title: tr("Add secret"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = self.tr("Name")
            field.autocapitalizationType = .allCharacters
        }
        alert.addTextField { field in
            field.placeholder = self.tr("Paste or type the key")
            field.isSecureTextEntry = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Save"), style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, let value = alert?.textFields?.last?.text, !value.isEmpty else { return }
            self?.run("secret-set", payload: ["name": .string(name), "value": .string(value)])
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ name: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Delete {name}?", ["name": name]),
                                      message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("Keep"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Delete"), style: .destructive) { [weak self] _ in
            self?.run("secret-delete", payload: ["name": .string(name)])
        })
        present(alert, animated: true)
    }

    private func run(_ endpoint: String, payload: [String: JSONValue]) {
        Task {
            do {
                _ = try await BotAPI.call(endpoint, payload: .object(payload), on: session)
                await load()
            } catch { showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: tr("Secret action failed"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("OK"), style: .default))
        present(alert, animated: true)
    }
}
