import UIKit

/// The native version of the chat capsule: mobile/src/screens/chat/composer.tsx for the
/// states, zen's ComposerHostView for the measuring. Send and stop glyphs follow
/// mobile/src/ui/icons.tsx.
final class NativeComposerView: UIView, UITextViewDelegate {
    var onSend: ((String, [String]) -> Void)?
    var onStop: (() -> Void)?
    var onAddPhoto: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onExpandedChange: ((Bool) -> Void)?
    var isExpanded: Bool { expanded }
    var canSend = false { didSet { updateAction() } }
    /// Chat.tsx:502: the plus is drawn only when the host listed "send-images"
    /// in its hello reply, so an older computer never invites a photo it cannot
    /// take. The gate is the host's, not the link's: it follows each hello.
    var canAttach = false { didSet { updateAction() } }
    var running = false { didSet { updateAction() } }

    let editor = UITextView()
    private let placeholder = UILabel()
    private let action = UIButton(type: .system)
    private let addPhotoButton = UIButton(type: .system)
    private let actionIcon = IconView(icon: .arrowUp, size: Glass.iconXL)
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let plusIcon = IconView(icon: .plus, size: Glass.iconLarge)
    private let rail = UIView()
    private let photoScroller = UIScrollView()
    private let photoStrip = UIStackView()
    private var photoHeight: NSLayoutConstraint!
    private var photos: [(UIImage, String)] = []
    private var railHeight: NSLayoutConstraint!
    private var expanded = false
    private var palette = Palette.make(dark: false)

    // Mirrors composer.tsx. LINE, TEXT_TOP, MEDIA and the 52pt rail are the reference
    // file's own layout constants; everything else is derived from DesignTokens.
    private enum Layout {
        static let line = TypeScale.bubble.lineHeight
        static let textTop: CGFloat = 14
        static let bar: CGFloat = 52
        static let media: CGFloat = 80
        static let photo: CGFloat = 64
        static let cardCorner = Radius.composer
        /// 124 in the reference: two resting capsules, kept derived.
        static let editing = Metrics.Composer.resting * 2
    }

    private func tr(_ key: String) -> String { NativeLanguage.text(key) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerRadius = Metrics.Composer.resting / 2
        layer.masksToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false

        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.backgroundColor = .clear
        editor.font = TypeScale.bubble.font
        editor.textContainer.lineFragmentPadding = 0
        editor.isScrollEnabled = false
        editor.delegate = self
        editor.accessibilityLabel = tr("Message")
        editor.textContainerInset = textInset(editing: false)

        placeholder.font = TypeScale.bubble.font
        placeholder.isUserInteractionEnabled = false

        rail.translatesAutoresizingMaskIntoConstraints = false
        photoScroller.translatesAutoresizingMaskIntoConstraints = false
        photoScroller.showsHorizontalScrollIndicator = false
        photoStrip.translatesAutoresizingMaskIntoConstraints = false
        photoStrip.axis = .horizontal
        photoStrip.spacing = Glass.gap
        photoStrip.alignment = .center
        photoScroller.addSubview(photoStrip)
        photoHeight = photoScroller.heightAnchor.constraint(equalToConstant: 0)

        addPhotoButton.translatesAutoresizingMaskIntoConstraints = false
        addPhotoButton.accessibilityLabel = tr("Add photos")
        addPhotoButton.addTarget(self, action: #selector(addPhotos), for: .touchUpInside)
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        addPhotoButton.addSubview(plusIcon)

        action.translatesAutoresizingMaskIntoConstraints = false
        action.layer.cornerRadius = Glass.control / 2
        action.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        actionIcon.translatesAutoresizingMaskIntoConstraints = false
        actionIcon.isUserInteractionEnabled = false
        action.addSubview(actionIcon)
        railHeight = rail.heightAnchor.constraint(equalToConstant: 0)

        for view in [surface, editor, placeholder, rail, photoScroller, addPhotoButton, action] as [UIView] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            editor.topAnchor.constraint(equalTo: topAnchor),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: photoScroller.topAnchor),
            photoScroller.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Glass.margin + 2),
            photoScroller.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Glass.margin - 2),
            photoScroller.bottomAnchor.constraint(equalTo: rail.topAnchor),
            photoHeight,
            photoStrip.leadingAnchor.constraint(equalTo: photoScroller.contentLayoutGuide.leadingAnchor),
            photoStrip.trailingAnchor.constraint(equalTo: photoScroller.contentLayoutGuide.trailingAnchor),
            photoStrip.centerYAnchor.constraint(equalTo: photoScroller.frameLayoutGuide.centerYAnchor),
            photoStrip.heightAnchor.constraint(equalToConstant: Layout.photo),
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.trailingAnchor.constraint(equalTo: trailingAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            railHeight,
            addPhotoButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            addPhotoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            addPhotoButton.widthAnchor.constraint(equalToConstant: Glass.control),
            addPhotoButton.heightAnchor.constraint(equalToConstant: Glass.control),
            plusIcon.centerXAnchor.constraint(equalTo: addPhotoButton.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: addPhotoButton.centerYAnchor),
            plusIcon.widthAnchor.constraint(equalToConstant: Glass.iconLarge),
            plusIcon.heightAnchor.constraint(equalToConstant: Glass.iconLarge),
            action.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            action.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            action.widthAnchor.constraint(equalToConstant: Glass.control),
            action.heightAnchor.constraint(equalToConstant: Glass.control),
            actionIcon.centerXAnchor.constraint(equalTo: action.centerXAnchor),
            actionIcon.centerYAnchor.constraint(equalTo: action.centerYAnchor),
            actionIcon.widthAnchor.constraint(equalToConstant: Glass.iconXL),
            actionIcon.heightAnchor.constraint(equalToConstant: Glass.iconXL),
        ])
        applyPalette()
        updateShape()
        updateAction()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func themeChanged() { applyPalette() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
        applyPalette()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionPlaceholder()
    }

    private var dark: Bool { traitCollection.userInterfaceStyle == .dark }

    /// Liquid glass carries its own highlight and refraction, so it takes no rim;
    /// the material fallback keeps the 1pt line the phone design uses.
    private func applySurface() {
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect()
            layer.borderWidth = 0
        } else {
            surface.effect = UIBlurEffect(style: dark ? .systemThickMaterial : .systemUltraThinMaterial)
            layer.borderWidth = 1
            layer.borderColor = palette.line.cgColor
        }
    }

    private func applyPalette() {
        palette = ThemeStore.palette(dark: dark)
        applySurface()
        editor.textColor = palette.ink
        editor.tintColor = palette.accent
        placeholder.textColor = palette.ink3
        plusIcon.color = palette.ink2
        updateAction()
    }

    /// One line for the field and one for the rail: the resting capsule lifts the text to
    /// the middle, the editing card puts it back at the top.
    private func textInset(editing: Bool) -> UIEdgeInsets {
        let top = editing ? Layout.textTop : (Metrics.Composer.resting - Layout.line) / 2
        let left = editing ? Glass.margin : Glass.control + Glass.margin
        return UIEdgeInsets(top: top, left: left, bottom: Glass.gap + 2, right: Glass.control + Glass.gap + 2)
    }

    private func positionPlaceholder() {
        let inset = editor.textContainerInset
        let height = placeholder.intrinsicContentSize.height
        placeholder.frame = CGRect(
            x: inset.left,
            y: inset.top + (Layout.line - height) / 2,
            width: max(0, bounds.width - inset.left - inset.right),
            height: height)
    }

    func textViewDidBeginEditing(_ textView: UITextView) { updateShape() }
    func textViewDidEndEditing(_ textView: UITextView) { updateShape() }
    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        updateShape()
        updateAction()
    }

    /// zen's resolve(): editing while it holds the focus, a draft or an attachment.
    private var isEditing: Bool {
        editor.isFirstResponder
            || !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !photos.isEmpty
    }

    private var availableHeight: CGFloat {
        let bounds = window?.bounds ?? UIScreen.main.bounds
        return bounds.height - safeAreaInsets.top
    }

    /// The card grows from 124 up to 46% of the screen, and the rail and media rows are
    /// reserved before the field: the field scrolls instead of pushing the controls out.
    private var cap: CGFloat {
        let available = availableHeight
        return min(available - 12, max(available * 0.46, Layout.textTop + Layout.bar + Layout.line))
    }

    private var textHeight: CGFloat {
        editor.sizeThatFits(CGSize(width: max(1, bounds.width), height: .greatestFiniteMagnitude)).height
    }

    private func updateShape() {
        let editing = isEditing
        let media = photoHeight.constant > 0 ? Layout.media : 0
        let room = max(Layout.line, cap - Layout.textTop - media - Layout.bar)
        let textMax = max(Layout.line, (editing ? cap : Metrics.Composer.resting) - Layout.textTop - media - Layout.bar)
        let text = min(max(Layout.line, textHeight), textMax)
        let target = editing
            ? min(cap, max(Layout.editing, Layout.textTop + media + text + Layout.bar))
            : Metrics.Composer.resting
        let corner = editing ? openCorner : Metrics.Composer.resting / 2
        editor.isScrollEnabled = editing && textHeight > room
        if expanded != editing {
            expanded = editing
            onExpandedChange?(editing)
            railHeight.constant = editing ? Layout.bar : 0
            editor.textContainerInset = textInset(editing: editing)
            animate { self.layer.cornerRadius = corner }
        } else {
            railHeight.constant = editing ? Layout.bar : 0
            layer.cornerRadius = corner
        }
        onHeightChange?(target)
        setNeedsLayout()
    }

    /// The card's corner is concentric with the display's, so it reads as a sheet.
    private var openCorner: CGFloat {
        let bounds = window?.bounds ?? UIScreen.main.bounds
        let screenR = Metrics.screenRadius(bottomInset: window?.safeAreaInsets.bottom ?? 0, bounds: bounds)
        let inset = Metrics.Composer.inset(screenR: screenR, screenWidth: bounds.width, expanded: true)
        return max(Layout.cardCorner, screenR - inset)
    }

    private func animate(_ changes: @escaping () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled else { changes(); return }
        let spring = Springs.shape
        UIView.animate(withDuration: spring.settling, delay: 0, usingSpringWithDamping: spring.dampingRatio, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
    }

    /// Three states, told apart by fill and glyph colour: accent means sendable, the
    /// line colour means nothing to send, and the running square stays neutral.
    private func updateAction() {
        let ready = canSend && (!editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty)
        let stop = running && !ready
        actionIcon.icon = stop ? .stop : .arrowUp
        actionIcon.color = stop ? palette.ink : (ready ? palette.accentInk : palette.ink3)
        action.backgroundColor = stop ? palette.line2 : (ready ? palette.accent : palette.line)
        action.isEnabled = stop || ready
        action.accessibilityLabel = stop ? tr("Stop") : tr("Send")
        addPhotoButton.isEnabled = canSend && canAttach
        addPhotoButton.alpha = canSend && canAttach ? 1 : 0.35
        // composer.tsx:84 drops the plus outright rather than dimming it, so an
        // old computer shows no entry to a picker it cannot use.
        addPhotoButton.isHidden = !canAttach
        action.setNeedsLayout()
    }

    func restoreDraft(_ text: String) {
        editor.text = text
        placeholder.isHidden = !text.isEmpty
        updateShape()
        updateAction()
    }

    /// Target switches and reconnects drop what was typed: the React Native composer
    /// was remounted by ShellB's key, so a draft never carried over (ShellB.tsx:219).
    /// updateShape reports the resting height, so the caller's inset follows it down.
    func clear() {
        editor.text = ""
        placeholder.isHidden = false
        photos = []
        refreshPhotos()
        editor.resignFirstResponder()
        updateShape()
    }

    func addPhoto(data: Data) {
        guard let image = UIImage(data: data) else { return }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 2048 ? 2048 / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let jpeg = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let prepared = UIImage(data: jpeg) else { return }
        photos.append((prepared, jpeg.base64EncodedString()))
        refreshPhotos()
    }

    private func refreshPhotos() {
        for view in photoStrip.arrangedSubviews { photoStrip.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, photo) in photos.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setImage(photo.0, for: .normal)
            button.imageView?.contentMode = .scaleAspectFill
            button.clipsToBounds = true
            button.layer.cornerRadius = Radius.card
            button.accessibilityLabel = tr("Remove photo")
            button.addTarget(self, action: #selector(removePhoto(_:)), for: .touchUpInside)
            photoStrip.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: Layout.photo).isActive = true
            button.heightAnchor.constraint(equalToConstant: Layout.photo).isActive = true
        }
        photoHeight.constant = photos.isEmpty ? 0 : Layout.media
        updateShape()
        updateAction()
    }

    @objc private func addPhotos() { onAddPhoto?() }
    @objc private func removePhoto(_ sender: UIButton) {
        guard photos.indices.contains(sender.tag) else { return }
        photos.remove(at: sender.tag)
        refreshPhotos()
    }

    @objc private func performAction() {
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (!text.isEmpty || !photos.isEmpty) && canSend {
            let images = photos.map { $0.1 }
            photos = []
            refreshPhotos()
            editor.text = ""
            placeholder.isHidden = false
            updateShape()
            updateAction()
            onSend?(text, images)
        } else if running {
            onStop?()
        }
    }
}
