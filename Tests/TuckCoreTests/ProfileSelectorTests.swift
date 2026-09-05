import XCTest
@testable import TuckCore

final class ProfileSelectorTests: XCTestCase {
    func testChoosesScreenSlidesForMostlyStaticContent() {
        let profile = CompressionProfileSelector.choose(
            for: mediaInfo(width: 1_920, height: 1_080),
            motion: MotionSummary(
                sampledFrameCount: 12,
                averagePixelDelta: 0.004,
                p90PixelDelta: 0.01,
                movingFrameRatio: 0
            )
        )

        XCTAssertEqual(profile, .screenSlides)
    }

    func testChoosesMixedGeneralForMotionBelow4K() {
        let profile = CompressionProfileSelector.choose(
            for: mediaInfo(width: 1_920, height: 1_080),
            motion: MotionSummary(
                sampledFrameCount: 12,
                averagePixelDelta: 0.05,
                p90PixelDelta: 0.08,
                movingFrameRatio: 0.7
            )
        )

        XCTAssertEqual(profile, .mixedGeneral)
    }

    func testChoosesHevcForSustained4KMotion() {
        let profile = CompressionProfileSelector.choose(
            for: mediaInfo(width: 3_840, height: 2_160),
            motion: MotionSummary(
                sampledFrameCount: 12,
                averagePixelDelta: 0.05,
                p90PixelDelta: 0.08,
                movingFrameRatio: 0.7
            )
        )

        XCTAssertEqual(profile, .highMotionDynamic4K)
    }

    func testFallsBackToMixedGeneralWithoutReliableMotionSamples() {
        let profile = CompressionProfileSelector.choose(
            for: mediaInfo(width: 1_920, height: 1_080),
            motion: nil
        )

        XCTAssertEqual(profile, .mixedGeneral)
    }

    private func mediaInfo(width: Int, height: Int) -> MediaInfo {
        MediaInfo(
            videoCodec: "h264",
            width: width,
            height: height,
            frameRate: 30,
            duration: 10,
            audioStreams: [AudioStreamInfo(index: 1, codecName: "aac")],
            subtitleStreams: [],
            fileSize: 1_000_000
        )
    }
}
