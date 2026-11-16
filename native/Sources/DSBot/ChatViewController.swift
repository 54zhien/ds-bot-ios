import UIKit

/// N1 step 1: an empty chat. The list and the composer are placeholders with the
/// shape they will keep, so step 3 and step 4 replace behaviour, not layout.
final class ChatViewController: UIViewController {
    private let list = UITableView(frame: .zero, style: .plain)
    private let emptyState = UILabel()
    private let composer = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chat"
        view.backgroundColor = .systemBackground
        configureList()
        configureComposer()
    }

    private func configureList() {
        list.translatesAutoresizingMaskIntoConstraints = false
        list.dataSource = self
        list.separatorStyle = .none
        list.contentInset.bottom = 76
        list.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(list)

        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.text = "No messages yet"
        emptyState.textColor = .secondaryLabel
        emptyState.textAlignment = .center
        emptyState.font = .preferredFont(forTextStyle: .subheadline)
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// The resting capsule's height, so step 4 can grow it in place.
    private func configureComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.backgroundColor = .secondarySystemBackground
        composer.layer.cornerRadius = 31
        composer.layer.borderWidth = 1
        composer.layer.borderColor = UIColor.separator.cgColor
        view.addSubview(composer)

        let placeholder = UILabel()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = "Message"
        placeholder.textColor = .placeholderText
        placeholder.font = .preferredFont(forTextStyle: .body)
        composer.addSubview(placeholder)

        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            composer.heightAnchor.constraint(equalToConstant: 62),
            placeholder.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 20),
            placeholder.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
        ])
    }
}

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    }
}
