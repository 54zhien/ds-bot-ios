import UIKit

/// The native version of the existing chat capsule. Its send and stop glyphs
/// follow mobile/src/ui/icons.tsx (the same paths as ds-bot/src/client/icons.js).
final class NativeComposerView: UIView, UITextViewDelegate {
    var onSend: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var canSend = false { didSet { updateAction() } }
    var running = false { didSet { updateAction() } }

    let editor = UITextView()
    private let placeholder = UILabel()
    private let action = UIButton(type: .system)
    private let icon = OriginalActionIcon()
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let rail = UIView()
    private var railHeight: NSLayoutConstraint!
    private var expanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerRadius = 31
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        layer.masksToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textContainerInset = UIEdgeInsets(top: 18, left: 16, bottom: 10, right: 54)
        editor.textContainer.lineFragmentPadding = 0
        editor.isScrollEnabled = false
        editor.delegate = self
        editor.accessibilityLabel = "Message"
        addSubview(editor)

        placeholder.text = "Message"
        placeholder.font = editor.font
        placeholder.textColor = .placeholderText
        placeholder.isUserInteractionEnabled = false
        addSubview(placeholder)

        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)
        action.translatesAutoresizingMaskIntoConstraints = false
        action.layer.cornerRadius = 22
        action.backgroundColor = tintColor
        action.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        addSubview(action)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        action.addSubview(icon)
        railHeight = rail.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            editor.topAnchor.constraint(equalTo: topAnchor),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: rail.topAnchor),
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.trailingAnchor.constraint(equalTo: trailingAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            railHeight,
            action.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            action.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            action.widthAnchor.constraint(equalToConstant: 44),
            action.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: action.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: action.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
        ])
        updateAction()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionPlaceholder()
    }

    private func positionPlaceholder() {
        let caret = editor.caretRect(for: editor.beginningOfDocument)
        placeholder.frame = CGRect(
            x: editor.frame.minX + caret.minX,
            y: editor.frame.minY + caret.minY + (caret.height - placeholder.intrinsicContentSize.height) / 2,
            width: bounds.width - caret.minX - 24,
            height: placeholder.intrinsicContentSize.height
        )
    }

    func textViewDidBeginEditing(_ textView: UITextView) { updateHeight() }
    func textViewDidEndEditing(_ textView: UITextView) { updateHeight() }
    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        updateHeight()
        updateAction()
    }

    private func updateHeight() {
        let shouldExpand = editor.isFirstResponder || !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if expanded != shouldExpand {
            expanded = shouldExpand
            layer.cornerRadius = shouldExpand ? 26 : 31
            railHeight.constant = shouldExpand ? 52 : 0
        }
        let textHeight = editor.sizeThatFits(CGSize(width: max(1, bounds.width), height: .greatestFiniteMagnitude)).height
        let target = shouldExpand ? min(max(124, textHeight + 52), 320) : 62
        onHeightChange?(target)
        setNeedsLayout()
    }

    private func updateAction() {
        let ready = canSend && !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let stop = running && !ready
        icon.showsStop = stop
        action.isEnabled = stop || ready
        action.alpha = action.isEnabled ? 1 : 0.35
        action.accessibilityLabel = stop ? "Stop" : "Send"
    }

    func restoreDraft(_ text: String) {
        editor.text = text
        placeholder.isHidden = !text.isEmpty
        updateHeight()
        updateAction()
    }

    @objc private func performAction() {
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && canSend {
            editor.text = ""
            placeholder.isHidden = false
            updateHeight()
            updateAction()
            onSend?(text)
        } else if running {
            onStop?()
        }
    }
}

private final class OriginalActionIcon: UIView {
    var showsStop = false { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        UIColor.white.setStroke()
        UIColor.white.setFill()
        if showsStop {
            UIBezierPath(roundedRect: CGRect(x: 3.5, y: 3.5, width: 13, height: 13), cornerRadius: 3).fill()
        } else {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 10, y: 16))
            path.addLine(to: CGPoint(x: 10, y: 4))
            path.move(to: CGPoint(x: 5, y: 9))
            path.addLine(to: CGPoint(x: 10, y: 4))
            path.addLine(to: CGPoint(x: 15, y: 9))
            path.lineWidth = 1.9
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        context?.restoreGState()
    }
}
