import UIKit

final class ProviderSettingsViewController: UITableViewController {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let session: LinkSession
    private var providers: [JSONValue] = []
    private var addable: [JSONValue] = []
    private var protocols: [String] = []
    private var available = true

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Model providers")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let result = try await BotAPI.call("providers", on: session)
            available = result["available"] != .bool(false)
            if case .array(let values)? = result["providers"] { providers = values } else { providers = [] }
            if case .array(let values)? = result["addable"] { addable = values } else { addable = [] }
            protocols = result["protocols"]?.stringArrayValue ?? []
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        tr(section == 0 ? "Model providers" : section == 1 ? "Known providers" : "Custom API")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(1, providers.count) : section == 1 ? addable.count : 1
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "provider")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "provider")
        cell.accessoryView = nil
        cell.selectionStyle = .default
        if indexPath.section == 0 && providers.isEmpty {
            cell.textLabel?.text = tr(available ? "No providers" : "This computer cannot set up model providers")
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
        } else if indexPath.section == 0 {
            let item = providers[indexPath.row]
            cell.textLabel?.text = item["name"]?.stringValue ?? item["id"]?.stringValue
            let configured = item["key"]?["configured"] == .bool(true)
            let key = tr(configured ? "Key set" : "Needs an API key")
            let count: Int
            if case .array(let models)? = item["models"] { count = models.count } else { count = 0 }
            cell.detailTextLabel?.text = "\(key) · \(count) models"
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        } else if indexPath.section == 1 {
            let item = addable[indexPath.row]
            cell.textLabel?.text = item["name"]?.stringValue ?? item["id"]?.stringValue
            cell.detailTextLabel?.text = nil
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        } else {
            cell.textLabel?.text = tr("Add custom provider")
            cell.detailTextLabel?.text = tr("API URL and model IDs")
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            guard !providers.isEmpty else { return }
            manage(providers[indexPath.row], source: tableView.cellForRow(at: indexPath))
        } else if indexPath.section == 1 { add(addable[indexPath.row]) }
        else { addCustom() }
    }

    private func manage(_ item: JSONValue, source: UIView?) {
        guard let id = item["id"]?.stringValue else { return }
        let sheet = UIAlertController(title: item["name"]?.stringValue ?? id,
                                      message: item["error"]?.stringValue, preferredStyle: .actionSheet)
        if item["key"]?["writable"] == .bool(true) {
            sheet.addAction(UIAlertAction(title: item["key"]?["configured"] == .bool(true)
                                          ? tr("Replace API key") : tr("Set API key"), style: .default) { [weak self] _ in
                self?.askKey(for: id)
            })
            if item["key"]?["configured"] == .bool(true) {
                sheet.addAction(UIAlertAction(title: tr("Remove key"), style: .destructive) { [weak self] _ in
                    self?.run("provider-key", payload: ["provider": .string(id), "value": .null])
                })
            }
        }
        if item["removable"] == .bool(true) {
            sheet.addAction(UIAlertAction(title: tr("Remove provider"), style: .destructive) { [weak self] _ in
                self?.confirmRemoval(id: id, name: item["name"]?.stringValue ?? id)
            })
        }
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        present(sheet, animated: true)
    }

    private func askKey(for id: String) {
        let alert = UIAlertController(title: tr("API key"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = self.tr("Paste API key")
            field.isSecureTextEntry = true
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Save"), style: .default) { [weak self, weak alert] _ in
            guard let value = alert?.textFields?.first?.text, !value.isEmpty else { return }
            self?.run("provider-key", payload: ["provider": .string(id), "value": .string(value)])
        })
        present(alert, animated: true)
    }

    private func add(_ item: JSONValue) {
        guard let id = item["id"]?.stringValue else { return }
        let alert = UIAlertController(title: "Add \(item["name"]?.stringValue ?? id)",
                                      message: tr("Enter an API key if you have one."), preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = self.tr("API key")
            field.isSecureTextEntry = true
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Add"), style: .default) { [weak self, weak alert] _ in
            self?.run("provider-add", payload: [
                "provider": .string(id), "key": .string(alert?.textFields?.first?.text ?? ""),
            ])
        })
        present(alert, animated: true)
    }

    private func addCustom() {
        let editor = CustomProviderViewController(session: session, protocols: protocols)
        editor.onSaved = { [weak self] in Task { await self?.load() } }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func confirmRemoval(id: String, name: String) {
        let alert = UIAlertController(title: "Remove \(name)?",
                                      message: tr("Bots using this provider need another model."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("Keep"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Remove"), style: .destructive) { [weak self] _ in
            self?.run("provider-remove", payload: ["provider": .string(id)])
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
        let alert = UIAlertController(title: tr("Provider action failed"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("OK"), style: .default))
        present(alert, animated: true)
    }
}
