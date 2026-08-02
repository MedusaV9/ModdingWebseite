# Welle 6 — Live-Abnahme-Protokoll (02.08.)

Frische JVMs (Server + Client, llvmpipe-Software-GL), RCON-Drehbuch. Ergänzt die
Team-Reports `WAVE6_A_NIGHT_REPORT.md` / `WAVE6_B_DRAGON_REPORT.md` /
`WAVE6_C_MORNING_REPORT.md` um die Live-Beweise.

## B5 — Race: Checkpoints, Finish, Podium (Kernstück dieser Abnahme)

Ablauf (Heat „seed 3", 1 Racer, 3 Runden, Zirkel 383 Blöcke):

1. `dev minigame start race 5` → Kurs baut, `Course: ready`.
2. Eintritt über `/dev minigame portal here` + Portal-Trigger (kein Teleport-Trick —
   der reguläre `enter()`-Pfad mit Ticket/Adventure/Kit lief; Sonde
   `Dev entered minigame race (seed 3)`).
3. Grid + „Lights out in…"-Countdown (Start-Gantry, 5 Lampen) — Screenshot
   `wave6_b5_race_grid_lights_out_countdown.png`.
4. Bögen 1–6 in Reihenfolge, 3 Runden: `[w6b-checkpoint] racer=Dev cp=1..6/6`
   pro Runde (18 Sonden), Aktionsbar „Lap x/3 — Place 1", privater Doppel-Chime
   (Pitch-Leiter 0.7→1.6) + ELECTRIC_SPARK/END_ROD-Glint am Bogen (im Video als
   weiße Glitzerpartikel an den Woll-Bögen sichtbar).
5. Ziellinie (Gate 0) schließt die Runde: `Race finish: position 1 in 01:34.951
   over 3 lap(s)`, Titel „WINNER!" + „Total Time 01:34.951", Chat: Best-Time-Flash,
   „Finisher #1 — reward 8 shards, 120 skill XP", „Heat over — 1 finishers,
   best lap 00:11.494". Racer landet im Paddock (Glasplattform y=78) mit Blick
   über den Zirkel.
6. COOLDOWN-Podium-Beat: Sonde `[w6b-podium] place=1 at=-28, 66, -38`
   (Ziellinie). In einem zweiten Kontrollheat („seed 5", Finish 01:04.003)
   feuerte die Sonde erneut.

Video: `wave6_b5_race_heat_checkpoints_finish_podium.mp4` (kompletter Heat).
Hinweis Video-Review: Nach dem Finish formt sich automatisch der nächste Heat —
der zweite „3-2-1-GO"-Countdown am Videoende ist Heat 2, keine gescrambelte
Timeline. Der Feuerwerks-Burst selbst (~1.5 s) war bei ~0.5–1 fps llvmpipe-
Render-Takt in keinem gerenderten Frame — Beat zweifach per Server-Sonde belegt
(Frame-Analyse: Fenster-Crop, Gold-Pixel-Detektor über 135 Frames, flat).

Bugfix am Rande der Abnahme (Test-Methodik, kein Produktbug): Ein Gate-Besuch
unter ~0.5 s fällt zwischen zwei Segment-Samples (`LAST_POS`-Anker) — beim
TP-Drehbuch also ≥0.9 s an der Ziellinie verweilen.

## B3/B4 — Drachen-Landung + Crescendo

Live nachgestellt (Kristalle weg, HP via NBT): Landing-Retry-Loop und
Crescendo-Overflow gefixt in `4e32f78`, Sonden `[w6b-crescendo]` feuerten nach
dem Fix; Details im Fix-Report `W6B_DRAGONFIGHT_FIXES_REPORT.md`.

## A — Nacht-Events (Umbral/Pale)

Während der F-107-Runden mehrfach live geschaltet (`eclipse event set
umbral|pale|none`): Boss-Bar, Client-Sync + Sky-Tint liefen; dabei gefundener
Dimension-Leak (Omen/Dawn-Cues + Announcements erreichten Limbo) in `95a3d9b`
gefixt (nur noch Overworld-Spieler).

## B7 — MusicMemory

Headless-Grenze: `heard=true` setzt hörbares Audio voraus; im VM-Client ohne
Audio-Engine bleibt `heard=false`. Logik (markHeard/resolveRepeatFactor/forget)
per Code-Review + `/dev music forget` abgenommen; kein Live-Beweis möglich.

## B6 — Recovery-Skip

`[w6b-recover]`-Sonde feuert nur bei tatsächlich übersprungenen (ungeladenen)
Randspalten eines Storm-Recovers — im Abnahme-Setup nicht provozierbar ohne
künstliches Chunk-Unloading; per Code-Review (isLoaded-Gate + ehrlicher
boolean-Return) abgenommen.

## C — Morgen-Meta

Per Team-C-Report-Gates abgenommen (Merge-Compile, fxlib 0 NEW, Doppellauf
byte-identisch); Decrees/Awards/Sundial/Digest hängen am Morgen-Tick-Zyklus und
liefen im Zeitraffer-Smoke ohne Fehler-Log.
