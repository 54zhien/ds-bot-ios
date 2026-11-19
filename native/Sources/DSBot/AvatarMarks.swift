import UIKit

/// marks.tsx's arithmetic with no view and no drawing: where a group's member
/// seats sit inside the frame, how deep the gap cut into an earlier seat runs,
/// the badge sizes on an avatar, and a character colour as paint. The character
/// markup itself comes from the desktop's characters.js and lands separately.
enum AvatarMarks {
    /// COLOR_PAINT (marks.tsx:17-21): a character colour as paint, for swatches
    /// and for a member's name in a group.
    static let paints: [String: String] = [
        "black": "#3c4048", "brown": "#8d6e57", "red": "#e5484d", "orange": "#f76b15",
        "yellow": "#d4a017", "green": "#30a46c", "cyan": "#12a5b4", "blue": "#4f7df3",
        "violet": "#7d5aff", "magenta": "#d3458b", "gray": "#8b8f98", "aurora": "#5cc8a0",
    ]

    /// A colour's paint. RN falls back to the palette's gray, not to a guess.
    static func paint(_ color: String) -> String { paints[color] ?? paints["gray"] ?? "#8b8f98" }

    /// clusterSeats (marks.tsx:96-106): the seats inside a square frame. One
    /// fills it; two straddle a diagonal at two thirds; three sit at five
    /// ninths; four split it in quarters.
    static func seats(count: Int, frame: CGFloat) -> [CGRect] {
        switch count {
        case ..<1:
            return []
        case 1:
            return [CGRect(x: 0, y: 0, width: frame, height: frame)]
        case 2:
            let side = frame * 2 / 3
            return [CGRect(x: 0, y: 0, width: side, height: side),
                    CGRect(x: frame / 3, y: frame / 3, width: side, height: side)]
        case 3:
            let side = frame * 5 / 9
            let rest = frame - side
            return [CGRect(x: rest / 2, y: 0, width: side, height: side),
                    CGRect(x: 0, y: rest, width: side, height: side),
                    CGRect(x: rest, y: rest, width: side, height: side)]
        default:
            let half = frame / 2
            return [CGRect(x: 0, y: 0, width: half, height: half),
                    CGRect(x: half, y: 0, width: half, height: half),
                    CGRect(x: 0, y: half, width: half, height: half),
                    CGRect(x: half, y: half, width: half, height: half)]
        }
    }

    /// marks.tsx:141: the gap is a fourteenth of the frame, whatever the seats.
    static func seatGap(frame: CGFloat) -> CGFloat { frame / 14 }

    /// marks.tsx:143: a seat's cut-out is 48% of its own side plus that gap,
    /// centred on the seat — the mask that lets what is behind show through.
    static func cutOut(seat: CGRect, frame: CGFloat) -> (centre: CGPoint, radius: CGFloat) {
        (CGPoint(x: seat.midX, y: seat.midY), seat.width * 0.48 + seatGap(frame: frame))
    }

    /// marks.tsx:149-150: a later seat only cuts into an earlier one when its
    /// cut-out reaches it. Diagonal neighbours in a four-seat cluster miss.
    static func reaches(_ later: CGRect, into earlier: CGRect, frame: CGFloat) -> Bool {
        let cut = cutOut(seat: later, frame: frame)
        let dx = cut.centre.x - earlier.midX
        let dy = cut.centre.y - earlier.midY
        return (dx * dx + dy * dy).squareRoot() < cut.radius + earlier.width * 0.46
    }

    /// marks.tsx:68: the star is 36% of the avatar, floored at 14 and capped at 22.
    static func star(size: CGFloat) -> CGFloat { min(22, max(14, (size * 0.36).rounded())) }

    /// marks.tsx:69-71: the status dot, and the equal inset on both axes that
    /// puts the badge on the 45° diagonal.
    static func badgeDot(size: CGFloat) -> CGFloat { (size * 0.27).rounded() }
    static func badgeInset(size: CGFloat) -> CGFloat { (size * 0.02).rounded() }

    /// marks.tsx:124-132: at 20pt and below a group avatar stacks its members
    /// overlapped instead of seating them.
    static func usesStack(size: CGFloat, people: Int) -> Bool { size <= 20 && people > 1 }
    static func stackOverlap(size: CGFloat) -> CGFloat { size * 0.3 }
    static func stackSide(size: CGFloat) -> CGFloat { size * 0.92 }

    /// marks.tsx:140: four seats fill the frame; anyone past the fourth folds
    /// into a "+n" that takes the last seat's place.
    static func overflow(people: Int) -> Int { people > 4 ? people - 3 : 0 }
}
