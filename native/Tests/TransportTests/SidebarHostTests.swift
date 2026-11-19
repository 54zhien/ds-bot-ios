import XCTest
@testable import DSBot

/// The wiring's two jobs: translate the page by progress times travel, and let the open
/// flag — never a second source — decide when the drawer is presented. The panel's own
/// slide is gone, so nothing here may move anything but the page.
@MainActor
final class SidebarHostTests: XCTestCase {
    private func fixture(travel: CGFloat = 340) -> (SidebarHost, SidebarTransportView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        _ = root.view
        window.isHidden = false
        let page = SidebarTransportView(frame: window.bounds)
        page.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: root.view.topAnchor),
            page.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
        ])
        root.view.layoutIfNeeded()
        let host = SidebarHost()
        host.travel = travel
        host.install(host: root, window: window, page: page)
        return (host, page)
    }

    func testThePageFollowsProgressTimesTravel() {
        let (host, page) = fixture()
        host.state.begin(eligible: true)
        host.state.drag(displacement: 170, travel: 340)
        XCTAssertEqual(host.state.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(page.offset, 170, accuracy: 0.5, "half of the drawer's width")

        host.state.drag(displacement: 400, travel: 340)
        XCTAssertEqual(page.offset, 340, accuracy: 0.5, "and no further than the width")
    }

    func testTheReadingDirectionFlipsTheSign() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        _ = root.view
        let page = SidebarTransportView(frame: window.bounds)
        page.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(page)
        let host = SidebarHost()
        host.travel = 340
        host.isRightToLeft = true
        host.install(host: root, window: window, page: page)
        host.state.begin(eligible: true)
        host.state.drag(displacement: 170, travel: 340)
        XCTAssertEqual(page.offset, -170, accuracy: 0.5)
    }

    /// The drawer is presented on the flag, once: a drag that never crosses keeps it shut.
    func testTheDrawerFollowsTheOpenFlagOnly() {
        let (host, _) = fixture()
        var opened = 0
        host.onOpen = { opened += 1 }

        host.state.begin(eligible: true)
        host.state.drag(displacement: 100, travel: 340)
        host.state.end(velocity: 0, travel: 340, cancelled: false)
        XCTAssertFalse(host.state.isOpen, "a third of the way is not open")
        XCTAssertEqual(opened, 0, "a third of the way is not open")
        // Every end leaves a settlement behind (SidebarDragState:78) and a gesture may not
        // start while one is settling (:49, zen's :58). The host reports the end back when
        // its animation lands; here that is done by hand, so the second drag below starts
        // on a free machine instead of racing a 0.22s animation.
        settle(host)

        host.state.begin(eligible: true)
        host.state.drag(displacement: 340, travel: 340)
        host.state.end(velocity: 0, travel: 340, cancelled: false)
        XCTAssertTrue(host.state.isOpen, "a full travel is past the half")
        XCTAssertEqual(opened, 1)
    }

    /// The call the host makes when the settlement animation finishes.
    private func settle(_ host: SidebarHost) {
        if let settlement = host.state.settlementID {
            host.state.completeSettlement(settlement)
        }
        XCTAssertNil(host.state.settlementID, "the settlement owns the gesture until it ends")
    }
}
