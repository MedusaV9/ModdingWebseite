# Gooby Mod addon API (5.x)

The package `de.sonic0810.goobymod.api` is source- and binary-stable within
the 5.x release line. Addons should compile against the public API and avoid
implementation fields in `GoobyEntity`.

## Read-only entity access

Treat a Gooby as `GoobyAccessor` to inspect owner, satisfaction, mood, command,
friendship tier, age/wild state, and copied wardrobe stacks.

## Lifecycle events

Listen on `NeoForge.EVENT_BUS` for:

- `GoobyTameEvent` after the first owner is assigned.
- `GoobyTierChangeEvent` after one player's friendship crosses a tier.
- `GoobyGiftEvent` after a gift is delivered, including recipient, copied
  stack, and whether it entered the satchel.

These events report completed state and are intentionally not cancellable.

## Hats and speech

Add hat item IDs to `#goobymod:gooby_hats` in a datapack. The same tag is
available as `GoobyApi.GOOBY_HATS`.

Register a localized speech pool during common setup:

```java
GoobyApi.registerSpeechPool(
    ResourceLocation.fromNamespaceAndPath("myaddon", "campfire"),
    List.of(
        "bubble.myaddon.campfire1",
        "bubble.myaddon.campfire2",
        "bubble.myaddon.campfire3",
        "bubble.myaddon.campfire4"));
```

Provide every key in each language supported by the addon. Pool identifiers
must be unique, keys must be nonblank, and registration is fail-fast.

## Stable sound events

Every Gooby sound event under `goobymod:entity.gooby.*` is declared in
`assets/goobymod/sounds.json` and registered 1:1 (game-test enforced), so
addons can resolve them via `BuiltInRegistries.SOUND_EVENT` and play them
like any vanilla event. Subtitles ship for `en_us` and `de_de`.

`goobymod:entity.gooby.ambient` is a **stable, addon-facing fallback**: the
mod itself voices ambience through the mood pools (`ambient_neutral`,
`ambient_happy`, `ambient_sleepy`), while the generic event stays registered
and aliases the neutral pool. Addons that want a mood-agnostic Gooby chirp
can play it without tracking mood state; it will not be removed within the
5.x line. See `docs/AUDIO.md` for the full pool/variant policy.

Made by Sonic0810.
