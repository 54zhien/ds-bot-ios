import UIKit

final class ChatMessageCell: UITableViewCell {
    var onOpenFile: ((ChatFile) -> Void)?
    var onOpenPhoto: ((String) -> Void)?
    private let bubble = UIView()
    private let authorLabel = UILabel()
    private let messageLabel = MarkdownLinkLabel()
    private let markdownView = ChatMarkdownView()
    private let photoScroll = UIScrollView()
    private let photoStack = UIStackView()
    private let fileStack = UIStackView()
    private let timeLabel = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var centered: NSLayoutConstraint!
    private var wideWidth: NSLayoutConstraint!
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
        bubble.layer.cornerRadius = 18
        contentView.addSubview(bubble)
        authorLabel.font = .preferredFont(forTextStyle: .caption1)
        authorLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.numberOfLines = 0
        photoScroll.showsHorizontalScrollIndicator = false
        photoStack.translatesAutoresizingMaskIntoConstraints = false
        photoStack.axis = .horizontal
        photoStack.spacing = 6
        photoScroll.addSubview(photoStack)
        NSLayoutConstraint.activate([
            photoScroll.heightAnchor.constraint(equalToConstant: 150),
            photoScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            photoStack.topAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.topAnchor),
            photoStack.bottomAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.bottomAnchor),
            photoStack.leadingAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.leadingAnchor),
            photoStack.trailingAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.trailingAnchor),
            photoStack.heightAnchor.constraint(equalTo: photoScroll.frameLayoutGuide.heightAnchor),
        ])
        fileStack.axis = .vertical
        fileStack.spacing = 6
        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .tertiaryLabel
        let text = UIStackView(arrangedSubviews: [authorLabel, messageLabel, markdownView, photoScroll, fileStack, timeLabel])
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
        bubble.backgroundColor = row.isNotice || row.kind == "steps" ? .clear
            : row.isUser ? tintColor.withAlphaComponent(0.12) : .secondarySystemBackground
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
        for view in photoStack.arrangedSubviews { photoStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for reference in row.imageRefs {
            let button = UIButton(type: .custom)
            button.clipsToBounds = true
            button.layer.cornerRadius = 12
            button.backgroundColor = .tertiarySystemBackground
            button.imageView?.contentMode = .scaleAspectFill
            button.setImage(images[reference], for: .normal)
            button.accessibilityLabel = NativeLanguage.text("Open photo")
            button.widthAnchor.constraint(equalToConstant: 150).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onOpenPhoto?(reference) }, for: .touchUpInside)
            photoStack.addArrangedSubview(button)
        }
        for data in row.localImageData {
            let thumbnail = UIImageView(image: UIImage(data: data))
            thumbnail.contentMode = .scaleAspectFill
            thumbnail.clipsToBounds = true
            thumbnail.layer.cornerRadius = 12
            thumbnail.widthAnchor.constraint(equalToConstant: 150).isActive = true
            photoStack.addArrangedSubview(thumbnail)
        }
        photoScroll.isHidden = row.imageRefs.isEmpty && row.localImageData.isEmpty
        if row.text.isEmpty && (!row.imageRefs.isEmpty || !row.localImageData.isEmpty) {
            messageLabel.isHidden = true
        }
        for view in fileStack.arrangedSubviews { fileStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for file in row.files {
            let button = UIButton(type: .system)
            button.setTitle(file.title, for: .normal)
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.lineBreakMode = .byTruncatingMiddle
            button.backgroundColor = .tertiarySystemBackground
            button.layer.cornerRadius = 10
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onOpenFile?(file) }, for: .touchUpInside)
            fileStack.addArrangedSubview(button)
        }
        fileStack.isHidden = row.files.isEmpty
        messageLabel.textAlignment = row.isNotice || row.kind == "steps" ? .center : .left
        messageLabel.textColor = row.isNotice || row.kind == "steps" ? .secondaryLabel : .label
        if row.localID == nil {
            timeLabel.text = row.time.map { Self.clock.string(from: $0) }
        } else if row.failed {
            let reason = row.failureReason.map { NativeLanguage.text("Not sent · {reason}", ["reason": $0]) }
            timeLabel.text = reason ?? NativeLanguage.text("Not sent. Tap to retry")
        } else {
            timeLabel.text = NativeLanguage.text("Sending…")
        }
        timeLabel.numberOfLines = row.failed ? 2 : 1
        timeLabel.isHidden = (row.time == nil && row.localID == nil) || row.isNotice || row.kind == "steps"
        accessibilityLabel = [row.author, row.text, row.failureReason ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
    }
}
