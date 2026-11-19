import XCTest
@testable import DSBot

/// SidebarSurfaceDecoration.swift:5-29 (the page's appearance while the sidebar
/// slides), :34-67 (per-corner radii), :148-227 (the silhouettes). Zen's numbers are
/// asserted as numbers: 0.10 in dark, 0.06 in light, an 0.08 tint, a 0.75pt outline.
@MainActor
final class SidebarDecorationTests: XCTestCase {
    func testThePageAppearanceIsZensOwnNumbers() {
        let closed = SidebarPageAppearance(progress: 0, dark: false, reduceTransparency: false)
        XCTAssertEqual(closed.surfaceOpacity, 1)
        XCTAssertEqual(closed.tintOpacity, 0)
        XCTAssertEqual(closed.outlineOpacity, 0)

        let openLight = SidebarPageAppearance(progress: 1, dark: false, reduceTransparency: false)
        XCTAssertEqual(openLight.surfaceOpacity, 0.94, accuracy: 0.0001, "1 - 1 * 0.06")
        XCTAssertEqual(openLight.tintOpacity, 0, "the light appearance takes no tint")
        XCTAssertEqual(openLight.outlineOpacity, 1)

        let openDark = SidebarPageAppearance(progress: 1, dark: true, reduceTransparency: false)
        XCTAssertEqual(openDark.surfaceOpacity, 0.90, accuracy: 0.0001, "1 - 1 * 0.10")
        XCTAssertEqual(openDark.tintOpacity, 0.08, accuracy: 0.0001)
        XCTAssertEqual(openDark.outlineOpacity, 1)

        let half = SidebarPageAppearance(progress: 0.5, dark: true, reduceTransparency: false)
        XCTAssertEqual(half.surfaceOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(half.tintOpacity, 0.04, accuracy: 0.0001)
        XCTAssertEqual(half.outlineOpacity, 0.5, accuracy: 0.0001)

        let solid = SidebarPageAppearance(progress: 1, dark: true, reduceTransparency: true)
        XCTAssertEqual(solid.surfaceOpacity, 1, "Reduce Transparency keeps the page solid")
        XCTAssertEqual(solid.tintOpacity, 0.08, accuracy: 0.0001)

        let broken = SidebarPageAppearance(progress: .nan, dark: true, reduceTransparency: false)
        XCTAssertEqual(broken.surfaceOpacity, 1)
        XCTAssertEqual(broken.outlineOpacity, 0)
    }

    /// :26-27: the tint is added towards white once, not multiplied by the page alpha
    /// on top of it.
    func testTheTintMovesTheSurfaceTowardsTheTintOnce() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let dark = SidebarPageAppearance(progress: 1, dark: true, reduceTransparency: false)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(dark.surfaceColor(resolving: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let base = UIColor.systemBackground.resolvedColor(with: traits)
        var baseRed: CGFloat = 0, baseGreen: CGFloat = 0, baseBlue: CGFloat = 0, baseAlpha: CGFloat = 0
        base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha)
        XCTAssertEqual(red, baseRed + (1 - baseRed) * 0.08, accuracy: 0.001)
        XCTAssertEqual(alpha, baseAlpha, accuracy: 0.001)
    }

    /// :40-58: the corner mask says which corners round, and one radius or none is
    /// uniform enough for a layer to draw.
    func testTheCornerMaskDecidesWhichCornersRound() {
        let top = SurfaceCornerRadii(uniform: 20, corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        XCTAssertEqual(top.topLeft, 20)
        XCTAssertEqual(top.topRight, 20)
        XCTAssertEqual(top.bottomLeft, 0)
        XCTAssertEqual(top.bottomRight, 0)
        XCTAssertTrue(top.isUniform)

        XCTAssertTrue(SurfaceCornerRadii(uniform: 0, corners: .allCorners).isUniform)
        XCTAssertFalse(SurfaceCornerRadii(topLeft: 20, topRight: 20, bottomLeft: 8, bottomRight: 8).isUniform)
    }

    /// :60-67: the path fills the rect it is asked for, inset and all.
    func testThePathFillsItsRect() {
        let radii = SurfaceCornerRadii(topLeft: 16, topRight: 16, bottomLeft: 8, bottomRight: 8)
        let rect = CGRect(x: 10, y: 20, width: 300, height: 500)
        let path = radii.path(in: rect)
        XCTAssertEqual(path.boundingBoxOfPath.minX, 10, accuracy: 0.5)
        XCTAssertEqual(path.boundingBoxOfPath.maxX, 310, accuracy: 0.5)
        XCTAssertEqual(path.boundingBoxOfPath.minY, 20, accuracy: 0.5)
        XCTAssertEqual(path.boundingBoxOfPath.maxY, 520, accuracy: 0.5)

        let inset = radii.path(in: rect, inset: 4)
        XCTAssertEqual(inset.boundingBoxOfPath.minX, 14, accuracy: 0.5)
        XCTAssertEqual(inset.boundingBoxOfPath.maxX, 306, accuracy: 0.5)

        let square = SurfaceCornerRadii(uniform: 0, corners: .allCorners).path(in: rect)
        XCTAssertEqual(square.boundingBoxOfPath, rect, "no radius is the plain rect")
    }

    /// :164-196: a silhouette is rebuilt when the geometry changes and not again for
    /// the same geometry — the reason the decoration can run on every browse frame.
    func testTheSilhouetteIsRebuiltOnlyWhenGeometryMoves() {
        let decoration = SidebarSurfaceDecoration()
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        let radii = SurfaceCornerRadii(uniform: 55, corners: .allCorners)
        decoration.updateGeometry(surface: surface, radii: radii, direction: 1)
        XCTAssertEqual(decoration.silhouetteBuildCount, 1)
        XCTAssertNotNil(decoration.shadowView.layer.shadowPath)
        XCTAssertEqual(decoration.shadowView.layer.shadowOffset.width, 3, "direction * 3")

        decoration.updateGeometry(surface: surface, radii: radii, direction: 1)
        XCTAssertEqual(decoration.silhouetteBuildCount, 1, "the same geometry is not rebuilt")

        surface.frame = CGRect(x: 0, y: 0, width: 280, height: 800)
        decoration.updateGeometry(surface: surface, radii: radii, direction: -1)
        XCTAssertEqual(decoration.silhouetteBuildCount, 2)
        XCTAssertEqual(decoration.shadowView.layer.shadowOffset.width, -3)
    }

    /// :214-227: a closed sidebar may not overwrite an appearance somebody else owns.
    func testAClosedSidebarLeavesAnOwnedAppearanceAlone() {
        let decoration = SidebarSurfaceDecoration()
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        decoration.install(on: surface)
        let traits = UITraitCollection(userInterfaceStyle: .light)
        decoration.applyAppearance(surface: surface, progress: 0.5, traits: traits)
        XCTAssertEqual(surface.alpha, 0.97, accuracy: 0.001)
        XCTAssertEqual(decoration.outlineAlpha, 0.5, accuracy: 0.001)

        surface.alpha = 0.8
        decoration.applyAppearance(surface: surface, progress: 0, traits: traits)
        XCTAssertEqual(surface.alpha, 0.8, accuracy: 0.001, "nothing was owned at 0, so nothing changed")
        XCTAssertEqual(decoration.outlineAlpha, 0.5, accuracy: 0.001)

        decoration.applyAppearance(surface: surface, progress: 0.25, traits: traits)
        decoration.applyAppearance(surface: surface, progress: 0, traits: traits)
        XCTAssertEqual(surface.alpha, 1, accuracy: 0.001, "after owning it, closing restores the page")
        XCTAssertEqual(decoration.outlineAlpha, 0, accuracy: 0.001)
    }
}
