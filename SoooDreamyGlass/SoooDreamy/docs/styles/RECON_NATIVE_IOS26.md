# RECON: Native iOS-26-TabView & System-Komponenten — Migrations-Dossier

Platform-Recon für die Migration der Custom-`LiquidTabBar` auf die echte native
iOS-26-`TabView` mit System-Liquid-Glass, plus Sweep-Katalog für mehr echte
Apple-Systemkomponenten, Layered-App-Icon-Strategie und iOS-26-Perlen.

**Rahmenbedingungen** (aus `ios/project.yml` und `.github/workflows/sooodreamy.yml`):
Deployment-Target **iOS 26.0**, CI baut auf **macos-26** (Xcode 26.x, iOS-26-SDK),
keine `#available(iOS 26)`-Gates nötig. XcodeGen kommt per `brew install xcodegen`
(also latest release). iPhone portrait-only, iPad alle Orientierungen ohne
`UIRequiresFullScreen`.

**Quellen-Disziplin:** Jede API-Behauptung trägt eine Apple-Doku-URL oder ist
explizit als *im SDK zu verifizieren* markiert. Community-Quellen sind als solche
gekennzeichnet und nur Ergänzung, nie alleinige Grundlage.

---

## 1. iOS-26-TabView-API-Inventar

### 1.1 Kern-Container: `TabView` + `Tab`-Builder (iOS 18+, Optik iOS 26)

Der deklarative `Tab`-Builder existiert seit iOS 18; die Liquid-Glass-Optik
(schwebende Kapsel, Morph-Verhalten, Search-Kreis) kommt in iOS 26 **automatisch**
für jede `TabView` — kein Opt-in nötig, solange man nicht gegen UIKit-Appearance
ankämpft.

| API | Signatur | Verfügbar ab | Quelle |
|---|---|---|---|
| `Tab`-Init mit Wert | `init(_ title: LocalizedStringKey, systemImage: String, value: Value, @ViewBuilder content: () -> Content)` (+ `StringProtocol`-Overload für unsere `L10n.t`-Strings) | iOS 18.0 | [Tab/init(_:systemImage:value:content:)](https://developer.apple.com/documentation/swiftui/tab/init(_:systemimage:value:content:)) |
| `Tab` mit Rolle | `init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content)` — `TabRole.search` für den abgesetzten Such-Kreis | iOS 18.0 (`TabRole.search` ebenfalls 18.0; der **abgesetzte Kreis + Morph zur Suchleiste** ist iOS-26-Systemoptik) | [TabRole](https://developer.apple.com/documentation/swiftui/tabrole), [WWDC25 #323, 13:17](https://developer.apple.com/videos/play/wwdc2025/323/) |
| Auswahl-Binding | `TabView(selection: $someHashable) { … }` — unser `AppTab` (`String`-RawValue, `Hashable`, `AppState.swift:12`) taugt direkt als `value` | iOS 18 (Tab-Builder-Variante) | [TabView](https://developer.apple.com/documentation/swiftui/tabview) |
| Badge | `TabContent.badge(_: Int)` / `badge(_: LocalizedStringKey)` / `badge(_: Text?)` — `0` bzw. `nil` versteckt das Badge | iOS 18.0 (TabContent-Variante; das View-`badge` gibt es seit iOS 15) | [TabContent/badge(_:)](https://developer.apple.com/documentation/swiftui/tabcontent/badge(_:)) |

### 1.2 iOS-26-Verhalten der Bar

| API | Signatur | Verfügbar ab | Quelle |
|---|---|---|---|
| Bar-Minimieren beim Scrollen | `func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View`; Werte: `.automatic`, `.never`, `.onScrollDown`, `.onScrollUp` | **iOS 26.0** (iPadOS/macOS/tvOS/visionOS/watchOS 26) | [tabBarMinimizeBehavior(_:)](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)), [TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior) |
| Bottom-Accessory | `func tabViewBottomAccessory<Content: View>(@ViewBuilder content: () -> Content) -> some View` und `func tabViewBottomAccessory<Content: View>(isEnabled: Bool, @ViewBuilder content: () -> Content) -> some View` | **iOS 26.0** (die `isEnabled:`-Variante ist in der Apple-Doku bestätigt; ob sie erst 26.1 kam: *im SDK zu verifizieren*) | [tabViewBottomAccessory(isEnabled:content:)](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)) |
| Accessory-Platzierung | `@Environment(\.tabViewBottomAccessoryPlacement)` → `TabViewBottomAccessoryPlacement?` mit `.expanded` (über der Bar) und `.inline` (in der minimierten Bar neben dem Rest-Tab) | **iOS 26.0** | [TabViewBottomAccessoryPlacement](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement) |
| Search-Aktivierung | `func tabViewSearchActivation(_ activation: TabSearchActivation) -> some View` — z. B. `.searchTabSelection` (Suchfeld aktiviert sich schon bei Auswahl des Search-Tabs; Default: nur der Nutzer aktiviert). Vollständige Case-Liste von `TabSearchActivation`: *im SDK zu verifizieren* | **iOS 26.0** | [tabViewSearchActivation(_:)](https://developer.apple.com/documentation/swiftui/view/tabviewsearchactivation(_:)) |
| Bar-Placement lesen | `@Environment(\.tabBarPlacement)`, `@Environment(\.isTabBarShowingSections)` | iOS 26 laut Doku-Nachbarschaft der Minimize-API; *im SDK zu verifizieren* | [TabBarPlacement](https://developer.apple.com/documentation/swiftui/tabbarplacement) |

Wichtig für Accessory-Inhalte: Das Accessory ist eine **volle-Breite-Glaskapsel
über der Bar** (Vorbild „Now Playing" in Music) — kein frei positionierbarer
Einzelknopf. Auf iPhone wandert es beim Minimieren der Bar `inline` neben den
verbleibenden Tab; das eigene Layout muss über das Placement-Environment beide
Formen bedienen ([Doku-Discussion](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:))).

### 1.3 iPad: `sidebarAdaptable` + Nutzer-Customization

| API | Signatur | Verfügbar ab | Quelle |
|---|---|---|---|
| Sidebar-fähiger Stil | `.tabViewStyle(.sidebarAdaptable)` | iOS 18.0 | [sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable) |
| Persistenz-Objekt | `struct TabViewCustomization` (`@AppStorage`-fähig), angehängt via `.tabViewCustomization($customization)` | iOS 18.0 / iPadOS 18.0 / macOS 15 | [TabViewCustomization](https://developer.apple.com/documentation/swiftui/tabviewcustomization), [tabViewCustomization(_:)](https://developer.apple.com/documentation/swiftui/view/tabviewcustomization(_:)) |
| Identität | `TabContent.customizationID(_ id: String)` — Pflicht für jeden anpassbaren Tab/`TabSection` | iOS 18.0 | [TabViewCustomization-Doku](https://developer.apple.com/documentation/swiftui/tabviewcustomization) |
| Verhalten pro Placement | `TabContent.customizationBehavior(_ behavior: TabCustomizationBehavior, for placements: AdaptableTabBarPlacement...)` — `.automatic` / `.reorderable` / `.disabled`, Placements `.sidebar` / `.tabBar` | iOS 18.0 | [customizationBehavior(_:for:)](https://developer.apple.com/documentation/swiftui/tabcontent/customizationbehavior(_:for:)) |
| Default-Sichtbarkeit | `TabContent.defaultVisibility(_:for:)`; `sidebarOnly` als Placement-Beschränkung | iOS 18.0 | [Enhancing your app's content with tab navigation](https://developer.apple.com/documentation/swiftui/enhancing-your-app-content-with-tab-navigation) |
| Drag-Quelle | `TabContent.draggable(_:)` — macht den Tab zur Drag-&-Drop-Quelle für App-Payloads, **nur in der Sidebar** ziehbar | iOS 18.0 | [customizationBehavior-Doku, „See Also“](https://developer.apple.com/documentation/swiftui/tabcontent/customizationbehavior(_:for:)) |

### 1.4 Konkrete Antwort: Welche Drag-Interaktionen bietet die native Bar?

**iPhone (iOS 26): KEINE Nutzer-Drag-Interaktionen an der Tab-Bar.**
Kein Tab-Reorder, kein Herausziehen, kein Edit-Modus. Die Apple-Doku sagt
ausdrücklich: „The `sidebarAdaptable` style supports customization of the tab
bar and sidebar **on iPad**" ([customizationBehavior(_:for:)](https://developer.apple.com/documentation/swiftui/tabcontent/customizationbehavior(_:for:))).
Auf iPhone bleibt die Reihenfolge exakt die des Tab-Builders. Was der Nutzer auf
iPhone „draggen" kann, ist nur indirekt: die Bar minimiert sich beim Scrollen
(`tabBarMinimizeBehavior`) und der Search-Tab morpht ins Suchfeld — beides
system-eigene Gesten, kein Reorder. (Das UIKit-Pendant `UITabBarController.Mode
.tabSidebar` ändert daran nichts — Customization bleibt iPad.)

**iPad (iPadOS 26) mit `.sidebarAdaptable` + `tabViewCustomization`:** alles
out-of-the-box, sobald jeder Tab eine `customizationID` trägt:
- Edit-Modus in der Sidebar (Edit-Button erscheint automatisch);
- Tabs per Drag & Drop **aus der Sidebar in die Tab-Bar** legen und **aus der
  Bar herausziehen**;
- **Reorder innerhalb der Tab-Bar** und innerhalb von Sidebar-Sections;
- Tabs ein-/ausblenden; Reset auf Default;
- Persistenz automatisch über das `TabViewCustomization`-Objekt in `@AppStorage`.
Quellen: [Enhancing your app's content with tab navigation](https://developer.apple.com/documentation/swiftui/enhancing-your-app-content-with-tab-navigation)
(„Drag and drop tabs to remove and add tabs to the tab bar … Reorder tabs in the
tab bar"), [WWDC24 #10147](https://developer.apple.com/videos/play/wwdc2024/10147/).

**macOS (nur der Vollständigkeit halber):** Default-Interaktion nur für
Section-Reorder, Sichtbarkeit einzelner Tabs muss die App selbst anbieten
([TabViewCustomization](https://developer.apple.com/documentation/swiftui/tabviewcustomization)).

**Ohne `.sidebarAdaptable`** (Default-Stil `.automatic`): keinerlei
Customization, auch auf iPad nicht. `customizationBehavior` ist dann laut Doku
wirkungslos („This modifier has no effect on other platforms or on a
TabViewStyle that doesn't support customization").

### 1.5 Ehrlichkeits-Kasten: was vor Baustart im SDK zu verifizieren ist

Billige Verifikation: ein Wegwerf-Swift-File gegen das iOS-26-SDK im
CI-Build-Job kompilieren (kein Simulator nötig).

1. Exakte Case-Liste von `TabSearchActivation` (Doku-Beispiel zeigt
   `.searchTabSelection`; ob es `.automatic`/weitere gibt: prüfen).
2. `tabViewBottomAccessory(isEnabled:content:)` vs. nur `(content:)` — welche
   Overloads das SDK der CI-Xcode-Version wirklich hat.
3. `@Environment(\.tabBarPlacement)` / `isTabBarShowingSections` Verfügbarkeit.
4. Ob `TabContent` einen `accessibilityLabel`-Modifier hat (für unsere
   Unread-Ansage, §2.4) — falls nein, übernimmt das Badge die VoiceOver-Ansage.
5. Lazy-/Keep-Alive-Verhalten der Tab-Inhalte (§2.3) — dokumentiert ist es
   nicht; empirisch per CI-Screenshot-Lauf absichern.
6. Ob die native Bar auf iPad **oben** liegt (iPadOS-18+-Verhalten) — relevant,
   weil unser Dock bisher unten zentriert schwebt; Screenshot-Lauf ansehen.

---

## 2. Migrations-Plan: `LiquidTabBar` → native `TabView`

### 2.1 Ist-Stand (gelesen: `App/RootView.swift`, `UI/LiquidTabBar.swift`, `Content/TabBarLogic.swift`)

`MainTabView` (`RootView.swift:172`) rendert **keine** `TabView`, sondern:
- einen `ZStack` aus fünf lazy-materialisierten, danach am Leben gehaltenen
  Panes (`tabPane`, `visitedTabs`, `RootView.swift:272–285`) mit
  `opacity/zIndex/allowsHitTesting/accessibilityHidden`-Schaltung;
- die `LiquidTabBar` in `safeAreaBar(edge: .bottom)` (`RootView.swift:210`),
  Kapsel + abgesetzter runder „?"-Hilfe-Knopf (`LiquidTabBar.swift:227`);
- Selektion-Linse per `matchedGeometryEffect` (`LiquidTabBar.swift:136`),
  Wiggle-Easteregg per Long-Press (`LiquidTabBar.swift:258`), Badge-Kapseln in
  Pink (`LiquidTabBar.swift:178`), AX5-Icon-only-Modus (`LiquidTabBar.swift:120`),
  iPad-Breitendeckel `LayoutMetrics.dockMax` (`Theme.swift:71`);
- Keyboard-Ausweichen per `keyboardWillShow/Hide`-Notifications
  (`RootView.swift:232–239`);
- Re-Tap → Scroll-to-top über einen UIKit-Window-Walk
  (`RootView.swift:335–362`, Regel in `TabBarLogic.shouldScrollToTop`);
- ⌘1–⌘5-Hardware-Shortcuts über unsichtbare Buttons (`RootView.swift:251`);
- Demo-Badge als `safeAreaBar(edge: .top)` (`RootView.swift:200`) — bleibt.

### 2.2 Ziel-Gerüst (Tab-Mapping)

```swift
TabView(selection: reselectAwareSelection) {          // §2.6 für das Binding
    Tab(L10n.t("tab.home"),  systemImage: "house",                        value: AppTab.home)     { DashboardView() }
    Tab(L10n.t("tab.chat"),  systemImage: "bubble.left.and.bubble.right", value: AppTab.chat)     { ChatView() }
        .badge(TabBarLogic.badgeText(for: appState.unreadChat) ?? "")     // „99+“-Deckel bleibt Logik
    Tab(L10n.t("tab.play"),  systemImage: "gamecontroller",               value: AppTab.play)     { PlayHubView() }
        .badge(TabBarLogic.badgeText(for: appState.gamesAwaitingMe.count) ?? "")
    Tab(L10n.t("tab.us"),    systemImage: "heart.text.square",            value: AppTab.memories) { MemoriesView() }
    Tab(L10n.t("tab.more"),  systemImage: "ellipsis.circle",              value: AppTab.settings) { SettingsView() }
}
.tabBarMinimizeBehavior(.onScrollDown)
.tint(CoupleTint(palette: appState.couple?.palette).blend)
```

Hinweise:
- Die Outline/Fill-Icon-Paare (`house` vs. `house.fill`) entfallen: das System
  rendert den selektierten Zustand selbst (SF-Symbols-Variantenwahl übernimmt
  die Bar). Kein eigener `selectedIcon` mehr.
- `AppTab` bleibt unverändert Selektionstyp; alle `appState.activeTab`-Konsumenten
  (HandbookView-Anker, Unread-Reset in `onChange`) funktionieren weiter.
- Badge als `String` statt `Int`, damit unser „99+"-Deckel
  (`TabBarLogic.badgeText`, LogicTest-gepinnt) erhalten bleibt. Leerstring vs.
  `Text?`-nil zum Verstecken: beide Overloads gegen das SDK prüfen (§1.5.4);
  notfalls `badge(count)` mit Int und den 99+-Deckel aufgeben.

### 2.3 Lazy-Pane-Lebensdauer

Erwartetes natives Verhalten (UIKit-gebackte `TabView`): Tab-Inhalte werden
**beim ersten Besuch materialisiert und danach am Leben gehalten** — exakt der
Lifecycle, den unser `visitedTabs`-Mechanismus nachbaut (der Kommentar in
`RootView.swift:168–171` sagt selbst: „the same lifecycle `TabView` had").
Das ist **nicht formell dokumentiert** → *im SDK/am Simulator zu verifizieren*
(Prüfidee: `ChatView`-Draft tippen, Tab wechseln, zurückwechseln — Draft muss
stehen; zweite Prüfung: Scroll-Position in `MemoriesView`).

Konsequenzen:
- `visitedTabs`, `tabPane(_:content:)` und die `opacity/zIndex`-Schaltung
  **ersatzlos löschen**.
- `ScreenshotSeed.prefilledTabs` (`ScreenshotSeed.swift:76`, Init in
  `RootView.swift:180–186`): Der Zweck war, dass der gestagte Tab im allerersten
  CI-Frame steht. Native `TabView` rendert den **selektierten** Tab im ersten
  Frame ohnehin; es reicht, `appState.activeTab` vor dem ersten Frame auf den
  Staging-Tab zu setzen. `prefilledTabs` entfällt (Verhalten im
  Screenshot-CI-Lauf gegenprüfen — das war eine echte Regression, siehe
  Kommentar „blank paired-de.png").
- Achtung Kompromiss: bei `.sidebarAdaptable` gibt es Community-Berichte über
  State-Verlust beim Umschalten Bar↔Sidebar. Solange wir beim Default-Stil
  bleiben (Empfehlung §2.7), irrelevant; sonst verifizieren.

### 2.4 Chat-Badge & Accessibility

- Unread-Badge: nativ via `.badge(…)` (§2.2). Das System rendert das Badge im
  iOS-26-Look (roter Punkt/Kapsel an der Bar); unsere pinke Custom-Kapsel mit
  Glow (`LiquidTabBar.swift:178–195`) entfällt — bewusster Identitätsverlust,
  dafür 100 % System.
- VoiceOver: Das System liest Tab-Titel + Badge-Wert zusammen an. Unsere
  maßgeschneiderten Ansagen (`chatTabA11yLabel`/`playTabA11yLabel`,
  `RootView.swift:309–319`, „Du bist dran!"-Semantik) sind reicher. Ob
  `TabContent` ein `accessibilityLabel` anbietet: §1.5.4. Falls nein: Verlust
  akzeptieren und die L10n-Keys `tab.chat.unreadA11y`/`tab.play.awaitingA11y`
  stilllegen (nicht löschen, L10n-Usage-Tests beachten — `L10nUsageTests`).
- AX5: Der komplette Dock-Breiten-Vertrag (Icon-Cap AX1, Icon-only-Modus,
  `TabBarLogic.dockMinimumWidth`, `axCappedSlotMinWidth`) **entfällt** — die
  System-Bar skaliert selbst und bietet bei AX-Größen den Large-Content-Viewer
  (Long-Press-HUD) gratis. Die zugehörigen LogicTests werden gelöscht (§2.9).

### 2.5 Wohin wandert der schwebende „?"-Hilfe-Knopf

Geprüfte Kandidaten:

1. **`tabViewBottomAccessory`** — taugt NICHT als 1:1-Ersatz für den
   abgesetzten runden Knopf: das Accessory ist eine volle-Breite-Kapsel über der
   Bar, dauerhaft sichtbar über allen Tabs, und kollabiert `inline` in die
   minimierte Bar (§1.2). Ein einzelnes „?" darin wirkt wie ein leerer
   Music-Player. **Nur sinnvoll, wenn wir das Accessory ohnehin mit
   Couple-Status füllen** (Partner-Presence + Streak + Hilfe-Knopf rechts,
   §2.8) — dann ist die Hilfe dort ein Trailing-Button des Accessories.
2. **Toolbar (`ToolbarItem(placement: .topBarTrailing)`)** — der HIG-konforme
   Ort für Hilfe. ABER: unsere Tab-Roots verstecken die Navigation-Bar
   (`.toolbar(.hidden, for: .navigationBar)` in `DashboardView.swift`,
   `MemoriesView.swift:145`, `ChatView.swift`, `PlayHubView.swift`) und rendern
   eigene Header. Toolbar-Hilfe hieße: vier Screens umbauen oder den Knopf in
   die Custom-Header integrieren (pro Screen ein Button, der
   `bus`-los `showHandbook` togglet).
3. **Empfehlung (geringstes Risiko):** Phase 1 der Migration behält einen
   frei schwebenden Glass-Circle-Button („?") als eigenes Overlay
   (`safeAreaBar(edge: .bottom)` existiert weiter für Nicht-Bar-Inhalte —
   [safeAreaBar(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)),
   iOS 26) — allerdings kollidiert ein Bottom-Overlay optisch mit der neuen
   System-Bar. Deshalb konkret: **Hilfe in die per-Screen-Header** (Kandidat 2,
   integriert in die bestehenden Custom-Header statt echte Toolbar) und
   mittelfristig ins Bottom-Accessory, sobald das Presence-Accessory kommt.
   `helpAnchor`-Logik (`RootView.swift:321`) bleibt unverändert.

### 2.6 Re-Tap („zurück nach oben") & Shortcuts & Keyboard

- **Re-Tap-Erkennung:** Native `TabView` meldet den Tap auf den bereits aktiven
  Tab über das Selection-Binding (Setter feuert mit identischem Wert). Muster:

  ```swift
  private var reselectAwareSelection: Binding<AppTab> {
      Binding(get: { appState.activeTab },
              set: { newTab in
                  if newTab == appState.activeTab { scrollActivePaneToTop() }
                  appState.activeTab = newTab
              })
  }
  ```

  Dieses Muster ist verbreitet, aber nicht dokumentiert → *zu verifizieren*;
  Fallback: Re-Tap-Feature ersatzlos streichen (UIKit-`UITabBarController`
  poppt bei Re-Tap den Navigation-Stack automatisch; ob SwiftUI-`TabView` auch
  Scroll-to-top für `ScrollView`-Roots auslöst: empirisch prüfen). Der
  Window-Walk (`scrollActivePaneToTop`, `RootView.swift:335`) und
  `TabBarLogic.shouldScrollToTop` bleiben in Phase 1 erhalten — sie
  funktionieren unabhängig von der Bar-Implementierung.
- **⌘1–⌘5:** bleibt wie gehabt (`tabShortcuts`, `RootView.swift:251`) — die
  native Bar liefert keine nummerierten Tab-Shortcuts.
- **Keyboard-Ausweichen:** die `keyboardWillShow/Hide`-Maschinerie
  (`RootView.swift:177–239`) **entfällt komplett** — die System-Bar regelt ihr
  Verhältnis zum Keyboard selbst.
- **Haptik:** `.sensoryFeedback(.selection, trigger: appState.activeTab)` auf
  die `TabView` übernehmen (die System-Bar tickt nicht hörbar von selbst).

### 2.7 iPad: `sidebarAdaptable` vs. unser bestehender Split-Ansatz

Fakten: Die App hat **kein** `NavigationSplitView`; der „Split" ist ein
handgebauter `HStack` mit eigener Sidebar-Spalte **innerhalb des Wir-Tabs**
(`MemoriesView.swift:172–202`, `splitHub`, `LayoutRules.memoriesUsesPersistentSidebar`).
Auf iPad zeigt die native `TabView` die Bar oben (seit iPadOS 18; §1.5.6
verifizieren) statt unseres unten zentrierten Docks mit `dockMax`-Deckel.

Bewertung:
- `.sidebarAdaptable` würde eine **zweite, systemweite Sidebar-Ebene** über
  unsere Memories-interne Sidebar legen — doppelte Sidebar-UX, und unsere fünf
  Top-Level-Tabs sind zu wenig, um eine System-Sidebar zu rechtfertigen
  (Apple-Beispiele nutzen sie für content-reiche `TabSection`-Kataloge).
- **Empfehlung:** Migration mit Default-Stil (`.automatic`) starten; die
  Memories-Split-Architektur bleibt unangetastet. `sidebarAdaptable` +
  `TabSection`s (z. B. Spiele-Kategorien als Sections) als eigenes Folgeprojekt
  evaluieren — erst dann lohnt auch `tabViewCustomization` (Drag-Reorder ist
  iPad-only, §1.4, und ohne `sidebarAdaptable` wirkungslos).
- Falls Drag-Customization dennoch Launch-Ziel ist: `.sidebarAdaptable` setzen,
  jedem Tab `customizationID("app.sooodreamy.tab.<raw>")` geben, Home per
  `customizationBehavior(.disabled, for: .sidebar, .tabBar)` festnageln,
  `@AppStorage("tabCustomization") var customization: TabViewCustomization`
  anhängen. Kosten: Bar↔Sidebar-State-Verlust-Risiko (§2.3) und UX-Prüfung der
  Doppel-Sidebar im Wir-Tab.

### 2.8 Was die native Bar NICHT kann → Verbleib/Umzug

| Custom-Feature (heute) | Nativ möglich? | Verbleib |
|---|---|---|
| Selektions-Linse im Couple-Farbverlauf + `matchedGeometryEffect` (`LiquidTabBar.swift:202–223`) | Nein — System rendert eigene Selektion (Tint via `.tint` bleibt Couple-Farbe) | **Entfällt.** System übernimmt; einzige Stellschraube ist `.tint` |
| Wiggle-Easteregg bei Long-Press (`LiquidTabBar.swift:258`) | Nein — an System-Tabs hängen keine Custom-Gesten; Long-Press gehört dem Large-Content-Viewer | **Entfällt** (bewusst; AX-HUD ist wichtiger als das Easteregg) |
| Pinke Badge-Kapsel mit Glow + `contentTransition(.numericText())` | Nein — Badge-Optik ist System | **Entfällt**, Zahl bleibt via `.badge` |
| Abgesetzter runder „?"-Knopf | Nein — Bar-Layout gehört dem System | **Umzug** in per-Screen-Header, später Bottom-Accessory (§2.5) |
| AX5-Icon-only-Modus + Dock-Breiten-Vertrag | Überflüssig — System skaliert selbst | **Entfällt** inkl. LogicTests |
| `dockMax`-Breitendeckel auf iPad (`Theme.swift:71`) | Nein — iPad-Bar liegt oben, Layout System | **Entfällt** |
| Partner-Presence-Glow im Dock | **Existiert heute nicht im Dock** (geprüft: kein Presence-Code in `LiquidTabBar.swift`/`RootView.swift`; Presence lebt als `PartnerPresencePill` in `Features/Home/PresenceViews.swift:173`) | **Neue Heimat: `tabViewBottomAccessory`** — die iOS-26-native Bühne für persistenten Couple-Status (Presence-Punkt, „denkt an dich"-Puls, Streak), mit `.inline`-Variante fürs Kollabieren. Das ist das eigentliche Upgrade dieser Migration |
| Keyboard-Ausweichen der Bar | Ja, automatisch | Custom-Code löschen |
| Re-Tap → Scroll-to-top | Teilweise (NavStack-Pop ja; ScrollView-Top *zu verifizieren*) | Binding-Trick + bestehender Window-Walk (§2.6) |

### 2.9 Zu löschende / zu ändernde Dateien

| Datei | Aktion |
|---|---|
| `ios/SoooDreamy/UI/LiquidTabBar.swift` | **Löschen** (LiquidTabItem, LiquidTabBar, TabWiggleModifier) |
| `ios/SoooDreamy/App/RootView.swift` | `MainTabView` neu: TabView-Gerüst §2.2; löschen: `visitedTabs`, `tabPane`, `keyboardVisible`+Notifications, `tabItems`, A11y-Label-Helfer (falls §1.5.4 negativ); behalten: Demo-Badge-`safeAreaBar(.top)`, `tint`, `onChange`-Unread-Reset, `tabShortcuts`, Handbook-Sheet, `scrollActivePaneToTop` |
| `ios/SoooDreamy/Content/TabBarLogic.swift` | Schrumpfen: `badgeText` + `shouldScrollToTop` + `reselectScrollTolerance` bleiben; löschen: `wiggleKeyframes`, `concentricRadius` (Nutzung prüfen), gesamter Dock-Breiten-Block (`dockSlotCount`…`dockMinimumWidth`) |
| `ios/LogicTests/TabBarLogicTests.swift` | Dock-Breiten- und Wiggle-Tests löschen; Badge-/ScrollToTop-Tests behalten |
| `ios/SoooDreamy/UI/Theme.swift` | `LayoutMetrics.dockMax` (`:71`) löschen |
| `ios/SoooDreamy/App/ScreenshotSeed.swift` | `prefilledTabs` entfernen (§2.3) |
| `ios/Package.swift` | Eintrag `SoooDreamy/Content/TabBarLogic.swift` bleibt (Datei existiert weiter) |
| `SoooDreamy/DESIGN.md` / Doku | Dock-Kapitel („Glas-Stufen"-Nutzung der Bar, AX5-Dock-Vertrag) auf System-Bar umschreiben |

Reihenfolge (jeder Schritt CI-grün): (1) TabView-Gerüst hinter identischem
`AppTab`-Binding + Badges, LiquidTabBar noch im Baum tot; (2) Hilfe-Knopf in
Header umziehen; (3) LiquidTabBar + Logik + Tests löschen; (4)
Screenshot-Staging + AX-Eval-Lauf; (5) optional Bottom-Accessory (Presence).

---

## 3. Native-Komponenten-Sweep — TOP 25 (priorisiert)

Gesamtbild vorweg: Die App ist bereits erstaunlich system-nah — `Menu`,
`confirmationDialog`, `presentationDetents` (20 Dateien), `DatePicker`,
`Slider`, `Toggle`, `ShareLink`, `.refreshable`, `Picker(.segmented)` (4×),
`scrollEdgeEffectStyle`, `safeAreaBar`, `glassEffect` sind verbreitet. Der
Sweep findet die verbliebenen Eigenbauten. P1 = klarer Gewinn, P2 = lohnend,
P3 = bewusste Design-Entscheidung dokumentieren statt umbauen.

| # | P | Fundort | Befund → Empfehlung |
|---|---|---|---|
| 1 | P1 | `App/RootView.swift:210` + `UI/LiquidTabBar.swift` (ganz) | Custom-Tab-Bar → native `TabView` (Abschnitt 2, das Hauptprojekt) |
| 2 | P1 | `App/RootView.swift:232–239` | Keyboard-Notification-Workaround → entfällt mit nativer Bar |
| 3 | P1 | `UI/LiquidTabBar.swift:178–195` | Hand-gebautes Badge → `TabContent.badge(_:)` |
| 4 | P1 | `Features/Chat/ChatView.swift:559–590` (`searchBar`) + `:534` (`searchToggleButton`) | Eigenes Suchfeld + Toggle-Knopf → `.searchable(text:)` am Chat-`NavigationStack` (System-Feld unten auf iPhone, `searchToolbarBehavior(.minimize)` möglich). Größter Einzel-Gewinn im Sweep |
| 5 | P1 | `Features/Memories/JournalView.swift:110–132` (`searchField`) | Zweites Eigenbau-Suchfeld → `.searchable` + `searchToolbarBehavior(.minimize)` |
| 6 | P1 | `Features/Games/PlayHubView.swift:1632–1650` (`GameProgressBar`) | GeometryReader-Capsule-Balken → `ProgressView(value:)` mit `.tint` (linear); Custom-Look ggf. via eigenem `ProgressViewStyle` statt Eigen-View |
| 7 | P1 | `Features/Memories/SharedListsView.swift:289` (`ListProgressRing`) | Eigenbau-Ring → `Gauge(value:)` mit `.gaugeStyle(.accessoryCircularCapacity)` — gratis A11y-Werte-Ansage |
| 8 | P1 | `Features/Memories/MemoriesHubComponents.swift:164` (`MiniProgressRing`) | dito → `Gauge` (accessoryCircular) |
| 9 | P1 | `UI/Theme.swift:933–957` (`SecondaryButtonStyle`) | Nutzt schon `glassEffect(.regular.interactive())`, aber eigenes Padding/Press-Scale → `.buttonStyle(.glass)` prüfen; der Datei-Kommentar nennt Typo/Padding als Grund — mit `controlSize(.large)` + `.buttonBorderShape(.capsule)` kommt das System-Pendant nah genug ([WWDC25 #323, 15:33](https://developer.apple.com/videos/play/wwdc2025/323/)) |
| 10 | P2 | `UI/Theme.swift:857–925` (`PrimaryButtonStyle`) | Bewusst NICHT `.glassProminent` (Datei-Kommentar: Zwei-Stopp-Couple-Gradient = Markensignatur, inkl. Kontrast-Scrim-Maschine). Empfehlung: **behalten**, aber als dokumentierte Ausnahme in DESIGN.md verankern; `.glassProminent` + `.tint(coupleBlend)` nur als A/B-Experiment |
| 11 | P2 | `UI/Components.swift:401–434` (`ConnectionBanner.label`) | Hand-gemalte schwarze Kapsel (`Color.black.opacity(0.35)`) → `.glass(.chrome, in: Capsule())` wie `ToastView` (`Components.swift:269`) — konsistente Chrome-Sprache, System-Degradation gratis |
| 12 | P2 | `Features/Memories/GalleryView.swift:307–320` (`filterChips`) | Chip-Reihe für Alle/Favoriten/Alben: dynamische N-Alben sprengen `Picker(.segmented)` → **behalten**, aber die zwei festen Filter (`.all`/`.favorites`) + Alben-`Menu` als native Alternative erwägen; mindestens: Chips auf `.buttonStyle(.glass)` heben |
| 13 | P2 | `Features/Settings/SettingsView.swift:49ff` | Settings als ScrollView+Glass-Cards statt `List`/`Form`: Design-Entscheidung (Aurora-Ästhetik), aber die reinen Einstell-Sheets (`NotificationSettingsSheet`, `LiveActivitySheet`, `ICloudSheet`) sollten `Form` mit `.formStyle(.grouped)` nutzen — System-Spacing, AX, Insetting gratis |
| 14 | P2 | `Features/Chat/ChatView.swift:1043,1063,1760` | Eigene runde Glass-Buttons im Composer: auf `.buttonStyle(.glass)` + `.buttonBorderShape(.circle)` umstellbar (ChatView nutzt `.buttonStyle(.glass)` bereits bei `:805` — Muster vereinheitlichen) |
| 15 | P2 | `Features/Home/PulseFan.swift:79,116` | FAB + Fan-Kreise: `glass(.chrome, interactive:)` ist ok; prüfen ob `.buttonStyle(.glass)`+`GlassEffectContainer`-Morph (`glassEffectID`) den Fan nativer öffnet — Vorsicht: CI-dokumentierte Group-Regression beachten (`Glass.swift:129–142`) |
| 16 | P2 | `Features/Memories/StoryTimelineView.swift:274` | Einzelner Chrome-Circle-Button → `.buttonStyle(.glass)`/`.buttonBorderShape(.circle)` |
| 17 | P2 | `Features/Home/LevelCard.swift:17` (`LevelRing`) | XP-Ring → `Gauge` (accessoryCircular) mit `currentValueLabel`; Level-Zahl bleibt Overlay |
| 18 | P2 | `Features/Chat/LetterWorkshopView.swift` / `LetterComposeView.swift` | Brief-Editor: iOS-26-`TextEditor` mit `AttributedString`-Binding = echter Rich-Text-Editor (fett/kursiv/Absatzstil) statt Plain-Text — die größte Feature-Perle des Sweeps (§5) |
| 19 | P2 | `Features/Games/PlayHubView.swift` (18× `.buttonStyle(.plain)`) | Spiele-Tiles als Plain-Buttons: ok für Cards, aber Aktions-Buttons darin (Start/Weiter) auf `.glass`/`.glassProminent` heben |
| 20 | P3 | `UI/Components.swift:468` (`EmojiPickerGrid`) + `:503` (`MemberColorPicker`) | Eigenbau-Picker mit korrekten A11y-Traits: **behalten** — es gibt kein System-Pendant (Emoji-Grid/Farb-Swatches); `ColorPicker` wäre falsches UX (freie Farbe statt Palette) |
| 21 | P3 | `Features/Home/MoodPickerSheet.swift:8` | Mood-Grid: behalten (Custom-Content), aber Detents/`presentationBackground` prüfen — iOS 26 gibt Sheets System-Glass, nichts drübermalen |
| 22 | P3 | `Features/Games/WordleView.swift` (Custom-Keyboard), `BattleshipView`, Brettspiel-Grids | Spielflächen: bewusster Eigenbau, kein System-Pendant — **behalten** |
| 23 | P3 | `UI/GlassSkeleton.swift` + `Components.swift:159` (`LoadingView`) | Skeleton statt `ProgressView`: bewusste Design-Regel (Commandment 7) — behalten; `BusySpinner` ist bereits `ProgressView` |
| 24 | P3 | `Features/Chat/ChatView.swift:2376` (`ChatDateChip`), `:2592` (`ChatReactionChips`) | Chat-Chrome-Chips: behalten (Messaging-UX), aber Reaktions-Auswahl könnte `ContextMenu`-Preview nutzen — prüfen ob heute schon `contextMenu` (ja, 6 Treffer in ChatView) |
| 25 | P3 | `Features/Rituals/*`, `Features/Memories/EventsView.swift` u. a.: lange `ScrollView`+`LazyVStack`-Listen | Wo Swipe-Actions/Edit-Mode/Reorder gebraucht werden (Listen in `SharedListsView`, `BucketListView`): `List` mit `.listRowBackground(Color.clear)` + `.scrollContentBackground(.hidden)` erwägen — sonst ScrollView behalten (Aurora-Design) |

Bereits erledigt / kein Handlungsbedarf: `Picker(.segmented)` in
`MancalaView:129`, `KaesekaestchenView:105`, `PersonalizationView:187`,
`SeasonEffectsView:180`; native `Menu` u. a. in `DateNightView:110`,
`GalleryView`; `presentationDetents` in 20 Dateien; native `Slider` (4×),
`Toggle` (15 Dateien), `confirmationDialog`/`.alert` breit im Einsatz.

---

## 4. Layered App Icon (Icon Composer `.icon`) in XcodeGen + CI

### 4.1 Faktenlage

- **Format:** Eine `.icon`-Datei ist ein **Ordner-Package**: `icon.json`
  (deklarative Komposition: `groups` → `layers`, Fills,
  per-Appearance-`*-specializations`, Liquid-Glass-Eigenschaften wie
  `specular`, `translucency`, `shadow`) + `Assets/` (SVG/PNG-Ebenen). Apple
  dokumentiert die **Nutzung** von Icon Composer
  ([Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)),
  aber **kein offizielles JSON-Schema** — das Format ist handschreibbar, aber
  nur community-dokumentiert (empirische Referenzen: IconComposerModel,
  diverse `icon.json`-Schema-Projekte). Einstufung: machbar, aber
  „reverse-engineered, forward-fragile".
- **Ohne GUI validieren/rendern:** `ictool` liegt in
  `$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool`
  (ab Xcode 26) und kann `.icon`-Packages headless rendern — das ist der
  CI-Gate: „wenn ictool es rendert, öffnet es auch Icon Composer". *Auf dem
  macos-26-Runner zu verifizieren* (Pfad + Version einmal im CI loggen).
- **Xcode-Wiring:** `.icon` in die Target-Sources legen,
  `ASSETCATALOG_COMPILER_APPICON_NAME` auf den Dateinamen ohne Endung setzen;
  Alternates einzeln als eigene `.icon`-Dateien in
  `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (Namen müssen zu den
  `setAlternateIconName`-Aufrufen passen — bei uns `AppIconKit`). Xcode
  schreibt `CFBundleIcons` selbst. Da die App **iOS-26-only** ist, entfällt
  die bekannte Xcode-26.1-Falle mit dualen Legacy+Glass-Icon-Sets für ältere
  Deployment-Targets komplett.
- **XcodeGen:** Natives `.icon`-Folder-Handling wurde am **2026-03-05
  gemerged** ([XcodeGen PR #1600](https://github.com/yonaskolb/XcodeGen/pull/1600));
  CI installiert `brew install xcodegen` (latest) → sollte enthalten sein, aber
  **im CI verifizieren** (`xcodegen version` loggen; prüfen, dass das
  `.icon`-Package als EIN Datei-Eintrag in den Resources landet, nicht als
  expandierter Ordner). Vor dieser Version musste man `.icon` als
  `buildPhase: resources`-Pfad mit Folder-Typ tricksen.

### 4.2 Ist-Stand unserer Icon-Pipeline

`ios/scripts/GenerateIcon.swift` rendert per CoreGraphics ein flaches
1024²-PNG (klassisch + 9 Varianten-Paletten für Icon-Gifts) direkt in die
`.appiconset`s; die CI ruft es in drei Jobs auf
(`sooodreamy.yml:85,88,165,167,244,246`). Das Icon ist intern bereits in
Ebenen gedacht (Nacht-Gradient → Aurora → Partikel → Glow → Glas-Herz →
Begleit-Herz → Gloss, siehe Header-Kommentar) — ideale Vorlage für echte
`.icon`-Layer.

### 4.3 Optionen mit Aufwand/Risiko

| Option | Was | Aufwand | Risiko |
|---|---|---|---|
| A. Status quo | Flaches PNG behalten; iOS 26 legt automatisch Default-Glass aufs Legacy-Icon | keiner | Icon wirkt gegenüber echten Layered-Icons flach; Dark/Tinted/Clear-Varianten nur System-Automatik |
| B. **Empfohlen:** `.icon` prozedural | `GenerateIcon.swift` in zwei Render-Pässe teilen (Hintergrund = Gradient+Aurora+Partikel+Glow als Ebene 1; Herz+Begleit-Herz als Ebene 2, **ohne** gebackene Specular/Gloss — das macht die Engine); dazu ein kleiner Emitter, der pro Palette das `icon.json` schreibt (Fills aus `Palette.bg`, Ebenen-PNGs in `Assets/`); CI-Gate: `ictool`-Render aller 10 Icons | Mittel: 1 Script-Refactor + JSON-Emitter + project.yml (Settings unverändert, nur Icon-Quelle) + CI-Step | JSON-Format inoffiziell (Schema-Drift bei Xcode-Updates), XcodeGen-`.icon`-Support im CI erst zu bestätigen, Icon-Gift-Namen müssen exakt `AppIconKit` matchen; Glass-Herz „doppelt verglast" (unser gemaltes Glas + Engine-Glas) → Ebene 2 bewusst matt anliefern |
| C. Icon Composer GUI einmalig | Designer baut `.icon` von Hand, Repo committet das Package | Klein | Bricht die „keine binären Assets im Repo"-Regel des Projekts (GenerateIcon existiert genau deshalb); 10 Varianten von Hand pflegen |

**Empfehlung:** Option B, aber als **eigener Wave nach der TabView-Migration**
(unabhängige Baustellen, getrennte CI-Läufe). Bis dahin Option A — sie ist
heute schon korrekt verdrahtet. Erststep von B ist ein 20-Zeilen-CI-Probe-Step:
`ictool --version` + Render eines minimalen handgeschriebenen `.icon` — damit
ist das Formatrisiko für unsere Xcode-Version in einem Lauf geklärt.

---

## 5. Sonstige iOS-26-Perlen für diese App

- **`backgroundExtensionEffect()`** — spiegelt+blurred eine View in
  angrenzende Safe-Areas; gedacht für Detail-Panes unter Sidebars. Kandidat:
  Foto-Hero in `GalleryPagerView`/`MemoriesView`-Split (Detail läuft unter die
  Sektions-Sidebar). [Doku](https://developer.apple.com/documentation/SwiftUI/View/backgroundExtensionEffect())
- **`scrollEdgeEffectStyle(_:for:)`** — Soft/Hard-Scroll-Edge unter Chrome;
  bereits adoptiert (`MemoriesView.swift:135` u. a.). Nach der Migration
  prüfen, dass jede Tab-Root-ScrollView `.soft` für `.bottom` setzt, damit
  Inhalt unter der System-Bar wegläuft. [WWDC25 #323](https://developer.apple.com/videos/play/wwdc2025/323/)
- **Rich-Text `TextEditor` (AttributedString-Binding)** — nativer
  Rich-Text-Editor mit Formatierungs-Constraints. Zielort: Brief-Werkstatt
  (`LetterWorkshopView`/`LetterComposeView`) — Liebesbriefe mit fett/kursiv.
  [WWDC25 „Code-along: Rich text"](https://developer.apple.com/videos/play/wwdc2025/280/) *(Session-Nr. im SDK-Release-Notes-Check verifizieren)*
- **`WebView`/`WebPage` (WebKit für SwiftUI)** — natives WebView-Paar mit
  Navigation/JS/Scroll-API. Für uns Randthema (Server-App ohne Web-Content);
  höchstens Credits/Server-Hilfeseiten. [WebKit-für-SwiftUI-Doku](https://developer.apple.com/documentation/webkit/webview)
- **`AssistiveAccess`-Szene** — `AssistiveAccess { … }` als eigene Scene +
  `UISupportsAssistiveAccess`-Info-Key: reduzierte Couple-Kernflows (Puls
  senden, letzte Nachricht) im System-Look für kognitive Barrierefreiheit.
  Passt zur A11y-DNA der App. [AssistiveAccess](https://developer.apple.com/documentation/swiftui/assistiveaccess),
  [Optimizing your app for Assistive Access](https://developer.apple.com/documentation/accessibility/optimizing-your-app-for-assistive-access)
- **`ControlWidget` (Control Center/Sperrbildschirm/Action Button)** — seit
  iOS 18, unter iOS 26 mit Liquid-Glass-Look: „Denk-an-dich-Puls senden" als
  Control neben unseren bestehenden Widgets/Live-Activities.
  [ControlWidget](https://developer.apple.com/documentation/widgetkit/controlwidget)
- **`searchToolbarBehavior(.minimize)` + `DefaultToolbarItem(kind: .search)`**
  — minimiertes Suchfeld als Toolbar-Knopf; Begleit-API der Sweep-Punkte 4/5.
  [searchToolbarBehavior(_:)](https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:))
- **`ToolbarSpacer(.fixed/.flexible)`** — gruppiert Toolbar-Glass-Cluster
  optisch; relevant, sobald die Tab-Roots echte Toolbars bekommen (§2.5).
  [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer)
- **Sheets & Glass:** Teilhöhen-Sheets bekommen in iOS 26 System-Glass
  automatisch; ein `presentationBackground(.glass)`-ShapeStyle existiert
  **nicht** als dokumentierte API (*im SDK zu verifizieren*) — Regel: in
  Sheets nichts über den System-Hintergrund malen (deckt sich mit unserer
  Glass-Charter in `Glass.swift`). [WWDC25 #323](https://developer.apple.com/videos/play/wwdc2025/323/)
- **`@Animatable`-Makro + neue Symbol-Effekte (`.drawOn`/`.drawOff`)** —
  weniger Boilerplate für animierte Shapes; Draw-Effekte für Herz-Symbole in
  Ceremonies. *Symbol-Effekt-Namen im SDK verifizieren.*
  [WWDC25 What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)
- **FoundationModels (On-Device-LLM)** — für die bestehende
  „Intelligence"-Schiene (`IntelligenceRulesTests`, Consent-Sheet): lokale
  Frage-Vorschläge ohne Server. Eigenes Recon nötig (Entitlement-/
  Geräteklassen-Fragen). [FoundationModels](https://developer.apple.com/documentation/foundationmodels)

---

## 6. Quellenverzeichnis (Kern-Links)

Apple-Doku: [Tab-Init](https://developer.apple.com/documentation/swiftui/tab/init(_:systemimage:value:content:)) ·
[TabRole](https://developer.apple.com/documentation/swiftui/tabrole) ·
[tabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)) ·
[TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior) ·
[tabViewBottomAccessory(isEnabled:content:)](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)) ·
[TabViewBottomAccessoryPlacement](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement) ·
[tabViewSearchActivation](https://developer.apple.com/documentation/swiftui/view/tabviewsearchactivation(_:)) ·
[sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable) ·
[TabViewCustomization](https://developer.apple.com/documentation/swiftui/tabviewcustomization) ·
[tabViewCustomization(_:)](https://developer.apple.com/documentation/swiftui/view/tabviewcustomization(_:)) ·
[customizationBehavior(_:for:)](https://developer.apple.com/documentation/swiftui/tabcontent/customizationbehavior(_:for:)) ·
[TabContent.badge](https://developer.apple.com/documentation/swiftui/tabcontent/badge(_:)) ·
[Tab-Navigation-Guide](https://developer.apple.com/documentation/swiftui/enhancing-your-app-content-with-tab-navigation) ·
[safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)) ·
[backgroundExtensionEffect](https://developer.apple.com/documentation/SwiftUI/View/backgroundExtensionEffect()) ·
[AssistiveAccess](https://developer.apple.com/documentation/swiftui/assistiveaccess) ·
[ControlWidget](https://developer.apple.com/documentation/widgetkit/controlwidget) ·
[Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
WWDC: [25 #323 „Build a SwiftUI app with the new design"](https://developer.apple.com/videos/play/wwdc2025/323/) ·
[25 #238 „Customize your app for Assistive Access"](https://developer.apple.com/videos/play/wwdc2025/238/) ·
[24 #10147 „Elevate your tab and sidebar experience in iPadOS"](https://developer.apple.com/videos/play/wwdc2024/10147/).
Tooling: [XcodeGen PR #1600 (.icon-Support, 2026-03-05)](https://github.com/yonaskolb/XcodeGen/pull/1600).
Community (nur ergänzend): [nilcoalescing — Search Enhancements iOS 26](https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26) ·
Stack Overflow zu BottomAccessory/Icon-Wiring (im Text markiert).
