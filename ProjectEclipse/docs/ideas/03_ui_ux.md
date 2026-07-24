# Collector #3 — UI / UX / HUD

Verified against neoforge-21.1.238-sources + patched MC 1.21.1 sources.

## A) API research (verified)

**GUI layers**: `RegisterGuiLayersEvent` (mod bus): `registerAbove/Below/AboveAll/BelowAll`, `replaceLayer(ResourceLocation, LayeredDraw.Layer)`, `wrapLayer(...)`. `RenderGuiLayerEvent.Pre` (game bus, cancellable) / `.Post`. `VanillaGuiLayers.PLAYER_HEALTH`, `BOSS_OVERLAY`, `SCOREBOARD_SIDEBAR`.

**Boss bar**: `CustomizeGuiOverlayEvent.BossEventProgress` (game bus, cancellable, per bar): `getBossEvent()` → client `LerpingBossEvent` (UUID, name, progress), `getX()/getY()`, `getIncrement()/setIncrement(int)` (reserve vertical space). Cancel + draw own at (x,y) = surgical skinning of only OUR bars (match by name/translation key or synced UUID set). Full replacement: cancel `RenderGuiLayerEvent.Pre` for BOSS_OVERLAY.

**Health bar**: vanilla `Gui.renderPlayerHealth`: origin `x0 = guiWidth()/2 - 91`, `y = guiHeight() - leftHeight`; NeoForge public `Gui.leftHeight`/`rightHeight` (base 39). Heart step = 8px, sprite 9×9 (`hud/heart/*` via blitSprite); rows stack up by `max(10 - (rows - 2), 3)` where rows = ceil((max+absorb)/2/10); regen wave = `tickCount % ceil(maxHealth + 5)`; jitter ±1px when health ≤ 4 (seed `tickCount * 312871`). → overlay burst effects exactly on heart positions WITHOUT replacing vanilla layer (safest interop).

**Scoreboard**: no dedicated event; cancel/replace SCOREBOARD_SIDEBAR layer. Better: skip vanilla scoreboard data; render own panel from ClientStateCache.

**Cursors** (no vanilla API): GLFW handle `Minecraft.getInstance().getWindow().getWindow()` (public). `GLFW.glfwCreateStandardCursor(GLFW_POINTING_HAND_CURSOR)` (guard + fallback ARROW if 0). Themed: PNG → GLFWImage (STBImage/NativeImage) → `glfwCreateCursor(image, hotX, hotY)`. Apply `glfwSetCursor(handle, ptr)`; **reset `glfwSetCursor(handle, MemoryUtil.NULL)` in `Screen#removed()`**; render-thread only; cache ptrs; destroy on resource reload. Swap only on hover-state change.

**Hover sounds**: edge-detect `wasHovered` → `Minecraft.getInstance().getSoundManager().play(SimpleSoundInstance.forUI(EclipseSounds.UI_HOVER.get(), pitch))`.

**Hi-res art**: author at 4× GUI px (200×20 button as 800×80), blit with full texture dims → sharp at scales 1–4. Pixel-snap `Math.round(v * guiScale) / guiScale`. Handbook sized as % of screen (90%×85%) — kills the "tiny box" feel.

**GUI shaders**: (a) vanilla core shaders via `RegisterShadersEvent` (`new ShaderInstance(event.getResourceProvider(), rl, DefaultVertexFormat.POSITION_TEX_COLOR)`), JSON+GLSL under `assets/eclipse/shaders/core/`, drawn via custom RenderType + `guiGraphics.bufferSource().getBuffer(type)`; (b) Veil post pipelines. Recommendation: (a) primary, Veil optional extras; every shader needs no-shader fallback.

**Title animation**: existing PanoramaRenderer/CubeMap animates; add parallax blits offset by mouse, screen-space particles, vignette in render().

## B) Handbook 2.0 — "The Ledger of the Drowned"

**IA — 6 tabs on left spine** (replaces ArtifactScreen content; keep ArtifactScreen as thin opener):
1. **Status** — big day counter, live heart row, altar progress ring, today's 3 goals w/ tick animation, online count.
2. **Timeline** — horizontal scrollable spine (see E).
3. **Rules** — absorb RulesScreen; scrollable parchment.
4. **Rewards** — milestone costs/rewards, item icons via `guiGraphics.renderItem`.
5. **Bestiary** — cards revealed as days unlock; locked = silhouette + glitch text.
6. **Map** — stylized ring diagram (concentric rings per stage/borderSize).

**Layout**: full-bleed dark vignette over world; centered book 90%w × 85%h; left page (nav + hero art), right page (content). Vertical parchment tab tongues far left with icons; active tab slides out 6px + glows. Bottom: page dots + hint. All coords from width/height percentages.

**Animations**: open = book unfolds (scaleY 0.9→1 + alpha, 8t, ease-out cubic); tab switch = page-turn (old page skews/compresses, 6t + page_turn sound); parallax (bg 8px opposite mouse, mid 4px); goal tick draws itself (fill sweep); altar ring pulses on level-up; hover = 2px purple glow fade (4t) + sound; inertial scroll.

**Cursor**: themed arrow 32×32 default; pointing-hand over interactives; grab while dragging timeline.

**Asset list (image-gen)**: book bg spread 2048×1280; 6 tab icons 64×64; parchment 1024×1024 tileable; hero art per tab 1024×768; cursor sheet 3× 32×32 (hotspots 0,0/8,0/16,16); heart icons (full/empty/cracked/burst×6) 36×36; altar ring 256×256; timeline nodes (locked/unlocked/current) 96×96; divider 512×64. Sounds: ui.hover, ui.page_turn, ui.tab, ui.unlock_sting.

## C) Hearts + burst

**Server**: real max health. `player.getAttribute(Attributes.MAX_HEALTH).addOrUpdateTransientModifier(new AttributeModifier(ResourceLocation.fromNamespaceAndPath("eclipse","hearts"), hearts*2 - 20, AttributeModifier.Operation.ADD_VALUE))` — 5 hearts ⇒ −10 ⇒ 10 max HP. Keep LIVES attachment as source of truth (copyOnDeath); reapply modifier in `PlayerEvent.PlayerRespawnEvent`, `PlayerEvent.Clone`, `PlayerLoggedInEvent` (transient avoids NBT double-apply). Clamp current health to new max; keep S2CLivesPayload.

**Burst**: do NOT replace PLAYER_HEALTH; overlay above. `S2CHeartBurstPayload(int heartIndex)` on respawn-with-loss; client stores start tick. `registerAbove(VanillaGuiLayers.PLAYER_HEALTH, ...)`. Position via vanilla math: `x = guiWidth()/2 - 91 + heartIndex*8`, `y = guiHeight() - 39` (recompute rows if max+absorb > 20). ~12t: flash white (2t), crack (3 frames), shatter into 6 shard quads flying w/ gravity + alpha fade, custom glass-crack sound + 2t red vignette. Mirror low-health jitter (same seed math) so overlay tracks vanilla.

**Sodium/Iris safety**: pure GuiGraphics blits on HUD layer — untouched by both. Read `gui.leftHeight` at render time (handles AppleSkin-style mods).

## D) Bossbar & scoreboard skinning

**Bossbar (surgical)**: `CustomizeGuiOverlayEvent.BossEventProgress`; match our bars (translation keys `ritual.eclipse.revive.bossbar`, `eclipse.day`, `eclipse.goal`, boss names or synced UUIDs); cancel, `setIncrement(getIncrement() + 10)`, draw: 256×32 frame (drawn 182×14+), lerped fill (0.05/frame), scrolling energy texture (UV by `Util.getMillis()`), end-cap glow flash on progress change. Toggle: hidden → render 4px minimal strip (never fully lose revive countdowns). Fallback: event absent → vanilla renders.

**Scoreboard**: don't use vanilla scoreboard. Cancel SCOREBOARD_SIDEBAR if set; register own right-side panel: rows = hearts (icon), day, altar level, online count, personal goal ticks (needs S2CGoalProgressPayload). 110×rows*12px, right-anchored, slide-in on change, 60% black rounded backdrop, 12×12 icons.

**Toggle persistence**: NeoForge `ModConfigSpec` client config (`showBossbar`, `showSidebar`, `customMenu`, `uiSounds`, `customCursor`) + `EclipseSettingsScreen` + `IConfigScreenFactory` extension point (appears in Mods list).

**Texture spec**: bossbar frame 512×64 ×3 themes (day/goal/boss), fill strip 512×32 + scroll overlay 256×32, end-glow 64×64; sidebar 9-slice 64×64; 5 sidebar icons 24×24.

## E) Timeline + announcements

**Data model**: `record TimelineEntry(int id, int unlockDay, String titleKey, ResourceLocation icon, boolean hidden, boolean reached)`; source days.json + milestones; `S2CTimelinePayload(List<TimelineEntry>)` on login + day change. Hidden future entries sent WITHOUT title/icon (anonymized server-side — no datamining). Rendered as "???" silhouettes + glitch text (random chars re-rolled every 3t).

**Announcements**: (1) chat typewriter — own overlay line above hotbar typing out (1 char/t, tick sound per 2 chars), then post complete Component to chat once. (2) bossbar sweep — client-only temp bar: fill sweeps 0→1 over 30t w/ bright leading edge, holds 60t ("DAY 4 — THE VEIL THINS"), fades. Both via one `S2CAnnouncePayload(title, subtitle, style)`.

## F) Ranked ideas

1. [MUST] Heart-burst shatter on respawn — 3
2. [MUST] Handbook 2.0 six-tab codex + page-turn + parallax — 5
3. [MUST] Custom cursor set (arrow/hand/grab) via GLFW — 2
4. [MUST] Hover/page/tab UI sound suite — 1
5. [MUST] Skinned event bossbars + animated fill + toggle — 3
6. [SHOULD] Custom sidebar panel w/ icons — 2
7. [SHOULD] Typewriter announcement + bossbar sweep — 2
8. [SHOULD] Glitch "???" on redacted timeline/bestiary — 1
9. [SHOULD] Heartbeat vignette + muffled thump at ≤2 hearts — 2
10. [SHOULD] Title screen v2: drifting panorama + 3 parallax cloud layers + wisp particles + logo eclipse-flare sweep — 3 (customMenu config off-switch fits TitleScreenSwap guard)
11. [NICE] Eye-blink screen transition — 3
12. [NICE] Admin editor screen (days.json goals/unlocks/border/timing GUI, C2SEditConfigPayload perm-checked) — 4
13. [NICE] Animated altar ring spin-up on level-up — 2
14. [NICE] "Drowned glass" core-shader wobble behind handbook — 4
15. [NICE] Logo long-press → dev credits page — 1

**Risks**: cursor lifecycle leaks (always reset in Screen#removed); max-health modifier double-apply (transient + reapply); bossbar event only fires while BOSS_OVERLAY runs; shaders never load-bearing (texture fallback everywhere).
