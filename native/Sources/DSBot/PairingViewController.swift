import UIKit

final class PairingViewController: UIViewController {
    var onPair: ((PairingOffer) -> Void)?
    private let field = UITextField()
    private let errorLabel = UILabel()
    private let progressLabel = UILabel()
    private var pendingLink: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Pair with computer")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NativeLanguage.text("Connect"), style: .done, target: self, action: #selector(submit)
        )
        let instructions = UILabel()
        instructions.text = NativeLanguage.text("On your computer, open DS Bot → Settings → Phone, then copy the pairing link.")
        instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .body)
        instructions.textColor = .secondaryLabel
        field.placeholder = "dsbot://pair?…"
        field.accessibilityLabel = NativeLanguage.text("Pairing link")
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.textContentType = .URL
        // "Go" submits, the way the RN pairing row does (Pair.tsx:55).
        field.returnKeyType = .go
        field.delegate = self
        errorLabel.numberOfLines = 0
        errorLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorLabel.textColor = .systemRed
        progressLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressLabel.textColor = .secondaryLabel
        let scanButton = UIButton(type: .system)
        scanButton.setTitle(NativeLanguage.text("Scan QR code"), for: .normal)
        scanButton.addTarget(self, action: #selector(scanCode), for: .touchUpInside)
        scanButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [instructions, scanButton, field, errorLabel, progressLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        applyPendingLink()
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func scanCode() {
        let scanner = PairingScannerViewController()
        scanner.onCode = { [weak self] code in
            guard let self else { return }
            field.text = code
            submit()
        }
        present(UINavigationController(rootViewController: scanner), animated: true)
    }

    func showStatus(_ status: LinkSession.Status) {
        switch status {
        case .connecting:
            progressLabel.text = NativeLanguage.text("Connecting…")
        case .offline:
            progressLabel.text = NativeLanguage.text("Waiting for computer…")
        case .online:
            progressLabel.text = NativeLanguage.text("Connected")
        case .disconnected:
            progressLabel.text = NativeLanguage.text("Could not connect. Check the link and try again.")
            navigationItem.rightBarButtonItem?.isEnabled = true
        }
    }

    func showError(_ message: String) { errorLabel.text = message }

    /// A pairing link that arrived from outside the app (a deep link) fills
    /// the field and submits at once, the way the scanner does.
    func open(link: String) {
        guard isViewLoaded else {
            pendingLink = link
            return
        }
        field.text = link
        submit()
    }

    private func applyPendingLink() {
        guard let pendingLink else { return }
        field.text = pendingLink
        pendingLink = nil
        submit()
    }

    @objc private func submit() {
        do {
            let offer = try PairingLink.parse(field.text ?? "")
            errorLabel.text = nil
            navigationItem.rightBarButtonItem?.isEnabled = false
            onPair?(offer)
        } catch let error as PairingLinkError {
            errorLabel.text = error.explanation
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
}

extension PairingViewController: UITextFieldDelegate {
    // Keep the keyboard up when the link does not parse: the explanation is
    // right under the field, and the fix is usually one character.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return false
    }
}
