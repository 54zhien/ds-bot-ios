import UIKit

/// A read-only browser frame and the explicit return decision used by RN BotBrowser.
final class BrowserHandoffViewController: UIViewController {
    var onChanged: (() -> Void)?

    private let botID: String
    private let hold: JSONValue
    private let session: LinkSession
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let frame = UIImageView()
    private let pageTitle = UILabel()
    private let address = UILabel()
    private let note = UILabel()
    private let errorLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)
    private let controlButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private var refreshTask: Task<Void, Never>?
    private var busy = false
    private var heldByUser: Bool

    init(botID: String, hold: JSONValue, session: LinkSession) {
        self.botID = botID
        self.hold = hold
        self.session = session
        heldByUser = hold["by"]?.stringValue == "user"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Browser handoff")
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                                target: self, action: #selector(close))
        }
        view.backgroundColor = .systemBackground
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 20, trailing: 16)
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        frame.contentMode = .scaleAspectFit
        frame.backgroundColor = .secondarySystemBackground
        frame.layer.cornerRadius = 18
        frame.clipsToBounds = true
        frame.heightAnchor.constraint(equalTo: frame.widthAnchor, multiplier: 1.45).isActive = true
        stack.addArrangedSubview(frame)
        for label in [pageTitle, address, note, errorLabel] {
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        pageTitle.font = .preferredFont(forTextStyle: .headline)
        address.font = .preferredFont(forTextStyle: .footnote)
        address.textColor = .secondaryLabel
        note.font = .preferredFont(forTextStyle: .subheadline)
        note.textColor = .secondaryLabel
        note.text = hold["note"]?.stringValue ?? hold["reason"]?.stringValue
        note.isHidden = note.text == nil
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        let actions = UIStackView(arrangedSubviews: [skipButton, doneButton, controlButton, stopButton])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 12
        stack.addArrangedSubview(actions)
        for (button, title) in [(skipButton, NativeLanguage.text("Skip")), (doneButton, NativeLanguage.text("Done")),
                                (controlButton, NativeLanguage.text("Take over")), (stopButton, NativeLanguage.text("Stop"))] {
            button.setTitle(title, for: .normal)
            button.layer.cornerRadius = 22
            button.backgroundColor = .tertiarySystemBackground
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        let isHandoff = hold["callId"]?.stringValue != nil
        skipButton.isHidden = !isHandoff
        doneButton.isHidden = !isHandoff
        controlButton.isHidden = isHandoff
        controlButton.setTitle(heldByUser ? NativeLanguage.text("Give back") : NativeLanguage.text("Take over"), for: .normal)
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skip), for: .touchUpInside)
        controlButton.addTarget(self, action: #selector(changeControl), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopBrowser), for: .touchUpInside)
    }

    @objc private func close() { dismiss(animated: true) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() async {
        do {
            let value = try await BotAPI.call("browser-frame", payload: .object([
                "botId": .string(botID),
            ]), on: session)
            guard !Task.isCancelled else { return }
            if let encoded = value["data"]?.stringValue,
               let bytes = Data(base64Encoded: encoded), let image = UIImage(data: bytes) {
                frame.image = image
            }
            pageTitle.text = value["title"]?.stringValue
            address.text = value["url"]?.stringValue
            errorLabel.isHidden = true
        } catch {
            guard !Task.isCancelled else { return }
            errorLabel.text = error.localizedDescription
            errorLabel.isHidden = false
        }
    }

    @objc private func done() { answer("done") }
    @objc private func skip() { answer("skip") }
    @objc private func changeControl() {
        run(heldByUser ? "browser-give-back" : "browser-takeover")
    }
    @objc private func stopBrowser() { run("browser-stop") }

    private func run(_ endpoint: String) {
        guard !busy else { return }
        busy = true
        controlButton.isEnabled = false
        stopButton.isEnabled = false
        Task {
            do {
                _ = try await BotAPI.call(endpoint, payload: .object(["botId": .string(botID)]), on: session)
                if endpoint == "browser-stop" {
                    if navigationController?.viewControllers.first === self {
                        navigationController?.dismiss(animated: true)
                    } else {
                        navigationController?.popViewController(animated: true)
                    }
                } else {
                    heldByUser = !heldByUser
                    controlButton.setTitle(heldByUser ? NativeLanguage.text("Give back") : NativeLanguage.text("Take over"), for: .normal)
                    await refresh()
                }
                onChanged?()
            } catch {
                errorLabel.text = error.localizedDescription
                errorLabel.isHidden = false
            }
            busy = false
            controlButton.isEnabled = true
            stopButton.isEnabled = true
        }
    }

    private func answer(_ outcome: String) {
        guard !busy, let callID = hold["callId"]?.stringValue else { return }
        busy = true
        doneButton.isEnabled = false
        skipButton.isEnabled = false
        Task {
            do {
                _ = try await BotAPI.call("browser-give-back", payload: .object([
                    "botId": .string(botID), "outcome": .string(outcome), "callId": .string(callID),
                ]), on: session)
                onChanged?()
                navigationController?.dismiss(animated: true)
            } catch {
                errorLabel.text = error.localizedDescription
                errorLabel.isHidden = false
                busy = false
                doneButton.isEnabled = true
                skipButton.isEnabled = true
            }
        }
    }
}
