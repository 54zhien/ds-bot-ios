import UIKit

/// Photos the way items.tsx grids them: one shows large, the rest two to a row,
/// with fixed tile sizes rather than a share of the width. The height comes from
/// the count alone, so a late image decode never changes the row height under
/// the thumb.
final class PhotoGridView: UIView {
    private var tiles: [UIView] = []

    /// items.tsx gridOf: one photo is a 200 square, several are 120 two to a
    /// row, six points apart.
    private static let single: CGFloat = 200
    private static let tile: CGFloat = 120
    private static let gap: CGFloat = 6

    static func height(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let columns = min(2, count)
        let side = count == 1 ? single : tile
        let rows = CGFloat((count + columns - 1) / columns)
        return rows * side + gap * (rows - 1)
    }

    func setViews(_ views: [UIView]) {
        for tile in tiles { tile.removeFromSuperview() }
        tiles = views
        for tile in views { addSubview(tile) }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height(for: tiles.count))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !tiles.isEmpty else { return }
        let columns = min(2, tiles.count)
        let side = tiles.count == 1 ? Self.single : Self.tile
        for (index, tile) in tiles.enumerated() {
            let column = index % columns
            let row = index / columns
            tile.frame = CGRect(x: CGFloat(column) * (side + Self.gap),
                                y: CGFloat(row) * (side + Self.gap),
                                width: side, height: side)
        }
    }
}


final class ChatMessageCell: UITableViewCell {
    var onOpenFile: ((ChatFile) -> Void)?
    var onOpenPhoto: ((String) -> Void)?
    private let bubble = UIView()
    private let authorLabel = UILabel()
    private let messageLabel = MarkdownLinkLabel()
    private let markdownView = ChatMarkdownView()
    private let photos = PhotoGridView()
    private let fileStack = UIStackView()
    // Two views, two rules: the clock obeys the room, the send state never does.
    private let viaLabel = ViaTagLabel()
    private let stampRow = UIStackView()
    private let timeLabel = UILabel()
    private let stateLabel = UILabel()
    private let textStack = UIStackView()
    /// The settled card's content, swapped in for the ordinary stack.
    private let cardStack = UIStackView()
    private var textInsets: [NSLayoutConstraint] = []
    private var cardInsets: [NSLayoutConstraint] = []
    /// A photos-only user row carries no bubble, so its stack hugs the row edge
    /// (items.tsx:248 zeroes the bubble's padding there).
    private var photoInsets: [NSLayoutConstraint] = []
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var centered: NSLayoutConstraint!
    private var botWidth: NSLayoutConstraint!
    private var userWidth: NSLayoutConstraint!
    private var noticeWidth: NSLayoutConstraint!
    private var wideWidth: NSLayoutConstraint!
    private var wideUserWidth: NSLayoutConstraint!

    /// items.tsx reads every colour and size from the palette and the type scale.
    private var palette: Palette { ThemeStore.palette(trait: traitCollection) }
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = Radius.bubble
        contentView.addSubview(bubble)
        authorLabel.font = TypeScale.caption.font
        authorLabel.textColor = palette.ink3
        messageLabel.font = TypeScale.bubble.font
        messageLabel.numberOfLines = 0
        photos.translatesAutoresizingMaskIntoConstraints = false
        fileStack.axis = .vertical
        fileStack.spacing = 6
        timeLabel.font = TypeScale.caption.font
        timeLabel.textColor = palette.ink3
        // items.tsx:547 styles.via: 11/16 with the platform painted onto the text.
        viaLabel.font = Typography(size: 11, lineHeight: 16, weight: .regular).font
        viaLabel.textColor = palette.ink3
        viaLabel.backgroundColor = palette.hover
        viaLabel.layer.cornerRadius = Radius.item
        viaLabel.clipsToBounds = true
        // items.tsx:271 lays the via tag and the clock on one row, six apart.
        stampRow.axis = .horizontal
        stampRow.spacing = 6
        stampRow.alignment = .center
        [viaLabel, timeLabel].forEach { stampRow.addArrangedSubview($0) }
        stateLabel.font = TypeScale.caption.font
        stateLabel.textColor = palette.ink3
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        [authorLabel, messageLabel, markdownView, photos, fileStack, stampRow, stateLabel]
            .forEach { textStack.addArrangedSubview($0) }
        bubble.addSubview(textStack)
        cardStack.axis = .vertical
        cardStack.spacing = 8
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.isHidden = true
        bubble.addSubview(cardStack)
        leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        centered = bubble.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        // Chat.tsx:267-271 caps each kind on its own, and a phone is always the
        // narrow branch there: a user bubble at 86% of the chat width, a Bot or
        // post row at 93%, a notice at 92%; the 100% - 40 form belongs to the
        // desktop's column window.
        botWidth = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.93)
        userWidth = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.86)
        noticeWidth = bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.92)
        // A wide block pins the row to its cap rather than merely capping it.
        wideWidth = bubble.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.93)
        wideUserWidth = bubble.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.86)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
        ])
        // The settled card's padding is its own (items.tsx: 16x12), so the two
        // stacks pin their insets separately and swap which one is active.
        textInsets = [
            textStack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            textStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9),
            textStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
        ]
        cardInsets = [
            cardStack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
            cardStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
            cardStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -16),
        ]
        photoInsets = [
            textStack.topAnchor.constraint(equalTo: bubble.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            textStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
        ]
        NSLayoutConstraint.activate(textInsets)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The two facts the flat layout turns on, read by the test that pins it
    /// (FlatLayoutTests) without reaching into the view tree.
    var bubbleFillColor: UIColor? { bubble.backgroundColor }
    var bubbleCornerRadius: CGFloat { bubble.layer.cornerRadius }

    func configure(_ row: ChatRow, images: [String: UIImage] = [:], stepsExpanded: Bool = false,
                   flat: Bool = false) {
        // The width rules are implicitly-unwrapped so init can build them: in an
        // array literal that reads as optional, hence the unwrap here.
        for constraint in [leading, trailing, centered, botWidth, userWidth,
                           noticeWidth, wideWidth, wideUserWidth].compactMap({ $0 }) {
            constraint.isActive = false
        }
        let notice = row.isNotice || row.kind == "steps"
        // items.tsx:317-327: the flat layout lays a Bot or member row straight on
        // the page colour, stretched to the whole column, with no bubble at all.
        // A user row and a settled card keep their own shapes.
        let bare = flat && !row.isUser && !notice && row.settled == nil
        // A settled card reuses the bubble as its full-width surface; the layer
        // state resets here because a reused cell may have drawn one.
        bubble.layer.borderWidth = 0
        bubble.layer.cornerRadius = bare ? 0 : Radius.bubble
        textStack.isHidden = row.settled != nil
        cardStack.isHidden = row.settled == nil
        textInsets.forEach { $0.isActive = row.settled == nil && !row.photosOnly && !bare }
        cardInsets.forEach { $0.isActive = row.settled != nil }
        photoInsets.forEach { $0.isActive = row.photosOnly || bare }
        for view in cardStack.arrangedSubviews {
            cardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if let settled = row.settled {
            // items.tsx settledCard stretches the row's full width.
            leading.isActive = true
            trailing.isActive = true
            buildSettledCard(settled, fallback: row.text)
        } else if notice {
            centered.isActive = true
            noticeWidth.isActive = true
        } else if bare {
            leading.isActive = true
            trailing.isActive = true
        } else if row.isUser {
            trailing.isActive = true
            userWidth.isActive = true
        } else {
            leading.isActive = true
            botWidth.isActive = true
        }
        // The asymmetry is deliberate: a user message is a bubble, a Bot message is text.
        // items.tsx:248 drops the bubble's fill and padding when photos stand alone.
        bubble.backgroundColor = row.settled != nil ? palette.card
            : row.isUser && !row.photosOnly ? palette.user : .clear
        if row.settled != nil {
            bubble.layer.cornerRadius = Radius.dialog
            bubble.layer.borderWidth = 1
            bubble.layer.borderColor = palette.line.cgColor
        }
        authorLabel.isHidden = notice || (bare && !row.inRoom)
        authorLabel.text = row.author
        let wideBlock = row.settled == nil && !notice && row.stepSummary == nil && ChatMarkdownView.hasWideBlock(row.text)
        // A bare row already spans the column, so the block cap has nothing to add.
        if wideBlock && !bare { (row.isUser ? wideUserWidth : wideWidth).isActive = true }
        if let summary = row.stepSummary {
            messageLabel.attributedText = nil
            messageLabel.text = summary
                + (stepsExpanded && !row.stepDetails.isEmpty ? "\n" + row.stepDetails.joined(separator: "\n") : "")
            markdownView.isHidden = true
            messageLabel.isHidden = false
        } else if wideBlock {
            messageLabel.attributedText = nil
            messageLabel.text = nil
            messageLabel.isHidden = true
            markdownView.isHidden = false
            markdownView.configure(row.text)
        } else if !row.isNotice, let markdown = try? AttributedString(markdown: MarkdownHanSpacing.apply(row.text)) {
            messageLabel.attributedText = NSAttributedString(markdown)
            messageLabel.isHidden = false
            markdownView.isHidden = true
        } else {
            messageLabel.attributedText = nil
            messageLabel.text = row.text
            messageLabel.isHidden = false
            markdownView.isHidden = true
        }
        var tiles: [UIView] = []
        for reference in row.imageRefs {
            let button = UIButton(type: .custom)
            button.clipsToBounds = true
            button.layer.cornerRadius = Radius.bubble
            button.backgroundColor = palette.hover
            button.imageView?.contentMode = .scaleAspectFill
            button.setImage(images[reference], for: .normal)
            button.accessibilityLabel = NativeLanguage.text("Open photo")
            button.addAction(UIAction { [weak self] _ in self?.onOpenPhoto?(reference) }, for: .touchUpInside)
            tiles.append(button)
        }
        for data in row.localImageData {
            let thumbnail = UIImageView(image: UIImage(data: data))
            thumbnail.contentMode = .scaleAspectFill
            thumbnail.clipsToBounds = true
            thumbnail.layer.cornerRadius = Radius.bubble
            tiles.append(thumbnail)
        }
        photos.setViews(tiles)
        photos.isHidden = tiles.isEmpty
        if row.text.isEmpty && (!row.imageRefs.isEmpty || !row.localImageData.isEmpty) {
            messageLabel.isHidden = true
        }
        for view in fileStack.arrangedSubviews { fileStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for file in row.files {
            let button = UIButton(type: .system)
            button.setTitle(file.title, for: .normal)
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.lineBreakMode = .byTruncatingMiddle
            button.backgroundColor = palette.hover
            button.layer.cornerRadius = Radius.row
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onOpenFile?(file) }, for: .touchUpInside)
            fileStack.addArrangedSubview(button)
        }
        fileStack.isHidden = row.files.isEmpty
        messageLabel.textAlignment = row.isNotice || row.kind == "steps" ? .center : .left
        messageLabel.textColor = row.isUser ? palette.userInk
            : (row.isNotice || row.kind == "steps" ? palette.ink3 : palette.ink)
        messageLabel.font = row.stepSummary == nil ? TypeScale.bubble.font : TypeScale.small.font
        authorLabel.textColor = palette.ink3
        // Two views, two rules: the clock obeys the room, the send state never does.
        // Chat.tsx shows stamps outside rooms only, one per Bot run on its last row.
        let stampable = row.kind == "user" || row.kind == "bot" || row.kind == "post"
        timeLabel.text = row.time.map { Self.clock.string(from: $0) }
        timeLabel.textColor = palette.ink3
        timeLabel.numberOfLines = 1
        timeLabel.isHidden = row.localID != nil || row.inRoom || !stampable || row.stampFolded
        // The tag is the item's own field, so items.tsx:268 keeps it where the
        // room hides the clock and where the stamp folds into a Bot's run.
        viaLabel.text = row.via.map { ChatRow.viaTagText($0) }
        viaLabel.textColor = palette.ink3
        viaLabel.backgroundColor = palette.hover
        viaLabel.isHidden = row.via == nil
        if row.failed {
            let reason = row.failureReason.map { NativeLanguage.text("Not sent · {reason}", ["reason": $0]) }
            stateLabel.text = reason ?? NativeLanguage.text("Not sent. Tap to retry")
            stateLabel.textColor = palette.danger
            stateLabel.numberOfLines = 2
        } else {
            stateLabel.text = NativeLanguage.text("Sending…")
            stateLabel.textColor = palette.ink3
            stateLabel.numberOfLines = 1
        }
        stateLabel.isHidden = row.localID == nil
        accessibilityLabel = [row.author, row.text, row.failureReason ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
    }

    // MARK: - The settled card

    private static let settledTitleFont = Typography(size: 13, lineHeight: 18, weight: .medium).font
    private static let viewTitleFont = Typography(size: 16, lineHeight: 22, weight: .semibold).font

    /// items.tsx renders every settled variant on the same full-width card.
    private func buildSettledCard(_ card: SettledCard, fallback: String) {
        switch card {
        case .closed(let prompt, let answered):
            cardStack.addArrangedSubview(settledHead(
                title: settledTitle(prompt),
                marker: settledBadge(answered ? NativeLanguage.text("Answered by message")
                                               : NativeLanguage.text("Dismissed"))))
        case .handoff(let title, let badge):
            let marker: UIView = badge != nil
                ? settledBadge(badge ?? "")
                : IconView(icon: .check, size: 16, color: palette.ink2)
            cardStack.addArrangedSubview(settledHead(title: settledTitle(title), marker: marker))
        case .views(let replies):
            for reply in replies {
                let block = UIStackView()
                block.axis = .vertical
                block.spacing = 4
                if !reply.title.isEmpty { block.addArrangedSubview(settledTitle(reply.title)) }
                // items.tsx falls back to the answers' own text when the view
                // gives none.
                block.addArrangedSubview(settledBody(reply.detail.isEmpty ? fallback : reply.detail))
                cardStack.addArrangedSubview(block)
            }
        case .questions(let questions):
            for question in questions {
                let block = UIStackView()
                block.axis = .vertical
                block.spacing = 6
                block.addArrangedSubview(settledTitle(question.question))
                for pick in question.picks {
                    block.addArrangedSubview(settledPickRow(pick))
                }
                cardStack.addArrangedSubview(block)
            }
        case .viewTitle(let title):
            let label = UILabel()
            label.font = Self.viewTitleFont
            label.textColor = palette.ink
            label.text = title
            cardStack.addArrangedSubview(label)
        }
    }

    private func settledHead(title: UILabel, marker: UIView) -> UIStackView {
        let head = UIStackView()
        head.axis = .horizontal
        head.spacing = 10
        head.alignment = .top
        head.addArrangedSubview(title)
        head.addArrangedSubview(marker)
        return head
    }

    private func settledTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = Self.settledTitleFont
        label.textColor = palette.ink2
        label.numberOfLines = 0
        label.text = text
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func settledBody(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = TypeScale.small.font
        label.textColor = palette.ink
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func settledBadge(_ text: String) -> UIView {
        let label = UILabel()
        label.font = TypeScale.caption.font
        label.textColor = palette.ink2
        label.text = text
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let pill = DashedPill(color: palette.line2)
        pill.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
        ])
        return pill
    }

    /// items.tsx pickLine: the accent letter badge, then the pick's own label.
    private func settledPickRow(_ pick: SettledPick) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .top
        let badge = UILabel()
        badge.font = .systemFont(ofSize: 12, weight: .semibold)
        badge.textColor = palette.accentInk
        badge.backgroundColor = palette.accent
        badge.textAlignment = .center
        badge.layer.cornerRadius = 7
        badge.clipsToBounds = true
        badge.text = pick.letter
        badge.widthAnchor.constraint(equalToConstant: 22).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(badge)
        row.addArrangedSubview(settledBody(pick.label))
        return row
    }
}

/// items.tsx:547 styles.via paints the tag's background straight onto the text
/// with six points of side padding and a 16-point line height, none of which a
/// plain label draws for itself.
private final class ViaTagLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 6, dy: 0))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: max(size.height, 16))
    }
}

/// RN's settledBadge rim is dashed; UIKit has no dashed border, so the pill
/// draws one with a shape layer sized on every layout pass.
private final class DashedPill: UIView {
    private let rim = CAShapeLayer()

    init(color: UIColor) {
        super.init(frame: .zero)
        rim.strokeColor = color.cgColor
        rim.fillColor = nil
        rim.lineWidth = 1
        rim.lineDashPattern = [4, 3]
        layer.addSublayer(rim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        rim.frame = bounds
        rim.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                cornerRadius: bounds.height / 2).cgPath
    }
}
