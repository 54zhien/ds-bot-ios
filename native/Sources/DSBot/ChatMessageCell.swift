import UIKit

/// Photos in a square grid. The height comes from the count and the width only, so a
/// late image decode never changes the row height under the thumb.
final class PhotoGridView: UIView {
    private var tiles: [UIView] = []

    /// Width / (smallest tile + gap), capped at three columns.
    static func columns(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, min(3, Int((width + Glass.gap) / (100 + Glass.gap))))
    }

    static func height(forWidth width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let columns = CGFloat(columns(for: width))
        let side = (width - Glass.gap * (columns - 1)) / columns
        let rows = CGFloat((count + Int(columns) - 1) / Int(columns))
        return rows * side + Glass.gap * (rows - 1)
    }

    func setViews(_ views: [UIView]) {
        for tile in tiles { tile.removeFromSuperview() }
        tiles = views
        for tile in views { addSubview(tile) }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: Self.height(forWidth: bounds.width > 0 ? bounds.width : 280, count: tiles.count))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !tiles.isEmpty else { return }
        let columns = Self.columns(for: bounds.width)
        let side = (bounds.width - Glass.gap * CGFloat(columns - 1)) / CGFloat(columns)
        for (index, tile) in tiles.enumerated() {
            let column = index % columns
            let row = index / columns
            tile.frame = CGRect(x: CGFloat(column) * (side + Glass.gap),
                                y: CGFloat(row) * (side + Glass.gap),
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
    private let timeLabel = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var centered: NSLayoutConstraint!
    private var wideWidth: NSLayoutConstraint!

    /// items.tsx reads every colour and size from the palette and the type scale.
    private var palette: Palette { Palette.make(dark: traitCollection.userInterfaceStyle == .dark) }
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
        let text = UIStackView(arrangedSubviews: [authorLabel, messageLabel, markdownView, photos, fileStack, timeLabel])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.axis = .vertical
        text.spacing = 4
        bubble.addSubview(text)
        leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        centered = bubble.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        wideWidth = bubble.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.86)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.86),
            text.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            text.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ row: ChatRow, images: [String: UIImage] = [:], stepsExpanded: Bool = false) {
        leading.isActive = false
        trailing.isActive = false
        centered.isActive = false
        wideWidth.isActive = false
        if row.isNotice || row.kind == "steps" {
            centered.isActive = true
        } else if row.isUser {
            trailing.isActive = true
        } else {
            leading.isActive = true
        }
        // The asymmetry is deliberate: a user message is a bubble, a Bot message is text.
        bubble.backgroundColor = row.isUser ? palette.user : .clear
        authorLabel.isHidden = row.isNotice || row.kind == "steps"
        authorLabel.text = row.author
        let wideBlock = !row.isNotice && row.stepSummary == nil && ChatMarkdownView.hasWideBlock(row.text)
        wideWidth.isActive = wideBlock
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
            button.layer.cornerRadius = Radius.card
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
            thumbnail.layer.cornerRadius = Radius.card
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
        if row.localID == nil {
            timeLabel.text = row.time.map { Self.clock.string(from: $0) }
        } else if row.failed {
            let reason = row.failureReason.map { NativeLanguage.text("Not sent · {reason}", ["reason": $0]) }
            timeLabel.text = reason ?? NativeLanguage.text("Not sent. Tap to retry")
        } else {
            timeLabel.text = NativeLanguage.text("Sending…")
        }
        timeLabel.numberOfLines = row.failed ? 2 : 1
        timeLabel.textColor = row.failed ? palette.danger : palette.ink3
        timeLabel.isHidden = (row.time == nil && row.localID == nil) || row.isNotice || row.kind == "steps" || row.stampFolded
        accessibilityLabel = [row.author, row.text, row.failureReason ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
    }
}
