import Foundation

/// How long keep-awake has been on, shown as the lamp's beam aging.
enum LampStage: Equatable {
    case fresh, dimmer, flicker

    /// Stage thresholds, measured from when the current activation began.
    static let dimmerAfter: TimeInterval = 3 * 60 * 60
    static let flickerAfter: TimeInterval = 6 * 60 * 60

    static func `for`(elapsed: TimeInterval) -> LampStage {
        if elapsed >= flickerAfter { return .flicker }
        if elapsed >= dimmerAfter { return .dimmer }
        return .fresh
    }
}
