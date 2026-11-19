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
    private let modeControl = UISegmentedControl(items: [
        NativeLanguage.text("Admin leads"), NativeLanguage.text("Everyone"),
    ])
    private let memberStack = UIStackView()
    private var memberRows: [GroupMemberRow] = []

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
        title = NativeLanguage.text(room == nil ? "Create group chat" : "Group settings")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NativeLanguage.text(room == nil ? "Create" : "Save"), style: .done, target: self, action: #selector(save)
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
        intro.text = NativeLanguage.text("Pick at least two Bots. The admin leads the group.")
        intro.textColor = .secondaryLabel
        intro.font = .preferredFont(forTextStyle: .subheadline)
        intro.numberOfLines = 0
        form.addArrangedSubview(intro)
        addLabel(NativeLanguage.text("Name"), to: form)
        nameField.borderStyle = .roundedRect
        nameField.placeholder = NativeLanguage.text("Name after members")
        nameField.text = room?["named"] == .bool(true) ? room?["name"]?.stringValue : ""
        nameField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        form.addArrangedSubview(nameField)
        addLabel(NativeLanguage.text("Notice"), to: form)
        noticeField.text = room?["notice"]?.stringValue ?? ""
        noticeField.font = .preferredFont(forTextStyle: .body)
        noticeField.layer.cornerRadius = 12
        noticeField.layer.borderWidth = 1
        noticeField.layer.borderColor = UIColor.separator.cgColor
        noticeField.heightAnchor.constraint(equalToConstant: 90).isActive = true
        form.addArrangedSubview(noticeField)
        addLabel(NativeLanguage.text("Who answers"), to: form)
        modeControl.selectedSegmentIndex = room?["mode"]?.stringValue == "everyone"
            || (room != nil && room?["admin"]?.stringValue == nil) ? 1 : 0
        form.addArrangedSubview(modeControl)
        addLabel(NativeLanguage.text("Members"), to: form)
        memberStack.axis = .vertical
        memberStack.spacing = 8
        form.addArrangedSubview(memberStack)
        for (index, bot) in bots.enumerated() {
            guard bot["id"]?.stringValue != nil else { continue }
            let row = GroupMemberRow(frame: .zero)
            row.member.tag = index
            row.lead.tag = index
            row.member.addTarget(self, action: #selector(toggleMember(_:)), for: .touchUpInside)
            row.lead.addTarget(self, action: #selector(makeAdmin(_:)), for: .touchUpInside)
            row.mark.configure(look: CharacterMarks.Look(bot: bot))
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            memberStack.addArrangedSubview(row)
            memberRows.append(row)
        }
        updateMembers()
        if room != nil {
            let remove = UIButton(type: .system)
            remove.setTitle(NativeLanguage.text("Delete group"), for: .normal)
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
        for row in memberRows {
            let index = row.member.tag
            guard bots.indices.contains(index), let id = bots[index]["id"]?.stringValue else { continue }
            row.configure(name: bots[index]["name"]?.stringValue ?? id,
                          checked: members.contains(id), admin: admin == id)
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
                                        name: response["room"]?["name"]?.stringValue ?? room["name"]?.stringValue ?? NativeLanguage.text("Group"))
                } else {
                    var payload: [String: JSONValue] = [
                        "members": .array(members.map(JSONValue.string)), "greet": .bool(true),
                    ]
                    if let admin { payload["admin"] = .string(admin) }
                    if !name.isEmpty { payload["name"] = .string(name) }
                    let created = try await BotAPI.call("create-room", payload: .object(payload), on: session)
                    guard let id = created["id"]?.stringValue else { throw NSError(
                        domain: "DSBot", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: NativeLanguage.text("The new group has no ID.")]
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
        let alert = UIAlertController(title: NativeLanguage.text("Delete this group?"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Delete"), style: .destructive) { [weak self] _ in
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
        let alert = UIAlertController(title: NativeLanguage.text("Could not save group"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
        present(alert, animated: true)
    }
}

/// manage.tsx:628-647: a member line is the Bot's 32pt mark, its name, and the admin
/// control. The tick rides the name button, as this screen has no check box.
final class GroupMemberRow: UIView {
    static let markSize: CGFloat = 32
    let mark = MarkView(frame: .zero)
    let member = UIButton(type: .system)
    let lead = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        mark.translatesAutoresizingMaskIntoConstraints = false
        member.translatesAutoresizingMaskIntoConstraints = false
        lead.translatesAutoresizingMaskIntoConstraints = false
        member.contentHorizontalAlignment = .leading
        member.titleLabel?.lineBreakMode = .byTruncatingTail
        member.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lead.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [mark, member, lead])
        row.axis = .horizontal
        row.alignment = .center
        // manage.tsx:631 spaces the name 10 off the mark.
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: Self.markSize),
            mark.heightAnchor.constraint(equalToConstant: Self.markSize),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, checked: Bool, admin: Bool) {
        member.setTitle("\(checked ? "✓" : "○")  \(name)", for: .normal)
        lead.isHidden = !checked
        lead.setTitle(NativeLanguage.text(admin ? "Admin" : "Make admin"), for: .normal)
        lead.setTitleColor(admin ? .systemBlue : .secondaryLabel, for: .normal)
    }
}
