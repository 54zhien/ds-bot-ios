import UIKit

final class NativeSettingsViewController: UITableViewController {
    var onComputers: (() -> Void)?
    var onUsage: (() -> Void)?
    private let computerName: String
    private let themes = ["System", "Light", "Dark"]

    init(computerName: String) {
        self.computerName = computerName
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Phone" : "DS Bot"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "setting")
        cell.accessoryType = .none
        cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = "Computers"
            cell.detailTextLabel?.text = computerName
        case (0, 1):
            cell.textLabel?.text = "Appearance"
            let selected = UserDefaults.standard.string(forKey: "dsbot.theme") ?? "System"
            cell.detailTextLabel?.text = selected
        case (0, 2):
            cell.textLabel?.text = "Usage"
            cell.detailTextLabel?.text = nil
        default:
            cell.textLabel?.text = "About DS Bot"
            cell.detailTextLabel?.text = nil
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            let action = onComputers
            dismiss(animated: true) { action?() }
        case (0, 1):
            let sheet = UIAlertController(title: "Appearance", message: nil, preferredStyle: .actionSheet)
            for theme in themes {
                sheet.addAction(UIAlertAction(title: theme, style: .default) { [weak self] _ in
                    UserDefaults.standard.set(theme, forKey: "dsbot.theme")
                    self?.view.window?.overrideUserInterfaceStyle = Self.style(for: theme)
                    self?.tableView.reloadData()
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(sheet, animated: true)
        case (0, 2):
            let action = onUsage
            dismiss(animated: true) { action?() }
        default:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let about = UIAlertController(title: "DS Bot", message: "iPhone app · version \(version)",
                                          preferredStyle: .alert)
            about.addAction(UIAlertAction(title: "OK", style: .default))
            present(about, animated: true)
        }
    }

    static func style(for theme: String) -> UIUserInterfaceStyle {
        switch theme {
        case "Light": return .light
        case "Dark": return .dark
        default: return .unspecified
        }
    }
}
