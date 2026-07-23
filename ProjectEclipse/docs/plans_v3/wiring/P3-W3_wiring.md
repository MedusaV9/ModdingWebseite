# P3-W3 — Settings platform (integration ledger)

## What landed

| File | Status | Role |
|---|---|---|
| `core/config/EclipseClientConfig.java` | extended | ALL §7.1 keys + typed getters + public `ModConfigSpec` value handles + `setLangOverride` |
| `client/menu/SettingsPanel.java` | NEW | Reusable Quiet-Eclipse settings composite (one `AbstractContainerWidget`); B13 + B18 fixed here |
| `client/menu/EclipseSettingsScreen.java` | rebuilt (v2) | Hosts `SettingsPanel` + Done; `isPauseScreen()==true`; ESC → parent; §2.3 fade/rise motion |
| `client/menu/PauseMenuHook.java` | NEW | "Eclipse…" pause-menu button (`ScreenEvent.Init.Post`, dedupe guard) |
| `client/menu/VanillaTitleGear.java` | NEW | Gear on the VANILLA title while `customMenu=false` (exact-class guard like `TitleScreenSwap`) |
| `client/handbook/tabs/SettingsTab.java` | NEW | Handbook tab embedding the same `SettingsPanel` (frozen tab API; rail icon `rail_settings.png` derives from `id()`) |
| `client/menu/SettingsReachability.java` | **DELETED** | Interim B1 hotfix fully replaced by `PauseMenuHook` + `VanillaTitleGear` |
| `client/lang/EclipseLang.java` | seam completed | `LangConfigBridge.load/save` → `langOverride` key; NEW `ModConfigEvent.Loading` hook restores the override at startup (title screen), login-time `initFromConfig()` (W4) still runs |
| `client/menu/EclipseMenuButton.java` | small fix | `playDownSound` → `UiSounds.click()` (B18: no vanilla plink on title/pause buttons) |
| `hearts/client/HeartBurstOverlay.java` | small fix | Warden heartbeat now ALSO gated behind `heartbeatSound()` (B12) |

All event hooks self-register via `@EventBusSubscriber` — **no `EclipseMod.java` edit needed**.

## Integrator MUST-DOs

1. **Langdrop**: merge `docs/plans_v3/langdrop/P3-W3.json` into `assets/eclipse/lang/{en_us,de_de}.json`.
   The 7 pre-existing option labels (`custom_menu`, `sidebar`, `bossbar`, `ui_sounds`, `cursor`,
   `veil_fx`, `reduced_fx`) stay as they are — the drop only adds their new `.tip` tooltips plus
   all new labels/sections/enum values.
2. **Remove orphaned lang key** `gui.eclipse.journey.settings_entry` from `en_us.json` + `de_de.json`
   (was only used by the deleted `SettingsReachability`; the pause entry now uses
   `gui.eclipse.settings.pause_entry`).
3. **Handbook roster** (W1 owns `HandbookScreen.java`): add `new SettingsTab()` to the `tabs` list,
   pinned **LAST** — `StatusTab`'s settings link presses the `8` hotkey, and §3.1 pins Settings as
   the final page. No other `HandbookScreen` change is required (the frozen widgets/keyPressed API
   carries everything).
4. **P3-W8 ledger note**: `P3-W8_wiring.md` lists `SettingsReachability` as a live GAME-bus handler
   and asks W3 for `isPauseScreen()` — both are resolved by this drop (class deleted; v2 screen
   returns `true` unconditionally, which is correct/harmless from the title screen too).

## Frozen contract notes (consumers, wave 2+)

- **§7.1 enum tokens**: implemented per the FROZEN plan list — `SidebarSide{LEFT,RIGHT}`,
  `SidebarOverflow{ELLIPSIS,MARQUEE}`, `BossbarStyle{ORNATE,SLIM}`, `sidebarScale` 0.6–1.4
  (0.05 detents). The kickoff prompt's variants (`CLIP/MARQUEE`, `FULL/SLIM`, tri-state scale)
  were superseded by §7.1; consumers MUST code against the frozen names.
- **`sidebarVisible`** from the kickoff prompt is the pre-existing v1 key `showSidebar`
  (getter `showSidebar()`) — deliberately NOT duplicated.
- **New getters ready for consumers**: `uiSoundVolume()` (double — the `UiSounds` reflective
  probe binds to it automatically, zero wiring), `heartbeatSound()`, `sidebarSide()`,
  `sidebarScale()`, `sidebarOverflow()`, `bossbarStyle()`, `showDayTimer()`,
  `customDeathScreen()`, `customLoadingScreens()`, `procMessages()`, `showCustomXpBar()`,
  `levelUpCelebrations()`, `allowServerRenderDistance()`, `langOverride()`. All are safe before
  config load (typed defaults) and read live values after every `SettingsPanel` write.
- **Writing config from UI code**: bind the `public static final` `ModConfigSpec` value handles
  in `EclipseClientConfig` and use `set()` + `save()` (see `SettingsPanel#save`). NEVER round-trip
  through `SPEC.getValues().valueMap()` (B13).
- **`EclipseTitleScreen`**: no hook needed — its gear already opens
  `new EclipseSettingsScreen(this)` and the v2 constructor signature is unchanged (same for
  `ClientMenuExtensions`' `IConfigScreenFactory`).

## Risks / follow-ups

- `SettingsPanel` renders section headers itself (inside its scissor); if W1 later adds a shared
  scrollable-list widget, the panel can migrate without changing its host surface.
- The pause-menu placement heuristic anchors on the `menu.options` widget; heavily modded pause
  screens without that key silently get no entry (settings stay reachable via handbook + Mods
  screen). The F3+Esc pause variant is intentionally skipped (vanilla shows no buttons there).
- Config file-watcher edge: editing `langOverride` in the TOML by hand mid-session updates the
  value but not the live override (UI/`/lang`/restart all do). Acceptable — the file watcher
  fires `ModConfigEvent.Reloading`, which we deliberately do not re-init from to avoid fighting
  an in-session `/lang` choice.
- Marquee (`SidebarOverflow.MARQUEE`) is a data value only for W3 — the sidebar owner implements
  the actual scrolling behavior against `sidebarOverflow()`.

## Test steps (manual)

1. **Pause reachability + pause**: singleplayer → ESC → "Eclipse…" → settings open, day/weather
   frozen (game paused); ESC returns to the pause menu.
2. **Title reachability, customMenu off**: settings → "Custom title" OFF → Done from the custom
   title → vanilla title appears with the bottom-right gear → gear opens settings → turn it back
   ON → Done → custom title returns (via `TitleScreenSwap`).
3. **Handbook tab**: open the artifact handbook → Settings tab (last page, `8`) → same rows;
   wheel scroll, slider drag, Tab-focus + ←/→ nudge, Enter flip all work; arrows still switch
   tabs while no row is focused.
4. **Live apply**: toggle "Sidebar" / move "Sidebar scale" with the HUD visible behind the
   handbook — changes appear immediately; check `eclipse-client.toml` updates on release, not
   per drag frame.
5. **B12**: at 1–2 lives, heartbeat audible; toggle "Low-lives heartbeat" OFF → silent within
   2 s (40-tick cadence).
6. **Language persistence**: set language to Deutsch (row or `/lang de`), quit the client,
   relaunch → title/settings strings are German before ever joining a world; `langOverride`
   in `eclipse-client.toml` reads `"de_de"`.
7. **B18**: no vanilla "plink" anywhere — title buttons, pause entry, settings rows all play the
   soft Eclipse click/toggle/slider cues, scaled by "UI sound volume".
