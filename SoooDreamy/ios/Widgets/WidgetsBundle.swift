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
        #if canImport(ActivityKit)
        CountdownLiveActivity()
        CouplePulseLiveActivity()
        #endif
    }
}
