# EVAL-2 — unabhängige Vollständigkeits- und Qualitätsprüfung

Stand: 27. Juli 2026 · Godot 4.4.1 · Vergleichsquelle: aktueller Inhalt von
`/workspace/GOOBY/src/**` gegen `/workspace/GOOBY-GODOT/**`.

> **Revision FERTIG-1 (27. Juli 2026, nach den Wellen REST-1…4/W10 und dem
> FERTIG-1-Pass):** jede „teilweise“- und „fehlt“-Zeile wurde erneut am Code
> nachgeprüft. Zeilen, deren Status sich geändert hat, tragen den Vermerk
> *(FERTIG-1 nachgeprüft)* im Godot-Beleg. Die EVAL-2-Testartefakte unter
> `/tmp/gooby-godot/artifacts/EVAL2/` beschreiben weiterhin den ALTEN Lauf;
> neue Belege dieser Revision liegen unter
> `/tmp/gooby-godot/artifacts/FERTIG1/`.

> **Revision W13 (31. Juli 2026, statische Code-Nachprüfung der
> W13-Planungswelle):** Die Bug-Zeilen B2–B11 wurden nach dem
> W10/REST5-Bug-Sweep (Commit `3e1d6c29`, „533 warnings → 5“) erneut am Code
> geprüft. **B2, B3, B5, B8, B9 und B10 sind BEHOBEN** (Belege in der
> Bug-Tabelle), **B4 ist teilweise behoben** (Nav-Map-RIDs werden freigegeben,
> Star-Hopper-Vorlagen-Leak gefixt; ein systematisches Leak-Gate über alle
> 37 Spiele fehlt), **B11 bleibt offen** und ist in W13 beim GvZ-Paket in
> Arbeit. Die Restlisten-Zeilen 23–28 sind entsprechend aktualisiert. Die
> FERTIG-1-Zahlen (70/79) und das Kurzurteil bleiben unverändert gültig; die
> offenen Feature-Restpunkte (Ball, Sammlungssets, Wetter-FX, Speisen/Nougat,
> Radio-Gate u. a.) sind Gegenstand der laufenden W13-Runde.

> **Revisionsnotiz W18 (2. August 2026, Doku-Refresh — Log-Abgleich, KEINE
> erneute zeilenweise Code-Prüfung):** Die in der W13-Revision noch offenen
> Feature-Restpunkte sind laut Wellen-Abnahmen im git-Log **mit W13
> gelandet**: Ball-Wurf, Sammlungssets im Album (inkl. Award-Verdrahtung),
> Wetter-FX in Haus/Garten/Stadt, 9 neue Speisen + Nougatschleuse,
> Radio-Gates, Fotomodus-Werkzeuge + Gyro-Parallax, City Drive als
> Arcade-Runde, semantischer E2E-„erste Stunde“-Test **und das B4-Leak-Gate
> (38 Spiele, 0 Orphans)**; B11 wurde im W13-GvZ-Paket verdrahtet (ein
> Warn-Sweep-Nachfasser aus der verlorenen Welle G6 ist neu einsortiert).
> Die Matrix-Zahlen dieser Datei (70/79) sind damit **konservativ veraltet**
> — nach unten hin ehrlich, real dürfte die Web-Parität höher liegen. Alles
> seit W14 (UI-Full-Rework, DLC-Fundamente „Goo und Bye“/„McGooby“,
> Marktstand, Urlaubs-Besuche, GvZ-PvP übers Netz, Läden-Ambient,
> Playtest-Harness …) liegt ZUSÄTZLICH über dem Web-Parität-Maßstab dieser
> Matrix und wird in `STATUS.md` (Wellen-Absätze W15–W18) geführt. Eine
> erneute unabhängige Vollprüfung nach dem Muster von EVAL-2/FERTIG-1 steht
> aus und wäre der saubere nächste Schritt, wenn die Zahlen wieder belastbar
> zitiert werden sollen. Das Projekt lebt seit W18 in
> `MedusaV9/ModdingWebseite` (Branch `cursor/bubble-shield-loop`).

## Kurzurteil

Die Aussage **„fast alles von davor fehlt“ ist nicht mehr haltbar** — und
seit der Revision gilt auch „es ist eine Alpha“ nur noch eingeschränkt. In
der gleichgewichteten Matrix aus 79 prüfbaren Web-Features sind jetzt
**70 vollständig, 5 teilweise, 3 nicht umgesetzt und 1 offiziell
gestrichen** (Gooby Welt, begründete Produktentscheidung, s. Zeile B-27).
Das entspricht rund 90 % vollständig.

Bei den 47 übergeordneten Spiel- und Meta-Systemen sind **40 vollständig,
4 teilweise und 3 fehlend**. Die früheren Kernlücken (Profil, Erfolge,
Tagesbonus, Tagesquests, geführtes Onboarding, Schlaf/Krankheit/Tierarzt/
Gewicht, Funkelpark, Radio, Codes, Galerie, Postkarten, Arcade-Modifier)
sind umgesetzt und testgedeckt. Offen bleiben: Ball-Wurf, die vier alten
Sammlungssets als eigenes Album-UI, Gyro-Parallax sowie Teilaspekte von
Lebensmittelkatalog, Wetter-FX, Fotomodus-Werkzeugen und Nougatschleuse.

Das revidierte Label lautet:

> **Inhaltlich komplettes Spiel mit wenigen bewusst dokumentierten
> Restlücken — kein Alpha-Zustand mehr, Feinschliff-Phase.**

Es gab im Test **keinen reproduzierten P0-Absturz und keinen Datenverlust**.
Der volle Routen-/Minigame-Durchlauf erreichte 24 Routen und startete/beendete
alle 37 registrierten Spiele. Die in EVAL-2 genannten harten semantischen
Lücken des Langzeit-Loops (Profil, Tagesquests, Erfolge, Tagesbonus,
Tierarzt, Funkelpark, Galerie, Radio- und Code-Oberflächen) sind in der
Revision **alle geschlossen** und über eigene Testdateien
(`tests/unit/test_rest*` u. a.) abgesichert.

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

Der HUD-Punkt „Profil“ öffnete zum EVAL-2-Zeitpunkt fälschlich „Freunde &
Besuche“ (inzwischen behoben — er öffnet den echten Profil-Screen, s. Zeile
A-28 und Ex-Bug B1):

![Profil-Fehlroute](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_05_profil.png)

Ein vollständiger Arcade-Ergebnisloop mit Score, Sternen, Coins, XP,
Tagesbonus und Level-up ist vorhanden:

![Minigame-Ergebnis](/tmp/gooby-godot/artifacts/EVAL2/ui-final/quer_1792x828_09_mg_results.png)

## Feature-Matrix A — Systeme, Screens und Inhalte (47)

| # | Web-Feature | Status | Web-Beleg | Godot-Beleg und Bewertung |
|---:|---|---|---|---|
| 1 | Boot, Loading, Szenenwechsel | **Vollständig** | `GOOBY/src/main.js`, `GOOBY/src/core/sceneManager.js`, `GOOBY/src/ui/loadingVeil.js` | `GOOBY-GODOT/scripts/boot/main.gd`, `scripts/core/scene_router.gd`, `scripts/core/loading_veil.gd`; Boot und 24 Ziele durchlaufen. |
| 2 | Save, Validierung, Migration, Recovery | **Vollständig** | `GOOBY/src/core/save.js`, `GOOBY/src/core/store.js` | `scripts/state/save_schema.gd`, `save_manager.gd`, `migration_v4.gd`, `state/import/transfer_service.gd`; abgeschnittene und Zukunfts-Saves werden abgefangen, Backup mit 777 Coins wurde korrekt geladen. |
| 3 | Erststart-Tutorial | **Vollständig** | `GOOBY/src/ui/onboarding.js`: Streicheln, Füttern, Bad, HUD, Carrot Catch, Shop, Quest/Garten | *(FERTIG-1 nachgeprüft)* `scripts/ui/onboarding/onboarding_flow.gd` (Willkommen/Name/Editor) PLUS handlungsgeführte Tour `onboarding_guide.gd`/`onboarding_guide_logic.gd` (Port der Web-Schrittfolge: ankunft/streicheln/fuettern/waschen/muenzen/minispiel/moebel/sticker/ausblick, Erfüllung über echte Save-Zähler); Tests `test_ui_onboarding*.gd`. |
| 4 | Fünf Räume und Navigation | **Vollständig** | `GOOBY/src/home/rooms/{kitchen,living,bathroom,bedroom,garden}.js`, `ui/roomNav.js` | `scripts/home/rooms/*.gd`, `room_defs.gd`, `door_transition.gd`; living, bathroom, bedroom, garden und kitchen im Durchlauf besucht. |
| 5 | Vier Care-Stats und Offline-Catch-up | **Vollständig** | `GOOBY/src/systems/stats.js`, `offline.js`, `core/timeEngine.js` | `scripts/logic/stats.gd`, `offline.gd`, `state/gooby_ticker.gd`; Live-Tick und Catch-up sind produktiv verkabelt. |
| 6 | Füttern aus dem Kühlschrank | **Vollständig** | `GOOBY/src/home/interactions.js`, `systems/inventory.js` | `scripts/home/interactables/kuehlschrank.gd`, `logic/food_catalog.gd`; Vorrat, Animation, Stat-Deltas und Sticker-Hook sind verkabelt. |
| 7 | Voller Lebensmittel-/Item-Katalog | **Teilweise** | `GOOBY/src/data/foods.js` enthält 39 Speisen plus Medizin/Dünger | *(FERTIG-1 nachgeprüft, verbessert)* `scripts/logic/food_catalog.gd` implementiert jetzt 32 erreichbare IDs — neu: `donut-sprinkles`/`hot-dog`/`pancakes` im REHWEI-Sortiment (vorhandene Kenney-GLBs) und die drei Funkelpark-Naschgassen-Speisen (`cottonCandy`/`softServe`/`waffle`) mit echten Web-Deltas statt Fallback-Snack. 26 der 39 Web-IDs sind gedeckt; die restlichen 12 (`ice-cream`, `cake`, `radish`, `eggplant`, `pumpkin`, `lollypop`, `candy-bar`, `corn-dog`, `sundae`, `nutella`, `cupcakePink`, `cinnamonRoll`) fehlen mangels 3D-Assets weiterhin. |
| 8 | Waschen, Dusche, Toilette, Zähne | **Vollständig** | `GOOBY/src/home/interactions.js`, `ui/careSheet.js` | `scripts/home/interactables/klo_dusche.gd`, `zahnputz.gd`, `bad_state.gd`; inklusive Timer, Bürstenbruch und Zähler. |
| 9 | Streicheln, Kitzeln, Poken/Schwindel | **Vollständig** | `GOOBY/src/home/interactions.js` | `scripts/home/gooby_reactions.gd`; Tap-/Pet-Kaskade, Tickles, Schwindel und Feedback vorhanden. |
| 10 | Ball werfen/Fangen | **Fehlt** | `GOOBY/src/home/interactions.js` | *(FERTIG-1 nachgeprüft)* Unverändert kein Ball-Interactable in `scripts/home/interactables/`; nur der `balls`-Lifetime-Zähler existiert (Profil-Statistik zeigt dauerhaft 0). |
| 11 | Schlafen, frühes Wecken, Schlaf-UI | **Vollständig** | `GOOBY/src/systems/sleep.js`, `ui/sleepFlow.js` | *(FERTIG-1 nachgeprüft)* `scripts/home/interactables/bett.gd` (Schlafen/Nickerchen/Geschichte/Sanft wecken inkl. Grumpy-Debuff) + `scripts/home/sleep/pflege_runner.gd` (Aufwach-Inszenierung); Tests `test_rest3_schlafzyklus.gd`, `test_logic_sleep.gd`. |
| 12 | Krankheit und Medizin | **Vollständig** | `GOOBY/src/systems/health.js`, `ui/vetPanel.js` | *(FERTIG-1 nachgeprüft)* sichtbare Symptome im Rig (`gooby_rig.gd`: Blässe, Schniefnase, Eisbeutel, Augenringe), Medizin über GOOBYTHEKE/Rezept-Flow, Heilung beim Tierarzt (Zeile 38); Test `test_rest3_krankheit.gd`. |
| 13 | Gewicht und vier sichtbare Körperstufen | **Vollständig** | `GOOBY/src/systems/weight.js`, `character/gooby.js` | *(FERTIG-1 nachgeprüft)* `gooby_rig.gd` wendet Gewicht wie die Web-`TIER_SCALE` als Körper-X/Z-Skalierung über `Weight.body_scale()` an (bewusst kein Shapekey — der Rig-Vertrag hat keinen „chubby“-Morph); Test `test_rest3_gewicht.gd`. |
| 14 | Garten: Pflanzen, Wässern, Wachstum, Ernte, Ausbau | **Vollständig** | `GOOBY/src/systems/garden.js`, `home/gardenInteractions.js`, `ui/gardenPanel.js` | `scripts/home/garden/{garden_host,garden_state,garden_growth,garden_crops,garden_world}.gd`; inklusive Echtzeitwachstum, Regenparameter, Schatten, Gewächshaus/Sprinkler. |
| 15 | Shop und Economy-Guards | **Vollständig** | `GOOBY/src/ui/shopScreen.js`, `systems/economy.js`, `systems/inventory.js` | `scripts/shop/ikea_screen.gd`, `logic/economy.gd`, `shop/shop_catalog.gd`; Kaufpfade und Tages-/Endlos-Caps getestet. |
| 16 | Möbel, Build-Mode, Platzierung, Lager | **Vollständig** | `GOOBY/src/systems/furniturePlacement.js`, `home/decor.js` | `scripts/home/build_mode/build_mode.gd`, `furniture_catalog.gd`, `storage_logic.gd`, `home_state.gd`; Pflichtmöbel-Schutz und Storage vorhanden. |
| 17 | Garderobe, vier Slots, Fellfarben | **Vollständig** | `GOOBY/src/ui/wardrobeScreen.js`, `character/outfitAttach.js`, `data/skins.js` | `scripts/cosmetics/wardrobe_screen.gd`, `cosmetics_state.gd`, `content/cosmetics/data/cosmetics.json` (92 Einträge); Live-Vorschau und Kauf/Equip. |
| 18 | Tag-/Nacht-Licht | **Vollständig** | `GOOBY/src/systems/dayNight.js`, `gfx/sky.js` | `scripts/home/home_licht.gd`, `city/city_ambiente.gd`, `world/himmel.gd`; weiche Tagesverläufe und Nachtprofile getestet. |
| 19 | Wetter in Haus, Garten und Stadt | **Teilweise** | `GOOBY/src/systems/weather.js`, `gfx/weatherFx.js` | *(FERTIG-1 nachgeprüft, verbessert)* Es gibt inzwischen EINEN deterministischen Zuhause-Wetterdienst (`scripts/soul/soul_wetter.gd`, Datum+Seed → Tagesplan inkl. Winter-Schnee), der Garten-Bewässerung (`garden_growth.gd`), Frier-Reaktionen (`gooby_ticker.gd`) und Gooby-Reaktionen speist. Sichtbarer Regen-/Schnee-Partikeleffekt in Haus/Stadt fehlt weiterhin. |
| 20 | Lokale Care-Benachrichtigungen | **Vollständig** | `GOOBY/src/core/notifications.js`, `systems/notifyRules.js` | *(FERTIG-1 nachgeprüft)* `notification_service.gd` ist als Autoload „Notify“ registriert und stellt fällige Einträge als In-App-Banner zu (Kategorien/Ruhezeiten über `notify_rules.gd`); Care-Quellen (`klo_dusche.gd`, `zahnputz.gd`, Taxi/Reise) planen `pflege_*`-Einträge. Native Zustellung bei GESCHLOSSENER App bleibt ein ehrlich dokumentierter Plugin-Andockpunkt (wie im Web, das ebenfalls nur bei offener Seite zustellte). Test `test_settings_notify.gd`. |
| 21 | XP, Level, Unlocks, Coin-Levelbonus | **Vollständig** | `GOOBY/src/systems/leveling.js`, `ui/xpInfoSheet.js` | `scripts/logic/leveling.gd`, `state/rewards/level_up_feier.gd`, `minigames/minigame_award.gd`; Ergebnis-Screenshot zeigt XP und Levelbonus. |
| 22 | Erstes Spiel pro Tag ×2 | **Vollständig** | `GOOBY/src/data/minigames.js`, `minigames/framework.js` | `scripts/minigames/minigame_award.gd`, `results.gd`; Screenshot zeigt „Tagesbonus ×2“. |
| 23 | Tagesbonus-Streak | **Vollständig** | `GOOBY/src/systems/dailyBonus.js`, `ui/dailyBonusPopup.js` | *(FERTIG-1 nachgeprüft)* `scripts/logic/daily/daily_bonus.gd` + `daily_bonus_popup.gd` (Claim, Streak, Popup, Anzeige im Profil); Test `test_rest1_daily.gd`. |
| 24 | Drei Tagesquests + Reroll/Claim | **Vollständig** | `GOOBY/src/data/quests.js`, `systems/quests.js`, `ui/questBoard.js` | *(FERTIG-1 nachgeprüft)* `scripts/logic/quests/{quest_catalog,quest_engine,quest_service}.gd` — täglicher Roll, 3 Karten, Fortschritt, Claim, Abschluss-Bonus, 1× täglicher Reroll, eigener HUD-Knopf `quests`; Pool 24 Quests (`content/quests/data/quests.json`, Web: 28). Test `test_rest2_quest_engine.gd`. |
| 25 | Erfolge mit Fortschritt und Coin-Rewards | **Vollständig** | `GOOBY/src/data/achievements.js` (44), `systems/achievementsEngine.js`, `ui/achievementsScreen.js` | *(FERTIG-1 nachgeprüft)* 44 Erfolge in `content/achievements/data/achievements.json`, Auswertung `scripts/logic/achievements/achievements_engine.gd`, Screen `scripts/ui/profil/achievements_screen.gd` (aus dem Profil erreichbar); Test `test_rest1_achievements.gd`. |
| 26 | Stickerbuch/Album | **Vollständig** | `GOOBY/src/data/stickers.js` (84 regulär + geheim), `systems/stickerBook.js`, `ui/albumScreen.js` | `scripts/ui/album/{album_screen,sticker_catalog,sticker_unlocks}.gd`, `state/rewards/reward_hub.gd`, `content/stickers/data/stickers.json` (141 Einträge); UI zeigt 140 reguläre Sticker. |
| 27 | Vier alte Sammlungssets (Fische/Gemüse/Landmarks/Treats) | **Fehlt** | `GOOBY/src/systems/collections.js`, `ui/albumScreen.js` | *(FERTIG-1 nachgeprüft)* Weiterhin kein eigenes Set-/Claim-UI: `save_schema.gd` migriert `collections`, und `achievements_engine.gd`/`sticker_unlocks.gd` WERTEN `collections.entries/claimedSets` inzwischen für Erfolge/Sticker aus — sichtbar gemacht werden die vier Web-Sets im Album aber nicht. |
| 28 | Profil mit Vitals, Lifetime-Stats und Bestscores | **Vollständig** | `GOOBY/src/ui/profileScreen.js`, `systems/profileStats.js` | *(FERTIG-1 nachgeprüft)* `scripts/ui/profil/profil_screen.gd` — GOOBY-PASS mit echtem 3D-Porträt, Level (jetzt sichtbar „x / 40“), Lifetime-Statistik, Lieblingen, Erfolgs-/Sticker-Fortschritt, Minispiel-Rekorden, Freunden UND der neuen Spiel-Abschluss-Karte (`abschluss_logic.gd`, Langzeit-Ziel in Prozent); HUD-Fehlroute (Ex-Bug B1) ist korrigiert. Tests `test_rest1_profil.gd`, `test_abschluss_logic.gd`. |
| 29 | Fotomodus | **Teilweise** | `GOOBY/src/ui/photoMode.js` mit Pose, Emotion, Rahmen | *(FERTIG-1 nachgeprüft)* `scripts/city/phone/foto_modus.gd` knipst jede laufende Szene (Sucher, Blitz, 40er-Index, POW-Kamera-Gate); Pose-/Emotions-/Rahmenwerkzeuge fehlen weiterhin. |
| 30 | Persistente Galerie, Anzeigen, Teilen, Löschen, 40er-Cap | **Vollständig** | `GOOBY/src/core/photoStore.js`, `systems/gallery.logic.js`, Album-Fototab | *(FERTIG-1 nachgeprüft)* `scripts/ui/galerie/{galerie_screen,galerie_logic}.gd`: Browser mit Vollbild, Favoriten, Löschen mit Nachfrage, Datum/Ort, Speicheranzeige (n/40) und echtem Foto-Export in den System-Bilderordner (FERTIG-1 statt des alten „Teilen bald“-Hinweises). Test `test_rest4_galerie.gd`. |
| 31 | Level-Rekap/Cinematic und Historie | **Vollständig** | `GOOBY/src/systems/recap*.js`, `ui/recapOverlay.js`, `recap/vignettes.js` | `scripts/recap/{recap_service,recap_engine,recap_director,recap_scene}.gd`; Queue, Historie und Cinematic vorhanden. |
| 32 | Zeitlich begrenzte Arcade-Modifikatoren | **Vollständig** | `GOOBY/src/systems/modifierEngine.js`, `ui/modifierGlow.js` | *(FERTIG-1 gebaut)* `scripts/minigames/modifier_engine.gd` — vollständiger Port: 6-Typen-Pool (Doppel-Gold, Münzregen, Turbo, Lernrausch, Federleicht, Glückspilz), Level-Freischaltung, deterministischer Scheduler (Save-Slice `modifiers`, additiv), Grace-Period, Consume/Refund pro Runde. Sichtbar: Arcade-Kachel-Badge (`arcade_screen.gd`), Pregame-Banner mit Restzeit (`pregame.gd`), Start-Toast (`reward_hub.gd`), Wirkung + Bonuszeilen im Ergebnis (`minigame_award.gd`, `results.gd`) — wirkt über das Framework auf ALLE Spiele. Tests `test_modifier_engine.gd`, `test_modifier_ui.gd`. |
| 33 | Radio mit Sendern, Now Playing, Track-Toggles und Trim | **Vollständig** | `GOOBY/src/ui/radioScreen.js`, `audio/radioPlayer.js`, `systems/musicRegistry.js` | *(FERTIG-1 nachgeprüft)* `scripts/ui/radio/{radio_sheet,radio_logic}.gd`: Senderwahl mit Level-Schlössern, Jetzt-läuft, An/Aus, Nächster Titel, Musik-Lautstärke, Lieblingssongs, Titelliste. Track-Trim bleibt Datenpflege (`music_registry.gd` `gain_trim`) statt Spieler-Bedienung — bewusste Reduktion. Test `test_rest4_radio.gd`. |
| 34 | Offline-Geheimcodes und Lockout | **Vollständig** | `GOOBY/src/data/codes.js`, `systems/codesEngine.js`, `ui/codesScreen.js` | *(FERTIG-1 nachgeprüft)* `scripts/ui/codes/{codes_engine,codes_screen}.gd` — Offline-Einlösung über den puren Katalog, Lockout, Verlauf, Feier, Route `codes` (Settings → Spiel). Test `test_rest4_codes.gd`. |
| 35 | Einstellungen, Accessibility, Grafik, Audio, Dev-Menü | **Vollständig** | `GOOBY/src/ui/settingsScreen.js`, `devPanel.js`, `settings.logic.js` | `scripts/ui/settings_screen.gd`, `settings/dev_unlock_dialog.gd`, `dev/dev_menu.gd`, `core/app_settings.gd`; umfangreicher als die Web-Oberfläche. |
| 36 | Gyro-/Pointer-Parallax | **Fehlt** | `GOOBY/src/systems/gyroParallax.js` | *(FERTIG-1 nachgeprüft)* Weiterhin kein Raum-Parallax-Dienst; ein `parallax`-Settings-Flag wird nur migriert (`migration_v4.gd`), Gyro-Eingabe existiert isoliert in der Ranch-Fahrsteuerung (`ranch/gameplay/ride_touch.gd`). |
| 37 | Freie Stadtfahrt und Orte/Landmarks | **Vollständig** | `GOOBY/src/city/cityBuilder.js`, `minigames/games/cityDrive.js`, `systems/shopTrip.js` | `scripts/city/city_scene.gd`, `city_bau.gd`, `city_map.gd`, `orte/*.gd`; 9 Innenräume wurden als eigene Routen besucht, Stadt besitzt Verkehr/Fußgänger. |
| 38 | Tierarztpraxis mit Checkup und Vollheilung | **Vollständig** | `GOOBY/src/city/vetClinic.js`, `ui/vetPanel.js` | *(FERTIG-1 nachgeprüft)* `city/orte/tierarzt.gd` — betretbare Praxis „Dr. Dr. Möhrchen“ mit Wartezimmer, Untersuchungs-Sequenz, Checkup (30) und Behandlung (120, `Health.pay_vet`) bzw. Rezept-Flow zur GOOBYTHEKE; eigener Karten-Ort in `city_map.json`. Test `test_rest3_tierarzt.gd`. |
| 39 | Urlaub: 9 Ziele, Buchen, Taxi, Abholen | **Vollständig** | `GOOBY/src/data/vacations.js`, `systems/vacation.js`, `ui/airportScreen.js`, `vacation/vacationCinematic.js` | *(FERTIG-1 nachgeprüft)* `scripts/logic/vacation.gd` (Phasen-Maschine), `city/travel/{reise_app,reise_logic,reise_cutscene}.gd`, `city/orte/flughafen.gd`; Archiv-Nachzug läuft im Vacation-Tick mit. Tests `test_logic_vacation.gd`, `test_city_reise.gd`. |
| 40 | Postkartenarchiv und Souvenirregal | **Vollständig** | `GOOBY/src/systems/postcards.js`, `home/souvenirShelf.js` | *(FERTIG-1 nachgeprüft)* Archiv-Generator portiert in `scripts/ui/postkarten/postkarten_logic.gd` (vom Vacation-Tick mitgezogen), Screen `postkarten_screen.gd` inkl. Souvenirregal (ein Slot je Reiseziel) und Set-Bonus. Der Post-Schalter endet nicht mehr in „Bald“: FERTIG-1 ersetzt den alten Multiplayer-Versand-Hook durch das TAGESPAKET (`city/ui/post_logic.gd`, 1 Paket/Lokaltag, 15–40 Münzen, seeded). Tests `test_rest4_postkarten.gd`, `test_post_paket.gd`. |
| 41 | Funkelpark: Plaza, Coaster, Riesenrad, Stände | **Vollständig** | `GOOBY/src/park/parkScene.js`, `park/coasterRide.js`, `park/ferrisWheel.js`, `ui/parkStall.js` | *(FERTIG-1 nachgeprüft)* `scripts/park/{funkelpark,coaster_ride,ferris_wheel,autoscooter,park_stall,park_state}.gd` — begehbare Parkszene mit Fahrten und Naschgassen-Ständen (deren Speisen seit FERTIG-1 echte Katalog-Deltas haben, s. Zeile 7); eigener Karten-Ort. Test `test_rest4_park.gd`. |
| 42 | Musik, SFX und Gooby-Stimme | **Vollständig** | `GOOBY/src/audio/*`, `systems/musicRegistry.js` | `scripts/audio/{audio_director,music_director,music_registry,sfx_map}.gd`, `character/gooby_voice.gd`; Kontextmusik, Crossfade, SFX und Stimme vorhanden. |
| 43 | Deutsch/Englisch | **Vollständig** | `GOOBY/src/data/strings.js`, `data/strings/*` | `GOOBY-GODOT/strings/de/**`, `strings/en/**`, `scripts/core/i18n.gd`; 14.995 UI-Checks bestätigen Parität. |
| 44 | Credits und „Was ist neu?“ | **Vollständig** | `GOOBY/src/ui/creditsScreen.js`, `whatsNew.js` | `scripts/ui/settings_screen.gd` enthält About/Credits; `ui/news_50_panel.gd` liefert Patchnotes/News. |
| 45 | Nutella und Nougatschleuse | **Teilweise** | `GOOBY/src/systems/nougat.logic.js`, `home/interactions.js` | *(FERTIG-1 nachgeprüft)* Unverändert: Nutella-Events/Nougat-Hindernisse und der `easterEggs.nougat`-Save-Slice existieren, die installierbare Küchen-Nougatschleuse als Interactable fehlt weiterhin (auch Nutella selbst ist mangels Asset nicht im Lebensmittelkatalog, s. Zeile 7). |
| 46 | Arcade-Shell, Pregame, Pause, Results | **Vollständig** | `GOOBY/src/ui/arcadeScreen.js`, `pregameScreen.js`, `minigames/framework.js` | `scripts/minigames/{arcade_screen,pregame,minigame_host,results}.gd`, `ui/pause_modal.gd`; kompletter Flow im UI-Audit und Walkthrough. |
| 47 | Leicht/Mittel/Schwer/Endlos | **Vollständig** | `GOOBY/src/data/difficultyTargets.js`, `minigames/framework.js` | Game-Manifeste, Pregame und Host führen Modus/Target/Endlos; alle registrierten Spiele starteten. |

**Kernsystem-Summe (Revision FERTIG-1): 40 vollständig, 4 teilweise
(7 Lebensmittelkatalog, 19 Wetter-FX, 29 Fotomodus-Werkzeuge,
45 Nougatschleuse), 3 fehlend (10 Ball, 27 Sammlungssets,
36 Gyro-Parallax) = 47.**
*(EVAL-2-Ausgangswert: 23 vollständig, 15 teilweise, 9 fehlend.)*

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
| 27 | Gooby Welt | **Gestrichen** | `GOOBY/src/welt/splatViewer.js`, `welt/weltScenes.js` | *(FERTIG-1 entschieden)* Offiziell aus dem Produktumfang gestrichen statt portiert. Begründung: Die Web-Fassung ist ein Gaussian-Splat-Betrachter (kein Spiel-Loop, keine Punkte/Belohnung); Godot 4.4 hat keinen brauchbaren Splat-Renderer, die `.splat`-Assets wären zusätzliche Downloads mit Mobil-Performance-Risiko, und der Betrachter zahlt nicht auf den Care-/Arcade-Kern ein. Aufgeräumt: kein Registry-/Katalog-Eintrag, keine Spieler-Strings; der Musik-Track `game-splat-wunderwelt` bleibt als reiner Radio-Song ohne toten Spiel-Kontext (`music_registry.gd`). |
| 28 | Pipe Flow | **Vollständig** | `GOOBY/src/minigames/games/pipeFlow.js` | `scripts/minigames/games/pipe_flow/pipe_flow.gd` |
| 29 | Toy Grand Prix | **Vollständig** | `GOOBY/src/minigames/games/toyRacer.js` | `scripts/minigames/games/toy_racer/toy_racer.gd` |
| 30 | Ghost Hunt | **Vollständig** | `GOOBY/src/minigames/games/ghostHunt.js` | `scripts/minigames/games/ghost_hunt/ghost_hunt.gd` |
| 31 | Rocket Rescue | **Vollständig** | `GOOBY/src/minigames/games/rocketRescue.js` | `scripts/minigames/games/rocket_rescue/rocket_rescue.gd` |
| 32 | Harbor Hopper | **Vollständig** | `GOOBY/src/minigames/games/harborHopper.js` | `scripts/minigames/games/harbor_hopper/harbor_hopper.gd` |

**Minigame-Summe (Revision FERTIG-1): 30 vollständig, 1 teilweise
(City Drive als Arcade-Runde), 0 fehlend, 1 offiziell gestrichen
(Gooby Welt) = 32.**

Godot besitzt darüber hinaus GvZ, GOB NOM und fünf Ranch-Spiele
(`ranchHerde`, `ranchParcours`, `ranchTonnen`, `ranchTurnier`, `ranchZeit`);
diese sieben Extras erhöhen die Web-Paritätsquote nicht.

## Gesamtsumme (Revision FERTIG-1)

| Sicht | Vollständig | Teilweise | Fehlt | Gestrichen | Gesamt |
|---|---:|---:|---:|---:|---:|
| Kernsysteme/Screens/Inhalte | 40 | 4 | 3 | 0 | 47 |
| Web-Minispiele | 30 | 1 | 0 | 1 | 32 |
| **Gesamt** | **70** | **5** | **3** | **1** | **79** |

*(EVAL-2-Ausgangswert: 53 vollständig, 16 teilweise, 10 fehlend.)*

## Bug-Jagd

### Reproduzierte Defekte

| ID | Schwere | Fund | Reproduktion | Beleg |
|---|---|---|---|---|
| B1 | ~~P1~~ **BEHOBEN** | HUD-„Profil“ öffnete den Social-Screen statt eines Profils. | Fix (REST-1): `home_entry.gd` dispatcht `profil` an `ProfilScreen.handle_hud_action`; „Freunde & Besuche“ bleibt aus dem Profil erreichbar. | `scripts/ui/profil/profil_screen.gd`, Test `test_rest1_profil.gd`. |
| B2 | ~~P1~~ **BEHOBEN** | Freigegebene Lambda-Captures werden nach Szenenwechseln auf `null` gesetzt. | Fix (W10/REST5): Methoden-Callables statt Timer-Lambdas (u. a. `gooby_reactions.gd`); Tripwire-Test scannt den GESAMTEN Quellbaum auf `timeout.connect(func…)` (Allowlist: 2 verifiziert sichere Fälle in `funkelpark.gd`). | `tests/unit/test_rest5_bugfixes.gd::test_keine_timer_lambdas_im_quellcode`. |
| B3 | ~~P1~~ **BEHOBEN** | Navigation-Map-Synchronisierung meldet überlappende/inkompatible Kanten. | Fix (W10/REST5): private `NavigationServer3D`-Map je Raum (`scripts/home/room_navmesh.gd::attach_private_map`), genutzt in `room_base.gd` und `visit_room_view.gd`. | Tests `test_rest5_bugfixes.gd::test_private_map_lebenszyklus`, `::test_zwei_raeume_bekommen_verschiedene_maps`. |
| B4 | **P1 — teilweise behoben** | Renderer-/ObjectDB-/Resource-Leaks bei langen Durchläufen. | Teil-Fix (W10/REST5): private Nav-Map-RIDs werden freigegeben (`room_navmesh.gd::free_private_map`, aufgerufen aus `room_base.gd`/`visit_room_view.gd`), Star-Hopper-Vorlagen-Leak gefixt (weakref-Test); Commit nennt „533 warnings → 5“. OFFEN: kein systematisches Teardown-/Leak-Gate über alle 37 Spiele. | `test_rest5_bugfixes.gd::test_star_hopper_gold_vorlage_wird_freigegeben`; Restrisiko s. Restliste #26. |
| B5 | ~~P1~~ **BEHOBEN** | Navigationsmesh wird zur Laufzeit aus GPU-Render-Meshes zurückgelesen. | Fix (W10/REST5): CPU-Quellgeometrie-Bake — `room_navmesh.gd::bake()` baut `NavigationMeshSourceGeometryData3D` aus Boden-Faces + projizierten Blocker-AABBs; `bake_navigation_mesh()` kommt im Quellbaum nur noch in Kommentaren vor. | Tests `::test_cpu_bake_erzeugt_polygone`, `::test_cpu_bake_blocker_verkleinert_flaeche`. |
| B6 | ~~P1~~ **BEHOBEN** | Postkarten-/Post-Aktion endete sichtbar in „Bald“ statt in einem Archivloop. | Fix (REST-4 + FERTIG-1): Archivgenerator portiert (`ui/postkarten/postkarten_logic.gd`), Post-Schalter durch das Tagespaket ersetzt (`city/ui/post_logic.gd`); der String `city.post.bald` existiert nicht mehr. | Tests `test_rest4_postkarten.gd`, `test_post_paket.gd`, `test_keine_platzhalter.gd`. |
| B7 | ~~P1~~ **BEHOBEN** | Gewicht veränderte den gespeicherten Wert, aber nicht Goobys sichtbare Silhouette. | Fix (REST-3): `gooby_rig.gd` skaliert den Körper wie die Web-`TIER_SCALE` über `Weight.body_scale()` (X/Z), plus Kränklichkeits-Optik. | `scripts/character/gooby_rig.gd`, Test `test_rest3_gewicht.gd`. |
| B8 | ~~P2~~ **BEHOBEN** | Garderoben-/Preview-SubViewports versuchen bei aktivem Stretch ihre Größe zu setzen. | Fix (W10/REST5): manuelles `_on_resized`-Handling in `furniture_showcase.gd` entfernt — `SubViewportContainer.stretch` bestimmt die Größe; die Garderobe (`wardrobe_screen.gd`) nutzt dasselbe Muster. | Test `test_rest5_bugfixes.gd::test_showcase_ueberlaesst_groesse_dem_stretch_container`. |
| B9 | ~~P2~~ **BEHOBEN** | Importierte 3.x-Materialien referenzieren den nicht gemappten Parameter `specular`. | Fix (W10/REST5): Quelle war `scripts/minigames/games/_3db_stage/fx3d.gd` (setzte das Godot-3-Property `specular`, über `fx3d.flat()` in vielen Spielen); jetzt `metallic_specular` — keine `.specular`-Zuweisung mehr im `scripts/`-Baum. | Quelltext-Guard `test_rest5_bugfixes.gd::test_fx3d_flat_nutzt_metallic_specular`. |
| B10 | ~~P2~~ **BEHOBEN** | Navigation-Agentenwerte werden an Voxelgrößen gerundet und verlieren Präzision. | Fix (W10/REST5): `room_navmesh.gd::make_mesh()` setzt `agent_radius`/`agent_max_climb` voxel-exakt auf das Raster (`CELL = 0.25`). | Test `test_rest5_bugfixes.gd::test_navmesh_werte_voxel_exakt` (fmod-Prüfung gegen cell_size/cell_height). |
| B11 | **P2 — offen (W13 in Arbeit)** | Ein Control hat gegensätzliche ungleiche Anchors und verliert seine gesetzte Größe nach `_ready()`. | GvZ im Walkthrough starten. Kandidat: `gvz_level_select.gd` (`_progress_fill` mit PRESET_FULL_RECT + variablem `anchor_right`). Der Fix läuft in W13 beim GvZ-Verdrahtungs-Paket. | `full-route-minigame-walkthrough.log`: `Nodes with non-equal opposite anchors...`. |

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
Spiel minutenlang menschlich zu spielen.

**Revision FERTIG-1:** Die zum EVAL-2-Zeitpunkt hier gelisteten
Meta-Loop-Stolpersteine (falscher Profil-Screen; fehlende Tagesquests/
Erfolge/Tagesbonus; unverkabelter Schlaf; unsichtbare Krankheit/Gewicht;
fehlender Tierarzt; „Bald“ an der Post; Radio/Codes ohne Oberfläche;
fehlender Funkelpark) sind sämtlich behoben (s. Matrix). Gooby Welt ist
kein Stolperstein mehr, sondern eine dokumentierte Streichung ohne toten
Eintrag.

### Gibt es einen roten Faden für neue Spieler?

**Ja (Revision FERTIG-1).** Der Erststart erklärt Identität und Charakter,
und die handlungsgeführte Tour (`onboarding_guide.gd`) führt den alten
Care→Füttern→Bad→Münzen→Arcade→Möbel→Sticker-Bogen wieder — Schritte
erfüllen sich durch echtes Tun. Danach leiten Tagesquests (HUD-Knopf),
Tagesbonus-Streak und Erfolge als tägliche Leitplanken.

### Ist die Progressionskurve rund?

**Ja, mit sichtbarem Endziel (Revision FERTIG-1).** XP, Levelbonus,
Arcade-Unlocks, Tages-×2 und Recaps funktionierten schon; dazu kommen
jetzt Tagesquests mit Claim/Reroll, 44 Erfolge mit Rewards, der
Tagesbonus-Claim, Modifier-Events als Abwechslungs-Taktgeber und im Profil
die Spiel-Abschluss-Karte (`abschluss_logic.gd`): Level x/40, Erfolge,
Sticker und „alle Arcade-Spiele gespielt“ ergeben einen Gesamt-Prozentwert
mit Feier-Zeile bei 100 % — ein ehrliches Langzeit-Ziel. Nur die vier
alten Sammlungssets fehlen als eigenes Album-UI (Zeile A-27).

### Wo wirkt es fertig?

- Arcade-Karten, Pregame, Pause, Resultate, XP, Belohnungsfeedback und
  jetzt Modifier-Events (Badge, Banner, Bonus im Ergebnis).
- 30 von 31 zählbaren alten Spielen plus sieben neue Spiele.
- Stickeralbum mit 140 regulären Stickern und globalem RewardHub.
- Haus, Möbel-/Build-Mode, Garderobe, Garten, die dichte freie Stadt,
  Funkelpark und die volle Care-Tiefe (Schlaf, Krankheit, Tierarzt,
  Gewicht sichtbar).
- Profil mit Abschluss-Karte, Tagesquests, Erfolge, Tagesbonus, Radio,
  Codes, Galerie mit Export, Postkartenarchiv + Tagespaket.
- Umfangreiche Einstellungen und saubere DE/EN-Abdeckung.
- Sehr breite automatisierte Suite (Haupt- + W1c-UI-Runner).

### Wo wirkt es unfertig? (Revision FERTIG-1)

- Vier alte Sammlungssets ohne eigenes Album-UI; Ball-Wurf und
  Gyro-Parallax fehlen; Fotomodus ohne Pose/Emotion/Rahmen.
- Lebensmittelkatalog: 12 Web-Speisen ohne 3D-Asset weiterhin offen.
- Wetter hat einen Dienst, aber keine sichtbaren Regen-/Schnee-Partikel
  in Haus/Stadt.
- Technische Hygiene: die EVAL-2-Engine-Befunde B2–B5 und B8–B11
  (Lambda-Captures, Navigation, Leaks, Materialwarnungen) waren zur
  FERTIG-1-Revision noch offen. *(Revision W13: B2/B3/B5/B8/B9/B10 sind seit
  dem W10/REST5-Sweep behoben; offen bleiben B4 — teilweise — und B11.)*

## Priorisierte Restliste (Top 30) — Stand Revision FERTIG-1

Umfang: **S** = lokal/geringes Risiko, **M** = mehrere Dateien/ein System,
**L** = mehrere Systeme, Content und Integrationsrisiko.

| Prio | Restpunkt | Umfang | Stand | Betroffene Systeme / Risiko |
|---:|---|:---:|:---:|---|
| 1 | Echtes Profil bauen und HUD-Fehlroute korrigieren | **M** | **ERLEDIGT** | `profil_screen.gd` + `abschluss_logic.gd`; Fehlroute behoben (Ex-B1). |
| 2 | Tagesquests vollständig portieren | **L** | **ERLEDIGT** | `quest_catalog/engine/service.gd`; Pool 24 (Web: 28), Claim/Bonus/Reroll vorhanden. |
| 3 | 44 Erfolge samt Rewards und Trophy-Screen portieren | **L** | **ERLEDIGT** | 44er-Katalog, `achievements_engine.gd`, `achievements_screen.gd`. |
| 4 | Handlungsgeführtes Onboarding wiederherstellen | **L** | **ERLEDIGT** | `onboarding_guide.gd` (+`_logic.gd`), Erfüllung über echte Save-Zähler. |
| 5 | Schlafen als echten Spielerloop verkabeln | **M** | **ERLEDIGT** | `bett.gd` (Schlafen/Nickerchen/Wecken), `pflege_runner.gd`. |
| 6 | Krankheit, sichtbare Symptome und Heilpfade fertigstellen | **L** | **ERLEDIGT** | Rig-Symptome, GOOBYTHEKE-Rezept, Tierarzt-Behandlung. |
| 7 | Tierarztpraxis mit Checkup/Vollheilung bauen | **M** | **ERLEDIGT** | `city/orte/tierarzt.gd` (Checkup 30 / Behandlung 120). |
| 8 | Tagesbonus-Claim und Streak-Popup portieren | **M** | **ERLEDIGT** | `daily_bonus.gd` + `daily_bonus_popup.gd`, Serie im Profil. |
| 9 | Funkelpark mit Plaza, Coaster, Riesenrad und Ständen portieren | **L** | **ERLEDIGT** | `scripts/park/*` inkl. Autoscooter und Naschgasse. |
| 10 | Radio-Oberfläche inklusive Now Playing, Track-Toggle und Trim | **M** | **ERLEDIGT** | `radio_sheet.gd`; Trim bleibt Datenpflege in der Registry. |
| 11 | Offline-Codes-Screen und Web-paritäre Einlösung | **M** | **ERLEDIGT** | `codes_engine.gd` + `codes_screen.gd`, Route `codes`. |
| 12 | Modifier-Scheduler, Arcade-Badge, Countdown und Rewards | **L** | **ERLEDIGT** | FERTIG-1: `modifier_engine.gd` + Badge/Banner/Toast/Results, alle Spiele via Framework. |
| 13 | Gooby Welt portieren oder bewusst aus dem Produktumfang streichen | **L** | **ERLEDIGT** | FERTIG-1: offiziell gestrichen, Referenzen bereinigt (s. Zeile B-27). |
| 14 | Vollständige Foto-Galerie bauen | **L** | **ERLEDIGT** | `galerie_screen.gd`/`galerie_logic.gd` inkl. Export in den System-Bilderordner (FERTIG-1). |
| 15 | Postkartenarchiv und Souvenirregal fertigstellen | **L** | **ERLEDIGT** | `postkarten_*`-Port; Post-„Bald“ durch Tagespaket ersetzt (FERTIG-1). |
| 16 | Gewichtsstufen auf den Gooby-Rig anwenden | **M** | **ERLEDIGT** | `gooby_rig.gd` skaliert wie Web-`TIER_SCALE`. |
| 17 | Ball-Wurf-/Fetch-Interaktion portieren | **M** | offen | Home-Input, Physik/Animation, Fun/Weight, Counter/Sticker. |
| 18 | Lebensmittelkatalog von 26 auf Web-Parität bringen | **M** | teilweise | FERTIG-1: 26→32 IDs (3 Shop- + 3 Park-Speisen); 12 Web-IDs ohne 3D-Asset offen. |
| 19 | Urlaubspass, Ziel-Gates und Ziel-Cinematics schließen | **M** | **ERLEDIGT** | Phasen-Maschine, Reise-App/-Cutscene, Archiv-Nachzug im Tick. |
| 20 | Vier alte Sammlungssets im Album wieder sichtbar machen | **M** | offen | Collections-Slice wird für Erfolge/Sticker ausgewertet, aber kein Set-UI. |
| 21 | Gyro-/Pointer-Parallax portieren oder offiziell entfernen | **M** | offen | Entscheidung steht aus; nur Ranch-Fahrsteuerung nutzt Gyro. |
| 22 | City Drive als Arcade-Runde mit Score/Resultat ergänzen | **M** | offen | Freie Fahrt existiert; Arcade-Runden-Loop fehlt. |
| 23 | Lambda-Capture-Lebenszyklusfehler beseitigen | **M** | **ERLEDIGT** | W10/REST5 (B2): Methoden-Callables statt Timer-Lambdas + repoweiter Tripwire-Test (`test_rest5_bugfixes.gd`). |
| 24 | Navigation-Synchronisierungsfehler reproduzierbar lokalisieren/fixen | **L** | **ERLEDIGT** | W10/REST5 (B3): private Nav-Maps je Raum (`room_navmesh.gd::attach_private_map`) + Lebenszyklus-Tests. |
| 25 | Laufzeit-Navmesh-Bake von Render-Meshes entfernen | **L** | **ERLEDIGT** | W10/REST5 (B5): CPU-Quellgeometrie-Bake (`room_navmesh.gd::bake()`); kein `bake_navigation_mesh()` mehr im Quellbaum. |
| 26 | Renderer-/RID-/ObjectDB-Leaks schließen | **L** | teilweise | W10/REST5 (B4): Nav-Map-RIDs freigegeben + Star-Hopper-Vorlagen-Fix („533 → 5“); systematisches Leak-Gate über alle 37 Spiele fehlt. |
| 27 | SubViewport-Stretch-/Resize-Konflikt korrigieren | **S** | **ERLEDIGT** | W10/REST5 (B8): `furniture_showcase.gd` ohne manuelles Resize — `SubViewportContainer.stretch` bestimmt die Größe. |
| 28 | Alte SpatialMaterial-`specular`-Imports bereinigen | **M** | **ERLEDIGT** | W10/REST5 (B9): Quelle war `fx3d.gd`, nutzt jetzt `metallic_specular`; Quelltext-Guard-Test. |
| 29 | Einheitlichen Wetterdienst für Haus/Garten/Stadt verdrahten | **M** | teilweise | `soul_wetter.gd` speist Garten/Ticker/Reaktionen; sichtbare Regen-/Schnee-FX fehlen. |
| 30 | Semantischen E2E-„erste Stunde“-Test ergänzen | **L** | offen | Echter Input: Tutorial, Care, Shop, Quest, Garten, 3 Spiele, Save/Reload; aktuelle Smoke-Tests prüfen primär Erreichbarkeit. |

## Schlussfolgerung (Revision FERTIG-1)

Die Rewrite-Basis ist groß und real: 30/31 zählbare alte Minispiele, sieben
neue Spiele, Haus, Garten, Stadt, Ranch, Funkelpark, Album und ein
belastbarer Save-Kern. „Fast alles fehlt“ beschreibt den aktuellen Code
nicht — und auch „es ist nur eine Alpha“ nicht mehr: Die Systeme, die aus
Content ein zusammenhängendes Spiel machen (geführter Einstieg, Profil mit
Abschluss-Ziel, Tagesquests, Erfolge, Tagesbonus, volle Care-Tiefe,
Tierarzt, Funkelpark, Radio, Codes, Galerie, Postkarten, Arcade-Modifier),
sind umgesetzt, sichtbar und testgedeckt. Erreichbare „Bald“-Platzhalter
gibt es nicht mehr; die verbliebenen Guard-Strings sind per Vertragstest
(`test_keine_platzhalter.gd`) als unerreichbar abgesichert.

Offen bleiben drei kleine Feature-Lücken (Ball-Wurf, Sammlungsset-UI,
Gyro-Parallax), vier Teilaspekte (Katalog-Rest, Wetter-FX,
Fotomodus-Werkzeuge, Nougatschleuse) und die technischen EVAL-2-Befunde
B2–B5/B8–B11 *(Revision W13: davon sind nur noch B4 — teilweise — und B11
offen)*. Die faire Einordnung lautet jetzt: **inhaltlich komplettes
Spiel in der Feinschliff-Phase** — nicht mehr Alpha, für ein poliertes
Release fehlen Engine-Hygiene und die letzten Nischen-Features.
