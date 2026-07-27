# WOAH-03 CHRONO-STASE — Verdrahtung / geteilte Dateien

Feature-Code lebt komplett in `woah/chronostasis` (+ `woah/chronostasis/client`).
Hier steht, was an geteilten Dateien angefasst wurde (minimal-additiv, frisch gelesen)
und was BEWUSST für den Hauptagenten offen bleibt.

## Angefasste geteilte Dateien (sanktionierte Ausnahmen)

1. **`veilfx/FxAnchors.java`** — neue frozen id `CHRONO_CENTER`
   (`eclipse:chrono_center`) + ein Javadoc-Satz in der Frozen-ids-Liste. Publisher:
   `ChronoStasisSite` (materialize + Server-Start-Restore + `/dev woah chrono reset`);
   Konsument: `client/ChronoZoneState` (Distanz/Ease) und darüber Grade, Ticken,
   Photon-Fenster, Regen-Mixin.
2. **`client/mixin/LevelRendererMixin.java`** — zwei HEAD-Cancels
   (`eclipse$chronoHideRain` auf `renderSnowAndRain`, `eclipse$chronoMuteRain` auf
   `tickRain`), beide gaten auf `ChronoZoneState.suppressVanillaRain()` (eased amount
   ≥ 0.6, während des Discharge-Regen-Beats freigegeben). Klasse steht bereits in
   `eclipse.client.mixins.json` — KEINE Mixin-Config-Änderung.
3. **`woah/WoahFeatures.java`** — eine Zeile unter dem Anker
   `// --- WOAH-03 chrono stasis: mod-bus registrations go here ---`:
   `ChronoStasisItems.register(modEventBus)` (eigene DeferredRegister-Klasse, weil
   `registry/EclipseItems.java` gesperrt ist).

## Bewusst NICHT angefasst (Feature funktioniert ohne)

4. **`network/fx/FxCues.java`** (gesperrt) — die zwei Cue-Ids leben als Konstanten in
   `woah/chronostasis/ChronoCues.java` via `FxCues.cue("woah_chrono_jolt")` /
   `FxCues.cue("woah_chrono_discharge")`. Wire-Format identisch; der Hauptagent KANN
   sie später als `FxCues.CUE_CHRONO_*` einziehen und `ChronoCues` delegieren lassen
   (reine Aufräumarbeit).
5. **`worldgen/DiscMapDefaults.java`** (gesperrt) — die Landmark-Zeile
   `eclipse:chrono_stasis, -24, 240, 26, 3` ist zentral BEREITS eingetragen;
   `ChronoStasisSite.landmarkXZ()` liest die frozen Row (Fallback: gespiegelte
   Konstanten `CENTER_X/CENTER_Z`).
6. **`registry/EclipseItems.java`** (gesperrt) — `chrono_core` registriert stattdessen
   `woah/chronostasis/ChronoStasisItems` (Rarity EPIC, stacksTo 1, `.lore`-Zeile im
   Haus-Stil). Modell `assets/eclipse/models/item/chrono_core.json` + Textur
   `textures/item/chrono_core.png` liegen bei. Der Hauptagent KANN das Item später
   nach `EclipseItems` umziehen (Registry-Name bleibt `eclipse:chrono_core`).
7. **`registry/EclipseSounds.java` + `assets/eclipse/sounds.json`** (gesperrt) — KEINE
   neuen Events; alle Plan-§6-Rezepte werden live aus Bestand/Vanilla gelayert.
   Inventar + aufgeschobene Row-Definitionen: `woah_chrono_sounds.json` (daneben).
8. **`assets/eclipse/lang/en_us.json`/`de_de.json`** (gesperrt) — alle Keys in
   `docs/plans_v3/langdrop/woah_chrono.json` (en_us + de_de). Ohne Merge zeigen
   Actionbar/Captions/Dev-Feedback rohe Keys — funktional, aber hässlich.
9. **`network/EclipsePayloads.java`** (gesperrt) — nicht nötig: Jolt/Discharge reiten
   die bestehenden `FxPayloads.sendFxEvent`-, `S2CShakePayload`- und
   `S2CCaptionPayload`-Schienen; der Anker synct via `FxAnchors`/`S2CAnchorPayload`.

## Brigadier-Hinweis

`ChronoStasisDevCommands` (im Feature-Package, NICHT in `devtools/dev`) legt den
`/dev woah`-Literal-Knoten ERSTMALIG an. Spätere Woah-Features hängen ihre Subtrees an
denselben Literal — Brigadier merged separate `register`-Aufrufe automatisch; keine
Koordination nötig, solange niemand denselben Leaf-Namen (`chrono`) belegt.
