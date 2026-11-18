import UIKit

final class AboutViewController: UITableViewController {
    private let computerName: String
    private let session: LinkSession
    private var versions: JSONValue?

    init(computerName: String, session: LinkSession) {
        self.computerName = computerName
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("About")
        Task {
            versions = try? await BotAPI.call("update-check", on: session)
            tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        NativeLanguage.text(section == 0 ? "About" : "Licenses")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? (versions?["dsh"]?["current"]?.stringValue == nil ? 3 : 4) : 2
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "about")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "about")
        let entry: (String, String)
        if indexPath.section == 1 {
            entry = indexPath.row == 0 ? ("DS Bot", "Apache License 2.0")
                : (NativeLanguage.text("Repository"), "github.com/Fei2411/DS-Bot")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else {
            var values: [(String, String)] = [("DS Bot", versions?["current"]?.stringValue ?? "—")]
            if let dsh = versions?["dsh"]?["current"]?.stringValue { values.append(("DSH", dsh)) }
            values.append((NativeLanguage.text("Phone app"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
            values.append((NativeLanguage.text("Computer"), computerName.isEmpty ? "—" : computerName))
            entry = values[indexPath.row]
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }
        cell.textLabel?.text = NativeLanguage.text(entry.0)
        cell.detailTextLabel?.text = NativeLanguage.text(entry.1)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let address = indexPath.row == 0
            ? "https://github.com/Fei2411/DS-Bot/blob/main/LICENSE"
            : "https://github.com/Fei2411/DS-Bot"
        if let url = URL(string: address) { UIApplication.shared.open(url) }
    }
}
