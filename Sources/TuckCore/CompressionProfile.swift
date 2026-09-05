import Foundation

public enum VideoEncoder: Equatable, Sendable {
    case h264
    case hevc
}

public enum CompressionProfile: String, CaseIterable, Equatable, Sendable {
    case screenSlides
    case mixedGeneral
    case highMotionDynamic4K

    public var displayName: String {
        switch self {
        case .screenSlides:
            return "Screen/slides"
        case .mixedGeneral:
            return "Mixed/general"
        case .highMotionDynamic4K:
            return "High-motion 4K"
        }
    }

    public var videoEncoder: VideoEncoder {
        switch self {
        case .screenSlides, .mixedGeneral:
            return .h264
        case .highMotionDynamic4K:
            return .hevc
        }
    }

    public var crf: Int {
        switch self {
        case .screenSlides:
            return 28
        case .mixedGeneral:
            return 24
        case .highMotionDynamic4K:
            return 26
        }
    }

    public var preset: String {
        switch self {
        case .screenSlides, .mixedGeneral:
            return "slow"
        case .highMotionDynamic4K:
            return "medium"
        }
    }

    public var audioBitrate: String {
        switch self {
        case .screenSlides:
            return "96k"
        case .mixedGeneral, .highMotionDynamic4K:
            return "128k"
        }
    }
}

public enum CompressionProfileSelector {
    public static func choose(for mediaInfo: MediaInfo, motion: MotionSummary?) -> CompressionProfile {
        guard let motion, motion.sampledFrameCount >= 2 else {
            return .mixedGeneral
        }

        let sustainedMotion = motion.averagePixelDelta >= 0.035 || motion.movingFrameRatio >= 0.55
        if mediaInfo.isFourKOrLarger && sustainedMotion {
            return .highMotionDynamic4K
        }

        let mostlyStatic = motion.averagePixelDelta <= 0.012 && motion.p90PixelDelta <= 0.025
        if mostlyStatic {
            return .screenSlides
        }

        return .mixedGeneral
    }
}
