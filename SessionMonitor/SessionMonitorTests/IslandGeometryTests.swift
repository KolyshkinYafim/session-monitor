import XCTest

/// Layout arithmetic for the island strip and panels. These are pure functions of
/// `Metrics` + theme constants, so every expectation below is a hand-computed number
/// derived from the constants in `IslandTheme` — if a constant changes on purpose,
/// the test documents what else moves with it.
final class IslandGeometryTests: XCTestCase {
    private func metrics(
        menuBar: CGFloat = 24,
        notch: CGFloat = 190,
        hasNotch: Bool = true,
        heightOffset: CGFloat = 0,
        screenWidth: CGFloat = 0
    ) -> IslandGeometry.Metrics {
        IslandGeometry.Metrics(
            menuBarHeight: menuBar,
            notchWidth: notch,
            hasNotch: hasNotch,
            heightOffset: heightOffset,
            screenWidth: screenWidth
        )
    }

    // MARK: - estimatedNotchWidth

    func testEstimatedNotchWidthWithoutNotchIsSmallGap() {
        XCTAssertEqual(IslandGeometry.estimatedNotchWidth(screenWidth: 1512, hasNotch: false), 16)
    }

    func testEstimatedNotchWidthClampsToMinimum() {
        // 1400 * 0.103 = 144.2 — below the 170 floor.
        XCTAssertEqual(IslandGeometry.estimatedNotchWidth(screenWidth: 1400, hasNotch: true), 170)
    }

    func testEstimatedNotchWidthIsProportionalInsideClampBand() {
        // 1800 * 0.103 = 185.4 → rounded 185.
        XCTAssertEqual(IslandGeometry.estimatedNotchWidth(screenWidth: 1800, hasNotch: true), 185)
    }

    func testEstimatedNotchWidthClampsToMaximum() {
        // 2400 * 0.103 = 247.2 — above the 220 ceiling.
        XCTAssertEqual(IslandGeometry.estimatedNotchWidth(screenWidth: 2400, hasNotch: true), 220)
    }

    // MARK: - Metrics derived values

    func testStripHeightEnforcesMinimumMenuBarHeight() {
        // max(24, 28) + stripHang(2) = 30.
        XCTAssertEqual(metrics(menuBar: 24).stripHeight, 30)
    }

    func testStripHeightAddsHeightOffset() {
        // max(38 + 4, 28) + 2 = 44.
        XCTAssertEqual(metrics(menuBar: 38, heightOffset: 4).stripHeight, 44)
    }

    func testUsableStripWidthIsZeroWhenScreenUnknown() {
        XCTAssertEqual(metrics(screenWidth: 0).usableStripWidth, 0)
    }

    func testUsableStripWidthSubtractsEdgeMargins() {
        // 1000 - 24*2 = 952.
        XCTAssertEqual(metrics(screenWidth: 1000).usableStripWidth, 952)
    }

    func testUsableStripWidthNeverShrinksBelowNotch() {
        // 200 - 48 = 152 < notch 190 → 190.
        XCTAssertEqual(metrics(notch: 190, screenWidth: 200).usableStripWidth, 190)
    }

    // MARK: - compactWidth / stripWingWidth

    func testCompactWidthCleanIsNotchPlusTwoWings() {
        // 190 + 64*2 = 318 (no screen budget → unclamped).
        let width = IslandGeometry.compactWidth(metrics: metrics(), scale: 1.0, style: .clean)
        XCTAssertEqual(width, 318)
    }

    func testCompactWidthDetailedIsClampedToScreenBudget() {
        // Full detailed width 190 + 168*2 = 526; budget max(400-48, 190) = 352 wins.
        let m = metrics(screenWidth: 400)
        let width = IslandGeometry.compactWidth(metrics: m, scale: 1.0, style: .detailed)
        XCTAssertEqual(width, 352)
    }

    func testStripWingWidthIsHalfOfWhatRemainsBesideNotch() {
        // (352 - 190) / 2 = 81.
        let m = metrics(screenWidth: 400)
        XCTAssertEqual(IslandGeometry.stripWingWidth(metrics: m, scale: 1.0, style: .detailed), 81)
    }

    func testStripWingWidthNeverGoesNegative() {
        // Budget clamps the whole strip to the notch width → zero-width wings, not negative.
        let m = metrics(notch: 300, screenWidth: 200)
        XCTAssertEqual(IslandGeometry.stripWingWidth(metrics: m, scale: 1.0, style: .detailed), 0)
    }

    // MARK: - rowHeight / visibleRows

    func testRowHeightAtBaseFontWithoutPath() {
        XCTAssertEqual(IslandGeometry.rowHeight(contentFontSize: 12.5, showsPath: false), 64)
    }

    func testRowHeightGrowsWithFontAndPathLine() {
        // 64 + (14.5 - 12.5) * 3 + 15 = 85.
        XCTAssertEqual(IslandGeometry.rowHeight(contentFontSize: 14.5, showsPath: true), 85)
    }

    func testVisibleRowsForDefaultPanelHeight() {
        // chrome = 10*2 + 40 + 32 + 8 = 100; (460-100)/64 = 5.6 → 5.
        XCTAssertEqual(IslandGeometry.visibleRows(maxPanelHeight: 460, rowHeight: 64), 5)
    }

    func testVisibleRowsNeverDropsBelowOne() {
        XCTAssertEqual(IslandGeometry.visibleRows(maxPanelHeight: 50, rowHeight: 64), 1)
    }

    func testVisibleRowsIsCappedAtMiniRowCount() {
        XCTAssertEqual(IslandGeometry.visibleRows(maxPanelHeight: 2000, rowHeight: 64), IslandTheme.miniRowCount)
    }

    // MARK: - size(for:)

    func testCompactSizeUsesStripHeightAndCompactWidth() {
        let size = IslandGeometry.size(for: .compact, metrics: metrics(), widthScale: 1.0, sessionRows: 0)
        XCTAssertEqual(size, CGSize(width: 318, height: 30))
    }

    func testWidthScaleIsClampedToUpperBound() {
        // Scale 2.0 clamps to 1.2: 190 + 128*1.2 = 343.6 → 344.
        let size = IslandGeometry.size(for: .compact, metrics: metrics(), widthScale: 2.0, sessionRows: 0)
        XCTAssertEqual(size.width, 344)
    }

    func testWidthScaleIsClampedToLowerBound() {
        // Scale 0.5 clamps to 0.9: 190 + 128*0.9 = 305.2 → 305.
        let size = IslandGeometry.size(for: .compact, metrics: metrics(), widthScale: 0.5, sessionRows: 0)
        XCTAssertEqual(size.width, 305)
    }

    func testActivitySizeGrowsWithRowsAndPendingDecisions() {
        // strip 30 + rows 3*64 + one decision row (38+6) + listPad 20 + newButton 40 + 8 = 334.
        let size = IslandGeometry.size(
            for: .activity,
            metrics: metrics(),
            widthScale: 1.0,
            sessionRows: 3,
            pendingRows: 1,
            rowHeight: 64,
            panelWidth: 420,
            maxPanelHeight: 340
        )
        XCTAssertEqual(size, CGSize(width: 420, height: 334))
    }

    func testActivitySizeIsCappedByMaxPanelHeight() {
        // 8 rows * 64 + 20 + 40 + 8 = 580 → capped at 340; 30 + 340 = 370.
        let size = IslandGeometry.size(
            for: .activity,
            metrics: metrics(),
            widthScale: 1.0,
            sessionRows: 8,
            rowHeight: 64,
            panelWidth: 420,
            maxPanelHeight: 340
        )
        XCTAssertEqual(size.height, 370)
    }

    func testExpandedSizeUsesMaxPanelHeightFloor() {
        // max(500, boardMinHeight 340) = 500; strip 30 → 530.
        let size = IslandGeometry.size(
            for: .expanded,
            metrics: metrics(),
            widthScale: 1.0,
            sessionRows: 0,
            panelWidth: 420,
            maxPanelHeight: 500
        )
        XCTAssertEqual(size, CGSize(width: 420, height: 530))
    }
}
