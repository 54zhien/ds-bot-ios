import UIKit

final class TextReaderViewController: UIViewController {
    private let content: String
    private let reader = UITextView()

    init(title: String, content: String) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        reader.translatesAutoresizingMaskIntoConstraints = false
        reader.isEditable = false
        reader.isSelectable = true
        reader.font = .preferredFont(forTextStyle: .body)
        reader.text = content
        view.addSubview(reader)
        NSLayoutConstraint.activate([
            reader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            reader.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            reader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            reader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
        ])
    }

    @objc private func close() { dismiss(animated: true) }
}
