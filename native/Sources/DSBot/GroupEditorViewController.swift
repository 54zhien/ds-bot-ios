import UIKit

final class GroupEditorViewController: UIViewController {
    var onSaved: ((ChatTarget?) -> Void)?
    private let room: JSONValue?
    private let bots: [JSONValue]
    private let session: LinkSession
    private var members: [String]
    private var admin: String?
    private var busy = false
    private let nameField = UITextField()
    private let noticeField = UITextView()
    private let modeControl = UISegmentedControl(items: ["Admin leads", "Everyone"])
    private let memberStack = UIStackView()

    init(room: JSONValue?, state: JSONValue, session: LinkSession) {
        self.room = room
        self.session = session
        if case .array(let values)? = state["bots"] { bots = values } else { bots = [] }
        members = room?["members"]?.stringArrayValue ?? []
        admin = room?["admin"]?.stringValue
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = room == nil ? "Create group chat" : "Group settings"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: room == nil ? "Create" : "Save", style: .done, target: self, action: #selector(save)
        )
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        let form = UIStackView()
        form.translatesAutoresizingMaskIntoConstraints = false
        form.axis = .vertical
        form.spacing = 14
        form.isLayoutMarginsRelativeArrangement = true
        form.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 28, trailing: 18)
        scroll.addSubview(form)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            form.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            form.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            form.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            form.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let intro = UILabel()
        intro.text = "Pick at least two Bots. The admin leads the group."
        intro.textColor = .secondaryLabel
        intro.font = .preferredFont(forTextStyle: .subheadline)
        intro.numberOfLines = 0
        form.addArrangedSubview(intro)
        addLabel("Name", to: form)
        nameField.borderStyle = .roundedRect
        nameField.placeholder = "Name after members"
        nameField.text = room?["named"] == .bool(true) ? room?["name"]?.stringValue : ""
        nameField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        form.addArrangedSubview(nameField)
        addLabel("Notice", to: form)
        noticeField.text = room?["notice"]?.stringValue ?? ""
        noticeField.font = .preferredFont(forTextStyle: .body)
        noticeField.layer.cornerRadius = 12
        noticeField.layer.borderWidth = 1
        noticeField.layer.borderColor = UIColor.separator.cgColor
        noticeField.heightAnchor.constraint(equalToConstant: 90).isActive = true
        form.addArrangedSubview(noticeField)
        addLabel("Who answers", to: form)
        modeControl.selectedSegmentIndex = room?["mode"]?.stringValue == "everyone"
            || (room != nil && room?["admin"]?.stringValue == nil) ? 1 : 0
        form.addArrangedSubview(modeControl)
        addLabel("Members", to: form)
        memberStack.axis = .vertical
        memberStack.spacing = 8
        form.addArrangedSubview(memberStack)
        for (index, bot) in bots.enumerated() {
            guard bot["id"]?.stringValue != nil else { continue }
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8
            let member = UIButton(type: .system)
            member.tag = index
            member.contentHorizontalAlignment = .leading
            member.addTarget(self, action: #selector(toggleMember(_:)), for: .touchUpInside)
            row.addArrangedSubview(member)
            let lead = UIButton(type: .system)
            lead.tag = index
            lead.setTitle("Admin", for: .normal)
            lead.addTarget(self, action: #selector(makeAdmin(_:)), for: .touchUpInside)
            row.addArrangedSubview(lead)
            member.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            memberStack.addArrangedSubview(row)
        }
        updateMembers()
        if room != nil {
            let remove = UIButton(type: .system)
            remove.setTitle("Delete group", for: .normal)
            remove.setTitleColor(.systemRed, for: .normal)
            remove.addTarget(self, action: #selector(confirmDelete), for: .touchUpInside)
            remove.heightAnchor.constraint(equalToConstant: 50).isActive = true
            form.addArrangedSubview(remove)
        }
    }

    private func addLabel(_ text: String, to stack: UIStackView) {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        stack.addArrangedSubview(label)
    }

    private func updateMembers() {
        for row in memberStack.arrangedSubviews.compactMap({ $0 as? UIStackView }) {
            guard let member = row.arrangedSubviews.first as? UIButton,
                  let lead = row.arrangedSubviews.last as? UIButton,
                  bots.indices.contains(member.tag),
                  let id = bots[member.tag]["id"]?.stringValue else { continue }
            let checked = members.contains(id)
            member.setTitle("\(checked ? "✓" : "○")  \(bots[member.tag]["name"]?.stringValue ?? id)", for: .normal)
            lead.isHidden = !checked
            lead.setTitle(admin == id ? "Admin" : "Make admin", for: .normal)
            lead.setTitleColor(admin == id ? .systemBlue : .secondaryLabel, for: .normal)
        }
        navigationItem.rightBarButtonItem?.isEnabled = members.count >= 2 && !busy
    }

    @objc private func toggleMember(_ sender: UIButton) {
        guard bots.indices.contains(sender.tag), let id = bots[sender.tag]["id"]?.stringValue else { return }
        if let index = members.firstIndex(of: id) {
            members.remove(at: index)
            if admin == id { admin = members.first }
        } else {
            members.append(id)
            if admin == nil { admin = id }
        }
        updateMembers()
    }

    @objc private func makeAdmin(_ sender: UIButton) {
        guard bots.indices.contains(sender.tag), let id = bots[sender.tag]["id"]?.stringValue,
              members.contains(id) else { return }
        admin = admin == id ? nil : id
        updateMembers()
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func save() {
        guard !busy, members.count >= 2 else { return }
        busy = true
        updateMembers()
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notice = noticeField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = modeControl.selectedSegmentIndex == 1 ? "everyone" : "admin"
        Task {
            do {
                let target: ChatTarget
                if let room, let id = room["id"]?.stringValue {
                    var patch: [String: JSONValue] = ["id": .string(id)]
                    if name != (room["named"] == .bool(true) ? room["name"]?.stringValue ?? "" : "") {
                        patch["name"] = .string(name)
                    }
                    if notice != (room["notice"]?.stringValue ?? "") { patch["notice"] = .string(notice) }
                    if mode != (room["mode"]?.stringValue ?? "admin") { patch["mode"] = .string(mode) }
                    if members != (room["members"]?.stringArrayValue ?? []) {
                        patch["members"] = .array(members.map(JSONValue.string))
                    }
                    if admin != room["admin"]?.stringValue {
                        patch["admin"] = admin.map(JSONValue.string) ?? .null
                    }
                    let response: JSONValue
                    if patch.count > 1 {
                        response = try await BotAPI.call("update-room", payload: .object(patch), on: session)
                    } else { response = .null }
                    target = ChatTarget(kind: .room, id: id,
                                        name: response["room"]?["name"]?.stringValue ?? room["name"]?.stringValue ?? "Group")
                } else {
                    var payload: [String: JSONValue] = [
                        "members": .array(members.map(JSONValue.string)), "greet": .bool(true),
                    ]
                    if let admin { payload["admin"] = .string(admin) }
                    if !name.isEmpty { payload["name"] = .string(name) }
                    let created = try await BotAPI.call("create-room", payload: .object(payload), on: session)
                    guard let id = created["id"]?.stringValue else { throw NSError(
                        domain: "DSBot", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "The new group has no ID."]
                    ) }
                    if !notice.isEmpty || mode != "admin" {
                        var patch: [String: JSONValue] = ["id": .string(id)]
                        if !notice.isEmpty { patch["notice"] = .string(notice) }
                        if mode != "admin" { patch["mode"] = .string(mode) }
                        _ = try await BotAPI.call("update-room", payload: .object(patch), on: session)
                    }
                    target = ChatTarget(kind: .room, id: id, name: created["name"]?.stringValue ?? name)
                }
                let complete = onSaved
                dismiss(animated: true) { complete?(target) }
            } catch { showError(error.localizedDescription) }
            busy = false
            updateMembers()
        }
    }

    @objc private func confirmDelete() {
        guard let room, let id = room["id"]?.stringValue else { return }
        let alert = UIAlertController(title: "Delete this group?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteRoom(id)
        })
        present(alert, animated: true)
    }

    private func deleteRoom(_ id: String) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                _ = try await BotAPI.call("delete-room", payload: .object(["id": .string(id)]), on: session)
                let complete = onSaved
                dismiss(animated: true) { complete?(nil) }
            } catch { showError(error.localizedDescription) }
            busy = false
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Could not save group", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
