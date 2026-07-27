# EVAL-2 — unabhängige Vollständigkeits- und Qualitätsprüfung

Stand: 27. Juli 2026 · Godot 4.4.1 · Vergleichsquelle: aktueller Inhalt von
`/workspace/GOOBY/src/**` gegen `/workspace/GOOBY-GODOT/**`.

## Kurzurteil

Die Aussage **„fast alles von davor fehlt“ ist nicht mehr haltbar**. In einer
gleichgewichteten Matrix aus 79 prüfbaren Web-Features sind **53 vollständig,
16 teilweise und 10 nicht umgesetzt**. Das entspricht 67 % vollständig, 20 %
teilweise und 13 % fehlend.

Diese Gesamtzahl wird von den 30 vollständig portierten Arcade-Spielen stark
nach oben gezogen. Betrachtet man nur die 47 übergeordneten Spiel- und
Meta-Systeme, sind **23 vollständig, 15 teilweise und 9 fehlend**. Weniger als
die Hälfte dieser Kernfamilien ist damit wirklich fertig. Die Kritik
**„es ist eine Alpha“ bleibt für das Gesamtspiel berechtigt**, obwohl die
Arcade, das Haus, der Garten, die Stadt und große Teile der Ranch bereits weit
über einen Prototyp hinausgehen.

Mein präzises Label lautet:

> **Spielbare Content-Alpha mit beta-reifer Arcade, aber noch kein
> veröffentlichungsreifes Vollspiel.**

Es gab im Test **keinen reproduzierten P0-Absturz und keinen Datenverlust**.
Der volle Routen-/Minigame-Durchlauf erreichte 24 Routen und startete/beendete
alle 37 registrierten Spiele. Trotzdem enthält der beabsichtigte
Langzeit-/Fortschrittsloop mehrere harte semantische Lücken: Profil,
Tagesquests, Erfolge, Tagesbonus, Tierarzt, Funkelpark, vollständige Galerie,
Radio- und Code-Oberflächen.

## Bewertungsmaßstab

- **Vollständig**: Der für Spieler sichtbare Web-Loop ist in Godot vorhanden,
  verkabelt und mindestens per automatisiertem Lauf/Tests belegt. Zusätzlicher
  Godot-Inhalt schadet der Wertung nicht.
- **Teilweise**: Daten, Save-Slice oder Einzellogik existieren, aber sichtbare
  Oberfläche, Einstieg, Wirkung oder ein wesentlicher Teil des Web-Loops fehlt.
- **Fehlt**: Kein spielbarer Godot-Pfad gefunden. Ein migrierter Save-Slice oder
  Sticker-Auswerter allein zählt ausdrücklich nicht als Umsetzung.
- Jede Tabellenzeile zählt gleich. Die getrennte Kernsystem-Zahl verhindert,
  dass 30 Minigames fehlende Meta-Systeme statistisch verdecken.

## Testumfang und Belege

| Prüfung | Ergebnis | Beleg |
|---|---:|---|
| GDScript-Lint | 0 Probleme | `/tmp/gooby-godot/artifacts/EVAL2/gdlint.log` |
| GDScript-Format | 930 Dateien unverändert | `/tmp/gooby-godot/artifacts/EVAL2/gdformat.log` |
| Godot-Hauptsuite | 2.074 Tests, 0 fehlgeschlagen | `/tmp/gooby-godot/artifacts/EVAL2/godot-main-tests.log` |
| Godot-UI-Suite | 14.995 Checks, 0 fehlgeschlagen | `/tmp/gooby-godot/artifacts/EVAL2/godot-ui-tests.log` |
| Multiplayer-Server | 99 Tests, 0 fehlgeschlagen | `/tmp/gooby-godot/artifacts/EVAL2/server-tests.log` |
| Web-Referenz | 2.619 Tests, 0 fehlgeschlagen | `/tmp/gooby-godot/artifacts/EVAL2/web-reference-tests.log` |
| Routen-/Arcade-Durchlauf | Onboarding, 24 Routen, 37 Spiele, Kantenfälle | `/tmp/gooby-godot/artifacts/EVAL2/full-route-minigame-walkthrough.log` |
| Save-Fuzz | leer, maximal, negativ, Urlaub, Wecker, 30 Tage, Uhr zurück, Teilkorruption, abgeschnitten, Zukunftsversion, Backup | `/tmp/gooby-godot/artifacts/EVAL2/extreme-save-route-fuzz.log` |
| UI-Audit | 15 Screens im repräsentativen Querformat; zusätzlich 60 Screens in vier Formaten im Gesamtlauf; geometrisch 0 Befunde | `/tmp/gooby-godot/artifacts/EVAL2/ui-final.log`, `/tmp/gooby-godot/artifacts/EVAL2/ui-audit-rerun.log` |

Wichtig: „0 fehlgeschlagene Tests“ ist nicht gleich „0 Engine-Fehler“. Die
Godot-Suiten melden trotz grünem Ergebnis Navigation-, Lambda- und
Ressourcenfehler. Diese stehen unten ausdrücklich in der Fehlerliste.

### Repräsentative Screenshots

Haus und HUD sind ein echter, zusammenhängender Spielraum:

![Haus/HUD](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_01_home_hud.png)

Die Arcade ist kein Platzhalter; Karten, Cover und Scroll-UI sind vorhanden:

![Arcade](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_05_arcade.png)

Das Stickeralbum enthält aktuell 140 regulär gezählte Sticker:

![Stickeralbum](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_05_album.png)

Der HUD-Punkt „Profil“ öffnet dagegen fälschlich „Freunde & Besuche“:

![Profil-Fehlroute](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_05_profil.png)

Ein vollständiger Arcade-Ergebnisloop mit Score, Sternen, Coins, XP,
Tagesbonus und Level-up ist vorhanden:

![Minigame-Ergebnis](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_09_mg_results.png)

## Feature-Matrix A — Systeme, Screens und Inhalte (47)

| # | Web-Feature | Status | Web-Beleg | Godot-Beleg und Bewertung |
|---:|---|---|---|---|
| 1 | Boot, Loading, Szenenwechsel | **Vollständig** | `GOOBY/src/main.js`, `GOOBY/src/core/sceneManager.js`, `GOOBY/src/ui/loadingVeil.js` | `GOOBY-GODOT/scripts/boot/main.gd`, `scripts/core/scene_router.gd`, `scripts/core/loading_veil.gd`; Boot und 24 Ziele durchlaufen. |
| 2 | Save, Validierung, Migration, Recovery | **Vollständig** | `GOOBY/src/core/save.js`, `GOOBY/src/core/store.js` | `scripts/state/save_schema.gd`, `save_manager.gd`, `migration_v4.gd`, `state/import/transfer_service.gd`; abgeschnittene und Zukunfts-Saves werden abgefangen, Backup mit 777 Coins wurde korrekt geladen. |
| 3 | Erststart-Tutorial | **Teilweise** | `GOOBY/src/ui/onboarding.js`: Streicheln, Füttern, Bad, HUD, Carrot Catch, Shop, Quest/Garten | `scripts/ui/onboarding/onboarding_flow.gd` bietet Willkommen, Name und Charaktereditor; der alte handlungsgeführte Care-/Arcade-/Shop-Tutorialbogen fehlt. |
| 4 | Fünf Räume und Navigation | **Vollständig** | `GOOBY/src/home/rooms/{kitchen,living,bathroom,bedroom,garden}.js`, `ui/roomNav.js` | `scripts/home/rooms/*.gd`, `room_defs.gd`, `door_transition.gd`; living, bathroom, bedroom, garden und kitchen im Durchlauf besucht. |
| 5 | Vier Care-Stats und Offline-Catch-up | **Vollständig** | `GOOBY/src/systems/stats.js`, `offline.js`, `core/timeEngine.js` | `scripts/logic/stats.gd`, `offline.gd`, `state/gooby_ticker.gd`; Live-Tick und Catch-up sind produktiv verkabelt. |
| 6 | Füttern aus dem Kühlschrank | **Vollständig** | `GOOBY/src/home/interactions.js`, `systems/inventory.js` | `scripts/home/interactables/kuehlschrank.gd`, `logic/food_catalog.gd`; Vorrat, Animation, Stat-Deltas und Sticker-Hook sind verkabelt. |
| 7 | Voller Lebensmittel-/Item-Katalog | **Teilweise** | `GOOBY/src/data/foods.js` enthält 38 Speisen plus Medizin/Dünger | `scripts/logic/food_catalog.gd` dokumentiert und implementiert nur 26 tatsächlich erreichbare IDs; fehlende Web-Speisen fallen generisch zurück. |
| 8 | Waschen, Dusche, Toilette, Zähne | **Vollständig** | `GOOBY/src/home/interactions.js`, `ui/careSheet.js` | `scripts/home/interactables/klo_dusche.gd`, `zahnputz.gd`, `bad_state.gd`; inklusive Timer, Bürstenbruch und Zähler. |
| 9 | Streicheln, Kitzeln, Poken/Schwindel | **Vollständig** | `GOOBY/src/home/interactions.js` | `scripts/home/gooby_reactions.gd`; Tap-/Pet-Kaskade, Tickles, Schwindel und Feedback vorhanden. |
| 10 | Ball werfen/Fangen | **Fehlt** | `GOOBY/src/home/interactions.js` | Kein Ball-Interactable in `scripts/home/interactables/`; `gooby_reactions.gd` implementiert Pet/Tickle, aber keinen Ballloop. |
| 11 | Schlafen, frühes Wecken, Schlaf-UI | **Teilweise** | `GOOBY/src/systems/sleep.js`, `ui/sleepFlow.js` | `scripts/logic/sleep.gd`, `state/gooby_ticker.gd` enthalten die Logik; produktiver Start-/Weck-Aufruf und Schlaf-Overlay fehlen. `lampen_schalter.gd` schaltet nur Licht. |
| 12 | Krankheit und Medizin | **Teilweise** | `GOOBY/src/systems/health.js`, `ui/vetPanel.js` | `save_schema.gd` und `food_catalog.gd` führen `healthy/queasy/sick`, JunkScore und Medizinbestand; ein vollständiger sichtbarer Krankheits-/Heilungsloop fehlt. |
| 13 | Gewicht und vier sichtbare Körperstufen | **Teilweise** | `GOOBY/src/systems/weight.js`, `character/gooby.js` | Gewicht wird in `food_catalog.gd` gespeichert; `character/gooby_rig.gd` sagt explizit, dass „chubby“/Weight-Tier noch kein Rig-Morph ist. |
| 14 | Garten: Pflanzen, Wässern, Wachstum, Ernte, Ausbau | **Vollständig** | `GOOBY/src/systems/garden.js`, `home/gardenInteractions.js`, `ui/gardenPanel.js` | `scripts/home/garden/{garden_host,garden_state,garden_growth,garden_crops,garden_world}.gd`; inklusive Echtzeitwachstum, Regenparameter, Schatten, Gewächshaus/Sprinkler. |
| 15 | Shop und Economy-Guards | **Vollständig** | `GOOBY/src/ui/shopScreen.js`, `systems/economy.js`, `systems/inventory.js` | `scripts/shop/ikea_screen.gd`, `logic/economy.gd`, `shop/shop_catalog.gd`; Kaufpfade und Tages-/Endlos-Caps getestet. |
| 16 | Möbel, Build-Mode, Platzierung, Lager | **Vollständig** | `GOOBY/src/systems/furniturePlacement.js`, `home/decor.js` | `scripts/home/build_mode/build_mode.gd`, `furniture_catalog.gd`, `storage_logic.gd`, `home_state.gd`; Pflichtmöbel-Schutz und Storage vorhanden. |
| 17 | Garderobe, vier Slots, Fellfarben | **Vollständig** | `GOOBY/src/ui/wardrobeScreen.js`, `character/outfitAttach.js`, `data/skins.js` | `scripts/cosmetics/wardrobe_screen.gd`, `cosmetics_state.gd`, `content/cosmetics/data/cosmetics.json` (92 Einträge); Live-Vorschau und Kauf/Equip. |
| 18 | Tag-/Nacht-Licht | **Vollständig** | `GOOBY/src/systems/dayNight.js`, `gfx/sky.js` | `scripts/home/home_licht.gd`, `city/city_ambiente.gd`, `world/himmel.gd`; weiche Tagesverläufe und Nachtprofile getestet. |
| 19 | Wetter in Haus, Garten und Stadt | **Teilweise** | `GOOBY/src/systems/weather.js`, `gfx/weatherFx.js` | Regen beeinflusst `garden_state.gd`, und Ranch/Himmel besitzen Wetter; ein einheitlicher Web-paritärer Wetterdienst samt sichtbarem Haus-/Stadtregen wurde nicht gefunden. |
| 20 | Lokale Care-Benachrichtigungen | **Teilweise** | `GOOBY/src/core/notifications.js`, `systems/notifyRules.js` | `scripts/platform/notification_service.gd`, `notify_rules.gd`; API und Regeln existieren, native Zustellung/Care-Verdrahtung wurde im Linux-Lauf nicht nachgewiesen. |
| 21 | XP, Level, Unlocks, Coin-Levelbonus | **Vollständig** | `GOOBY/src/systems/leveling.js`, `ui/xpInfoSheet.js` | `scripts/logic/leveling.gd`, `state/rewards/level_up_feier.gd`, `minigames/minigame_award.gd`; Ergebnis-Screenshot zeigt XP und Levelbonus. |
| 22 | Erstes Spiel pro Tag ×2 | **Vollständig** | `GOOBY/src/data/minigames.js`, `minigames/framework.js` | `scripts/minigames/minigame_award.gd`, `results.gd`; Screenshot zeigt „Tagesbonus ×2“. |
| 23 | Tagesbonus-Streak | **Fehlt** | `GOOBY/src/systems/dailyBonus.js`, `ui/dailyBonusPopup.js` | `save_schema.gd` bewahrt nur `daily.lastClaimDay/streak`; keine Claim-Logik oder Popup-Szene gefunden. |
| 24 | Drei Tagesquests + Reroll/Claim | **Fehlt** | `GOOBY/src/data/quests.js`, `systems/quests.js`, `ui/questBoard.js` | Nur `quests.completedTotal` und Ranch-spezifische `scripts/ranch/quest/*`; kein Hauptspiel-Questpool, HUD-Board oder täglicher Roll. |
| 25 | Erfolge mit Fortschritt und Coin-Rewards | **Fehlt** | `GOOBY/src/data/achievements.js` (44), `systems/achievementsEngine.js`, `ui/achievementsScreen.js` | `save_schema.gd` hat Counter, aber kein Achievement-Katalog, Auswertungsdienst oder Erfolge-Screen. Sticker sind kein Ersatz für die 44 Erfolge. |
| 26 | Stickerbuch/Album | **Vollständig** | `GOOBY/src/data/stickers.js` (84 regulär + geheim), `systems/stickerBook.js`, `ui/albumScreen.js` | `scripts/ui/album/{album_screen,sticker_catalog,sticker_unlocks}.gd`, `state/rewards/reward_hub.gd`, `content/stickers/data/stickers.json` (141 Einträge); UI zeigt 140 reguläre Sticker. |
| 27 | Vier alte Sammlungssets (Fische/Gemüse/Landmarks/Treats) | **Fehlt** | `GOOBY/src/systems/collections.js`, `ui/albumScreen.js` | `save_schema.gd` migriert `collections`, aber `album_screen.gd` zeigt nur den neuen Stickerkatalog; kein Claim-/Set-UI für die vier Web-Sets. |
| 28 | Profil mit Vitals, Lifetime-Stats und Bestscores | **Fehlt** | `GOOBY/src/ui/profileScreen.js`, `systems/profileStats.js` | Kein Godot-ProfileScreen. `home_entry.gd` routet die HUD-Aktion `profil` auf `SocialScreen`; Screenshot zeigt „Freunde & Besuche“. |
| 29 | Fotomodus | **Teilweise** | `GOOBY/src/ui/photoMode.js` mit Pose, Emotion, Rahmen | `scripts/city/phone/foto_modus.gd`, `kamera_app.gd`; Screenshotaufnahme und PNG-Speicherung funktionieren, aber Pose-/Emotions-/Rahmenwerkzeuge fehlen. |
| 30 | Persistente Galerie, Anzeigen, Teilen, Löschen, 40er-Cap | **Teilweise** | `GOOBY/src/core/photoStore.js`, `systems/gallery.logic.js`, Album-Fototab | Kamera-App zeigt Anzahl und letzte Aufnahme (`kamera_app.gd`); kein Galerie-Browser, Teilen/Export, Löschen oder 40er-Cap. |
| 31 | Level-Rekap/Cinematic und Historie | **Vollständig** | `GOOBY/src/systems/recap*.js`, `ui/recapOverlay.js`, `recap/vignettes.js` | `scripts/recap/{recap_service,recap_engine,recap_director,recap_scene}.gd`; Queue, Historie und Cinematic vorhanden. |
| 32 | Zeitlich begrenzte Arcade-Modifikatoren | **Teilweise** | `GOOBY/src/systems/modifierEngine.js`, `ui/modifierGlow.js` | Einzelne Spiele besitzen `apply_modifier`, Economy kennt Modifier-Caps; `migration_v4.gd` verwirft aktive Modifier ausdrücklich, globaler Scheduler/Badge/Countdown fehlt. |
| 33 | Radio mit Sendern, Now Playing, Track-Toggles und Trim | **Teilweise** | `GOOBY/src/ui/radioScreen.js`, `audio/radioPlayer.js`, `systems/musicRegistry.js` | `scripts/audio/music_director.gd` und `music_registry.gd` haben 5 Sender und Tracks; keine Radio-/Now-Playing-Oberfläche oder Track-Toggle/Trim-Bedienung gefunden. |
| 34 | Offline-Geheimcodes und Lockout | **Teilweise** | `GOOBY/src/data/codes.js`, `systems/codesEngine.js`, `ui/codesScreen.js` | `content/codes/data/codes.json` und `scripts/net/redeem_service.gd` existieren, sind aber server-/onlineorientiert; kein Codes-Screen und keine Web-paritäre Offline-Einlösung. |
| 35 | Einstellungen, Accessibility, Grafik, Audio, Dev-Menü | **Vollständig** | `GOOBY/src/ui/settingsScreen.js`, `devPanel.js`, `settings.logic.js` | `scripts/ui/settings_screen.gd`, `settings/dev_unlock_dialog.gd`, `dev/dev_menu.gd`, `core/app_settings.gd`; umfangreicher als die Web-Oberfläche. |
| 36 | Gyro-/Pointer-Parallax | **Fehlt** | `GOOBY/src/systems/gyroParallax.js` | Kein entsprechender Godot-Dienst oder Raumeffekt gefunden; `platform/haptics.gd` ist nicht Parallax. |
| 37 | Freie Stadtfahrt und Orte/Landmarks | **Vollständig** | `GOOBY/src/city/cityBuilder.js`, `minigames/games/cityDrive.js`, `systems/shopTrip.js` | `scripts/city/city_scene.gd`, `city_bau.gd`, `city_map.gd`, `orte/*.gd`; 9 Innenräume wurden als eigene Routen besucht, Stadt besitzt Verkehr/Fußgänger. |
| 38 | Tierarztpraxis mit Checkup und Vollheilung | **Fehlt** | `GOOBY/src/city/vetClinic.js`, `ui/vetPanel.js` | `city/orte/goobytheke.gd` ist eine Apotheke, kein Tierarzt; kein Checkup-/120-Coin-Cure-Panel und keine Dr.-Hoppel-Szene. |
| 39 | Urlaub: 9 Ziele, Buchen, Taxi, Abholen | **Teilweise** | `GOOBY/src/data/vacations.js`, `systems/vacation.js`, `ui/airportScreen.js`, `vacation/vacationCinematic.js` | `scripts/logic/vacation.gd`, `city/travel/{reise_app,reise_logic,reise_cutscene}.gd`, `city/orte/flughafen.gd`; 9 Ziele/Phasen vorhanden, Recap-Level-Gates und volle Ziel-Cinematics nicht vollständig belegt. |
| 40 | Postkartenarchiv und Souvenirregal | **Teilweise** | `GOOBY/src/systems/postcards.js`, `home/souvenirShelf.js` | `vacation.gd` sagt ausdrücklich „archive generator NOT ported“; `city/ui/post_sheet.gd` zeigt Anzahl, die Aktion endet aber mit `city.post.bald`. |
| 41 | Funkelpark: Plaza, Coaster, Riesenrad, Stände | **Fehlt** | `GOOBY/src/park/parkScene.js`, `park/coasterRide.js`, `park/ferrisWheel.js`, `ui/parkStall.js` | Nur `park`-Save-Slice/Migration und Stickerbedingungen in `save_schema.gd`/`sticker_unlocks.gd`; keine Parkszene oder Fahrt. |
| 42 | Musik, SFX und Gooby-Stimme | **Vollständig** | `GOOBY/src/audio/*`, `systems/musicRegistry.js` | `scripts/audio/{audio_director,music_director,music_registry,sfx_map}.gd`, `character/gooby_voice.gd`; Kontextmusik, Crossfade, SFX und Stimme vorhanden. |
| 43 | Deutsch/Englisch | **Vollständig** | `GOOBY/src/data/strings.js`, `data/strings/*` | `GOOBY-GODOT/strings/de/**`, `strings/en/**`, `scripts/core/i18n.gd`; 14.995 UI-Checks bestätigen Parität. |
| 44 | Credits und „Was ist neu?“ | **Vollständig** | `GOOBY/src/ui/creditsScreen.js`, `whatsNew.js` | `scripts/ui/settings_screen.gd` enthält About/Credits; `ui/news_50_panel.gd` liefert Patchnotes/News. |
| 45 | Nutella und Nougatschleuse | **Teilweise** | `GOOBY/src/systems/nougat.logic.js`, `home/interactions.js` | Nutella-Events und Nougat-Hindernisse existieren (`events/event_runner.gd`, Minigames), Save-Slice ist vorhanden; installierbare Küchen-Nougatschleuse als Interactable fehlt. |
| 46 | Arcade-Shell, Pregame, Pause, Results | **Vollständig** | `GOOBY/src/ui/arcadeScreen.js`, `pregameScreen.js`, `minigames/framework.js` | `scripts/minigames/{arcade_screen,pregame,minigame_host,results}.gd`, `ui/pause_modal.gd`; kompletter Flow im UI-Audit und Walkthrough. |
| 47 | Leicht/Mittel/Schwer/Endlos | **Vollständig** | `GOOBY/src/data/difficultyTargets.js`, `minigames/framework.js` | Game-Manifeste, Pregame und Host führen Modus/Target/Endlos; alle registrierten Spiele starteten. |

**Kernsystem-Summe: 23 vollständig, 15 teilweise, 9 fehlend = 47.**

## Feature-Matrix B — die 32 Web-Minispiele

„Vollständig“ bedeutet hier: konkrete Godot-Szene/Logik vorhanden, Registry
kennt sie, und der EVAL-Walkthrough konnte das Spiel über Pregame/Countdown
starten und sauber zur Arcade zurückführen. Die Prüfung beweist keinen
mehrstündigen Balance-Pass für jedes Spiel.

| # | Web-Spiel | Status | Web-Beleg | Godot-Beleg |
|---:|---|---|---|---|
| 1 | Carrot Catch | **Vollständig** | `GOOBY/src/minigames/games/carrotCatch.js` | `scripts/minigames/games/carrot_catch/carrot_catch.gd` |
| 2 | Bunny Hop | **Vollständig** | `GOOBY/src/minigames/games/bunnyHop.js` | `scripts/minigames/games/bunny_hop/bunny_hop.gd` |
| 3 | City Drive | **Teilweise** | `GOOBY/src/minigames/games/cityDrive.js` | Freie Fahrt in `scripts/city/city_scene.gd`, aber kein `cityDrive`-Eintrag/Arcade-Runden- und Scoringloop in `minigame_registry.gd`. |
| 4 | Carrot Guard | **Vollständig** | `GOOBY/src/minigames/games/carrotGuard.js` | `scripts/minigames/games/carrot_guard/carrot_guard.gd` |
| 5 | Gooby Says | **Vollständig** | `GOOBY/src/minigames/games/goobySays.js` | `scripts/minigames/games/gooby_says/gooby_says.gd` |
| 6 | Hide & Seek | **Vollständig** | `GOOBY/src/minigames/games/hideSeek.js` | `scripts/minigames/games/hide_seek/hide_seek.gd` |
| 7 | Memory Match | **Vollständig** | `GOOBY/src/minigames/games/memoryMatch.js` | `scripts/minigames/games/memory_match/memory_match.gd` |
| 8 | Tea Party | **Vollständig** | `GOOBY/src/minigames/games/teaParty.js` | `scripts/minigames/games/tea_party/tea_party.gd` |
| 9 | Basket Bounce | **Vollständig** | `GOOBY/src/minigames/games/basketBounce.js` | `scripts/minigames/games/basket_bounce/basket_bounce.gd` |
| 10 | Garden Rush | **Vollständig** | `GOOBY/src/minigames/games/gardenRush.js` | `scripts/minigames/games/garden_rush/garden_rush.gd` |
| 11 | Pancake Tower | **Vollständig** | `GOOBY/src/minigames/games/pancakeTower.js` | `scripts/minigames/games/pancake_tower/pancake_tower.gd` |
| 12 | Burger Build | **Vollständig** | `GOOBY/src/minigames/games/burgerBuild.js` | `scripts/minigames/games/burger_build/burger_build.gd` |
| 13 | Shopping Surf | **Vollständig** | `GOOBY/src/minigames/games/shoppingSurf.js` | `scripts/minigames/games/shopping_surf/shopping_surf.gd` |
| 14 | Gooby Runner | **Vollständig** | `GOOBY/src/minigames/games/runner.js` | `scripts/minigames/games/runner/runner.gd` |
| 15 | Veggie Chop | **Vollständig** | `GOOBY/src/minigames/games/veggieChop.js` | `scripts/minigames/games/veggie_chop/veggie_chop.gd` |
| 16 | Purble Place | **Vollständig** | `GOOBY/src/minigames/games/purblePlace.js` | `scripts/minigames/games/purble_place/purble_place.gd` |
| 17 | Snail Mail | **Vollständig** | `GOOBY/src/minigames/games/snailMail.js` | `scripts/minigames/games/snail_mail/snail_mail.gd` |
| 18 | Bubble Pop | **Vollständig** | `GOOBY/src/minigames/games/bubblePop.js` | `scripts/minigames/games/bubble_pop/bubble_pop.gd` |
| 19 | Delivery Rush | **Vollständig** | `GOOBY/src/minigames/games/deliveryRush.js` | `scripts/minigames/games/delivery_rush/delivery_rush.gd` |
| 20 | Lantern Float | **Vollständig** | `GOOBY/src/minigames/games/lanternFloat.js` | `scripts/minigames/games/lantern_float/lantern_float.gd` |
| 21 | Fishing Pond | **Vollständig** | `GOOBY/src/minigames/games/fishingPond.js` | `scripts/minigames/games/fishing_pond/fishing_pond.gd` |
| 22 | Dance Party | **Vollständig** | `GOOBY/src/minigames/games/danceParty.js` | `scripts/minigames/games/dance_party/dance_party.gd` |
| 23 | Mini Golf | **Vollständig** | `GOOBY/src/minigames/games/miniGolf.js` | `scripts/minigames/games/mini_golf/mini_golf.gd` |
| 24 | Trampoline | **Vollständig** | `GOOBY/src/minigames/games/trampoline.js` | `scripts/minigames/games/trampoline/trampoline.gd` |
| 25 | Goalie Gooby | **Vollständig** | `GOOBY/src/minigames/games/goalieGooby.js` | `scripts/minigames/games/goalie_gooby/goalie_gooby.gd` |
| 26 | Star Hopper | **Vollständig** | `GOOBY/src/minigames/games/starHopper.js` | `scripts/minigames/games/star_hopper/star_hopper.gd` |
| 27 | Gooby Welt | **Fehlt** | `GOOBY/src/welt/splatViewer.js`, `welt/weltScenes.js` | Kein Spiel/Manifest in `scripts/minigames/games/`; `minigame_registry.gd` enthält keinen `goobyWelt`-Eintrag. |
| 28 | Pipe Flow | **Vollständig** | `GOOBY/src/minigames/games/pipeFlow.js` | `scripts/minigames/games/pipe_flow/pipe_flow.gd` |
| 29 | Toy Grand Prix | **Vollständig** | `GOOBY/src/minigames/games/toyRacer.js` | `scripts/minigames/games/toy_racer/toy_racer.gd` |
| 30 | Ghost Hunt | **Vollständig** | `GOOBY/src/minigames/games/ghostHunt.js` | `scripts/minigames/games/ghost_hunt/ghost_hunt.gd` |
| 31 | Rocket Rescue | **Vollständig** | `GOOBY/src/minigames/games/rocketRescue.js` | `scripts/minigames/games/rocket_rescue/rocket_rescue.gd` |
| 32 | Harbor Hopper | **Vollständig** | `GOOBY/src/minigames/games/harborHopper.js` | `scripts/minigames/games/harbor_hopper/harbor_hopper.gd` |

**Minigame-Summe: 30 vollständig, 1 teilweise, 1 fehlend = 32.**

Godot besitzt darüber hinaus GvZ, GOB NOM und fünf Ranch-Spiele
(`ranchHerde`, `ranchParcours`, `ranchTonnen`, `ranchTurnier`, `ranchZeit`);
diese sieben Extras erhöhen die Web-Paritätsquote nicht.

## Gesamtsumme

| Sicht | Vollständig | Teilweise | Fehlt | Gesamt |
|---|---:|---:|---:|---:|
| Kernsysteme/Screens/Inhalte | 23 | 15 | 9 | 47 |
| Web-Minispiele | 30 | 1 | 1 | 32 |
| **Gesamt** | **53** | **16** | **10** | **79** |

## Bug-Jagd

### Reproduzierte Defekte

| ID | Schwere | Fund | Reproduktion | Beleg |
|---|---|---|---|---|
| B1 | **P1** | HUD-„Profil“ öffnet den Social-Screen statt eines Profils. | Frischen Save booten, Onboarding beenden, HUD → „Profil“. Überschrift ist „Freunde & Besuche“; Lifetime-Stats/Vitals fehlen. | Screenshot `ui-final/quer_1792x828_05_profil.png`; `home_entry.gd`, `social_screen.gd`. |
| B2 | **P1** | Freigegebene Lambda-Captures werden nach Szenenwechseln auf `null` gesetzt. | `godot --headless --path GOOBY-GODOT --script res://tests/tools/bughunt_fuzz.gd`; Fälle `alles_null`, `alles_voll`, `negativ`, Urlaub, Wecker, 30 Tage, Teilkorruption und Backup. | `extreme-save-route-fuzz.log`: wiederholt `ERROR: Lambda capture at index 0 was freed`. Auch nach Route `album` im Walkthrough. |
| B3 | **P1** | Navigation-Map-Synchronisierung meldet überlappende/inkompatible Kanten. | Hauptsuite headless ausführen; Navigation/Room-Aufbau abwarten. | `godot-main-tests.log`: `ERROR: Navigation map synchronization error`. |
| B4 | **P1** | Renderer-/ObjectDB-/Resource-Leaks bei langen Durchläufen. | Hauptsuite oder 37-Spiele-Walkthrough bis zum regulären Quit laufen lassen. | Hauptsuite: 15 Texturen, 12 Meshes, 9 Materialien, 3 Shader, 10 Instanzen und 23 Ressourcen; Walkthrough ebenfalls RID-/Resource-Leaks. |
| B5 | **P1** | Navigationsmesh wird zur Laufzeit aus GPU-Render-Meshes zurückgelesen. | Haus/Stadt im Headless- oder Renderer-Lauf laden. | Alle großen Läufe: `Source geometry parsing ... RenderingServer meshes ... significant performance issues`. Auf Mobilgeräten ein reales Hitch-/Akku-Risiko. |
| B6 | **P1** | Postkarten-/Post-Aktion endet sichtbar in „Bald“ statt in einem Archivloop. | Urlaub/Postkartenstand laden, Post betreten, Archiv/Aktion auslösen. | `scripts/city/ui/post_sheet.gd` ruft `city.post.bald`; `logic/vacation.gd` erklärt den Archivgenerator als nicht portiert. |
| B7 | **P1** | Gewicht verändert den gespeicherten Wert, aber nicht Goobys sichtbare Silhouette. | Junkfood mehrfach füttern oder Maximal-Save laden; Rig neu aufbauen. | `food_catalog.gd` erhöht Gewicht; `gooby_rig.gd` dokumentiert: „chubby ist Weight-Tier und (noch) kein Rig-Morph“. |
| B8 | **P2** | Garderoben-/Preview-SubViewports versuchen bei aktivem Stretch ihre Größe zu setzen. | HUD → Möbel/Garderobe bzw. UI-Audit; Viewport wechseln. | `full-route-minigame-walkthrough.log`, `extreme-save-route-fuzz.log`, `ui-final.log`: `Can't change the size of a SubViewport...`. |
| B9 | **P2** | Importierte 3.x-Materialien referenzieren den nicht gemappten Parameter `specular`. | Einen Großteil der Arcade-Spiele starten. | Hunderte `Godot 3.x SpatialMaterial remapped parameter not found: specular` im Walkthrough/Haupttest. |
| B10 | **P2** | Navigation-Agentenwerte werden an Voxelgrößen gerundet und verlieren Präzision. | Räume/Stadt laden bzw. Navmesh backen. | Wiederholte `agent_max_climb ... loses precision` und `agent_radius ... loses precision`. |
| B11 | **P2** | Ein Control hat gegensätzliche ungleiche Anchors und verliert seine gesetzte Größe nach `_ready()`. | GvZ im Walkthrough starten. | `full-route-minigame-walkthrough.log`: `Nodes with non-equal opposite anchors...`. |

**P0-Ergebnis:** Kein Absturz und kein Datenverlust reproduziert. Korrupte Saves
werden nicht still überschrieben: abgeschnittene und Zukunfts-Saves lösen
Recovery aus; der explizite Backup-Fall stellt den Wert 777 wieder her.

### Vollständiges Diagnose-Ledger

Nicht jede Logzeile ist ein Produktbug. Damit „alle Fehler/Warnungen“ nicht
selektiv zitiert werden, sind auch absichtlich erzeugte und
umgebungsbedingte Meldungen aufgeführt:

| Diagnose | Einordnung |
|---|---|
| `Lambda capture ... was freed` | echter P1-Defekt, B2 |
| `Navigation map synchronization error` | echter P1-Defekt, B3 |
| PagedAllocator/RID/ObjectDB/resources leaked | echter P1-Stabilitätsdefekt, B4 |
| Runtime-Parsing von RenderingServer-Meshes | echter P1-Performancebefund, B5 |
| SubViewport-Stretch/Resize | echter P2-Defekt, B8 |
| SpatialMaterial `specular` | echter P2-Importbefund, B9 |
| Nav-Agent-Rundung | echter P2-Konfigurationsbefund, B10 |
| Opposite-anchor-Größenwarnung | echter P2-Layoutbefund, B11 |
| `save_manager corrupt save ... trying backups` | im Fuzzer absichtlich; Recovery funktioniert |
| korrupte AppSettings/boot_guard/installed.json | negative Tests, erwartete Warnungen |
| unbekannte Emotion/Cutscene/Game-ID | negative Tests/Kantenfälle, erwartete Guard-Warnungen |
| `Gooby erschöpft — Start verweigert` | erwartete Produktregel |
| fehlender Key `gibt.es.nicht` | absichtlicher i18n-Fallback-Test, kein fehlender echter String |
| VSync, ALSA/Dummy-Audio, Orientation unter Xvfb | Linux/Xvfb-Umgebung, kein Gerätebefund |
| anfänglicher `RewardHub not declared` | veralteter Godot-Class-Cache nach paralleler Änderung; nach `--import` nicht reproduzierbar, daher nicht als Spielbug gewertet |

## Extremspielstände

| Save-Fall | Ergebnis |
|---|---|
| Alles leer/null | Routen beendet; Lambda- und SubViewport-Fehler, kein Crash |
| Alles maximal/voll | Routen beendet; Lambda- und SubViewport-Fehler, kein Crash |
| Negative Werte | normalisiert; Routen beendet, kein Crash |
| Mitten im Urlaub | Routen beendet; Lambda-/Viewport-Fehler |
| Wecker überfällig | Routen beendet; Lambda-/Viewport-Fehler |
| 30 Tage offline | Catch-up beendet; Lambda-/Viewport-Fehler |
| Systemuhr zurückgestellt | defensiv beendet; Viewport-Warnungen |
| Teilwerte korrupt | normalisiert; Lambda-/Viewport-Fehler |
| JSON abgeschnitten | als korrupt erkannt, Backup-Pfad versucht |
| Save-Version 99 | als nicht lesbare Zukunftsversion erkannt |
| Korrupt + gültiges Backup | Backup geladen; Coins exakt 777 |

Der geforderte „ohne Möbel“-Fall wird durch einen leeren `home.rooms`-/
`storage`-Zustand im Null-/Teilkorruptionspfad abgedeckt; Pflichtmöbel-Defaults
und die Räume blieben routbar. Das beweist Robustheit, nicht zwangsläufig eine
gute Spielerführung für einen tatsächlich leergeräumten Haushalt.

## „Alpha oder Spiel?“

### Kann man eine Stunde spielen?

**Technisch wahrscheinlich ja, als beabsichtigtes Vollspiel noch nicht
verlässlich.** Ein Spieler kann ohne offensichtlichen Crash eine Stunde in 30
portierten Web-Minispielen, sieben neuen Spielen, Haus, Garten, Stadt oder
Ranch verbringen. Der automatisierte Lauf startet alle 37 Spiele, prüft
Countdown/Quit/Szenenwechsel/Back-Spam und erreicht alle 24 erfassten Routen.

Das ist aber kein Beweis für eine reale, ununterbrochene Stunde mit normalem
Input und Progression. Der Walkthrough beendet Runden kontrolliert, statt jedes
Spiel minutenlang menschlich zu spielen. Im beabsichtigten Meta-Loop trifft ein
Spieler schnell auf:

- „Profil“ → falscher Social-Screen;
- keine Tagesquests, Erfolge oder Tagesbonus-Claim;
- Schlaflogik ohne fertigen Start-/Weck-Flow;
- Krankheit/Gewicht als Daten ohne vollständige sichtbare Konsequenz;
- Apotheke statt des alten Tierarztes;
- Postkartenaktion „Bald“;
- Radio- und Codes-Logik ohne Oberfläche;
- kein Funkelpark und kein Gooby Welt.

### Gibt es einen roten Faden für neue Spieler?

**Nur teilweise.** Der aktuelle Erststart erklärt Identität und Charakter, aber
nicht den alten geführten Care→Füttern→Bad→Arcade→Shop→Quest→Garten-Bogen.
Haus-HUD und Räume sind verständlich aufgebaut, danach präsentiert das Spiel
viele gleichrangige Systeme. Gerade die im Web als tägliche Leitplanken
dienenden Quests, Bonus-Streak und Erfolge fehlen.

### Ist die Progressionskurve rund?

**Nein, noch nicht als Gesamtprodukt.** XP, Levelbonus, Arcade-Unlocks,
Tages-×2 und Recaps funktionieren. Die mittelfristigen Motivatoren fehlen aber:
Tagesquests, Erfolge, Daily Claim, vollständige Sammlungssets, Urlaubspass,
Park-Progression und ein auswertbares Profil. Dadurch ist die lokale
Rundenbelohnung gut, die Wochen-/Monatskurve aber löchrig.

### Wo wirkt es fertig?

- Arcade-Karten, Pregame, Pause, Resultate, XP und Belohnungsfeedback.
- 30 von 32 alten Spielen plus sieben neue Spiele.
- Stickeralbum mit 140 regulären Stickern und globalem RewardHub.
- Haus, Möbel-/Build-Mode, Garderobe, Garten und die dichte freie Stadt.
- Umfangreiche Einstellungen und saubere DE/EN-Abdeckung.
- Sehr breite automatisierte Suite: 2.074 Godot-Tests, 14.995 UI-Checks.

### Wo wirkt es unfertig?

- Meta-Navigation: Der sichtbare Profilknopf führt semantisch falsch.
- Save-Felder ersetzen mehrfach noch keinen Gameplay-Loop
  (Daily, Achievements, Park, Radio, Codes).
- Sichtbare Platzhalter: Postkarten/Post endet mit „Bald“.
- Care-Tiefe: Schlaf, Krankheit, Tierarzt und Gewicht sind unvollständig.
- Technische Hygiene: Engine-Fehler trotz grünem Testresultat, sehr laute
  Materialwarnungen und bestätigte Ressourcenleaks.

## Priorisierte Restliste (Top 30)

Umfang: **S** = lokal/geringes Risiko, **M** = mehrere Dateien/ein System,
**L** = mehrere Systeme, Content und Integrationsrisiko.

| Prio | Restpunkt | Umfang | Betroffene Systeme / Risiko |
|---:|---|:---:|---|
| 1 | Echtes Profil bauen und HUD-Fehlroute korrigieren | **M** | HUD, Router, Profile/Lifetime-Stats, Bestscores; derzeit sichtbarer Hauptbutton falsch. |
| 2 | Tagesquests vollständig portieren | **L** | 28er-Pool, täglicher Roll, 3 Karten, Fortschritt, Claim, Reroll, Save/Offline. Zentrale neue-Spieler-Leitplanke. |
| 3 | 44 Erfolge samt Rewards und Trophy-Screen portieren | **L** | Katalog, Auswertung, Economy, UI, Migration; aktuell nur Counter. |
| 4 | Handlungsgeführtes Onboarding wiederherstellen | **L** | Care, Räume, Arcade, Shop, Quest, Garten, Resume/Skip; entscheidend für roten Faden. |
| 5 | Schlafen als echten Spielerloop verkabeln | **M** | Bett/Lampe, Sleep-Overlay, früher Weckpfad, Animation, `BadState.mark_woke_up`. |
| 6 | Krankheit, sichtbare Symptome und Heilpfade fertigstellen | **L** | Ticker, Rig/Emotion, Arcade-Gate, Medizin, Feedback. |
| 7 | Tierarztpraxis mit Checkup/Vollheilung bauen | **M** | Stadt-Ort, Economy, Health, UI, Dr. Hoppel; alte Kernlocation fehlt. |
| 8 | Tagesbonus-Claim und Streak-Popup portieren | **M** | Daily-Slice, Offline-Tag, Economy/Items, UI; hohe tägliche Retention-Wirkung. |
| 9 | Funkelpark mit Plaza, Coaster, Riesenrad und Ständen portieren | **L** | Welt/Rendering, Fahrten, Economy, Save, Audio, Sticker; größter fehlender alter Ort. |
| 10 | Radio-Oberfläche inklusive Now Playing, Track-Toggle und Trim | **M** | MusicDirector/Registry sind vorhanden; UI/Persistenz/Bedienung fehlen. |
| 11 | Offline-Codes-Screen und Web-paritäre Einlösung | **M** | UI, lokaler Hash/Katalog, Lockout, Buff/Sticker/Economy; Server-Redeem allein ist nicht gleichwertig. |
| 12 | Modifier-Scheduler, Arcade-Badge, Countdown und Rewards | **L** | Engine, Save, Arcade, Pregame, Spiele, Results; einzelne Apply-Hooks reichen nicht. |
| 13 | Gooby Welt portieren oder bewusst aus dem Produktumfang streichen | **L** | Splat-Renderer/Assets, Arcade, Steuerung, Lizenz/Performance. |
| 14 | Vollständige Foto-Galerie bauen | **L** | Browser, 40er-Cap, Anzeigen, Löschen, Share/Export, Persistenz und Fehlerfälle. |
| 15 | Postkartenarchiv und Souvenirregal fertigstellen | **L** | Vacation-Tick, generierte Karten, Post-UI, Home-Regal; sichtbares „Bald“ entfernen. |
| 16 | Gewichtsstufen auf den Gooby-Rig anwenden | **M** | Rig-Morph, Outfits/Collision/Animation, Save-Wert; gespeicherte Mechanik derzeit unsichtbar. |
| 17 | Ball-Wurf-/Fetch-Interaktion portieren | **M** | Home-Input, Physik/Animation, Fun/Weight, Counter/Sticker. |
| 18 | Lebensmittelkatalog von 26 auf Web-Parität bringen | **M** | Shop/REHWEI, Icons, Effekte, Health/Weight, Lokalisierung. |
| 19 | Urlaubspass, Ziel-Gates und Ziel-Cinematics schließen | **M** | Recap-Gates, Airport-Cards, Cutscenes, Rückkehr/Rewards. |
| 20 | Vier alte Sammlungssets im Album wieder sichtbar machen | **M** | Collections-Slice, Fische/Gemüse/Landmarks/Treats, Claim-Rewards, Album-Navigation. |
| 21 | Gyro-/Pointer-Parallax portieren oder offiziell entfernen | **M** | Sensor/Input, Räume, Settings, Reduced Motion, Gerätefallback. |
| 22 | City Drive als Arcade-Runde mit Score/Resultat ergänzen | **M** | Stadtfahrphysik, Timer, Kollisionen, Coins, Arcade-Registry. |
| 23 | Lambda-Capture-Lebenszyklusfehler beseitigen | **M** | Album/Routen/Callbacks, Save-Fuzz; Risiko still ausfallender UI-Aktionen. |
| 24 | Navigation-Synchronisierungsfehler reproduzierbar lokalisieren/fixen | **L** | Raum-Navmeshes, Kanten/Cell-Size, dynamischer Rebuild. |
| 25 | Laufzeit-Navmesh-Bake von Render-Meshes entfernen | **L** | Collision-Quellen/prozedurale Geometrie; Mobile-Hitch-/Akku-Risiko. |
| 26 | Renderer-/RID-/ObjectDB-Leaks schließen | **L** | Minigame-/Scene-Teardown, SubViewports, Materialien, Ressourcen. |
| 27 | SubViewport-Stretch-/Resize-Konflikt korrigieren | **S** | Garderobe/Möbel-/3D-Preview; Warnspam und mögliches falsches Preview-Seitenverhältnis. |
| 28 | Alte SpatialMaterial-`specular`-Imports bereinigen | **M** | Viele Minigame-Assets; Logsignal und Materialparität. |
| 29 | Einheitlichen Wetterdienst für Haus/Garten/Stadt verdrahten | **M** | Wetterzustand, FX, Regenbewässerung, Fenster/Stadt, Offline-Tag. |
| 30 | Semantischen E2E-„erste Stunde“-Test ergänzen | **L** | Echter Input: Tutorial, Care, Shop, Quest, Garten, 3 Spiele, Save/Reload; aktuelle Smoke-Tests prüfen primär Erreichbarkeit. |

## Schlussfolgerung

Die Rewrite-Basis ist groß und real: 30/32 alte Minispiele, sieben neue Spiele,
Haus, Garten, Stadt, Ranch, Album und ein belastbarer Save-Kern. „Fast alles
fehlt“ beschreibt den aktuellen Code nicht.

Was weiterhin fehlt, sind ausgerechnet mehrere Systeme, die aus viel Content
ein zusammenhängendes Spiel machen: Einstieg, Profil, tägliche Ziele,
Erfolge, Tagesbonus und einige ikonische Orte/Activities. Solange diese
Lücken und die reproduzierten Engine-Fehler bestehen, wäre die Bezeichnung
„Vollversion“ irreführend. „Spielbare Content-Alpha“ ist die faire,
belegbare Einordnung.
