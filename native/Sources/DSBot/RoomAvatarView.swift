import UIKit

/// marks.tsx:113-192 RoomAvatar: a group's members seated in one frame. A later
/// seat cuts a gap of its own size plus frame/14 into the seats it overlaps, so
/// whatever is behind the avatar shows between them instead of a guessed ring.
/// The user's own seat is a quiet rim, and anyone past the fourth folds into "+n".
final class RoomAvatarView: UIView {
    private var members: [CharacterMarks.Look] = []
    /// The disc an empty room shows, in the ring colour of the place it sits in.
    var plate: UIColor = .clear {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// members in roster order, as marks.tsx maps the room's list.
    func configure(members: [CharacterMarks.Look]) {
        guard members != self.members else { return }
        self.members = members
        setNeedsDisplay()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        // marks.tsx:117-118: a group down to one Bot shows the user beside it.
        let people: [CharacterMarks.Look?] = members.count == 1
            ? [members[0], nil] : members.map { Optional($0) }
        guard !people.isEmpty else {
            plate.setFill()
            UIBezierPath(ovalIn: frame).fill()
            return
        }
        let dark = traitCollection.userInterfaceStyle == .dark
        let seats = AvatarMarks.seats(count: min(people.count, 4), frame: side)
        let overflow = AvatarMarks.overflow(people: people.count)
        for (index, seat) in seats.enumerated() {
            let box = seat.offsetBy(dx: frame.minX, dy: frame.minY)
            // The last seat is the "+n" plate, a seat with no Bot is the user, and a
            // picture is drawn over the marks: none of the three cuts a gap.
            guard overflow == 0 || index < 3 else { continue }
            guard index < people.count, let person = people[index] else { continue }
            guard !CharacterPaint.hasPhoto(person) else { continue }
            CharacterPaint.draw(person, in: box, dark: dark)
            // marks.tsx:142-153: only the seats after this one, and only the ones
            // whose cut-out reaches it, take a bite out of what was just drawn.
            context.setBlendMode(.clear)
            for laterIndex in (index + 1)..<seats.count {
                guard AvatarMarks.reaches(seats[laterIndex], into: seat, frame: side) else { continue }
                let cut = AvatarMarks.cutOut(seat: seats[laterIndex], frame: side)
                context.fillEllipse(in: CGRect(x: frame.minX + cut.centre.x - cut.radius,
                                               y: frame.minY + cut.centre.y - cut.radius,
                                               width: cut.radius * 2, height: cut.radius * 2))
            }
            context.setBlendMode(.normal)
        }
        // marks.tsx:155-175: the plates and pictures ride on top of every mark.
        let palette = ThemeStore.palette(trait: traitCollection)
        for (index, seat) in seats.enumerated() {
            let box = seat.offsetBy(dx: frame.minX, dy: frame.minY)
            if overflow > 0, index == 3 {
                let inset = seat.width * 0.04
                let disc = CGRect(x: box.minX + inset, y: box.minY + inset,
                                  width: seat.width * 0.92, height: seat.width * 0.92)
                drawPlate(disc, dark: dark, ink: palette.ink2, text: "+\(overflow)")
                continue
            }
            guard index < people.count else { continue }
            guard let person = people[index] else {
                let inset = seat.width * 0.04
                let ring = CGRect(x: box.minX + inset, y: box.minY + inset,
                                  width: seat.width * 0.92, height: seat.width * 0.92)
                (dark ? UIColor(white: 1, alpha: 0.09) : UIColor(white: 0, alpha: 0.08)).setStroke()
                let path = UIBezierPath(ovalIn: ring)
                path.lineWidth = 1
                path.stroke()
                continue
            }
            if let photo = CharacterPaint.photo(for: person.image), let context = UIGraphicsGetCurrentContext() {
                context.saveGState()
                UIBezierPath(ovalIn: box).addClip()
                photo.draw(in: box)
                context.restoreGState()
            }
        }
    }

    /// materialSkin: a flat translucent plate with the one rim everything we draw
    /// ourselves carries, then the count in the surface's own ink.
    private func drawPlate(_ rect: CGRect, dark: Bool, ink: UIColor, text: String) {
        (dark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 0, alpha: 0.045)).setFill()
        UIBezierPath(ovalIn: rect).fill()
        (dark ? UIColor(white: 1, alpha: 0.09) : UIColor(white: 0, alpha: 0.08)).setStroke()
        let rim = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        rim.stroke()
        let size = max(8, (rect.width * 0.39).rounded())
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: ink,
        ]
        let string = text as NSString
        let measured = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2),
                    withAttributes: attributes)
    }
}
