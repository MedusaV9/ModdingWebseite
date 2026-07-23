# WB-MUSIC wiring — P5-W11 music, credits, docs

This worker deliberately does **not** edit the frozen/shared files listed in its prompt.
Apply the following integration lines after all workers merge.

## 1. `EclipseMod.java` — one required registrar line

In the constructor next to `EclipseSounds.register(modEventBus);`:

```java
dev.projecteclipse.eclipse.music.EclipseMusicSounds.register(modEventBus);
```

`MusicPayloads`, `MusicManager`, `DevMusicCommands`, and `MusicConfig.SelfRegistrar`
self-register through event subscribers. Do not add them to `EclipsePayloads`.

## 2. `assets/eclipse/sounds.json` — required entries

Merge these top-level members (the source file was intentionally not edited):

```json
"music.boss_ferryman": {
  "sounds": [{ "name": "eclipse:music/boss_ferryman", "stream": true }]
},
"music.boss_herald": {
  "sounds": [{ "name": "eclipse:music/boss_herald", "stream": true }]
},
"music.limbo_ambience": {
  "sounds": [{ "name": "eclipse:music/limbo_ambience", "stream": true }]
},
"music.title_theme": {
  "sounds": [{ "name": "eclipse:music/title_theme", "stream": true }]
},
"music.expansion_theme": {
  "sounds": [{ "name": "eclipse:music/expansion_theme", "stream": true }]
},
"music.intro_storm": {
  "sounds": [{ "name": "eclipse:music/intro_storm", "stream": true }]
},
"music.victory_theme": {
  "sounds": [{ "name": "eclipse:music/victory_theme", "stream": true }]
},
"music.xbox_nostalgia": {
  "sounds": [{ "name": "eclipse:music/xbox_nostalgia", "stream": true }]
}
```

Do not add subtitles for MUSIC-category tracks.

## 3. `client/menu/EclipseTitleScreen.java` — credits entry

Add a normal `EclipseMenuButton` before Quit (and increment `y` afterward):

```java
addRenderableWidget(Button.builder(Component.translatable("gui.eclipse.credits.title"),
        button -> this.minecraft.setScreen(new CreditsScreen(this)))
        .bounds(x, y, BUTTON_WIDTH, BUTTON_HEIGHT)
        .build(EclipseMenuButton::new));
y += BUTTON_SPACING;
```

`CreditsScreen` is also reachable now through `/dev credits`; this menu line makes attribution
discoverable for non-operators as required by the Incompetech CC attribution guidance.

## 4. Sequence/event cue calls

The manager already detects these without foreign edits:

* `EclipseTitleScreen` present → `title_theme`
* Limbo dimension → `limbo_ambience`
* Herald/Ferryman translatable bossbars → matching boss track
* `ClientStateCache.stageAnimatingOverworld|Nether` → `expansion_theme`
* Xbox dimension → `xbox_nostalgia`; if P5-W9's `XboxMusicHook` is present, its reflective
  bridge also resolves `MusicCues.play(String, ServerPlayer)` / `stop(ServerPlayer)` and
  explicitly owns dimension entry/exit without another shared-file edit

Add the two one-shot cues at their authoritative server transitions:

```java
// FinaleRitual.beginVictory, immediately after AnnouncementService.announce(...):
for (ServerPlayer player : server.getPlayerList().getPlayers()) {
    dev.projecteclipse.eclipse.music.MusicPayloads.sendPlay(player, "victory_theme");
}
```

```java
// EclipsePayloads.handleCutscene (client handler):
if (payload.phase() == S2CCutscenePayload.Phase.TILT) {
    dev.projecteclipse.eclipse.music.MusicCues.play("intro_storm");
} else if (payload.phase() == S2CCutscenePayload.Phase.EMERGE) {
    dev.projecteclipse.eclipse.music.MusicCues.stop();
}
```

Optional explicit Xbox payload ownership when `XboxMusicHook` is not merged (the dimension
fallback already works):

```java
// XboxPayloads.handleTimer, after TimerClientState.update(payload):
if (payload.active()) {
    dev.projecteclipse.eclipse.music.MusicCues.play("xbox_nostalgia");
} else {
    dev.projecteclipse.eclipse.music.MusicCues.stop();
}
```

The static calls above run only in client payload handlers. Server-side code should use
`MusicPayloads.sendPlay/sendStop`.

## 5. Lang and generated docs

* Merge `docs/plans_v3/langdrop/WB-MUSIC.json` into both real language files.
* Start a dev client/server after all command workers merge and run `/dev docs export`;
  the `DevMusicCommands` static docs add `music.play`, `music.stop`, `music.list`, and
  `credits`. Commit the regenerated `docs/DEV_COMMANDS.md` only if byte-stable on a second run.

## 6. Credits consistency

`CREDITS.md` and `assets/eclipse/credits.json` intentionally enumerate the same eight tracks,
classic texture source, three tutorial-world sources/legal warning, and four currently bundled
libraries. Reconcile both if `docs/BUNDLING.md` changes the final nested-jar set.
