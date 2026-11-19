import PhotosUI
import UIKit

final class BotEditorViewController: UIViewController {
    var onSaved: ((ChatTarget?) -> Void)?
    private let bot: JSONValue?
    private let state: JSONValue
    private let session: LinkSession
    private let scroll = UIScrollView()
    private let form = UIStackView()
    private let nameField = UITextField()
    private let roleField = UITextField()
    private let instructionsField = UITextView()
    private let privateSwitch = UISwitch()
    private let mainSwitch = UISwitch()
    private let colorButton = UIButton(type: .system)
    private let shapeButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let effortButton = UIButton(type: .system)
    private var color: String
    private var shape: String
    private var model: String?
    private var effort: String?
    private var efforts: [(id: String, name: String)] = []
    private var busy = false
    private let uploadPhotoButton = UIButton(type: .system)
    private let removePhotoButton = UIButton(type: .system)
    // Avatar keys already written by the photo rows this session. The form's
    // Save is deferred, so its shape patch must build on these — not on the
    // bot snapshot taken at init, which predates any upload.
    private var pendingAvatar: [String: JSONValue]?
    private var clashLabel: UILabel?

    private static let colors = ["black", "brown", "red", "orange", "yellow", "green",
                                 "cyan", "blue", "violet", "magenta", "gray", "aurora"]
    private static let shapes = ["acorn", "berry", "bunny", "gem", "gumdrop", "kitty",
                                 "moon", "peanut", "star", "wave"]

    init(bot: JSONValue?, state: JSONValue, session: LinkSession) {
        self.bot = bot
        self.state = state
        self.session = session
        color = bot?["color"]?.stringValue ?? "blue"
        shape = bot?["avatar"]?["shape"]?.stringValue ?? "star"
        model = bot?["model"]?.stringValue ?? state["defaultModel"]?.stringValue
        effort = bot?["effort"]?.stringValue
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text(bot == nil ? "Create new Bot" : "Bot settings")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NativeLanguage.text(bot == nil ? "Create" : "Save"), style: .done, target: self, action: #selector(save)
        )
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        form.translatesAutoresizingMaskIntoConstraints = false
        form.axis = .vertical
        form.spacing = 18
        form.isLayoutMarginsRelativeArrangement = true
        form.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 18, bottom: 30, trailing: 18)
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

        addField(NativeLanguage.text("Name"), field: nameField, text: bot?["name"]?.stringValue ?? "",
                 placeholder: NativeLanguage.text("New Bot"))
        if bot == nil {
            let label = UILabel()
            label.text = NativeLanguage.text("Another Bot has this name.")
            label.font = .preferredFont(forTextStyle: .caption1)
            label.textColor = ThemeStore.palette(trait: traitCollection).danger
            label.isHidden = true
            form.addArrangedSubview(label)
            clashLabel = label
            nameField.addTarget(self, action: #selector(nameEdited), for: .editingChanged)
            updateClashState()
        }
        addField(NativeLanguage.text("Label"), field: roleField, text: bot?["role"]?.stringValue ?? "",
                 placeholder: NativeLanguage.text("Research, admin…"))
        let instructionsLabel = UILabel()
        instructionsLabel.text = NativeLanguage.text("What this Bot does")
        instructionsLabel.font = .preferredFont(forTextStyle: .subheadline)
        form.addArrangedSubview(instructionsLabel)
        instructionsField.text = bot?["instructions"]?.stringValue ?? ""
        instructionsField.font = .preferredFont(forTextStyle: .body)
        instructionsField.layer.cornerRadius = 12
        instructionsField.layer.borderWidth = 1
        instructionsField.layer.borderColor = UIColor.separator.cgColor
        instructionsField.heightAnchor.constraint(equalToConstant: 110).isActive = true
        form.addArrangedSubview(instructionsField)
        addPicker(colorButton, label: NativeLanguage.text("Character color"), value: color, action: #selector(pickColor))
        addPicker(shapeButton, label: NativeLanguage.text("Character shape"), value: shape, action: #selector(pickShape))
        if bot != nil {
            uploadPhotoButton.setTitle(NativeLanguage.text("Upload photo"), for: .normal)
            uploadPhotoButton.addTarget(self, action: #selector(pickPhoto), for: .touchUpInside)
            uploadPhotoButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            form.addArrangedSubview(uploadPhotoButton)
            removePhotoButton.setTitle(NativeLanguage.text("Remove photo"), for: .normal)
            removePhotoButton.addTarget(self, action: #selector(removePhoto), for: .touchUpInside)
            removePhotoButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            removePhotoButton.isHidden = bot?["avatar"]?["image"] == nil
            form.addArrangedSubview(removePhotoButton)
        }
        if case .array(let models)? = state["models"], !models.isEmpty {
            addPicker(modelButton, label: NativeLanguage.text("Model"), value: model ?? NativeLanguage.text("Default"), action: #selector(pickModel))
            addPicker(effortButton, label: NativeLanguage.text("Thinking level"), value: effort ?? NativeLanguage.text("Default"), action: #selector(pickEffort))
            effortButton.isHidden = true
            loadEfforts()
        }
        if bot != nil {
            privateSwitch.isOn = bot?["private"] == .bool(true)
            addToggle(NativeLanguage.text("Private"), control: privateSwitch)
            let id = bot?["id"]?.stringValue ?? ""
            let mains = state["mainBotIds"]?.stringArrayValue ?? []
            mainSwitch.isOn = mains.contains(id) || state["mainBotId"]?.stringValue == id
            addToggle(NativeLanguage.text("Main Bot"), control: mainSwitch)
            let more = UIButton(type: .system)
            more.setTitle(NativeLanguage.text("Duplicate or delete Bot"), for: .normal)
            more.addTarget(self, action: #selector(moreActions), for: .touchUpInside)
            more.heightAnchor.constraint(equalToConstant: 48).isActive = true
            form.addArrangedSubview(more)
        }
    }

    private func addField(_ title: String, field: UITextField, text: String, placeholder: String) {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        form.addArrangedSubview(label)
        field.text = text
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
        form.addArrangedSubview(field)
    }

    private func addPicker(_ button: UIButton, label: String, value: String, action: Selector) {
        button.contentHorizontalAlignment = .leading
        button.setTitle("\(label) · \(value)", for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        form.addArrangedSubview(button)
    }

    private func addToggle(_ title: String, control: UISwitch) {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        form.addArrangedSubview(row)
    }

    private func choose(_ title: String, values: [String], from button: UIButton,
                        update: @escaping (String) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for value in values {
            sheet.addAction(UIAlertAction(title: value, style: .default) { _ in update(value) })
        }
        sheet.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = button
        present(sheet, animated: true)
    }

    @objc private func pickColor() {
        choose(NativeLanguage.text("Character color"), values: Self.colors, from: colorButton) { [weak self] value in
            self?.color = value
            self?.colorButton.setTitle(NativeLanguage.text("Character color") + " · " + value, for: .normal)
        }
    }

    @objc private func pickShape() {
        choose(NativeLanguage.text("Character shape"), values: Self.shapes, from: shapeButton) { [weak self] value in
            self?.shape = value
            self?.shapeButton.setTitle(NativeLanguage.text("Character shape") + " · " + value, for: .normal)
        }
    }

    @objc private func pickModel() {
        guard case .array(let entries)? = state["models"] else { return }
        let refs = entries.compactMap { $0["ref"]?.stringValue }
        choose(NativeLanguage.text("Model"), values: refs, from: modelButton) { [weak self] value in
            self?.model = value
            self?.modelButton.setTitle(NativeLanguage.text("Model") + " · " + value, for: .normal)
            self?.effort = nil
            self?.loadEfforts()
        }
    }

    private func loadEfforts() {
        guard let model else { effortButton.isHidden = true; return }
        let served: JSONValue?
        if case .array(let models)? = state["models"] {
            served = models.first { $0["ref"]?.stringValue == model }?["reasoning"]
        } else { served = nil }
        if let served { showEfforts(served); return }
        Task {
            guard let response = try? await BotAPI.call("efforts", payload: .object(["ref": .string(model)]), on: session),
                  self.model == model else { return }
            showEfforts(response)
        }
    }

    private func showEfforts(_ reasoning: JSONValue) {
        if case .array(let values)? = reasoning["efforts"] {
            efforts = values.compactMap { item in
                guard let id = item["id"]?.stringValue else { return nil }
                return (id, item["name"]?.stringValue ?? id)
            }
        } else { efforts = [] }
        effortButton.isHidden = efforts.isEmpty
        let name = efforts.first { $0.id == effort }?.name ?? "Default"
        effortButton.setTitle(NativeLanguage.text("Thinking level") + " · " + name, for: .normal)
    }

    @objc private func pickEffort() {
        let sheet = UIAlertController(title: NativeLanguage.text("Thinking level"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NativeLanguage.text("Default"), style: .default) { [weak self] _ in
            self?.effort = nil
            self?.effortButton.setTitle(NativeLanguage.text("Thinking level") + " · " + NativeLanguage.text("Default"), for: .normal)
        })
        for item in efforts {
            sheet.addAction(UIAlertAction(title: item.name, style: .default) { [weak self] _ in
                self?.effort = item.id
                self?.effortButton.setTitle(NativeLanguage.text("Thinking level") + " · " + item.name, for: .normal)
            })
        }
        sheet.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = effortButton
        present(sheet, animated: true)
    }

    @objc private func nameEdited() { updateClashState() }

    private var finalBotName: String {
        let raw = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? NativeLanguage.text("New Bot") : raw
    }

    private var nameClash: Bool {
        guard bot == nil else { return false }
        guard case .array(let bots)? = state["bots"] else { return false }
        return bots.contains { $0["name"]?.stringValue?.lowercased() == finalBotName.lowercased() }
    }

    private func updateClashState() {
        clashLabel?.isHidden = !nameClash
        refreshSaveButton()
    }

    private func refreshSaveButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !busy && !nameClash
    }

    @objc private func pickPhoto() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func removePhoto() {
        guard !busy else { return }
        // RN drops every avatar key but the shape when the photo goes.
        let avatar: [String: JSONValue] = ["shape": .string(shape)]
        pendingAvatar = avatar
        removePhotoButton.isHidden = true
        sendAvatar(avatar)
    }

    private func applyAvatarPhoto(_ image: UIImage) {
        guard !busy, let data = Self.avatarPhotoData(from: image) else { return }
        var avatar = Self.avatarBase(pending: pendingAvatar, saved: bot?["avatar"])
        avatar["image"] = .string("data:image/jpeg;base64," + data.base64EncodedString())
        pendingAvatar = avatar
        removePhotoButton.isHidden = false
        sendAvatar(avatar)
    }

    private func sendAvatar(_ avatar: [String: JSONValue]) {
        guard let bot, let id = bot["id"]?.stringValue else { return }
        busy = true
        refreshSaveButton()
        Task {
            do {
                _ = try await BotAPI.call("update-bot", payload: .object(["id": .string(id), "avatar": .object(avatar)]), on: session)
            } catch { showError(error.localizedDescription) }
            busy = false
            refreshSaveButton()
        }
    }

    // pending wins over the init-time snapshot: once a photo row has written,
    // every later avatar patch grows from that dict or the photo is lost.
    static func avatarBase(pending: [String: JSONValue]?, saved: JSONValue?) -> [String: JSONValue] {
        if let pending { return pending }
        if case .object(let value)? = saved { return value }
        return [:]
    }

    // RN crops in its picker's square edit sheet. The bundle declares no
    // photo-library permission, so PHPicker has no edit step — degrade to a
    // centered crop, capped at 512 with JPEG 0.8. The stored form matches
    // RN's data URL; only the crop is fixed instead of chosen.
    private static func avatarPhotoData(from image: UIImage) -> Data? {
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let side = min(pixelWidth, pixelHeight, 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            let fill = max(CGFloat(side) / CGFloat(pixelWidth), CGFloat(side) / CGFloat(pixelHeight))
            image.draw(in: CGRect(x: (CGFloat(side) - CGFloat(pixelWidth) * fill) / 2,
                                  y: (CGFloat(side) - CGFloat(pixelHeight) * fill) / 2,
                                  width: CGFloat(pixelWidth) * fill, height: CGFloat(pixelHeight) * fill))
        }
        return square.jpegData(compressionQuality: 0.8)
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func save() {
        guard !busy, !nameClash else { return }
        let finalName = finalBotName
        let role = roleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let instructions = instructionsField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            do {
                let target: ChatTarget?
                if let bot, let id = bot["id"]?.stringValue {
                    var patch: [String: JSONValue] = ["id": .string(id)]
                    if finalName != bot["name"]?.stringValue { patch["name"] = .string(finalName) }
                    if role != (bot["role"]?.stringValue ?? "") { patch["role"] = .string(role) }
                    if instructions != (bot["instructions"]?.stringValue ?? "") {
                        patch["instructions"] = .string(instructions)
                    }
                    if color != bot["color"]?.stringValue { patch["color"] = .string(color) }
                    if shape != bot["avatar"]?["shape"]?.stringValue {
                        var avatar = Self.avatarBase(pending: pendingAvatar, saved: bot["avatar"])
                        avatar["shape"] = .string(shape)
                        patch["avatar"] = .object(avatar)
                    }
                    if model != bot["model"]?.stringValue, let model { patch["model"] = .string(model) }
                    if effort != bot["effort"]?.stringValue { patch["effort"] = effort.map(JSONValue.string) ?? .null }
                    if privateSwitch.isOn != (bot["private"] == .bool(true)) {
                        patch["private"] = .bool(privateSwitch.isOn)
                    }
                    if patch.count > 1 { _ = try await BotAPI.call("update-bot", payload: .object(patch), on: session) }
                    let mains = state["mainBotIds"]?.stringArrayValue ?? []
                    let wasMain = mains.contains(id) || state["mainBotId"]?.stringValue == id
                    if !privateSwitch.isOn && mainSwitch.isOn != wasMain {
                        _ = try await BotAPI.call("set-main", payload: .object([
                            "id": .string(id), "main": .bool(mainSwitch.isOn),
                        ]), on: session)
                    }
                    target = ChatTarget(kind: .bot, id: id, name: finalName)
                } else {
                    var payload: [String: JSONValue] = [
                        "name": .string(finalName), "role": .string(role),
                        "instructions": .string(instructions), "color": .string(color),
                        "avatar": .object(["shape": .string(shape)]),
                    ]
                    if let model { payload["model"] = .string(model) }
                    if let effort { payload["effort"] = .string(effort) }
                    let created = try await BotAPI.call("create-bot", payload: .object(payload), on: session)
                    guard let id = created["id"]?.stringValue else { throw NSError(
                        domain: "DSBot", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "The new Bot has no ID."]
                    ) }
                    target = ChatTarget(kind: .bot, id: id, name: finalName)
                }
                let complete = onSaved
                dismiss(animated: true) { complete?(target) }
            } catch { showError(error.localizedDescription) }
            busy = false
            refreshSaveButton()
        }
    }

    @objc private func moreActions() {
        guard let bot, let id = bot["id"]?.stringValue else { return }
        let sheet = UIAlertController(title: bot["name"]?.stringValue, message: nil, preferredStyle: .actionSheet)
        if bot["private"] != .bool(true) {
            sheet.addAction(UIAlertAction(title: NativeLanguage.text("Duplicate"), style: .default) { [weak self] _ in
                self?.performBotAction("duplicate-bot", id: id)
            })
        }
        sheet.addAction(UIAlertAction(title: NativeLanguage.text("Delete Bot"), style: .destructive) { [weak self] _ in
            self?.confirmDelete(id: id)
        })
        sheet.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = form
        present(sheet, animated: true)
    }

    private func confirmDelete(id: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Delete this Bot?"),
                                      message: NativeLanguage.text("Its chat and settings will be removed."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NativeLanguage.text("Delete"), style: .destructive) { [weak self] _ in
            self?.performBotAction("delete-bot", id: id)
        })
        present(alert, animated: true)
    }

    private func performBotAction(_ endpoint: String, id: String) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let value = try await BotAPI.call(endpoint, payload: .object(["id": .string(id)]), on: session)
                let target: ChatTarget?
                if endpoint == "duplicate-bot", let newID = value["id"]?.stringValue {
                    target = ChatTarget(kind: .bot, id: newID, name: value["name"]?.stringValue ?? NativeLanguage.text("Bot"))
                } else { target = nil }
                let complete = onSaved
                dismiss(animated: true) { complete?(target) }
            } catch { showError(error.localizedDescription) }
            busy = false
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Could not save Bot"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
        present(alert, animated: true)
    }
}

extension BotEditorViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor [weak self] in self?.applyAvatarPhoto(image) }
        }
    }
}
