import WidgetKit
import SwiftUI

@main
struct SoooDreamyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DaysTogetherWidget()
        MoodWidget()
        CountdownWidget()
        DailyQuestionWidget()
        StreakWidget()
        PhotoWidget()
        CanvasWidget()
        SendLoveWidget()
        MemoryWidget()   // „An diesem Tag"
        #if canImport(ActivityKit)
        CountdownLiveActivity()
        CouplePulseLiveActivity()
        DateNightLiveActivity()   // Date night
        #endif
        // Controls — Control Center / Lock Screen /
        // Action Button. iOS 26-only app → no availability gates.
        HeartbeatControlWidget()
        OpenNeedButtonControlWidget()
        ThinkingOfYouControlWidget()
        StartDateNightControlWidget()
        // W7: the evening ritual + the only control with real state.
        GoodNightControlWidget()
        SleepPresenceControlWidget()
    }
}
