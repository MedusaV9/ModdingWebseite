# PLAN F-074 — Altar-UI Lesbarkeit + Kaufbestätigung + Kauf-Animation + Nach-Kauf-Cutscene

> **User report (F-074):** _"Verbessere das Altar UI noch etwas mehr das alles etwas leichter
> lesbar ist und beim Shop Tab mach das man seinen kauf bestätigen muss plus so eine Kauf
> Animation hat und dann so eine kurze Cutscene danach jenachdem was man geholt hat."_
> — (1) make the altar panel easier to read, (2) shop purchases need a CONFIRM step plus a
> purchase animation in the UI, (3) afterwards a SHORT cutscene plays that depends on WHAT
> was bought.
>
> **Status:** plan matches the implementation landed in commit `681f98e` — this document is
> the design spec + the verification recipe for that wave. All paths relative to
> `ProjectEclipse/` unless absolute.

---

## 1. Current-state survey (what the altar UI actually is)

There is no `MenuType`/container and no literal "Shop tab": the altar panel is ONE pure
client `Screen` with two columns — milestone requirements left, the shard shop right. The
user's "Shop Tab" = the right column.

| Concern | Where it lives |
|---|---|
| Panel screen (client) | `src/main/java/dev/projecteclipse/eclipse/client/altar/AltarScreen.java` |
| Panel/buy payloads + server assembly | `src/main/java/dev/projecteclipse/eclipse/network/altar/AltarPayloads.java` (self-registering, version group `v6altarui…`) |
| Offer table, guard chain, purse charging | `src/main/java/dev/projecteclipse/eclipse/economy/ShardEconomy.java` (`allOffers()`, `buyById`, `buy`) |
| Theme (colors/metrics) | `client/handbook/EclipseUiTheme.java` — `PANEL 0xF2120B1E`, `PANEL_RAISED`, `HAIRLINE 0xFF2E2347`, `ACCENT 0xFFB98CFF`, `TEXT 0xFFEDE7F8`, `DIM 0xFF9A8FB8`, `GOOD`, `DANGER`, `VEIL`; `ROW=12`, `GAP=4`, `PAD=12` |
| UI sounds | `client/handbook/UiSounds.java` → `assets/eclipse/sounds.json` ids `ui.page_turn`, `ui.click`, `ui.error_glitch`, `ui.roulette_tick`, `ui.roulette_win` |
| Reduced-FX switch | `core/config/EclipseClientConfig.reducedFx()` |
| Existing ceremony/FX primitives | `S2CQuasarPayload` (emitters in `assets/eclipse/quasar/emitters/`: `altar_beam`, `altar_pillar`, `altar_levelup_ring`, `heart_burst`, …), `network/fx/FxPayloads.FX_SHOCKWAVE`, `ritual/AltarModelTriggers.gift()` (altar model bow), Display-entity pattern from `sequence/HeraldSummonSequence` |

**Flow before F-074:** right-click altar → `S2CAltarPanelPayload(openScreen=true)` → screen
polls `C2SAltarPanelRequestPayload` every 40 t; clicking an offer row sent
`C2SAltarBuyPayload` IMMEDIATELY (blind buy — the exact complaint), and the only feedback
was the refreshed snapshot. Anti-spoiler contract (AUDITFIX-3): only currently purchasable
offers are ever transmitted; locked ones ride as an opaque `sealedOffers` count ("???" rows).

**Shop offer table** (`ShardEconomy.OFFERS` — categories derive from the DATA SHAPE, below):
`grave_dowser` 4 (day 1) · `compass_of_watcher` 8 (day 3) · `umbral_pick` 12 (day 4) ·
`umbral_blade` 16 (day 6) · `vitae_shard` 20 (day 8) — personal purse; pooled team offers:
`eclipses_favor` 16 (day 2) · `double_xp` 20 (day 4) · `supply_beacon` 24 (day 5), all with
`item == null`.

---

## 2. Files to touch

| File | Change |
|---|---|
| `client/altar/AltarScreen.java` (existing) | Readability pass + confirm overlay + purchase animation + fail flash (all in §3–§5) |
| `network/altar/AltarPayloads.java` (existing) | `ShopEntry.rewardItemId`, new `S2CAltarBuyResultPayload`, success detection in `handleBuy`, version bump (§4) |
| `economy/AltarBuyCeremony.java` (**new**) | The 3–6 s category-dependent world mini-cutscene (§6) |
| `assets/eclipse/lang/de_de.json` + `en_us.json` (existing) | ~7 new keys (§7) |
| No other files | No new payload registrar, no new Quasar emitter JSON, no new Photon `.fx`, no client FX class, no sounds.json entries (§8) |

---

## 3. Readability pass (`AltarScreen`, concrete per drawing site)

1. **Panel floor** 420×250 → clamp **440–600 × 260–340** (`Mth.clamp(width-40, 440, 600)`).
2. **Column divider:** 1 px `HAIRLINE` vertical between milestone and shop columns.
3. **Requirement rows** `REQ_ROW_H` 22 → **24**; banked count carries the state color
   (`GOOD` when done — with a `✓` prefix — else `ACCENT`), the `" / needed"` tail stays
   `DIM`; progress bar 3 px floating sliver → **4 px on a full-width `HAIRLINE` underlay**.
4. **Hover tooltips** on requirement rows: full item name + exact `banked / needed`
   (names ellipsize on narrow panels; suppressed while a modal layer is open).
5. **Offer rows:** adaptive height 28 px, compressing to ≥20 px on offer-heavy days so the
   footer never clips; a **2 px affordability edge** left (`GOOD` buyable / `DANGER` short);
   the price in a **framed chip** (`×N` + currency ITEM icon) so it reads as one unit;
   second line = currency display name · which purse pays (· Double-XP countdown).
6. **Balance footer** (40 px): hairline + both balances led by the actual currency item
   icon — the same icon the price chips use.
7. **Boss instruction body** was the least readable text on the panel: `DIM` →
   `withAlpha(TEXT, 0.85F)`.
8. Sealed "???" rows stay inert at 0.45 alpha (unchanged contract).

---

## 4. Payload changes (`AltarPayloads`, wire version → `v6altarui4`)

- **`ShopEntry` + `rewardItemId`** (7th field → hand-rolled `StreamCodec.of`, past the
  6-component `composite()` ceiling): registry id of the reward item, `""` for the non-item
  team offers. Resolved from the SAME `Offer.item()` supplier the buy path delivers — no
  spoiler surface (only purchasable offers ever carry a `ShopEntry`). Feeds the confirm
  overlay's "what you are buying" icon.
- **New `S2CAltarBuyResultPayload(pos, offerId, success)`**, buyer-private, id
  `eclipse:altar/buy_result`, registered `playToClient` in the same self-registrar. Needed
  because the refresh snapshot carries no success bit and inferring success from balance
  deltas would misread concurrent team-pool spends.
- **`handleBuy` success detection WITHOUT touching the guard chain:** `ShardEconomy.buyById`
  stays the single validation authority; the purse before/after delta (`== cost`) inside the
  synchronous server-thread call IS the success bit. On success: arm
  `AltarBuyCeremony.begin(player, pos, offer)` → send the receipt → send the refresh
  snapshot (win or refuse).

---

## 5. UI state machine + purchase animation (`AltarScreen`)

```
IDLE ──row click──▶ CONFIRM ──Kaufen/Enter──▶ AWAITING ──receipt ok──▶ BUYFX ──1250 ms──▶ close (world ceremony)
  ▲                   │ Esc / Abbrechen / outside click                   │
  └───────────────────┘◀──────── receipt fail: FAIL_FLASH (450 ms) ◀──────┘
```

- **CONFIRM** (modal, `confirmOffer != null`): veiled panel + 248×132 dialog — reward icon +
  name, itemised price (`N × <currency icon+name>`, `ACCENT`/`DANGER`), which purse pays,
  balance AFTER the buy (or `short_by`), keyboard hint; **Abbrechen** (quiet) / **Kaufen**
  (accent, disabled while short). Enter confirms, Esc/outside click cancels (Esc never
  closes the whole panel). Buttons are plain rect hit-tests drawn after `super.render`
  (widgets would z-order under the veil). Refresh snapshots landing mid-modal re-resolve
  the offer by id; a vanished offer dismisses the dialog — a stale confirm must never buy.
- **AWAITING** (`awaitingResult`): input locked, 60 t watchdog clears a lost receipt.
- **BUYFX** (ms clock, `Util.getMillis`): 6 currency icons fly footer-balance-line → offer
  row (520 ms each, 55 ms stagger, easeOutQuad + sine arc, `ui.roulette_tick` per landing,
  pitch rising); gold pulse over the row 320–1140 ms (`0xFFF2C879`/`0xFFFFE9B0` fill + ring)
  under 10 deterministic spark crosses + one `ui.roulette_win` sting; panel **closes itself
  at 1250 ms** so the world ceremony takes the stage. `reducedFx`: no frames — sting + close
  at 300 ms. 2-click protection end-to-end: row clicks are ignored in every non-IDLE state.
- **FAIL_FLASH:** refused row flashes `DANGER` 450 ms + `ui.error_glitch`.

---

## 6. Post-purchase mini-cutscene (`economy/AltarBuyCeremony`, new, server-driven)

Short 3–6 s in-world beat at the altar, `ServerTickEvent.Post`-scripted (NOT a
credits-style camera sequence — camera stays with the player; visible to everyone within
48 blocks). Starts after a **28 t UI grace** so the panel animation lands first. Concurrent
runs capped at 8 (oldest finished early).

**Category mapping is data-driven off the `Offer` shape** (no hand-kept id lists; new
offers pick their ceremony automatically): `item == null` → **TEAM**; reward
`instanceof VitaeShardItem` → **HEART**; every other item → **GEAR**. (Three categories,
not four: the real offer table has no weapon/tool/consumable split worth separate beats.)

Shared **t=0 opening beat**: `altar_beam` Quasar + amethyst chime (1.1) +
`AltarModelTriggers.gift()` (the altar model bows its gift animation).

### TEAM — rising light spiral + violet→gold colour wave (~5 s, 100 t)
| Tick | Beat |
|---|---|
| 0–80, every 2 t | two-arm END_ROD spiral climbing 6 blocks off the crown, radius 1.25 tapering; dust tint lerps `(0.72,0.55,1.0)` → `(1.0,0.83,0.45)` |
| 16 | `FX_SHOCKWAVE` (0.5 / 26) — NOT the reserved (1.0, 50) giant pair — + `beacon.activate` (1.2) |
| 16–44 | 16-point dust ring rolling outward to r=8 at ankle height |
| 52 | second `FX_SHOCKWAVE` (0.32 / 20) + `beacon.power_select` (1.35) |
| 84 | `altar_levelup_ring` Quasar + chime (1.5) |
| 100 | end |

### GEAR — the bought item rises, spins in a light spot, flies into the buyer (~4.1 s, 82 t)
| Tick | Beat |
|---|---|
| 0 | spawn ONE `Display.ItemDisplay` of the reward (tag `eclipse_altar_buy_gift`, brightness 15/15) |
| 0–30 | rise easeOutCubic to +1.35, scale 0.3→0.85, spin 5°/t; chime (1.4) at 30 |
| 30–58 | hover bob; spin 11°/t; END_ROD + gold-dust motes circling every 4 t |
| 58 | flight endpoints locked; buyer >24 blocks → abort, burst at the crown instead |
| 58–82 | smoothstep flight with LIVE retarget to the moving buyer, +0.6 sine arc, scale→0.2, spin 17°/t, END_ROD trail every 2 t |
| 82 | catch: `heart_burst` Quasar + 10 END_ROD + `item.pickup` + `player.levelup` (0.45, 1.6) |

Transform pushes every 2 t with `interpolationDuration = 2` (the DisplayAnimator law).
Despawn guarantee (StormDebrisFx doctrine): live-UUID set + `EntityJoinLevelEvent` sweep of
tagged strays; `/kill @e[tag=eclipse_altar_buy_gift]` always works; `ServerStoppedEvent`
clears runs.

### HEART — vitae shard: light fountain + bells (~6 s, 120 t)
| Tick | Beat |
|---|---|
| 0 | `bell.resonate` (0.7) |
| 4 / 10 / 16 | three `altar_pillar` Quasars stacked +2.2 blocks apiece |
| 0–90, every 3 t | 3 directed END_ROD fountain jets (count=0 velocity form) + pink dust `(1.0,0.38,0.55)` |
| 24 / 44 / 64 | chime + bell at pitches 0.8 / 1.0 / 1.25 (descending-then-ascending bell line) |
| 30 | `heart_burst` Quasar |
| 90–120 | pink-gold ash settling; final bell (1.4) at 112 |

**Budget:** ZERO block displays; GEAR uses exactly 1 item display; particle rate ≤ ~8/t
worst case — far under the <300-display ceiling. Photon-less / `reducedFx` clients keep the
full read (Quasar degrades in `QuasarSpawner.spawnOrFallback`; the rest is vanilla
particles + sounds). **No new Photon `.fx`** — `tools/photon/*.py` generators (e.g.
`ceremony_fx.py`) stay untouched; the existing altar emitters already carry the identity.

---

## 7. Lang keys (de_de + en_us)

New: `gui.eclipse.altar.confirm.title` ("Kauf bestätigen"), `.price` ("%1$s × %2$s"),
`.after` ("Guthaben nach dem Kauf: %1$s"), `.buy` ("Kaufen"), `.cancel` ("Abbrechen"),
`.hint` ("Enter bestätigt · ESC bricht ab"), `gui.eclipse.altar.shop.count` ("×%1$s").
Reused: `gui.eclipse.altar.shop.cost/pooled/personal/have.*/short_by/buy_hint`.

## 8. Sounds (all pre-existing — nothing added to `sounds.json`)

UI: `eclipse:ui.page_turn` (open), `ui.click` (buttons), `ui.roulette_tick` (fly-in blips +
buy-fx landings), `ui.roulette_win` (purchase sting), `ui.error_glitch` (refusal) — all via
`UiSounds`, behind the `uiSounds` switch. World: vanilla `amethyst_block.chime`,
`beacon.activate`, `beacon.power_select`, `bell.resonate`, `item.pickup`, `player.levelup`.

---

## 9. Test checklist

**RCON / dedicated** (`run/server.properties`: rcon on, port 25575, pw `eclipsedev`):
1. `/eclipse shards add <p> 100`, `/eclipse shards pool set 100`, `/eclipse day set 8` —
   all 8 offers open.
2. Buy each category via panel; server log prints
   `Altar buy ceremony armed: <p> bought '<id>' (<CATEGORY>) at <pos>` — verify
   TEAM/GEAR/HEART mapping for `eclipses_favor` / `umbral_pick` / `vitae_shard`.
3. Refusal path: pool/balance at 0 → buy → `success=false` receipt, purse untouched, no
   ceremony log.
4. `/kill @e[tag=eclipse_altar_buy_gift]` mid-GEAR-flight → run ends quietly, no orphan.
5. Crash-stray sweep: force-quit during GEAR, reboot, confirm the saved display is
   discarded on join.
6. `/dev altar offer disable <id>` while the confirm dialog is open → next refresh
   dismisses the dialog (no stale buy).

**Client (manual):**
1. Readability: divider, 24 px req rows + ✓/colored banked counts + 4 px bars, price chips,
   affordability edges, footer icons, boss text contrast; hover tooltips on req rows.
2. Confirm: click row → dialog; Esc / Abbrechen / outside-click cancel; Enter / Kaufen buy;
   Kaufen disabled + error blip when short; double-click spam sends exactly ONE
   `C2SAltarBuyPayload`.
3. Buy animation: icons fly from the CORRECT balance line (pooled vs personal), gold pulse +
   sparks + win sting, panel self-closes ~1.25 s, world ceremony follows seamlessly.
4. `reducedFx=true`: no fly-in, no buy-fx frames — sting + quick close; ceremony still full.
5. Walk >8 blocks with dialog open → panel closes; balances move live while dialog open.
