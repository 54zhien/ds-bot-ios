import UIKit

/// Settings rows as the RN screens draw them: Settings.tsx's Section/Row metrics,
/// so no settings table falls back to the plain system look.
enum SettingsStyle {
    /// Settings.tsx styles.row: horizontal 16, vertical 10, at least 50 tall.
    static let rowHeight: CGFloat = 50

    static func palette(of trait: UITraitCollection) -> Palette {
        Palette.make(dark: trait.userInterfaceStyle == .dark)
    }

    static func prepare(_ table: UITableView) {
        let palette = palette(of: table.traitCollection)
        table.backgroundColor = palette.main
        // Settings.tsx styles.divider starts under the row's own padding.
        table.separatorColor = palette.line
        table.rowHeight = rowHeight
        table.estimatedRowHeight = rowHeight
    }

    /// Settings.tsx section label: caption-size 11, ink3, uppercase, inset 18.
    static func headerView(title: String, palette: Palette) -> UIView {
        let header = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title.uppercased()
        label.font = .systemFont(ofSize: 11)
        label.textColor = palette.ink3
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -18),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -6),
        ])
        return header
    }

    /// A row whose second line sits under the label, not beside it.
    static func styleSubtitle(_ cell: UITableViewCell, palette: Palette) {
        style(cell, palette: palette)
        cell.detailTextLabel?.font = TypeScale.rowPreview.font
        cell.detailTextLabel?.textColor = palette.ink2
    }

    /// A titled section's header height; a gap-only header when the RN screen has no label.
    static let headerHeight: CGFloat = 38
    static let gapHeaderHeight: CGFloat = 22

    static func style(_ cell: UITableViewCell, palette: Palette, danger: Bool = false) {
        cell.backgroundColor = palette.card
        cell.separatorInset = UIEdgeInsets(top: 0, left: Glass.margin, bottom: 0, right: 0)
        cell.textLabel?.font = TypeScale.settingsRow.font
        cell.textLabel?.textColor = danger ? palette.danger : palette.ink
        cell.detailTextLabel?.font = TypeScale.settingsRow.font
        cell.detailTextLabel?.textColor = palette.ink2
        if let chevron = cell.accessoryView as? IconView {
            chevron.color = palette.ink3
        } else if let chevron = cell.accessoryView as? OriginalIconView {
            chevron.tintColor = palette.ink3
        }
    }
}
