import SwiftUI

// "Euer erster Moment" — the ONE focused stage a brand-new couple sees
// (DashboardPriority.firstMomentPending). Instead of eight competing cards,
// fresh couples get a single invitation: the first daily question with the
// answer composer DIRECTLY on the sheet (re-eval №5 — focus, send: two
// interactions, never an "Antworten" detour and never a second bright
// daily card stacked under the stage), plus the first greeting as the
// quiet secondary call. The moment happens, the stage retires and the
// normal rhythm begins.

struct FirstMomentCard: View {
    /// The Zustellrunden stamp line ON the sheet ("MORGENPOST · TAG 137")
    /// — since the day letter is ALWAYS the stamped hero (re-eval №2),
    /// the first Briefbogen carries the same printed head as the daily
    /// card. Nil while the rounds are off.
    var rundenStempel: String?

    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    /// Secondary call taken: the greeting is out; the button becomes the
    /// confirmation so the moment reads as "done", not as a dead control.
    @State private var greetingSent = false

    var body: some View {
        stage
    }

    /// The REAL first question, from the same source the DailyQuestionCard
    /// reads (ContentPack + the server-pinned id/text when an entry already
    /// exists) — the stage shows the actual invitation, never a generic
    /// teaser, and the embedded composer answers exactly this question.
    private var question: DailyQuestion? {
        guard let couple = appState.couple else { return nil }
        let entry = appState.dailyEntry?.dateKey == SharedDates.todayKey()
            ? appState.dailyEntry : nil
        return ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(),
                                         coupleId: couple.id,
                                         pinnedId: entry?.questionId,
                                         pinnedText: entry?.questionText)
    }

    /// The "TAG {n}" postmark of the Briefbogen (daysTogether biography) —
    /// only while the Stempelzeile does not already print the day count
    /// (the number never appears twice, same law as the daily hero).
    private var heroStamp: String? {
        guard rundenStempel == nil,
              let days = appState.daysTogether, days > 0 else { return nil }
        return L10n.t("home.stamp.day", ["n": String(days)])
    }

    private var stage: some View {
        VStack(spacing: Space.m) {
            if let rundenStempel {
                // Fix2-A №1: the first Briefbogen carries the same wax
                // seal in its top-left corner — the printed head starts
                // clear of the overhang (decor never eats information).
                StempelzeileView(text: rundenStempel)
                    .padding(.leading, BriefbogenDekor.stempelEinzug(
                        contentPadding: CardPadding.hero.value))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Seal wax instead of lamp gold — gold never marks paper
            // (1.4:1); the warm glow stays BEHIND the glyph (legal role).
            Image(systemName: "sparkles")
                .font(.system(.largeTitle).weight(.semibold))
                .foregroundStyle(coupleTint.tinte)
                .shadow(color: Theme.gold.opacity(0.5), radius: LayoutMetrics.s(14))
                .accessibilityHidden(true)

            Text(L10n.t("firstMoment.title"))
                .font(Typo.title)
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)

            Text(L10n.t("firstMoment.subtitle", ["name": appState.partnerName]))
                .font(Typo.label)
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The question lives on the stage in the day's serif voice —
            // and the ink well sits DIRECTLY beneath it: the first answer
            // is written on the first Briefbogen itself.
            if let question {
                let custom = appState.dailyEntry?.customQuestion
                Text(custom?.text
                     ?? question.text.filled(partner: appState.partnerName,
                                             lang: L10n.lang))
                    .font(Typo.voice)
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.innenFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control,
                                                 style: .continuous)
                                    .strokeBorder(Papier.kante,
                                                  lineWidth: Theme.hairlineWidth))
                    )
                DailyAnswerComposer(question: question)
            }

            if greetingSent {
                Label(L10n.t("firstMoment.greetingSent", ["name": appState.partnerName]),
                      systemImage: "checkmark.heart.fill")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.sekundaer)
            } else {
                Button {
                    appState.sendTouch(.heartbeat)
                    withAnimation(Theme.Motion.settle) { greetingSent = true }
                } label: {
                    Label(L10n.t("firstMoment.secondary"), systemImage: "heart.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("home.firstGreeting")
            }
        }
        // iPad: the words and CTAs hold a readable ~640 pt column while the
        // hero SURFACE keeps the full width — margin inside, not zoom.
        .contentColumn(.reading)
        .frame(maxWidth: .infinity)
        .paperCard(.briefbogen, padding: .hero)
        .briefbogenDekor(stamp: heroStamp)
    }
}
