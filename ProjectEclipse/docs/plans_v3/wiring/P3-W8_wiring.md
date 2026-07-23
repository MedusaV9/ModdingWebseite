# P3-W8 — Main menu v2 / Journey (integration ledger)

## Self-contained (no hub edit required)

W8 registers everything via `@EventBusSubscriber` — **do not duplicate** in `EclipseMod.java`
or `EclipsePayloads.java`:

| Class | Bus | Role |
|---|---|---|
| `core/config/EclipseJourneyConfig$SelfRegistrar` | MOD (client) | Registers the `eclipse-journey.toml` CLIENT spec during `FMLConstructModEvent` (verified to run before FML's "Config loading" stage) |
| `network/JourneyPayloads` | MOD | Registers `S2COpStatusPayload` on registrar `"2"` |
| `network/JourneyPayloads$LoginSender` | GAME | Sends op level (`player.server.getProfilePermissions`) on every login |
| `client/menu/SettingsReachability` | GAME (client) | B1 entry points: pause-menu "Eclipse…" button + vanilla-title gear (`customMenu=false`) |

## Optional integrator dedupe

- **Config registration**: the plan ledger listed an `EclipseMod` line
  `EclipseJourneyConfig.register(modContainer)` (CLIENT dist guard). The self-registrar makes
  it unnecessary, and `register(...)` is idempotent (`AtomicBoolean`) — adding the hub line is
  harmless but redundant. **Pick one** (recommended: keep self-registration, add nothing).
- **B1 entry points vs. P3-W3**: W3 owns the settings platform (`SettingsPanel`,
  `EclipseSettingsScreen` v2, `PauseMenuHook`, `VanillaTitleGear`). `SettingsReachability`
  runs at `EventPriority.LOW` and **skips injection when the screen already has any widget
  labelled with a `gui.eclipse.*` translation key**, so both implementations coexist without
  double buttons in any merge order. Once W3's mounts are merged, the integrator MAY delete
  `SettingsReachability.java` (and the `gui.eclipse.journey.settings_entry` lang key); until
  then it is the live fix for B1.
- **W3 note**: `EclipseSettingsScreen.isPauseScreen()` currently returns `false` — opened from
  the pause menu in singleplayer the game keeps running behind it. Reachability is fixed
  either way; W3's settings v2 should return `true` when the parent is a `PauseScreen`.

## P3-W1 (widget kit / sounds) — swap points, not blockers

- `GlitchErrorTheater.playGlitchBurst()` uses the §2.3 procedural fallback (shipped
  `event.border_glitch` static burst + `ui.tab` pitched to 0.55, both `SimpleSoundInstance.forUI`
  and gated by `uiSounds`). When W1 lands `ui.error_glitch` + `UiSounds.error()`, replace the
  body with `UiSounds.error()`.
- `GlitchErrorTheater` mirrors the frozen §2.1 palette in private constants (`PANEL`,
  `PANEL_RAISED`, `HAIRLINE`, `ACCENT`, `TEXT`, `DIM`, `DANGER`, `VEIL`). When W1's
  `EclipseUiTheme` lands, the constants can be swapped for the shared tokens verbatim
  (identical values).

## P5 (modpack / config distribution)

- Ship `eclipse-journey.toml` in the pack config overrides (plan §5.3). The event switch:

  ```toml
  serverHost = "play.example.org"        # or "host:port" (bracket IPv6: "[2001:db8::1]:25565")
  serverPort = 25565
  activationIso = "2026-08-01T18:00:00+02:00"   # ISO-8601 WITH zone/offset
  modpackMode = true
  devUnlock = false
  ```

- The date gate runs on the **local clock** (cosmetic theater); keep the server whitelist as
  the hard gate until launch (§3.8 clock-source note).
- State file written by the client: `config/eclipse-journey-state.json` (`{"opGranted":bool}`)
  — do NOT ship it in the pack; it is per-player cache (cleared by deleting the file; W3's
  settings SERVER section gets the clear button per risk R-11).

## Langdrop

Merge `docs/plans_v3/langdrop/P3-W8.json` (14 keys × 2 locales, `gui.eclipse.journey.*`).
No new sound events, hence no new `subtitles.eclipse.ui.*` keys from W8
(`subtitles.eclipse.ui.error_glitch` belongs to W1's registration).
