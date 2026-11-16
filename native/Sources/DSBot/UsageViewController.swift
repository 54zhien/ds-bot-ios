import UIKit

/// Team usage from the same hourly projection shown by the RN Settings page.
final class UsageViewController: UITableViewController {
    private struct Total {
        var input = 0
        var output = 0
        var combined: Int { input + output }
    }

    private let session: LinkSession
    private var totals = Total()
    private var owners: [(String, Int)] = []
    private var models: [(String, Int)] = []
    private var loaded = false

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Usage"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await loadUsage() }
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func refresh() { Task { await loadUsage() } }

    private func loadUsage() async {
        do {
            let result = try await BotAPI.call("usage", payload: .object([
                "timeZone": .string(TimeZone.current.identifier),
            ]), on: session)
            let rows: [[JSONValue]]
            if case .array(let entries)? = result["rows"] {
                rows = entries.compactMap { entry in
                    if case .array(let columns) = entry { return columns }
                    return nil
                }
            } else { rows = [] }
            func total(_ matches: (Int, Int) -> Bool) -> Total {
                var sum = Total()
                for row in rows where row.count >= 8 && matches(row[1].intValue ?? -1, row[2].intValue ?? -1) {
                    sum.input += (row[4].intValue ?? 0) + (row[5].intValue ?? 0) + (row[6].intValue ?? 0)
                    sum.output += row[7].intValue ?? 0
                }
                return sum
            }
            totals = total { _, _ in true }
            if case .array(let entries)? = result["owners"] {
                owners = entries.enumerated().compactMap { index, owner in
                    let count = total { ownerIndex, _ in ownerIndex == index }.combined
                    guard count > 0 else { return nil }
                    return (owner["name"]?.stringValue ?? "Bot", count)
                }
            } else { owners = [] }
            if case .array(let entries)? = result["models"] {
                models = entries.enumerated().compactMap { index, model in
                    let count = total { _, modelIndex in modelIndex == index }.combined
                    guard count > 0 else { return nil }
                    return (model["name"]?.stringValue ?? "Model", count)
                }
            } else { models = [] }
            loaded = true
            tableView.reloadData()
        } catch {
            let alert = UIAlertController(title: "Usage unavailable", message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
        refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Usage", "Bots", "Models"][section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2
        case 1: return owners.count
        default: return models.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "usage")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "usage")
        let item: (String, String)
        switch (indexPath.section, indexPath.row) {
        case (0, 0): item = ("Tokens in", loaded ? totals.input.formatted() : "—")
        case (0, 1): item = ("Tokens out", loaded ? totals.output.formatted() : "—")
        case (1, _): item = (owners[indexPath.row].0, owners[indexPath.row].1.formatted())
        default: item = (models[indexPath.row].0, models[indexPath.row].1.formatted())
        }
        cell.textLabel?.text = item.0
        cell.detailTextLabel?.text = item.1
        cell.selectionStyle = .none
        return cell
    }
}
