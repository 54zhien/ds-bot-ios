import UIKit

final class FolderPickerViewController: UITableViewController {
    enum Owner {
        case team
        case bot(String)
        case room(String)
    }

    var onPicked: ((String) -> Void)?
    private let owner: Owner
    private let session: LinkSession
    private var path: String
    private var parent: String?
    private var recent: [JSONValue] = []
    private var entries: [JSONValue] = []
    private var truncated = false

    init(current: String, owner: Owner, session: LinkSession) {
        path = current
        self.owner = owner
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Working folder"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Use this folder", style: .done, target: self, action: #selector(choose)
        )
        Task {
            if let value = try? await BotAPI.call("folders", on: session),
               case .array(let values)? = value["folders"] {
                recent = values
                tableView.reloadData()
            }
            await load(path)
        }
    }

    private func load(_ next: String) async {
        do {
            let result = try await BotAPI.call("folder-list", payload: .object([
                "path": .string(next),
            ]), on: session)
            path = result["path"]?.stringValue ?? next
            parent = result["parent"]?.stringValue
            if case .array(let values)? = result["entries"] { entries = values } else { entries = [] }
            truncated = result["truncated"] == .bool(true)
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Folders" : path.isEmpty ? "/" : path
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? recent.count : (parent == nil ? 0 : 1) + entries.count + (truncated ? 1 : 0)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "folder")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "folder")
        cell.selectionStyle = .default
        if indexPath.section == 0 {
            let item = recent[indexPath.row]
            cell.textLabel?.text = item["title"]?.stringValue ?? "Folder"
            cell.detailTextLabel?.text = item["path"]?.stringValue
        } else if parent != nil && indexPath.row == 0 {
            cell.textLabel?.text = "Up one level"
            cell.detailTextLabel?.text = parent
        } else {
            let offset = indexPath.row - (parent == nil ? 0 : 1)
            if offset < entries.count {
                let item = entries[offset]
                cell.textLabel?.text = item["name"]?.stringValue ?? "Folder"
                cell.detailTextLabel?.text = item["path"]?.stringValue
            } else {
                cell.textLabel?.text = "Some folders are not shown"
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let next: String?
        if indexPath.section == 0 { next = recent[indexPath.row]["path"]?.stringValue }
        else if parent != nil && indexPath.row == 0 { next = parent }
        else {
            let offset = indexPath.row - (parent == nil ? 0 : 1)
            next = entries.indices.contains(offset) ? entries[offset]["path"]?.stringValue : nil
        }
        if let next { Task { await load(next) } }
    }

    @objc private func choose() {
        let endpoint: String
        let payload: [String: JSONValue]
        switch owner {
        case .team:
            endpoint = "team-workspace"
            payload = ["path": .string(path)]
        case .bot(let id):
            endpoint = "update-bot"
            payload = ["id": .string(id), "workDir": .string(path)]
        case .room(let id):
            endpoint = "update-room"
            payload = ["id": .string(id), "workDir": .string(path)]
        }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            do {
                _ = try await BotAPI.call(endpoint, payload: .object(payload), on: session)
                onPicked?(path)
                navigationController?.popViewController(animated: true)
            } catch {
                navigationItem.rightBarButtonItem?.isEnabled = true
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Folder unavailable", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
