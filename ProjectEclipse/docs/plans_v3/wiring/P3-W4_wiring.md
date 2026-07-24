# P3-W4 — Localization core (integration ledger)

## Self-contained (no hub edit required)

W4 registers these via `@EventBusSubscriber` — **do not duplicate** in `EclipseMod.java` or
`EclipsePayloads.java`:

| Class | Bus | Role |
|---|---|---|
| `network/LangPayloads.java` | MOD | Registers `C2SLocalePayload` on registrar `"2"` |
| `lang/LocaleAttachmentStore.java` | MOD | Registers `eclipse:locale_override` attachment |
| `lang/LangService.java` | GAME | Login/logout session cache |
| `client/lang/LangClientCommands.java` | CLIENT | `/lang`, `/sprache`, login sync |
| `client/lang/EclipseLang.java` | CLIENT | Resolver + resource reload listener |

## Optional integrator dedupe

The plan ledger listed `locale_override` on `registry/EclipseAttachments.java`. W4 already
registers the same id in `LocaleAttachmentStore` — **pick one** (keep W4's self-registration
OR move to the hub; never both).

## P3-W3 (Settings) wiring — wave 1 partner

`EclipseClientConfig` (owned by W3) must add §7.1 key `langOverride` (`auto` / `en_us` /
`de_de`). Wire persistence into `EclipseLang.LangConfigBridge`:

```java
static String load() { return EclipseClientConfig.langOverride(); }
static void save(String value) { EclipseClientConfig.setLangOverride(value); }
```

Settings language row should call `EclipseLang.setOverride(...)` + send
`C2SLocalePayload` (same path as `LangClientCommands.apply`).

## P4 (gameplay) — frozen APIs

### `Localized` (`core/config/Localized.java`)

```java
record Localized(String en, @Nullable String de)
static Localized of(String english)
static Localized parse(JsonElement element)  // string OR {en,de}
JsonElement toJsonElement()                   // legacy string or object
String pick(String locale)                    // locale = "en" | "de" from LangService
```

**`days.json` schema** (parser change is P4-owned in `EclipseConfig`):

```json
{
  "day": 3,
  "goals": ["Legacy english only", {"en": "Mine ore", "de": "Erz abbauen"}],
  "title": {"en": "Day 3", "de": "Tag 3"},
  "subtitle": {"en": "…", "de": "…"}
}
```

Legacy plain string → `Localized.parse` treats it as English (`de` falls back via `pick`).

### `LangService` (`lang/LangService.java`)

```java
static String locale(ServerPlayer player)           // "en" | "de"
static String pick(Localized text, ServerPlayer player)
static void applyLocale(ServerPlayer player, String locale, boolean explicit)
static void resendLocaleSensitive(ServerPlayer player)
```

P4 should localize `S2CDayStatePayload` / `S2CGoalProgressPayload` goal lines with
`LangService.pick(localizedGoal, player)` before send (replace raw `List<String>` in
`DayPlan` with `List<Localized>`).

## Client audit hooks (`EclipseLang`)

```java
static String locale()              // effective en_us | de_de
static String overrideRaw()         // auto | en_us | de_de
static int generation()             // cache key bump on reload/override
static boolean usesVanillaPath()    // true when auto matches game language
static boolean hasKey(String key)   // literal-audit helper
static void addReloadListener(Runnable)
```

Frozen §7.2: `tr`, `trString`, `setOverride`, `reload`.

## Reload flow (instant, no global language change)

1. `/lang de` → `EclipseLang.setOverride("de_de")` → `reload()` rebuilds EN/DE prefix
   tables from all packs, bumps `generation()`, re-inits open Eclipse screens via
   `Screen.resize()` (re-runs `init()`).
2. Same command sends `C2SLocalePayload("de_de", explicit=true)` → server
   `LangService.applyLocale` stores override on `locale_override` attachment + session map
   → `resendLocaleSensitive`: `EclipsePayloads.sendArtifactState`, `S2CGoalProgressPayload`,
   `TimelineService.syncTo`.
3. HUD/widgets include `EclipseLang.generation()` in cache keys (sibling workers) so strings
   flip next frame without restarting the game. When override is `auto` and matches vanilla
   language, `usesVanillaPath()` stays true (zero-cost `Component.translatable` path).

## Langdrop

Merge `docs/plans_v3/langdrop/P3-W4.json` (17 keys × 2 locales).
