import UIKit

// The drawer's two fixed blocks. Neither has a source to copy: zen's rail has no
// device row at all, and the mobile drawer opens with the product name and two round
// buttons (ShellB.tsx:63-72, no device head, no grey section titles). The parts are
// therefore taken from this app's own tokens — the same caption, ink3 and hairline the
// rest of the drawer already uses — rather than invented per screen.

/// Who the phone is paired with and whether the link is up.
final class SidebarDeviceHeaderView: UIView {
    private let nameLabel = UILabel()
    private let dot = UIView()
    private let statusLabel = UILabel()

    var deviceName: String? { nameLabel.text }
    /// The words under the name, for the tests: "Connected" or "Offline".
    var statusText: String? { statusLabel.text }
    var statusColor: UIColor? { statusLabel.textColor }
    var isConnected: Bool = false { didSet { applyStatus() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = TypeScale.headerTitle.font
        nameLabel.textColor = ThemeStore.palette(trait: traitCollection).ink
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        statusLabel.font = TypeScale.caption.font
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            dot.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyStatus()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A nil name is a phone that has not read its pairing yet: the row keeps its
    /// height and says nothing rather than flashing a placeholder.
    func configure(name: String?, connected: Bool) {
        nameLabel.text = name
        nameLabel.isHidden = name == nil
        isConnected = connected
        accessibilityLabel = [name, statusLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    private func applyStatus() {
        let palette = ThemeStore.palette(trait: traitCollection)
        statusLabel.text = NativeLanguage.text(isConnected ? "Connected" : "Offline")
        statusLabel.textColor = isConnected ? palette.green : palette.ink3
        dot.backgroundColor = statusLabel.textColor
        dot.isHidden = false
    }

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        let palette = ThemeStore.palette(trait: traitCollection)
        nameLabel.textColor = palette.ink
        applyStatus()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) { applyTheme() }
    }
}

/// A grey title over the hairline that opens a group of rows.
final class SidebarSectionHeaderView: UIView {
    private let titleLabel = UILabel()
    private let line = UIView()
    private var lineHeight: NSLayoutConstraint!

    var title: String? { titleLabel.text }
    var titleColor: UIColor? { titleLabel.textColor }
    /// One device pixel at this screen's scale, as StyleSheet.hairlineWidth is.
    var hairlineHeight: CGFloat { lineHeight.constant }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = TypeScale.caption.font
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        lineHeight = line.heightAnchor.constraint(equalToConstant: hairline)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineHeight,
        ])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String) {
        titleLabel.text = title
        isAccessibilityElement = false
        line.isAccessibilityElement = false
    }

    /// StyleSheet.hairlineWidth (ShellB.tsx:97) is one device pixel, whatever the scale.
    private var hairline: CGFloat { 1 / max(1, traitCollection.displayScale) }

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        let palette = ThemeStore.palette(trait: traitCollection)
        titleLabel.textColor = palette.ink3
        line.backgroundColor = palette.line
        lineHeight.constant = hairline
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous)
            || traitCollection.displayScale != previous?.displayScale {
            applyTheme()
        }
    }
}
