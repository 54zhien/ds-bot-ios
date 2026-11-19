import UIKit

/// The native EmptyChat from Chat.tsx: who the chat is with, large, where the
/// messages will be. With an action it also carries the one button the state needs,
/// which Chat.tsx leaves to the surrounding screens.
final class EmptyChatView: UIView {
    /// The 64pt mark: a Bot's character, a room's cluster, and the letter the block
    /// used before it had one — kept for a caller that has nothing to draw from.
    private let avatarBox = UIView()
    private let avatar = MarkView(frame: .zero)
    private let avatarLetter = UILabel()
    private let nameLabel = UILabel()
    private let roleLabel = UILabel()
    private let captionLabel = UILabel()
    private let action = UIButton(type: .system)
    private var onAction: (() -> Void)?

    /// The letter is the fallback for a caller with no look; the test that pins
    /// "a look replaces the letter" reads it here rather than through the tree.
    var isShowingLetter: Bool { !avatarLetter.isHidden }

    /// Chat.tsx styles.empty: absolute, inset 24 each side, top 28%.
    static let sideInset: CGFloat = 24
    static let topPercent: CGFloat = 0.28

    override init(frame: CGRect) {
        super.init(frame: frame)
        let palette = ThemeStore.palette(trait: traitCollection)

        let column = UIStackView(arrangedSubviews: [avatarBox, nameLabel, roleLabel, captionLabel, action])
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

        // 64 is EmptyChat's own mark size in Chat.tsx.
        avatarBox.translatesAutoresizingMaskIntoConstraints = false
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatarLetter.translatesAutoresizingMaskIntoConstraints = false
        avatarLetter.font = .systemFont(ofSize: TypeScale.largeTitle.size, weight: .semibold)
        avatarLetter.textAlignment = .center
        avatarLetter.textColor = .white
        avatarLetter.layer.cornerRadius = 32
        avatarLetter.clipsToBounds = true
        avatarLetter.layer.borderWidth = 1
        [avatarLetter, avatar].forEach { avatarBox.addSubview($0) }
        NSLayoutConstraint.activate([
            avatarBox.widthAnchor.constraint(equalToConstant: 64),
            avatarBox.heightAnchor.constraint(equalToConstant: 64),
        ] + [avatarLetter, avatar].flatMap { view in
            [view.leadingAnchor.constraint(equalTo: avatarBox.leadingAnchor),
             view.trailingAnchor.constraint(equalTo: avatarBox.trailingAnchor),
             view.topAnchor.constraint(equalTo: avatarBox.topAnchor),
             view.bottomAnchor.constraint(equalTo: avatarBox.bottomAnchor)]
        })

        nameLabel.font = .systemFont(ofSize: TypeScale.settingsRow.size, weight: .semibold)
        nameLabel.textColor = palette.ink
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.topAnchor.constraint(equalTo: avatarBox.bottomAnchor, constant: 12).isActive = true

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

    /// Chat.tsx:449: a Bot shows its mark, a room its members' cluster. A caller that
    /// has neither passes no look and gets the letter this block drew before marks
    /// existed, so an unfinished call site never turns every chat into a gumdrop.
    func configure(name: String, role: String, color: String?, caption: String,
                   look: CharacterMarks.Look? = nil,
                   members: [CharacterMarks.Look] = [],
                   actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        let palette = ThemeStore.palette(trait: traitCollection)
        avatar.plate = palette.main
        avatar.configure(look: look, members: members)
        avatarLetter.isHidden = look != nil || !members.isEmpty || name.isEmpty
        avatarLetter.backgroundColor = Inks.bot(color, dark: traitCollection.userInterfaceStyle == .dark)
        avatarLetter.layer.borderColor = palette.main.cgColor
        avatarLetter.text = name.isEmpty ? "" : String(name.prefix(1)).uppercased()
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
        // The mark is decoration: the name it belongs to is the next element.
        accessibilityElements = [nameLabel, roleLabel, captionLabel, action].filter { !$0.isHidden }
    }
}
