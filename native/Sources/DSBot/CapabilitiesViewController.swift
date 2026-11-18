import UIKit

final class CapabilitiesViewController: UITableViewController {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let session: LinkSession
    private var items: [JSONValue] = []
    private var statuses: JSONValue?

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Capabilities")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self,
                                                            action: #selector(add))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let state = try await BotAPI.call("state", on: session)
            if case .array(let values)? = state["capabilities"] { items = values } else { items = [] }
            statuses = state["capabilityStatuses"]
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, items.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "capability")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "capability")
        cell.detailTextLabel?.numberOfLines = 2
        if items.isEmpty {
            cell.textLabel?.text = tr("No capabilities")
            cell.detailTextLabel?.text = tr("Tap + to add an MCP server, skill, or pack")
            cell.accessoryType = .none
        } else {
            let item = items[indexPath.row]
            let name = item["name"]?.stringValue ?? ""
            let status = statuses?[name]
            cell.textLabel?.text = name
            let kind = item["kind"]?.stringValue ?? "mcp"
            let detail = tr(kind == "mcp" ? (item["transport"]?.stringValue == "stdio" ? "Local command" : "HTTP server")
                : kind == "skill" ? "Skill" : "Pack")
            let state = status?["state"]?.stringValue
            let stateText = state == "ready" ? tr("Ready") : state == "needs-approval" ? tr("Needs approval")
                : state == "error" ? status?["error"]?.stringValue ?? tr("Connection error") : nil
            cell.detailTextLabel?.text = [detail, item["description"]?.stringValue, stateText]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row) else { return }
        let item = items[indexPath.row]
        guard let name = item["name"]?.stringValue else { return }
        let sheet = UIAlertController(title: name,
                                      message: item["content"]?.stringValue ?? item["description"]?.stringValue,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: tr("Edit"), style: .default) { [weak self] _ in
            self?.edit(item)
        })
        if statuses?[name]?["state"]?.stringValue == "needs-approval" {
            sheet.addAction(UIAlertAction(title: tr("Approve"), style: .default) { [weak self] _ in
                self?.run("capability-approve", payload: ["name": .string(name)])
            })
        }
        sheet.addAction(UIAlertAction(title: tr("Delete"), style: .destructive) { [weak self] _ in
            self?.confirmDelete(name)
        })
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(sheet, animated: true)
    }

    @objc private func add() {
        let sheet = UIAlertController(title: tr("Add capability"), message: nil, preferredStyle: .actionSheet)
        for (kind, title) in [("mcp", "MCP server"), ("skill", "Skill"), ("pack", "Pack")] {
            sheet.addAction(UIAlertAction(title: tr(title), style: .default) { [weak self] _ in
                self?.showEditor(kind: kind, item: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func edit(_ item: JSONValue) {
        showEditor(kind: item["kind"]?.stringValue ?? "mcp", item: item)
    }

    private func showEditor(kind: String, item: JSONValue?) {
        if kind == "mcp" {
            let sheet = UIAlertController(title: tr("MCP transport"), message: nil, preferredStyle: .actionSheet)
            for (transport, title) in [("stdio", "Local command"), ("streamable-http", "HTTP server")] {
                sheet.addAction(UIAlertAction(title: tr(title), style: .default) { [weak self] _ in
                    self?.showFields(kind: kind, transport: transport, item: item)
                })
            }
            sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
            sheet.popoverPresentationController?.sourceView = view
            present(sheet, animated: true)
        } else {
            showFields(kind: kind, transport: nil, item: item)
        }
    }

    private func showFields(kind: String, transport: String?, item: JSONValue?) {
        let names = ["Name", "Description"] + (kind == "skill" ? ["Skill instructions"]
            : kind == "pack" ? ["Items (comma separated)"]
            : transport == "stdio" ? ["Command", "Arguments (comma separated)", "Environment (JSON object)"]
            : ["URL", "Headers (JSON object)"])
        let alert = UIAlertController(title: tr(item == nil ? "Add capability" : "Edit capability"),
                                      message: nil, preferredStyle: .alert)
        let values = [item?["name"]?.stringValue ?? "", item?["description"]?.stringValue ?? ""]
            + (kind == "skill" ? [item?["content"]?.stringValue ?? ""]
               : kind == "pack" ? [item?["items"]?.stringArrayValue?.joined(separator: ", ") ?? ""]
               : transport == "stdio" ? [item?["command"]?.stringValue ?? "",
                                         item?["args"]?.stringArrayValue?.joined(separator: ", ") ?? "",
                                         Self.jsonText(item?["env"])]
               : [item?["url"]?.stringValue ?? "", Self.jsonText(item?["headers"])])
        for (index, name) in names.enumerated() {
            alert.addTextField { field in
                field.placeholder = self.tr(name)
                field.text = values[index]
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
                if index == 0 && item != nil { field.isEnabled = false }
            }
        }
        alert.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Save"), style: .default) { [weak self, weak alert] _ in
            guard let fields = alert?.textFields else { return }
            let texts = fields.map { $0.text ?? "" }
            let name = texts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            var payload: [String: JSONValue] = ["name": .string(name), "kind": .string(kind),
                                                "description": .string(texts[1])]
            if item != nil { payload["originalName"] = .string(name) }
            if kind == "skill" { payload["content"] = .string(texts[2]) }
            else if kind == "pack" {
                payload["items"] = .array(texts[2].split(separator: ",").map {
                    .string($0.trimmingCharacters(in: .whitespacesAndNewlines))
                })
            } else if let transport {
                payload["transport"] = .string(transport)
                if transport == "stdio" {
                    payload["command"] = .string(texts[2])
                    payload["args"] = .array(texts[3].split(separator: ",").map {
                        .string($0.trimmingCharacters(in: .whitespacesAndNewlines))
                    })
                    guard let value = Self.parseObject(texts[4]) else {
                        self?.showError("Environment must be a JSON object")
                        return
                    }
                    payload["env"] = value
                } else {
                    payload["url"] = .string(texts[2])
                    guard let value = Self.parseObject(texts[3]) else {
                        self?.showError("Headers must be a JSON object")
                        return
                    }
                    payload["headers"] = value
                }
            }
            self?.run("capability-save", payload: payload)
        })
        present(alert, animated: true)
    }

    private static func parseObject(_ text: String) -> JSONValue? {
        guard let data = (text.isEmpty ? "{}" : text).data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object = value else { return nil }
        return value
    }

    private static func jsonText(_ value: JSONValue?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func confirmDelete(_ name: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Delete {name}?", ["name": name]), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("Keep"), style: .cancel))
        alert.addAction(UIAlertAction(title: tr("Delete"), style: .destructive) { [weak self] _ in
            self?.run("capability-delete", payload: ["name": .string(name)])
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
        let alert = UIAlertController(title: tr("Capability action failed"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("OK"), style: .default))
        present(alert, animated: true)
    }
}

final class BotCapabilitiesViewController: UITableViewController {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let botID: String
    private let session: LinkSession
    private var items: [JSONValue] = []
    private var attached = Set<String>()
    private var statuses: JSONValue?

    init(botID: String, session: LinkSession) {
        self.botID = botID
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Bot capabilities")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let state = try await BotAPI.call("state", on: session)
            if case .array(let values)? = state["capabilities"] { items = values } else { items = [] }
            if case .array(let bots)? = state["bots"],
               let bot = bots.first(where: { $0["id"]?.stringValue == botID }) {
                attached = Set(bot["capabilities"]?.stringArrayValue ?? [])
            }
            statuses = state["capabilityStatuses"]?[botID]
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, items.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bot-capability")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "bot-capability")
        if items.isEmpty {
            cell.textLabel?.text = tr("No capabilities in team library")
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let item = items[indexPath.row]
            let name = item["name"]?.stringValue ?? ""
            cell.textLabel?.text = name
            cell.detailTextLabel?.text = statuses?[name]?["state"]?.stringValue
                ?? item["description"]?.stringValue
            cell.accessoryType = attached.contains(name) ? .checkmark : .none
            cell.selectionStyle = .default
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard items.indices.contains(indexPath.row), let name = items[indexPath.row]["name"]?.stringValue else {
            return
        }
        let enabled = !attached.contains(name)
        Task {
            do {
                _ = try await BotAPI.call("bot-capability", payload: .object([
                    "botId": .string(botID), "name": .string(name), "attached": .bool(enabled),
                ]), on: session)
                if enabled { attached.insert(name) } else { attached.remove(name) }
                tableView.reloadRows(at: [indexPath], with: .automatic)
            } catch { showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: tr("Could not update capabilities"), message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("OK"), style: .default))
        present(alert, animated: true)
    }
}
