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
            tile.frame = CGRect(x: CGFloat(column) * (side + gap),
                                y: CGFloat(row) * (side + gap),
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
    private let timeLabel = UILabel()
    private let stateLabel = UILabel()
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
        stateLabel.font = TypeScale.caption.font
        stateLabel.textColor = palette.ink3
        let text = UIStackView(arrangedSubviews: [authorLabel, messageLabel, markdownView, photos, fileStack, timeLabel, stateLabel])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.axis = .vertical
        text.spacing = 4
        bubble.addSubview(text)
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
            text.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            text.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9),
            text.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ row: ChatRow, images: [String: UIImage] = [:], stepsExpanded: Bool = false) {
        for constraint in [leading, trailing, centered, botWidth, userWidth, noticeWidth, wideWidth, wideUserWidth] {
            constraint.isActive = false
        }
        let notice = row.isNotice || row.kind == "steps"
        if notice {
            centered.isActive = true
            noticeWidth.isActive = true
        } else if row.isUser {
            trailing.isActive = true
            userWidth.isActive = true
        } else {
            leading.isActive = true
            botWidth.isActive = true
        }
        // The asymmetry is deliberate: a user message is a bubble, a Bot message is text.
        bubble.backgroundColor = row.isUser ? palette.user : .clear
        authorLabel.isHidden = notice
        authorLabel.text = row.author
        let wideBlock = !notice && row.stepSummary == nil && ChatMarkdownView.hasWideBlock(row.text)
        if wideBlock { (row.isUser ? wideUserWidth : wideWidth).isActive = true }
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
        } else if !row.isNotice, let markdown = try? AttributedString(markdown: row.text) {
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
}
