# WAVE6_A_NIGHT_REPORT — Team A „Umbral-Uhr & Nacht-Dread" (F-106, Sonden `[w6a-*]`)

Charter: `WAVE6_PLAN.md` §3. Basis: HEAD `0960532` (Branch `cursor/project-eclipse`),
geteilter Worktree mit Team B/C — deren Dateien (u. a. `worldgen/end/EclipseDragonFight`,
`minigames/LegacyRace`, `veilfx/Wave6DragonFxRows`, `wave6_crystal_burst.*`,
`wave6_dragon_wisp.*`) wurden NICHT angefasst.

Status: **A1–A7 alle done** (A7-Stretch inklusive). Kein Langdrop nötig (§5).

---

## 1. Erst-Verifikationstabelle (rg gegen den Live-Tree, VOR jeder Codezeile)

Alle Greps aus `src/main/java/dev/projecteclipse/eclipse/`, Stand HEAD `0960532`.
Nach der SACHE gegreppt (Payload-Klassen, Cue-Strings, Sound-Pakete, Emissive-Hooks),
nicht nur nach Plan-Vokabular.

| # | Item | rg-Beweis | Befund |
|---|---|---|---|
| A1 | Kein Nacht-Event-Client-Sync | `rg -in "NightEventPayload\|S2CNight\|network/night\|NightDreadFx" .` → **0 Treffer**; `rg -ln "getActiveNightEvent" .` → nur `devtools/TimelineInspector`, `skills/SkillService`, `admin/EclipseCommands`, `entity/EclipseSpawner`, `core/state/EclipseWorldState` (+ `entity/package-info`) — **kein einziger `client/**`-Konsument** | offen — kein Payload, keine Senke |
| A2/A3 | `client/sky/**` kennt `umbral\|pale` nicht | `rg -in "umbral\|pale" client/sky/` → 2 Treffer, beide Kommentar-Prosa („violet ties …" `LimboSpecialEffects` Z. 577, „Deep-purple palette" `RimMountainSilhouette` Z. 78) — **0 funktionale Treffer**; Mond-Pass (`OverworldPurpleEffects` Z. 291–312) zeichnet mit fixem `setShaderColor(1,1,1,rainAlpha)` | offen |
| A4 | Kein Pack-Land-Cue | `rg "wave6_pack_land"` (Repo-weit) → **0**; `rg -n "sendFxEvent" entity/EclipseSpawner.java` → nur Z. 194 (`wave3_night_omen`, personal lane beim Announce) — der Howl-Block (Z. 257 ff.) sendet ausschließlich `ClientboundSoundPacket` | offen |
| A5 | Kein Nähe-Tell in The Other | `rg -icn "whisper\|proximity\|heartbeat\|ClientboundSoundPacket" entity/TheOtherEntity.java` → **0** (Server-Sounds nur `despawnAtDawn`/`die` via `playSound`) | offen |
| A6 | Keine Morgen-Erlösung | `rg -in "wave6_dawn_release\|dawnrelease" .` → **0**; `clearNightEvent` (alt Z. 177–183) = State-Clear + INFO-Log, kein Player-Beat | offen |
| A7 | Kein Event-Glow im Stalker-Renderer | `rg -icn "glow\|emissive\|umbral" client/entity/stalker/*` → nur Klassennamen + `withGlowmask()`-Registrierung (Stock-`AutoGlowingGeoLayer`, ungegated); **kein** NightDread-/Event-Hook | offen |
| Cmd | Abnahme-Kommando-Syntax | `rg -n "event set" admin/EclipseCommands.java` → Literal-Baum Z. 156–160 (`event` → `set` → `StringArgumentType.word()` + Suggests `pale/umbral/none`), Handler `eventSet` Z. 428–447 | **exakt** `/eclipse event set <pale\|umbral\|none>`; Achtung: der `none`-Zweig ruft `announceNightEvent` NICHT (→ §2 A1, Drift-Watcher) |
| Lang | Announce-Keys vorhanden | `rg -c "announce.eclipse.night" src/main/resources/assets/eclipse/lang/{en_us,de_de}.json` → je **4** | keine neuen Keys nötig (§5) |

---

## 2. Umsetzung + Design-Entscheidungen je Deliverable

### A1 Nacht-Event-Client-Sync — done

**Neu**: `network/night/S2CNightEventPayload.java` (`(String event, int day)`,
`StreamCodec.composite`, id `eclipse:night/event`), `network/night/NightPayloads.java`
(eigener MOD-Bus-Registrar, Versionsgruppe `night1`, exakt das `BestiaryPayloads`-Idiom
inkl. installierbarem Consumer — Server-loadable ohne Client-Klassen),
`client/drama/NightDreadFx.java` (statische Senke; installiert ihren Consumer im
static-Initializer, `ClientBestiaryCache`-Muster). **Sends** (Charter): in
`EclipseSpawner.announceNightEvent` nach dem Omen-Loop (`nightfall`), in
`clearNightEvent` (`dawn`, event = none) und im Login-Subscriber
(`NightPayloads.Sync.onPlayerLoggedIn`, liest `EclipseWorldState.getActiveNightEvent()`
strikt READ-only — `EclipseWorldState.java` unverändert).

**Entscheidung 1 (Drift-Watcher)**: `/eclipse event set none` schreibt den State,
durchläuft aber KEINEN der beiden Spawner-Hooks (Erst-Verifikation, Zeile „Cmd") — das
Akzeptanzkriterium „`event set none` → dawn-Zeile" wäre mit den drei Charter-Sends
allein erst beim nächsten natürlichen Dawn-Edge erfüllbar. `NightPayloads.Sync
.onServerTick` (20t-Kadenz, 1 SavedData-Lookup/s) vergleicht deshalb den State gegen
die `lastSyncedEvent`-Marke der letzten Broadcast und re-synct NUR bei Drift; die
expliziten Sends halten die Marke aktuell, der Watcher bleibt im Normalbetrieb stumm.
Liegt vollständig in meiner neuen Datei — keine Verbotszone berührt (die Alternative
wäre ein Edit in `admin/EclipseCommands.java` gewesen, das gehört mir nicht).

**Entscheidung 2 (Sonden-Split)**: Die Origin-Tags `(login|nightfall|dawn)` kennt nur
der Server exakt — der Server loggt sie an jeder Send-Stelle (Broadcast 1×/Batch, Login
1×/Spieler ins Server-`debug.log`). Die Client-Senke loggt dieselbe Zeile mit
INFERIERTEM Tag (erster Sync der Session = `login`, sonst `none`→`dawn`,
andernfalls `nightfall`) — deckungsgleich mit der Server-Semantik, und das Payload
bleibt exakt die Charter-Form `event+day`.

**Entscheidung 3 (Dimension-Gate in der Senke)**: `NightDreadFx.isUmbral()/isPale()/
mode()` melden nur im Overworld — `StarField` wird auch vom Limbo-Himmel
(`LimboSpecialEffects`) benutzt und darf dort nie dimmen; End/Arena erben ebenso
nichts. Reset auf `LoggingOut` (der nächste Server hat ggf. kein Event).

### A2 Umbral-Mond & Pale-Blässe — done

Im bestehenden Mond-Pass von `OverworldPurpleEffects`: der bisher fixe
`setShaderColor(1,1,1,rainAlpha)`-Aufruf bekommt einen Tint-Vektor davor — Umbral
`(0.415, 0.122, 0.690)` (#6A1FB0-Familie), Pale `(1.0, 0.965, 0.870)` (multiplikative
Knochenweiß-Bleiche: die kühlen Kanäle leicht runter, damit der Mond bleich statt blau
liest — multiplikativ kann nur entsättigen, nie aufhellen), `none` = literal `(1,1,1)`
→ **byte-gleicher Vanilla-Call**. Der Tint multipliziert NACH allen Bestands-Faktoren
(`rainAlpha` faltet Regen + `creditsDark` bereits); Iris-Gate (`return false` ganz
oben) und `creditsDark`-Fade unangetastet. Umbral zusätzlich: EIN Ghost-Doppelquad
(gleiche Textur/UV, ×1.08 Größe, +5/−3.5 Offset in der Mondebene, α 0.25·rainAlpha,
hellerer Violett-Ton `(0.55, 0.28, 0.90)`) im selben additiven Pass — der emergente
F-105-„Doppelmond" wird Kanon. `reducedFx`: Tint bleibt (kostenlos), Ghost-Quad
entfällt. Sonde `[w6a-moon] mode=<m>` 1× pro Wechsel (statische Dedup-Marke).

### A3 Umbral-Sternfeld — done

`StarField.draw`: bei `NightDreadFx.isUmbral()` wird die vom Caller gesetzte
Shader-Farbe kanalweise multipliziert — r×0.70 / g×0.50 / b×0.45 / α×0.55 (netto
≈×0.55 Helligkeit mit warmem Rotstich: der Rotkanal überlebt am stärksten) — und nach
dem Draw exakt restauriert (der Pass bleibt für jede andere Nacht eine reine Funktion
seiner Inputs; Eclipse-/Credits-Boosts wirken unverändert darunter). Pale ±0 (die Pale
Night gehört dem Mond). Reine Konstanten-Mathe, kein neuer Draw.

### A4 Rudel-Landungs-Bühne — done

`EclipseSpawner.spawnStalkerPack`: nach `howlAround` ein
`FxPayloads.sendFxEvent(overworld, FxCues.cue("wave6_pack_land"),
Vec3.atBottomCenterOf(packCenter), spawned, umbral ? 1 : 0, HOWL_RANGE)` — API-only,
`FxPayloads.java`/`FxCues.java` unverändert; Publikum = derselbe 64-Block-Radius, der
den Howl hört; `a` = tatsächlich gelandete Rudelgröße, `b` = Umbral-Flag. Asset
`eclipse:wave6_pack_land` (NEU via `tools/photon/wave6_night_fx.py`): Bodennebel-Ring
(alpha-blended Smoke, DISTANCE-sortiert, Flüster-Alpha 0.16, 2.2 Blöcke Auswärts-Atem)
+ 3–4 Augen-Glints (zwei gestaffelte Bursts auf Stalker-Augenhöhe, Cyan-Weiß aus dem
Glowmask-Shard-Palette, SEG_POP_SHRINK-Blinzeln, nahezu bewegungslos — Augen starren).
One-Shot hart ≤60t (letzte Fog-Geburt t8 + 52t Life = 60t). Row in NEU
`veilfx/Wave6NightFxRows.java`: LAYER, BURST-Channel, Quasar-Leg `null` (neuer Cue,
legal), Photon-Leg skaliert ~0.9→1.1 mit der Rudelgröße; **Vanilla-Fallback** bei
fehlendem/abgelehntem Photon = CAMPFIRE_COSY_SMOKE-Ring (12 Partikel, Charter-Vorgabe);
`reducedFx` skippt komplett (der Howl trägt die Fairness-Info). Sonde
`[w6a-packland] size=<n> umbral=<b> at=<pos>`.

### A5 The-Other-Nähe-Flüstern — done

`TheOtherEntity`-Server-Tick: ist der NÄCHSTE Spieler ≤12 Blöcke, alle 60–80t
(gejittert via `nextWhisperTick`-Marke, **transient** — nie ins NBT) ein privates
`ClientboundSoundPacket`-Paar NUR an diesen Spieler: AMBIENT_CAVE 0.35F **an der
Position des Doppelgängers** (die Richtung ist der Schrecken) + WARDEN_HEARTBEAT 0.25F
**an den Ohren des Spielers** (es ist DEIN Puls), beide Pitch 0.6. Leerlauf-Kosten:
eine Spielerlisten-Distanzprüfung alle 10t, solange niemand in der Bande steht. Sonde
`[w6a-otherdread] target=<name> dist=<f>` — das ≥60t-Intervall IST die
1-Zeile-pro-3-s-Drossel. Kein zusätzliches Pale-Gate: der Mob existiert per Spawner
nur in Pale Nights, `/summon` für die Abnahme funktioniert damit jederzeit nachts
(tags löst `despawnAtDawn` ihn ohnehin auf).

### A6 Morgen-Erlösung — done

`EclipseSpawner.clearNightEvent`: war ein Event aktiv, geht nach State-Clear +
Dawn-Sync pro Online-Spieler `sendFxEventTo(p, FxCues.cue("wave6_dawn_release"),
p.position(), umbralWar ? 1 : 0, 0)` (Personal-Lane, exakt das
`wave3_night_omen`-Idiom) + ein leiser Exhale (`AMBIENT_UNDERWATER_EXIT` — der
Vanilla-Auftauch-Atemzug — 0.35F, Pitch 0.75 = Seufzer). Asset
`eclipse:wave6_dawn_release` im selben Generator: die INVERSION des Umbral-Gulps —
Elfenbein-Mote-Ring steigt aus dem Boden (1.8–2.4 Blöcke), öffnet sich leicht nach
außen und löst sich Richtung Knochenweiß auf; dazu ein Exhale-Halo auf Brusthöhe und
drei weiche Lift-Glows (~5 s, Omen-Präzedenz). Row: LAYER, SEQUENCE-Channel, Quasar
`null`, Vanilla-Fallback = 8 steigende END_ROD-Motes, `reducedFx` skippt (Exhale +
zurückkehrendes Tageslicht tragen). `a` = 1 (umbral endete) / 0 (pale) — reserviert,
EIN geteilter „Ausatmen"-Look (Photon hat keinen Runtime-Tint; dokumentiert im
Row-Javadoc). Sonde `[w6a-dawnrelease] players=<n> event=<e>`, 1× pro Dawn (der
State-Active-Check garantiert Stille an Folge-Dawns).

### A7 (Stretch) Stalker-Umbral-Glow — done

NEU `client/entity/stalker/UmbralNightGlowLayer.java` — exakt die W5-B4-Präzedenz
(`FogGlowBreathLayer`/`EnrageGlowLayer`-Zweipass): Basis-Pass = byte-äquivalenter
Stock-Glowmask-Re-Render (inkl. `getRenderColor`-Fades), und weil Farb-Ints bei 1.0
clampen, rendert der 0.6-Überschuss als zweiter Emissive-Pass NUR wenn
`NightDreadFx.isUmbral() && !reducedFx && deathTime <= 0` → Emissive ×1.6 total.
`reducedFx` lässt den Basis-Look unangetastet (nur der Boost entfällt).
**Ersetzte Bestandszeile** (begründet): in `UmbralStalkerGeoRenderer` wurde
`withGlowmask()` → `addRenderLayer(new UmbralNightGlowLayer<>(this))` getauscht — der
1-Zeilen-Swap ist das dokumentierte W5-B4-Verfahren (`StormHoundRenderer` etc., Report
WAVE5_B §B4), der Stock-Layer und der neue Layer sind im Ungebosteten identisch.
Zusatz-Sonde `[w6a-stalkerglow] umbral=<b>` (1× pro Boost-Flip, llvmpipe-Beweis; im
Plan nicht gefordert, Präfix-konform `[w6a-*]`).

---

## 3. Gate-Belege

| Gate | Kommando | Ergebnis |
|---|---|---|
| Compile | `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** (nur die haus-bekannten `EventBusSubscriber.Bus`-Deprecation-Warnings, auch in Fremd-Dateien) |
| Ressourcen | `flock /tmp/gradle.lock ./gradlew compileJava processResources --offline --console=plain` | **BUILD SUCCESSFUL** (beide neuen `.fx`+`.fxproj` gepackt, keine Tag-Duplikate) |
| fxlib-Lint | `python3 tools/photon/fxlib.py validate --lint` | `lint: 293 file(s), `**`0 NEW error/warn`**`, 27 grandfathered, 149 advisory info` |
| Doppellauf | 2× `python3 tools/photon/wave6_night_fx.py` + `sha256sum`-Diff | **byte-identisch** (uuid5-deterministisch) |

sha256 (Lauf 1 == Lauf 2):

```
38332bc42ddf1ed1b6eceb7e95515632b2a6930add09c4c41c30383d587c4834  wave6_pack_land.fx      (raw 7313 B, gzip 1702 B)
bf2740fb8b6fd39efeb01a05d8e4bd813f63ca6552dbf5618fea3bd8edf97fda  wave6_dawn_release.fx   (raw 12302 B, gzip 1875 B)
fa3a0bf7c621bec0119438ba5255b4a7dfa3164817a3a4a1daf6df04bfa03b8d  wave6_pack_land.fxproj
916ca254094454a1f457b15afe77ac65719c86e2f77df101127f43cced90912f  wave6_dawn_release.fxproj
```

V2.1-Konformität der Assets: dunkle Birth-Tints überall (GLI_DEAD/PALE_BIRTH/
DUST_BIRTH_VIOLET-Floors), HDR via lokalem `hdr()`-Clamp ≤1.45 (Hue-erhaltend),
CullBox auf jedem Emitter, `random_gradient` auf jeder echten Population,
Alpha-Smoke DISTANCE-sortiert, One-Shots ohne Loops/Prewarm.

**Nachtrag geteilter Worktree**: Beide Gates liefen GRÜN mit dem KOMPLETTEN
Team-A-Change-Set (Gate 1 nach allen Java-Dateien, Gate 2 nach den Assets — Belege
oben). Ein Kontroll-Rerun danach zeigte 3 Compile-Fehler, alle in parallel
IN-FLIGHT befindlichen Team-B/C-Dateien (`devtools/dev/DevMusicCommands.java`
`::forget` = B7-Stretch; `client/awards/AwardsOverlay.java` referenziert
`AnnouncementOverlay.isIdle()`/`DecreesCard` = C1/C2, zum Prüfzeitpunkt noch
unvollständig) — **keine der drei Meldungen referenziert ein Team-A-Symbol**
(kein `night/`, `NightDreadFx`, `Wave6Night`, `EclipseSpawner`, `StarField`,
`UmbralNightGlowLayer` im Fehlerbild). Das ist der erwartete Zwischenzustand der
Parallel-Phase; der Merge-Gate-Lauf des Hauptagenten (§8 Schritt 1) prüft den
Gesamtstand, sobald alle Teams gelandet sind.

---

## 4. Angefasste / neue Dateien (Ownership-Abgleich §3/§6: alle exklusiv Team A)

**Editiert (additive Hooks, `WAVE6 (F-106 A)`-kommentiert):**
`entity/EclipseSpawner.java` (A1-Sends, A4-Cue+Sonde, A6-Release+Exhale+Sonde,
2 Konstanten), `entity/TheOtherEntity.java` (A5), `client/sky/OverworldPurpleEffects.java`
(A2), `client/sky/StarField.java` (A3), `client/entity/stalker/UmbralStalkerGeoRenderer.java`
(A7, 1 begründeter Zeilentausch).

**Neu:** `network/night/S2CNightEventPayload.java`, `network/night/NightPayloads.java`,
`client/drama/NightDreadFx.java`, `veilfx/Wave6NightFxRows.java`,
`client/entity/stalker/UmbralNightGlowLayer.java`, `tools/photon/wave6_night_fx.py`,
`assets/eclipse/fx/wave6_pack_land.{fx,fxproj}`,
`assets/eclipse/fx/wave6_dawn_release.{fx,fxproj}`, dieser Report.

**Bewusst NICHT angefasst:** `core/state/EclipseWorldState.java` (nur Getter/Konstanten
gelesen), `client/ClientStateCache.java`, `veilfx/FxPayloads|PhotonFxRegistry|FxCues|
FxAnchors` (nur public API), `admin/EclipseCommands.java`, alle übrigen
`client/sky/**`-Dateien, `client/drama/LastMinuteHush.java`, sämtliche Team-B/C-Zonen.

## 5. Langdrop

**Kein `WAVE6A.json`.** A1–A7 erzeugen keinerlei UI-Text: die Nacht-Announcements
laufen über die BESTEHENDEN Keys `announce.eclipse.night.<event>.title/.sub`
(Erst-Verifikation: je 4 Treffer in `en_us.json`/`de_de.json`); Sonden sind
DEBUG-Log-only, Sounds/FX textlos. Die beiden Mod-lang-JSONs blieben unberührt.

---

## 6. RCON-Abnahme-Drehbuch (Hauptagent, llvmpipe-tauglich)

Voraussetzungen: Server + Client **frisch von diesem Stand** booten (F-103; beide
Seiten brauchen Payload-Registrar UND Senke). Wegen der zwei neuen `.fx`-Assets einmal
im CLIENT-Chat `/photon_client clear_client_fx_cache` + F3+T. RCON-Aufrufe:
`python3 tools/rcon/rcon.py "<cmd>"`. Sonden: Server-Zeilen in `run/logs/debug.log`
des Servers, Client-Zeilen im Client-`debug.log`. Kommando-Syntax verifiziert (§1):
`/eclipse event set <pale|umbral|none>`.

**Reihenfolge-Warnung:** erst `time set midnight`, DANN `event set …` — der
Nightfall-Edge des Spawners (`scheduleNightEvent`, ≤100t nach dem Time-Sprung) kann
auf Tagen ≥4 mit 25 % eine Pale Night würfeln und würde ein VORHER manuell gesetztes
Event überschreiben (ein `none`-Wurf überschreibt dagegen nicht).

```
# --- Schritt A: Nacht-Referenz (VOR den Events) --------------------------------
time set midnight
tick rate 20                                # normale Rate; der Nacht-Zustand hält von selbst
# FOTO 1 "none-Referenz": Vanilla-Mond + Sterne (Gegenprobe-Basis = F-105-Midnight-Fotos)

# --- Schritt B: A1 + A2 + A3 Umbral --------------------------------------------
eclipse event set umbral
#   Server-debug.log:  [w6a-nightsync] event=umbral day=<d> (nightfall)
#   Client-debug.log:  [w6a-nightsync] event=umbral day=<d> (nightfall|login)  (login nur beim 1. Sync der Session)
#   Client-debug.log:  [w6a-moon] mode=umbral            (1x, beim ersten Sky-Frame danach)
# FOTO 2 "umbral": Mond tief-violett + Ghost-Doppelquad (versetzt, ~0.25 alpha)
#                  + Sterne sichtbar dunkler mit warmem Stich (vgl. FOTO 1)
# Relog des Clients → Client-debug.log: [w6a-nightsync] event=umbral day=<d> (login)

# --- Schritt C: Pale-Blässe ------------------------------------------------------
eclipse event set pale
#   [w6a-nightsync] event=pale ... (nightfall);  [w6a-moon] mode=pale
# FOTO 3 "pale": Mond fahl/knochenweiß entsättigt; Sterne UNVERÄNDERT zu FOTO 1 (A3: Pale ±0)

# --- Schritt D: Override-Sync (Drift-Watcher) ------------------------------------
eclipse event set none
#   binnen <=1 s (20t-Watcher): [w6a-nightsync] event=none ... (dawn) auf BEIDEN Seiten
#   [w6a-moon] mode=none
# FOTO 4 "none-Gegenprobe": byte-gleiche Optik zu FOTO 1 (PFLICHT-Kriterium §3)
# Optional Iris-Gegenprobe: Shaderpack aktivieren -> Custom-Sky deaktiviert sich wie im Bestand
#   (das Iris-Gate liegt VOR dem Mond-Pass; A2/A3 koennen dort nie zeichnen)

# --- Schritt E: A4 Rudel-Landung --------------------------------------------------
time set midnight
eclipse event set umbral
eclipse day set 6                            # STALKER_MIN_DAY=5; Gate-Logs beachten
difficulty easy                              # Peaceful despawnt Hostiles (Spawner skippt)
kill @e[type=eclipse:umbral_stalker]         # Cap freimachen, sonst kein neues Pack
# <=100t (5 s) warten, dann:
#   rg "\[w6a-packland\]" run/logs/debug.log   -> size=<3|4> umbral=true at=<pos>  (>=1)
# FOTO 5: tick rate 2 setzen SOBALD die Sonde faellt -> die 60t-Buehne dehnt sich auf ~30 s
#   (Bodennebel-Ring + Augen-Glints am gemeldeten <pos>)
# Deterministischer Foto-Fallback (umgeht Spawner-RNG):
#   execute as Dev run dev photon test "eclipse:wave6_pack_land" <x> <y> <z>
tick rate 20

# --- Schritt F: A5 Doppelgaenger-Fluestern ----------------------------------------
eclipse event set pale
execute as Dev at Dev run summon eclipse:the_other ~5 ~ ~
# Dev stehen lassen (<=12 Bloecke):
#   rg "\[w6a-otherdread\]" run/logs/debug.log -> target=Dev dist=<f>, Abstand 3-4 s je Zeile
# Gegenprobe: Dev >12 Bloecke weg -> Zeilen stoppen; 2. Spieler weiter weg taucht nie als target auf
# (Audio-Beleg nur mit Kopfhoerer noetig — die Sonde ist der Primaerbeweis)

# --- Schritt G: A6 Morgen-Erloesung ------------------------------------------------
# (Pale-Event aus Schritt F ist noch aktiv; Spawner muss die Nacht GESEHEN haben:
#  nach dem letzten "event set" >=5 s warten, dann)
time set day
# <=100t (5 s):
#   [w6a-dawnrelease] players=<n> event=pale
#   [w6a-nightsync] event=none ... (dawn)
#   The Other loest sich auf (Bestand: SOUL_ESCAPE + arm_wisps)
# Client: leiser Exhale hoerbar; FOTO 6 (optional): tick rate 2 direkt vor time set day ->
#   aufsteigender Mote-Ring am eigenen Standpunkt (~5 s -> ~50 s Echtzeit)
#   Foto-Fallback: execute as Dev run dev photon test "eclipse:wave6_dawn_release" <x> <y> <z>
# Gegenprobe: erneut time set night, KEIN Event setzen, wieder time set day -> Sonde bleibt still
tick rate 20

# --- Schritt H: A7 Stalker-Glow -----------------------------------------------------
time set midnight
eclipse event set none
execute as Dev at Dev run summon eclipse:umbral_stalker ~8 ~ ~
# FOTO 7a "Basis-Glow" (Client-debug.log: [w6a-stalkerglow] umbral=false)
eclipse event set umbral
# FOTO 7b "Boost" — glow_spine/Augen deutlich heller ([w6a-stalkerglow] umbral=true)
# reducedFx-Gegenprobe: im CLIENT run/config/eclipse-client.toml reducedFx=true setzen
#   (Config-Reload/Client-Neustart) -> Optik == FOTO 7a, Sonde umbral=false; danach zuruecksetzen
#   (gleiches Bild prueft A2-Ghost-Quad-Entfall: Mond-Tint bleibt, Doppelquad weg)

# --- Schritt I: Hygiene ---------------------------------------------------------------
eclipse event set none
kill @e[type=eclipse:umbral_stalker]
kill @e[type=eclipse:the_other]
tick rate 20
rg "\[w6a-" run/logs/debug.log | wc -l        # Sammelgrep archivieren (Plan §8 Schritt 5)
```

**Erwartete Sonden-Übersicht** (Grep-Anker): `[w6a-nightsync]` (beidseitig, Origin-Tags
`login|nightfall|dawn`), `[w6a-moon]` (Client, 1×/Wechsel), `[w6a-packland]` (Server),
`[w6a-otherdread]` (Server, ≥3 s Abstand), `[w6a-dawnrelease]` (Server, 1×/Dawn),
`[w6a-stalkerglow]` (Client, 1×/Flip).

## 7. Scope-/Verhaltens-Notizen für den Hauptagenten

- **Kein Bestandsverhalten geändert**: alle Diffs additiv bis auf den begründeten
  1-Zeilen-Layer-Swap in `UmbralStalkerGeoRenderer` (§2 A7) und den erweiterten
  `clearNightEvent`-Body (State-Clear + INFO-Log des Bestands unverändert davor).
- `event set none` bei Tag: der Drift-Watcher synct auch das (Tag-Semantik `dawn`).
- Der `[w6a-nightsync]`-Login-Eintrag erscheint serverseitig 1× pro Login zusätzlich
  zur Client-Zeile — beim Sammelgrep nicht als Doppel-Event verbuchen.
- Photon-lose Clients: A4 degradiert zum CAMPFIRE_COSY_SMOKE-Ring, A6 zu END_ROD-Motes
  (Vanilla-Fallback im jeweiligen Photon-Leg); `reducedFx` skippt beide Cues komplett.
