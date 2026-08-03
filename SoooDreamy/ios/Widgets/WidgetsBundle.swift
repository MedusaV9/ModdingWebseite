import WidgetKit
import SwiftUI

@main
struct SoooDreamyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DaysTogetherWidget()
        MoodWidget()
        CountdownWidget()
        DailyQuestionWidget()
        #if canImport(ActivityKit)
        CountdownLiveActivity()
        #endif
    }
}
