import UIKit

final class LocationSettingsViewController: UITableViewController {
    private let session: LinkSession
    private var workspace = ""
    private var dataPath: String?

    init(session: LinkSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Location")
        Task { await load() }
    }

    private func load() async {
        if let folders = try? await BotAPI.call("folders", on: session) {
            workspace = folders["team"]?.stringValue ?? ""
        }
        if let state = try? await BotAPI.call("state", on: session) {
            dataPath = state["dataPath"]?.stringValue
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        dataPath == nil ? 1 : 2
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "location")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "location")
        cell.textLabel?.text = indexPath.row == 0 ? "Team workspace" : "Data location"
        cell.detailTextLabel?.text = indexPath.row == 0 ? workspace : dataPath
        cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = indexPath.row == 0 ? .default : .none
        cell.accessoryView = indexPath.row == 0
            ? OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16)) : nil
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row == 0 else { return }
        let folder = FolderPickerViewController(current: workspace, owner: .team, session: session)
        folder.onPicked = { [weak self] path in
            self?.workspace = path
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(folder, animated: true)
    }
}
