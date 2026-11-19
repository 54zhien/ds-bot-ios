import UIKit

/// The row the chat still draws while the capsule is being wired. The words and the
/// state walk live in ThinkingCapsulePresentation now, so both read one source.
struct WorkStatusPresentation {
    let text: String

    init?(target: ChatTarget, state: JSONValue) {
        guard let thinking = ThinkingCapsulePresentation(target: target, state: state) else { return nil }
        text = thinking.text
    }
}

final class WorkStatusView: UIStackView {
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .horizontal
        alignment = .center
        spacing = 8
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        addArrangedSubview(indicator)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        addArrangedSubview(label)
        isHidden = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ presentation: WorkStatusPresentation?) {
        label.text = presentation?.text
        isHidden = presentation == nil
        if presentation == nil { indicator.stopAnimating() } else { indicator.startAnimating() }
    }
}
