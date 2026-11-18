import UIKit

/// The native EmptyChat from Chat.tsx: who the chat is with, large, where the
/// messages will be. With an action it also carries the one button the state needs,
/// which Chat.tsx leaves to the surrounding screens.
final class EmptyChatView: UIView {
    private let avatar = UILabel()
    private let nameLabel = UILabel()
    private let roleLabel = UILabel()
    private let captionLabel = UILabel()
    private let action = UIButton(type: .system)
    private var onAction: (() -> Void)?

    /// Chat.tsx styles.empty: absolute, inset 24 each side, top 28%.
    static let sideInset: CGFloat = 24
    static let topPercent: CGFloat = 0.28

    override init(frame: CGRect) {
        super.init(frame: frame)
        let palette = ThemeStore.palette(trait: traitCollection)

        let column = UIStackView(arrangedSubviews: [avatar, nameLabel, roleLabel, captionLabel, action])
        column.axis = .vertical
        column.alignment = .center
        column.translatesAutoresizingMaskIntoConstraints = false
        column.spacing = 0
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // 64 is EmptyChat's own avatar size in Chat.tsx, with the page colour as its ring.
        avatar.font = .systemFont(ofSize: TypeScale.largeTitle.size, weight: .semibold)
        avatar.textAlignment = .center
        avatar.textColor = .white
        avatar.layer.cornerRadius = 32
        avatar.clipsToBounds = true
        avatar.layer.borderWidth = 1
        avatar.widthAnchor.constraint(equalToConstant: 64).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 64).isActive = true

        nameLabel.font = .systemFont(ofSize: TypeScale.settingsRow.size, weight: .semibold)
        nameLabel.textColor = palette.ink
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 12).isActive = true

        roleLabel.font = TypeScale.small.font
        roleLabel.textColor = palette.ink3
        roleLabel.textAlignment = .center
        roleLabel.lineBreakMode = .byTruncatingTail
        roleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2).isActive = true

        captionLabel.font = TypeScale.caption.font
        captionLabel.textColor = palette.ink3
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        captionLabel.topAnchor.constraint(equalTo: roleLabel.bottomAnchor, constant: 10).isActive = true

        action.titleLabel?.font = .systemFont(ofSize: TypeScale.rowName.size, weight: .semibold)
        action.setTitleColor(palette.accentInk, for: .normal)
        action.backgroundColor = palette.accent
        action.layer.cornerRadius = Radius.input
        action.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        action.heightAnchor.constraint(equalToConstant: Glass.control).isActive = true
        action.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 12).isActive = true
        action.addTarget(self, action: #selector(run), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { onAction?() }

    func configure(name: String, role: String, color: String?, caption: String,
                   actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        let palette = ThemeStore.palette(trait: traitCollection)
        avatar.backgroundColor = Inks.bot(color, dark: traitCollection.userInterfaceStyle == .dark)
        avatar.layer.borderColor = palette.main.cgColor
        avatar.text = name.isEmpty ? "" : String(name.prefix(1)).uppercased()
        nameLabel.text = name
        roleLabel.text = role
        roleLabel.isHidden = role.isEmpty
        captionLabel.text = caption
        if let actionTitle {
            action.isHidden = false
            action.setTitle(actionTitle, for: .normal)
            self.onAction = onAction
        } else {
            action.isHidden = true
            self.onAction = nil
        }
        accessibilityElements = [avatar, nameLabel, roleLabel, captionLabel, action].filter { !$0.isHidden }
    }
}
