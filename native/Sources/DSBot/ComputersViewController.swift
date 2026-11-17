import UIKit

final class ComputersViewController: UITableViewController {
    var onSwitch: ((PairingOffer) -> Void)?
    var onAdd: (() -> Void)?
    var onForget: ((String) -> Void)?
    private let store: PairingStore
    private var computers: [PairingOffer] = []

    init(store: PairingStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Computers")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        reload()
    }

    private func reload() {
        computers = store.all()
        tableView.reloadData()
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? computers.count : 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? NativeLanguage.text("Computers") : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "computer")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "computer")
        if indexPath.section == 1 {
            cell.textLabel?.text = NativeLanguage.text("Add a computer")
            cell.detailTextLabel?.text = nil
            cell.textLabel?.textColor = view.tintColor
            cell.accessoryType = .none
        } else {
            let offer = computers[indexPath.row]
            cell.textLabel?.text = offer.name.isEmpty ? offer.serverURL.host : offer.name
            cell.detailTextLabel?.text = offer.serverURL.absoluteString
            cell.textLabel?.textColor = .label
            cell.accessoryType = store.load()?.hostDeviceId == offer.hostDeviceId ? .checkmark : .none
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            let add = onAdd
            dismiss(animated: true) { add?() }
        } else {
            let offer = computers[indexPath.row]
            store.activate(offer.hostDeviceId)
            onSwitch?(offer)
            reload()
            dismiss(animated: true)
        }
    }
    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 0 else { return nil }
        let offer = computers[indexPath.row]
        let forget = UIContextualAction(style: .destructive, title: NativeLanguage.text("Forget")) { [weak self] _, _, done in
            guard let self else { done(false); return }
            let alert = UIAlertController(
                title: NativeLanguage.text("Forget {name}?", ["name": offer.name.isEmpty ? NativeLanguage.text("this computer") : offer.name]),
                message: nil, preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel) { _ in done(false) })
            alert.addAction(UIAlertAction(title: NativeLanguage.text("Forget"), style: .destructive) { _ in
                self.store.remove(offer.hostDeviceId)
                self.onForget?(offer.hostDeviceId)
                self.reload()
                done(true)
            })
            self.present(alert, animated: true)
        }
        return UISwipeActionsConfiguration(actions: [forget])
    }
}
