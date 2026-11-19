import XCTest
@testable import DSBot

/// marks.tsx is arithmetic before it is a picture: these hold the seat layout,
/// the gap a mask cuts, and the badge sizes to the numbers the phone uses, so a
/// later port of the character markup has a frame to land in.
final class AvatarMarksTests: XCTestCase {
    private let frame: CGFloat = 44

    func testOneMemberFillsTheFrame() {
        let seats = AvatarMarks.seats(count: 1, frame: frame)
        XCTAssertEqual(seats, [CGRect(x: 0, y: 0, width: 44, height: 44)])
    }

    func testTwoMembersStraddleTheDiagonal() {
        let seats = AvatarMarks.seats(count: 2, frame: 44)
        XCTAssertEqual(seats.count, 2)
        XCTAssertEqual(seats[0].width, 44 * 2 / 3, accuracy: 0.001)
        XCTAssertEqual(seats[0].origin, .zero)
        XCTAssertEqual(seats[1].origin.x, 44 / 3, accuracy: 0.001)
        XCTAssertEqual(seats[1].origin.y, 44 / 3, accuracy: 0.001)
    }

    func testThreeMembersSitAtFiveNinths() {
        let seats = AvatarMarks.seats(count: 3, frame: 44)
        XCTAssertEqual(seats.count, 3)
        let side = 44 * 5 / 9
        let rest = 44 - side
        XCTAssertEqual(seats[0].width, side, accuracy: 0.001)
        XCTAssertEqual(seats[0].origin.x, rest / 2, accuracy: 0.001)
        XCTAssertEqual(seats[0].origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(seats[1].origin, CGPoint(x: 0, y: rest))
        XCTAssertEqual(seats[2].origin, CGPoint(x: rest, y: rest))
    }

    func testFourMembersSplitTheFrame() {
        let seats = AvatarMarks.seats(count: 4, frame: 44)
        XCTAssertEqual(seats.count, 4)
        XCTAssertTrue(seats.allSatisfy { $0.width == 22 && $0.height == 22 })
        XCTAssertEqual(seats[2].origin, CGPoint(x: 0, y: 22))
        XCTAssertEqual(seats[3].origin, CGPoint(x: 22, y: 22))
    }

    func testPastFourStillSeatsFour() {
        // marks.tsx:139 passes Math.min(people.length, 4).
        XCTAssertEqual(AvatarMarks.seats(count: 9, frame: 30).count, 4)
    }

    func testTheGapIsAFourteenth() {
        XCTAssertEqual(AvatarMarks.seatGap(frame: 44), 44.0 / 14.0, accuracy: 0.0001)
    }

    func testCutOutIsAPercentageOfTheSeatPlusTheGap() {
        let seat = CGRect(x: 11, y: 11, width: 22, height: 22)
        let cut = AvatarMarks.cutOut(seat: seat, frame: 44)
        XCTAssertEqual(cut.centre, CGPoint(x: 22, y: 22))
        XCTAssertEqual(cut.radius, 22 * 0.48 + 44.0 / 14.0, accuracy: 0.0001)
    }

    func testNeighboursCutIntoEachOtherButDiagonalsDoNot() {
        let seats = AvatarMarks.seats(count: 4, frame: 44)
        // Right neighbour of the top-left seat, then the diagonal one.
        XCTAssertTrue(AvatarMarks.reaches(seats[1], into: seats[0], frame: 44))
        XCTAssertFalse(AvatarMarks.reaches(seats[3], into: seats[0], frame: 44))
    }

    func testTwoSeatsAlwaysCutIntoEachOther() {
        let seats = AvatarMarks.seats(count: 2, frame: 44)
        XCTAssertTrue(AvatarMarks.reaches(seats[1], into: seats[0], frame: 44))
    }

    func testTheStarIsClampedBetween14And22() {
        XCTAssertEqual(AvatarMarks.star(size: 24), 14, "9 rounds up, the floor holds")
        XCTAssertEqual(AvatarMarks.star(size: 36), 14, "13 rounds to 13, the floor holds")
        XCTAssertEqual(AvatarMarks.star(size: 44), 16)
        XCTAssertEqual(AvatarMarks.star(size: 56), 20)
        XCTAssertEqual(AvatarMarks.star(size: 72), 22, "26 rounds past the cap")
    }

    func testTheBadgeGrowsWithTheAvatar() {
        XCTAssertEqual(AvatarMarks.badgeDot(size: 22), 6)
        XCTAssertEqual(AvatarMarks.badgeDot(size: 36), 10)
        XCTAssertEqual(AvatarMarks.badgeDot(size: 44), 12)
        XCTAssertEqual(AvatarMarks.badgeInset(size: 22), 0)
        XCTAssertEqual(AvatarMarks.badgeInset(size: 44), 1)
        XCTAssertEqual(AvatarMarks.badgeInset(size: 100), 2)
    }

    func testSmallGroupAvatarsStackInsteadOfSeating() {
        XCTAssertTrue(AvatarMarks.usesStack(size: 20, people: 2))
        XCTAssertFalse(AvatarMarks.usesStack(size: 20, people: 1))
        XCTAssertFalse(AvatarMarks.usesStack(size: 28, people: 2))
        XCTAssertEqual(AvatarMarks.stackOverlap(size: 20), 6, accuracy: 0.0001)
        XCTAssertEqual(AvatarMarks.stackSide(size: 20), 18.4, accuracy: 0.0001)
    }

    func testThePlusFoldsEveryonePastTheFourth() {
        XCTAssertEqual(AvatarMarks.overflow(people: 4), 0)
        XCTAssertEqual(AvatarMarks.overflow(people: 5), 2)
        XCTAssertEqual(AvatarMarks.overflow(people: 7), 4)
    }

    func testACharacterColourAsPaint() {
        XCTAssertEqual(AvatarMarks.paint("black"), "#3c4048")
        XCTAssertEqual(AvatarMarks.paint("aurora"), "#5cc8a0")
        XCTAssertEqual(AvatarMarks.paint("chartreuse"), "#8b8f98", "unknown names fall back to gray")
        XCTAssertEqual(AvatarMarks.paints.count, 12)
    }
}
