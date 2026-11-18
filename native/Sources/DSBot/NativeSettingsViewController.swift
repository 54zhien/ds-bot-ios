import UIKit

final class NativeSettingsViewController: UITableViewController {
    var onComputers: (() -> Void)?
    var onUsage: (() -> Void)?
    private let computerName: String
    private let session: LinkSession
    private let themes = ["System", "Light", "Dark"]
    private let languages = [("system", "Follow system"), ("zh", "简体中文"), ("en", "English")]
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }

    init(computerName: String, session: LinkSession) {
        self.computerName = computerName
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = tr("Settings")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [4, 7, 1][section]
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Phone", "Team", "DS Bot"].map(tr)[section]
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "setting")
        cell.accessoryType = .none
        cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = tr("Computers")
            cell.detailTextLabel?.text = computerName
        case (0, 1):
            cell.textLabel?.text = tr("Appearance")
            let selected = UserDefaults.standard.string(forKey: "dsbot.theme") ?? "System"
            cell.detailTextLabel?.text = tr(selected)
        case (0, 2):
            cell.textLabel?.text = tr("In-app banners")
            cell.detailTextLabel?.text = nil
            cell.accessoryView = nil
            let toggle = UISwitch()
            toggle.isOn = UserDefaults.standard.string(forKey: "dsbot.banners") != "off"
            toggle.addTarget(self, action: #selector(changeBanners(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case (0, 3):
            cell.textLabel?.text = tr("Language")
            let selected = languages.first { $0.0 == NativeLanguage.mode }?.1 ?? "Follow system"
            cell.detailTextLabel?.text = tr(selected)
        case (1, 0):
            cell.textLabel?.text = tr("Model providers")
            cell.detailTextLabel?.text = nil
        case (1, 1):
            cell.textLabel?.text = tr("Connectors")
            cell.detailTextLabel?.text = nil
        case (1, 2):
            cell.textLabel?.text = tr("Capabilities")
            cell.detailTextLabel?.text = nil
        case (1, 3):
            cell.textLabel?.text = tr("Usage")
            cell.detailTextLabel?.text = nil
        case (1, 4):
            cell.textLabel?.text = tr("Secrets")
            cell.detailTextLabel?.text = nil
        case (1, 5):
            cell.textLabel?.text = tr("Location")
            cell.detailTextLabel?.text = nil
        case (1, 6):
            cell.textLabel?.text = tr("Updates & diagnostics")
            cell.detailTextLabel?.text = nil
        default:
            cell.textLabel?.text = tr("About DS Bot")
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
            let sheet = UIAlertController(title: tr("Appearance"), message: nil, preferredStyle: .actionSheet)
            for theme in themes {
                sheet.addAction(UIAlertAction(title: tr(theme), style: .default) { [weak self] _ in
                    UserDefaults.standard.set(theme, forKey: "dsbot.theme")
                    self?.view.window?.overrideUserInterfaceStyle = Self.style(for: theme)
                    self?.tableView.reloadData()
                })
            }
            sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(sheet, animated: true)
        case (0, 2):
            if let toggle = tableView.cellForRow(at: indexPath)?.accessoryView as? UISwitch {
                toggle.setOn(!toggle.isOn, animated: true)
                changeBanners(toggle)
            }
        case (0, 3):
            let sheet = UIAlertController(title: tr("Language"), message: nil, preferredStyle: .actionSheet)
            for (mode, name) in languages {
                sheet.addAction(UIAlertAction(title: tr(name), style: .default) { [weak self] _ in
                    NativeLanguage.set(mode)
                    self?.title = self?.tr("Settings")
                    self?.tableView.reloadData()
                })
            }
            sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(sheet, animated: true)
        case (1, 0):
            navigationController?.pushViewController(ProviderSettingsViewController(session: session), animated: true)
        case (1, 1):
            navigationController?.pushViewController(ConnectorSettingsViewController(session: session), animated: true)
        case (1, 2):
            navigationController?.pushViewController(CapabilitiesViewController(session: session), animated: true)
        case (1, 3):
            let action = onUsage
            dismiss(animated: true) { action?() }
        case (1, 4):
            navigationController?.pushViewController(SecretsSettingsViewController(session: session), animated: true)
        case (1, 5):
            navigationController?.pushViewController(LocationSettingsViewController(session: session), animated: true)
        case (1, 6):
            navigationController?.pushViewController(UpdatesSettingsViewController(session: session), animated: true)
        default:
            navigationController?.pushViewController(
                AboutViewController(computerName: computerName, session: session), animated: true
            )
        }
    }

    @objc private func changeBanners(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn ? "on" : "off", forKey: "dsbot.banners")
    }

    static func style(for theme: String) -> UIUserInterfaceStyle {
        switch theme {
        case "Light": return .light
        case "Dark": return .dark
        default: return .unspecified
        }
    }
}
