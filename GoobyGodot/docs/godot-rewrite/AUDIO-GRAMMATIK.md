# Audio- & Haptik-Grammatik (GOOBY, Stand W16)

Verbindliche Konvention für ALLE UI-Pakete (Herkunft: G1-Scout `sound-haptik`,
G2-Fixliste `sound-haptik-fixliste` §3; verankert von P09 SOUND-KERN, Welle G3).
Wer Buttons/Sheets/Screens baut oder umbaut, hält sich an diese Regeln — der
Wächter-Test `GOOBY-GODOT/tests/unit/test_w16_sound_haptik.gd` wächst
wellenweise mit und scannt reparierte Builder/Screens.

## Die Regeln

- **Jeder interaktive Knopf ist ein `SquishButton`** (nie `Button.new()`;
  `OptionButton`-Dropdowns und reine Anzeige-Chips mit `MOUSE_FILTER_IGNORE`
  sind ausgenommen). Tap-Haptik (10 ms) und Press-Squish kommen automatisch —
  NIEMALS `Haptics.tap()` manuell in pressed-Handlern.
- **Jeder pressed-Handler spielt genau EINE `SfxMap`-Id**
  (`AudioDirector.try_play(self, "<id>")`, Ids nie hartkodiert-neu):
  `ui_click` Standard-Aktion · `ui_chip` Tab/Chip/Auswahl/Ansichtswechsel ·
  `ui_back` Zurück/Abbrechen/Verlassen · `ui_confirm` Bestätigen/Start/
  Senden-Erfolg · `ui_toggle` An-Aus-Schalter · `ui_tick` Mikro-Schritte
  (Stepper, Slider-Rasten, Likes; ggf. drosseln) · `ui_buy` abgeschlossene
  Münz-AUSGABE · `ui_coins` Münz-EINNAHME · `ui_sticker` Belohnung/
  Sammelstück · `ui_error` ungültig/fehlgeschlagen.
- **Outcome schlägt Press:** Steht der Ausgang erst NACH dem Druck fest
  (Netz-Call, Validierung), bleibt der Druck stumm und der AUSGANG klingt
  (`ui_error`/`ui_sticker`/`ui_coins`). Ist der Knopf bei Nichterfüllbarkeit
  disabled, darf der Druck selbst klingen.
- **Öffnen/Schließen klingt NUR über `PanelSheet.open()/close()`**
  (`ui_open`/`ui_close`). Knöpfe, die ein PanelSheet öffnen/schließen, spielen
  selbst KEINEN Sound (Doppel-Klang). Eigenbau-Overlays müssen
  `ui_open`/`ui_close` + `PanelStack` selbst nachbauen. Reisen/Szenenwechsel =
  `travel_whoosh_*` via LoadingVeil, nie `ui_open/close`.
- **Zusatz-Haptik nur an Momenten:** `Haptics.success()` bei Belohnung/Kauf-
  bzw. Sende-Erfolg/Quest-Claim/gerettetem Spielstand; `Haptics.warn()` bei
  Fehler/destruktiver Aktion. Nichts anderes.
- **Pitch:** Grund-Variation NUR über `pitch_jitter` in der SfxMap
  (UI 0.02–0.03, Minigame/Foley 0.05–0.10). Manuelle `pitch`-Parameter an
  `try_play` nur für semantische Steigerungsreihen (Combo, Stepper,
  Streicheln), Bereich 0.9–1.6.
- **Pegel:** Neue Verdrahtungen nutzen NUR bestehende SfxMap-Ids. Wirklich
  neue Sounds: Quelldatei Peak ≤ −1 dBFS, `volume_db`-Trim auf die gemeinsame
  Effekt-Ebene ~−22 dBFS eff. (Richtwerte: UI −2…−7, Foley −4…−12,
  Loops/Ambience −6…−12), danach `python3 tools/audio/ef2_manifest.py`
  (sonst reißt `test_ef2_audio_levels.gd`). Musik bleibt −13 dB unter dem
  Sfx-Bus (Test erzwingt 6–10 dB Abstand).
- Der 45-ms-Debounce des AudioDirector schluckt Doppel-Trigger derselben Id —
  trotzdem Doppel-Verdrahtung vermeiden. Erfolgs-Toasts bleiben stumm
  (`ui_toast` nur deklarativ in Cutscenes/FeelEmotions — nicht „aufräumen“).

## Haptik-Stärke (W16 F11)

Die RW-7-Stufe `controls.haptics` (aus/dezent/normal/stark) wirkt zentral in
`Haptics.plan()` als Dauer-Multiplikator (0.6 / 1.0 / 1.6); „aus“ blockt im
Gate `Haptics.is_enabled()`. Screens lesen die Stufe NIE selbst — `Haptics`
holt sie aus den AppSettings.

## Bewährte Bausteine statt Eigenbau

- City-Ort-Sheets: `CitySheetBausteine.kauf_zeile(...)` baut den SquishButton
  und spielt den parametrischen Press-Sound selbst (Default `ui_buy`;
  Nicht-Kauf-Zeilen übergeben eine andere Id, `""` = stumm für
  Outcome-Verdrahtung beim Aufrufer). `farb_knopf(...)` klingt als
  `ui_toggle`. Aufrufer verdrahten dort KEINE eigenen Press-Sounds mehr.
- Referenz-Muster im Code: `ikea_screen.gd` (Kauf-Erfolg `ui_buy` +
  `Haptics.success`, Fehler + `Haptics.warn`), `chess_scene.gd`
  (Spielmoment-Sounds), `hud.gd` (click/chip/toggle je Semantik).
