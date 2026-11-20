import CoreGraphics
import Foundation
import Testing
@testable import Sumly

@Test func navigatorHandleHitTargetsAre48ptBy48pt() {
    #expect(ChartRangeNavigatorLayout.handleHitWidth == 48)
    #expect(ChartRangeNavigatorLayout.trackHeight == 48)
    #expect(ChartRangeNavigatorLayout.handleVisualWidth < ChartRangeNavigatorLayout.handleHitWidth)
    #expect(ChartRangeNavigatorLayout.dragMinimumDistance == 0)
}

@Test func fullRangeSelectionProvidesFull48ptHandlesAndWidePanWindow() {
    let bounds = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1000)
    let layout = ChartRangeNavigatorLayout(trackWidth: 357, bounds: bounds, window: bounds)

    #expect(layout.startHandleHitRange == 0...48)
    #expect(layout.endHandleHitRange == 309...357)
    #expect(layout.windowHitRange == 48...309)
    #expect(layout.interactiveRange == 0...357)

    #expect(layout.hitPart(at: 0) == .start)
    #expect(layout.hitPart(at: 24) == .start)
    #expect(layout.hitPart(at: 48) == .start)
    #expect(layout.hitPart(at: 49) == .window)
    #expect(layout.hitPart(at: 180) == .window)
    #expect(layout.hitPart(at: 308) == .window)
    #expect(layout.hitPart(at: 309) == .end)
    #expect(layout.hitPart(at: 357) == .end)
}

@Test func centeredSelectionExpands48ptHandlesAroundEdgesAndLeavesDimmedTrackUntouched() {
    let bounds = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1000)
    let window = Date(timeIntervalSince1970: 300)...Date(timeIntervalSince1970: 700)
    let layout = ChartRangeNavigatorLayout(trackWidth: 400, bounds: bounds, window: window)

    #expect(layout.boxRange == 120...280)
    #expect(layout.startHandleHitRange == 96...144)
    #expect(layout.windowHitRange == 144...256)
    #expect(layout.endHandleHitRange == 256...304)
    #expect(layout.startHandleHitRange.upperBound - layout.startHandleHitRange.lowerBound == 48)
    #expect(layout.endHandleHitRange.upperBound - layout.endHandleHitRange.lowerBound == 48)

    // Visual handles must remain strictly inside their 48pt hit targets.
    #expect(layout.startHandleHitRange.contains(layout.startHandleVisualRange.lowerBound))
    #expect(layout.startHandleHitRange.contains(layout.startHandleVisualRange.upperBound))
    #expect(layout.endHandleHitRange.contains(layout.endHandleVisualRange.lowerBound))
    #expect(layout.endHandleHitRange.contains(layout.endHandleVisualRange.upperBound))

    // Dimmed regions outside the interactive envelope return nil so parent ScrollView can scroll freely.
    #expect(layout.hitPart(at: 40) == nil)
    #expect(layout.hitPart(at: 95.5) == nil)
    #expect(layout.hitPart(at: 96) == .start)
    #expect(layout.hitPart(at: 120) == .start)
    #expect(layout.hitPart(at: 200) == .window)
    #expect(layout.hitPart(at: 280) == .end)
    #expect(layout.hitPart(at: 304) == .end)
    #expect(layout.hitPart(at: 304.5) == nil)
    #expect(layout.hitPart(at: 380) == nil)
}

@Test func narrowSelectionNeverOverlapsHandlesOrLocksOutWindowPanning() throws {
    let bounds = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 100_000)
    let positions: [ClosedRange<Date>] = [
        Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 10),         // pinned left
        Date(timeIntervalSince1970: 5_000)...Date(timeIntervalSince1970: 5_010), // near left
        Date(timeIntervalSince1970: 50_000)...Date(timeIntervalSince1970: 50_010), // centered
        Date(timeIntervalSince1970: 95_000)...Date(timeIntervalSince1970: 95_010), // near right
        Date(timeIntervalSince1970: 99_990)...Date(timeIntervalSince1970: 100_000) // pinned right
    ]

    for window in positions {
        let layout = ChartRangeNavigatorLayout(trackWidth: 339, bounds: bounds, window: window)
        let startWidth = layout.startHandleHitRange.upperBound - layout.startHandleHitRange.lowerBound
        let endWidth = layout.endHandleHitRange.upperBound - layout.endHandleHitRange.lowerBound

        #expect(abs(startWidth - 48) < 0.001)
        #expect(abs(endWidth - 48) < 0.001)
        #expect(layout.startHandleHitRange.upperBound < layout.endHandleHitRange.lowerBound)

        let windowRange = try #require(layout.windowHitRange)
        #expect(windowRange.upperBound - windowRange.lowerBound >= ChartRangeNavigatorLayout.minimumWindowHitWidth)
        #expect(windowRange.lowerBound == layout.startHandleHitRange.upperBound)
        #expect(windowRange.upperBound == layout.endHandleHitRange.lowerBound)

        // Visual centers of start handle, window, and end handle must always hit their own part.
        let startVisualCenter = (layout.startHandleVisualRange.lowerBound + layout.startHandleVisualRange.upperBound) / 2
        let boxCenter = (layout.boxRange.lowerBound + layout.boxRange.upperBound) / 2
        let endVisualCenter = (layout.endHandleVisualRange.lowerBound + layout.endHandleVisualRange.upperBound) / 2

        #expect(layout.hitPart(at: startVisualCenter) == .start)
        #expect(layout.hitPart(at: boxCenter) == .window)
        #expect(layout.hitPart(at: endVisualCenter) == .end)
    }
}

@Test func compactTrackDegradesGracefullyWithoutOverlapOrOutOfBounds() {
    let bounds = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1000)
    let narrowWindow = Date(timeIntervalSince1970: 490)...Date(timeIntervalSince1970: 510)

    for width in [CGFloat(90), CGFloat(60), CGFloat(24)] {
        let layout = ChartRangeNavigatorLayout(trackWidth: width, bounds: bounds, window: narrowWindow)
        #expect(layout.startHandleHitRange.lowerBound >= 0)
        #expect(layout.endHandleHitRange.upperBound <= width)
        #expect(layout.startHandleHitRange.upperBound <= layout.endHandleHitRange.lowerBound)

        let startMid = (layout.startHandleHitRange.lowerBound + layout.startHandleHitRange.upperBound) / 2
        let endMid = (layout.endHandleHitRange.lowerBound + layout.endHandleHitRange.upperBound) / 2
        #expect(layout.hitPart(at: startMid) == .start)
        #expect(layout.hitPart(at: endMid) == .end)
        if let windowRange = layout.windowHitRange {
            let windowMid = (windowRange.lowerBound + windowRange.upperBound) / 2
            #expect(layout.hitPart(at: windowMid) == .window)
        }
    }
}

@Test func invalidInputsAndTranslationFractionsAreHandledSafely() {
    let base = Date(timeIntervalSince1970: 1000)
    let degenerateBounds = base...base
    let layout = ChartRangeNavigatorLayout(trackWidth: 300, bounds: degenerateBounds, window: degenerateBounds)

    #expect(layout.hitPart(at: .nan) == nil)
    #expect(layout.hitPart(at: .infinity) == nil)
    #expect(layout.hitPart(at: -.infinity) == nil)
    #expect(layout.hitPart(at: -1) == nil)
    #expect(layout.hitPart(at: 301) == nil)

    #expect(layout.translationFraction(for: 75) == 0.25)
    #expect(layout.translationFraction(for: -150) == -0.5)
    #expect(layout.translationFraction(for: .nan) == 0)
    #expect(layout.translationFraction(for: .infinity) == 0)
}
