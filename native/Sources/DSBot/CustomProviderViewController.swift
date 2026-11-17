import UIKit

final class CustomProviderViewController: UITableViewController {
    var onSaved: (() -> Void)?

    private let session: LinkSession
    private let protocols: [String]
    private let providerID = UITextField()
    private let providerName = UITextField()
    private let baseURL = UITextField()
    private let apiKey = UITextField()
    private let manualModels = UITextField()
    private var selectedProtocol: String?
    private var foundModels: [JSONValue] = []
    private var selectedModels = Set<String>()
    private var discovering = false
    private var saving = false

    init(session: LinkSession, protocols: [String]) {
        self.session = session
        self.protocols = protocols
        selectedProtocol = protocols.first
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Custom provider")
        tableView.keyboardDismissMode = .interactive
        for (field, hint) in [(providerID, "Provider ID"), (providerName, "Name"),
                              (baseURL, "API base URL"), (apiKey, "API key"),
                              (manualModels, "Model IDs, comma separated")] {
            field.placeholder = NativeLanguage.text(hint)
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
            field.font = .preferredFont(forTextStyle: .body)
        }
        apiKey.isSecureTextEntry = true
        baseURL.keyboardType = .URL
        providerID.accessibilityLabel = NativeLanguage.text("Provider ID")
        providerName.accessibilityLabel = NativeLanguage.text("Provider name")
        baseURL.accessibilityLabel = NativeLanguage.text("API base URL")
        apiKey.accessibilityLabel = NativeLanguage.text("API key")
        manualModels.accessibilityLabel = NativeLanguage.text("Manual model IDs")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Connection", "Models", nil][section].map(NativeLanguage.text)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 5 : section == 1 ? 2 + foundModels.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "custom-provider")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "custom-provider")
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = nil
        cell.contentView.subviews.filter { $0 is UITextField }.forEach { $0.removeFromSuperview() }
        if path.section == 0 && path.row != 3 {
            let field = [providerID, providerName, baseURL, apiKey][path.row]
            field.removeFromSuperview()
            attach(field, to: cell)
            cell.textLabel?.text = nil
            cell.selectionStyle = .none
        } else if path.section == 0 {
            cell.textLabel?.text = NativeLanguage.text("Protocol")
            cell.detailTextLabel?.text = selectedProtocol ?? NativeLanguage.text("Default")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else if path.section == 1 && path.row == 0 {
            cell.textLabel?.text = NativeLanguage.text(discovering ? "Finding models…" : "Find models")
            cell.textLabel?.textColor = view.tintColor
            cell.selectionStyle = .default
        } else if path.section == 1 && path.row == 1 {
            manualModels.removeFromSuperview()
            attach(manualModels, to: cell)
            cell.textLabel?.text = nil
            cell.selectionStyle = .none
        } else if path.section == 1 {
            let model = foundModels[path.row - 2]
            let id = model["id"]?.stringValue ?? ""
            cell.textLabel?.text = model["name"]?.stringValue ?? id
            cell.detailTextLabel?.text = id
            cell.accessoryType = selectedModels.contains(id) ? .checkmark : .none
            cell.selectionStyle = .default
        } else {
            cell.textLabel?.text = NativeLanguage.text(saving ? "Adding…" : "Add provider")
            cell.textLabel?.textColor = view.tintColor
            cell.selectionStyle = .default
        }
        return cell
    }

    private func attach(_ field: UITextField, to cell: UITableViewCell) {
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        if path.section == 0 && path.row == 3 { chooseProtocol(from: tableView.cellForRow(at: path)) }
        else if path.section == 1 && path.row == 0 { discover() }
        else if path.section == 1 && path.row >= 2 {
            guard let id = foundModels[path.row - 2]["id"]?.stringValue else { return }
            if !selectedModels.insert(id).inserted { selectedModels.remove(id) }
            tableView.reloadRows(at: [path], with: .automatic)
        } else if path.section == 2 { save() }
    }

    private func chooseProtocol(from source: UIView?) {
        guard !protocols.isEmpty else { return }
        let sheet = UIAlertController(title: NativeLanguage.text("API protocol"), message: nil, preferredStyle: .actionSheet)
        for api in protocols {
            sheet.addAction(UIAlertAction(title: api, style: .default) { [weak self] _ in
                self?.selectedProtocol = api
                self?.tableView.reloadRows(at: [IndexPath(row: 3, section: 0)], with: .none)
            })
        }
        sheet.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        present(sheet, animated: true)
    }

    private func discover() {
        let url = baseURL.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty, !discovering else { return }
        view.endEditing(true)
        discovering = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
        Task {
            defer {
                discovering = false
                tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
            }
            do {
                var payload: [String: JSONValue] = ["baseURL": .string(url),
                                                    "key": .string(apiKey.text ?? "")]
                if let selectedProtocol { payload["api"] = .string(selectedProtocol) }
                let result = try await BotAPI.call("provider-models", payload: .object(payload), on: session)
                if case .array(let models) = result { foundModels = models } else { foundModels = [] }
                selectedModels = []
                tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
            } catch { showError("Could not find models", message: error.localizedDescription) }
        }
    }

    private func save() {
        guard !saving else { return }
        let id = providerID.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = baseURL.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typed = (manualModels.text ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
        let discovered = foundModels.filter { selectedModels.contains($0["id"]?.stringValue ?? "") }
        let discoveredIDs = Set(discovered.compactMap { $0["id"]?.stringValue })
        let models = discovered + typed.filter { !discoveredIDs.contains($0) }.map {
            .object(["id": .string($0)])
        }
        guard !id.isEmpty, !url.isEmpty, !models.isEmpty else {
            showError("Missing details", message: NativeLanguage.text("Provider ID, API URL and at least one model are required."))
            return
        }
        view.endEditing(true)
        saving = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
        Task {
            defer {
                saving = false
                tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
            }
            do {
                var payload: [String: JSONValue] = [
                    "custom": .bool(true), "provider": .string(id), "name": .string(providerName.text ?? ""),
                    "baseURL": .string(url), "key": .string(apiKey.text ?? ""), "models": .array(models),
                ]
                if let selectedProtocol { payload["api"] = .string(selectedProtocol) }
                _ = try await BotAPI.call("provider-add", payload: .object(payload), on: session)
                onSaved?()
                navigationController?.popViewController(animated: true)
            } catch { showError("Could not add provider", message: error.localizedDescription) }
        }
    }

    private func showError(_ title: String, message: String) {
        let alert = UIAlertController(title: NativeLanguage.text(title), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
        present(alert, animated: true)
    }
}
