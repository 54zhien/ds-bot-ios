import UIKit

final class BotUsageViewController: UITableViewController {
    private let botID: String
    private let session: LinkSession
    private var summary: JSONValue?
    private var stats: JSONValue?

    init(botID: String, name: String, session: LinkSession) {
        self.botID = botID
        self.session = session
        super.init(style: .insetGrouped)
        title = name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        let payload: JSONValue = .object(["botId": .string(botID)])
        if let result = try? await BotAPI.call("usage-summary", payload: payload, on: session) {
            summary = result
            tableView.reloadData()
        }
        if let result = try? await BotAPI.call("run-stats", payload: payload, on: session) {
            stats = result
            tableView.reloadData()
        }
        refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        NativeLanguage.text(["Usage", "Model", "Runs"][section])
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 1 {
            if case .array(let models)? = summary?["models"] { return models.count }
            return 0
        }
        return 3
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bot-usage")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "bot-usage")
        let item: (String, String)
        switch (indexPath.section, indexPath.row) {
        case (0, 0): item = (NativeLanguage.text("Day"), total(summary?["day"]))
        case (0, 1): item = (NativeLanguage.text("Week"), total(summary?["week"]))
        case (0, _): item = (NativeLanguage.text("Month"), total(summary?["month"]))
        case (1, _):
            if case .array(let models)? = summary?["models"], models.indices.contains(indexPath.row) {
                let model = models[indexPath.row]
                item = (model["name"]?.stringValue ?? NativeLanguage.text("Model"), total(model))
            } else { item = (NativeLanguage.text("Model"), "—") }
        case (2, 0): item = (NativeLanguage.text("Turns"), stats?["sessionStats"]?["turns"]?.intValue.map { String($0) } ?? "—")
        case (2, 1): item = (NativeLanguage.text("Steps"), stats?["sessionStats"]?["steps"]?.intValue.map { String($0) } ?? "—")
        default:
            if let used = stats?["contextPressure"]?["pressureTokens"]?.intValue,
               let window = stats?["contextPressure"]?["contextWindow"]?.intValue, window > 0 {
                item = (NativeLanguage.text("Context used"), "\(Int((Double(used) / Double(window) * 100).rounded()))%")
            } else { item = (NativeLanguage.text("Context used"), "—") }
        }
        cell.textLabel?.text = NativeLanguage.text(item.0)
        cell.detailTextLabel?.text = item.1
        cell.selectionStyle = .none
        return cell
    }

    private func total(_ value: JSONValue?) -> String {
        guard let value, value != .null else { return "—" }
        let count = (value["input"]?.intValue ?? 0) + (value["cacheRead"]?.intValue ?? 0)
            + (value["cacheWrite"]?.intValue ?? 0) + (value["output"]?.intValue ?? 0)
        return count.formatted()
    }
}
