# Gooby Player Manual EN · v5.2.0 “Companion Deluxe”

For **Minecraft 1.21.1**, NeoForge **21.1.248**, and GeckoLib 4.9.x.

## New in v5.2.0

- **Fetch:** Throw the new Gooby Ball (slime ball + string + Gooby Fluff,
  makes two) — your adult Gooby returns exactly your ball, losslessly across
  chunk and server reloads.
- **Six tricks:** Roll and Dance join Spin, High Five, Flop, and Speak. The
  sneak air-whistle now opens a real selection screen; selecting works up to
  64 blocks away.
- **Explorer outfit:** Flower Crown (head), dyeable Adventure Bandana
  (neck), and Picnic Backpack (back) — the complete set grants “Ready for
  Adventure”.
- **Companion HUD & effects:** compact companion card, cuddle vignette,
  alarm pulse, and gentle camera shake, all adjustable in the new config
  screen (mod list → Config).
- **Decor & snacks:** Nutella Toast (speed boost), Button Eye, squeezable
  Gooby Plushie (cushions landings like Gooby Wool), and the nightly
  sparkling Gooby Statue (“Set in Stone”).
- **World:** Gooby burrows now have tunnels, dens, and a pantry; rare Gooby
  picnics await in plains, meadows, flower forests, and cherry groves.
- **Motion & looks:** real walk/run gaits for adults and babies; all five
  coats repainted as premium textures.
- **Voice:** 91 audio clips — virtually every noise now has three variants.

## Fetch with the Gooby Ball

1. Craft Gooby Balls shapelessly from a slime ball, string, and Gooby Fluff
   (makes two).
2. Throw a ball with right-click. Only your own adult Gooby recognizes your
   throw and dashes after it.
3. Gooby picks up exactly one ball and brings it back to you; the return
   trip resumes even after a chunk change or server restart.
4. The first successful return grants “Fetch!”.

If a ball is unreachable (hole, fence), Gooby gives up after a short while
and temporarily avoids that specific ball instead of pathfinding against it
forever. Picked-up balls are ordinary throwable items again. Stay, alarm,
and family behavior still take priority over play.

## Explorer outfit

Three matching accessories for your adult Gooby's server-authoritative
wardrobe path:

| Accessory | Slot | Recipe |
|---|---|---|
| Flower Crown | head | 3× small flower over string–fluff–string |
| Adventure Bandana | neck | wool–string–wool over Gooby Fluff |
| Picnic Backpack | back | leather frame around Gooby Wool + Button Eye |

The bandana can be dyed in crafting or directly on the worn Gooby with all
16 vanilla dyes. Shears still remove the complete outfit at once; swapping
in a different accessory safely drops the old piece. The full three-piece
set grants “Ready for Adventure”.

## Companion HUD, effects & config screen

The companion card in the top-left shows the name, mood, whistle command,
plus health and satisfaction bars of your nearest own Gooby. It only uses
already-synchronized data, fades out after brief inactivity, and hides
behind menus, the debug overlay, and F1.

Cuddling shows a warm vignette; a real alarm subtly pulses at the screen
edge and adds a minimal camera shake. Reduced motion automatically disables
the pulse and shake as well.

The config screen (mod list → Config) gathers every client option: sliders
and toggles edit a draft, **Done** saves everything at once, **Cancel**/Esc
discards (with a confirmation when changes are unsaved). A live preview on
the right shows the companion card including GUI-scale-dependent position
clamping.

## Picnic blankets & expanded burrows

Gooby burrows are small cave systems: tunnels, dens, and a pantry with its
own chest (carrots, wheat, fluff, Nutella, button eyes, rarely a golden
carrot) attach to the grassy mound. The resident stays persistent and
treats the den as home.

Very rarely you will find a **Gooby Picnic** in plains, sunflower plains,
flower forests, meadows, and cherry groves: a laid-out blanket with treats
like Nutella Toast, cake, and cookies — sometimes even a plushie, a bowtie,
or a flower crown.

## New in v5.1.0

- Every click gets an answer: denials (snuggle, wardrobe, dyeing, shears,
  coats, satchel) are now audible, and brush plus Sniff & Seek cooldowns show
  their remaining time on the action bar.
- Pet click-spam no longer triggers trick refusals — a double click only
  becomes a trick request when your adult Gooby actually knows the trick.
- Offhand care works: an empty main hand plus Nutella, brush, or treat in the
  other hand now uses the item.
- Shy wild Goobys no longer beg for pets while fleeing. After being woken,
  Gooby gets up immediately instead of freezing.
- Riding without a Jar of Nutella shows a steering hint. Spin, High Five, and
  trick selection have their own sounds.
- The baby model is textured without holes; `baby_hop` and the greeting
  animation loop seamlessly.

## New in v5.0.2

- Long-running servers retain only bounded session, emote, and partner history
  per Gooby. Logout releases player-session state immediately while persistent
  friendship remains.
- Social behavior remains lowest priority, but its normal AI path can now
  choose either a greeting or the bounded play chase. Commands, danger, sleep,
  and family behavior still win.
- All twelve ordinary crafting recipes appear in the recipe book when their
  relevant material is found. Usage hints on Nutella, the brush, Training
  Treat, Shimmer Fluff, and treasure map point to the next gameplay step.
- Bubble, outfit, and hutch-name strings have packet-safe entity/block-entity
  sync limits. The crowd-sound limiter starts clean for each server session.

## New in v5.0.0

- Handbook 2.0 opens as an eight-chapter illustrated screen with an animated
  cover portrait, direct chapter tabs, localized navigation, and the complete
  care-to-treasure journey. A 16-page written-book payload remains available
  to tooling and external readers.
- Local client options `accessibility.reducedMotion` and
  `accessibility.highContrastBubbles` stop cosmetic motion and strengthen
  bubble contrast without changing server gameplay. Whistle modes now include
  distinct visible icons in the actionbar; every sound remains subtitled.
- Micro-animations and cosmetic paw accents suspend outside 24 blocks or while
  not rendered. Periodic ambience coalesces per chunk. Relationship storage is
  bounded to the 32 most recently used non-owner entries while always keeping
  the owner; old visitor scores may be forgotten after the cap.
- Addons receive a stable 5.x `GoobyAccessor`, tame/tier/gift events, the
  public hat tag, and a validated localized speech-pool registration hook.
  See [`docs/ADDON_API.md`](../ADDON_API.md).
- Every built-in speech pool now has at least four idiomatic lines. Twelve
  handbook illustrations and the reproducible
  [`docs/demo_world`](../demo_world/README.md) showcase blueprint complete the
  presentation pass.

## Accessibility and performance

Client accessibility lives in `config/goobymod-client.toml`. Reduced Motion
disables only micro-animation and bubble pop/tail motion; gameplay actions,
state, and timing stay intact. High Contrast uses an opaque cream panel and
dark text. Both default to `false`.

The 24-block cosmetic LOD does not suspend movement, AI, needs, saving, or
commands. The sound limiter coalesces only periodic crowd ambience per
dimension/chunk/sound; interaction feedback remains immediate.

## New in v4.3.0

- Equip the Tiny Satchel, then use another satchel on your own adult Gooby to
  open four storage slots. The inventory is owner-only, survives reload, and
  spills safely if the satchel is removed or Gooby is forcibly killed.
- At Friend tier, sneak-show a carrot, potato, beetroot seed, or block while a
  Training Treat is in the other hand. Gooby searches one bounded 24-block
  underground area, sends a paw trail, and marks a matching find.
- The five-minute cooldown also applies when nothing is found. The consolation
  bubble is intentional feedback, not a silent failure. Ores require
  `seek.allowOres=true`; cozy targets work by default.
- Distant dug gifts enter the satchel atomically. A world drop reserves pickup
  for its intended friend for ten seconds.
- Best Friends have a rare 5% chance to dig a Torn Map Scrap. Four scraps craft
  a Gooby Treasure Map; unfold it to locate a generated treasure cache.

## Treasure hunting

1. Raise Gooby to Friend and equip a Tiny Satchel.
2. Hold the item to seek in the interaction hand and a Training Treat in the
   other. Sneak-use Gooby. A sniff and paw trail confirm a found target.
3. Follow Gooby to the dig marker. If there is no target, enjoy the consolation
   line and wait for the configured cooldown.
4. Continue caring for a Best Friend and collect four rare map scraps. Craft
   them in a 2×2 square, then use the restored map to reveal a red X.

The cache is a rare jigsaw structure with cosmetic accessories, Shimmer Fluff,
Gooby Fluff, and Nutella. “X Marks the Floof” rewards the restored map;
“Packed With Care” rewards all four satchel slots being occupied.

## New in v4.2.0

- Nearby Goobys perform a synchronized greeting, bounded play chase, cosmetic
  gift exchange, and huddled nap. Every social movement is lower priority than
  Stay, Follow, sleep, shelter, family, and danger behavior.
- A play chase ends after 30 seconds and the same pair waits five minutes.
  Disable it with `social.playChase=false`.
- Deliberate player emotes receive answers: press sneak twice within one second
  while looking at your Gooby for a bow, or jump three times near a Happy Gooby
  for a shared bounce. `social.emoteReactions` is the server switch.
- Three sleepers within three blocks form a group nap and grant “Fluff Pile”.
  Their individual Zzz particles merge into one larger huddle marker.
- Speech bubbles now stagger by entity, pop gently in and out, point toward a
  nearby addressed player, and support heart, Nutella, sleep, and alarm glyphs.

## Goobys among themselves

Social play never changes a command. A Stay Gooby remains exactly where it was
placed, and a Follow Gooby still prioritizes its owner. Greeting partners mirror
the same two-stage bounce; play-chase always has a hard 600-tick stop and a
per-pair cooldown. Named Goobys can appear by name in social bubbles.

For the bow emote, face your Gooby and make two distinct sneak presses within
20 ticks. Ordinary crouching does not repeat the reaction. The jump response
requires a Happy mood and three separate jumps within 40 ticks.

## New in v4.1.0

- Rare wild Goobys now spawn singly in flower forests, cherry groves, and
  meadows. `worldgen.wildSpawns` can disable natural spawns without affecting
  burrows or player-created companions.
- Wild Goobys flee unfamiliar players until their first Nutella feed. They
  peek shyly, leave temporary paw particles on sand and snow, and call over
  32 blocks so careful explorers can find them.
- Grass-covered Gooby burrows contain a persistent resident and a starter
  cache with one Nutella jar, carrots, and fluff. Discovery grants
  “Who Lives Here?”.
- Digging leaves a non-colliding dirt mark that decays after two minutes.
  Rabbits follow wild Goobys, cats stare, and untamed wolves trigger alarms.
- Only naturally spawned, unnamed wild Goobys despawn normally. Tamed,
  converted, spawn-egg, and burrow Goobys remain persistent.

## Wild Goobys & burrows

Listen for the distant two-note wild call in a meadow, cherry grove, or flower
forest. Approach slowly: a newly found Gooby keeps ten blocks away until
offered Nutella. A burrow looks like a low grassy mound with a south-facing
tunnel. Its resident treats the chamber as home and never despawns; the chest
inside provides the first jar needed to earn trust.

Natural spawning is deliberately very rare (weight 1, groups of one). Server
owners can set `worldgen.wildSpawns=false`; generated burrows and existing
Goobys are untouched.

## New in v4.0.0

- Create 6.0.10 is a compile-visible but optional integration. Without Create,
  Gooby Mod keeps all compatibility features dormant and classloads normally.
  With Create, typed seat, contraption, and kinetic APIs replace class-name
  guesses; a verified reflection seat fallback protects against API drift.
- A Gooby seated before a mechanical-bearing, gantry, or train contraption is
  assembled transfers onto the moving contraption and remains a passenger.
  Relaxed sway and train-lean clips follow the motion. On arrival Gooby shares
  one of six bubbles.
- An air-whistle never yanks Gooby off a moving contraption. Gooby politely
  answers that it is riding the train and stays seated.
- A Stay-mode Gooby within five blocks of a running, non-overstressed kinetic
  machine gains one satisfaction every 30 seconds and uses six machinery lines.
- Empty Gooby Jars craft from three glass panes. Create adds two conditional
  production routes while the original hand recipe remains unchanged.
- Create failures are classified: API/linkage mismatches permanently disable
  only integration; transient runtime failures receive three non-blocking
  retries with 1/2/4-tick backoff.

## Create Express

Both processing recipes exist only when Create is loaded:

```text
Mechanical Mixer
250 mB milk + cocoa beans ×3 + sugar
                         │
                         ▼
                   Jar of Nutella

Spout
250 mB Create chocolate
           │
           ▼
    Empty Gooby Jar ──► Jar of Nutella
```

The mixer is the bulk path and does not replace the shapeless milk-bucket
recipe. The Spout consumes one Empty Gooby Jar and 250 mB chocolate. Craft two
empty jars from three glass panes in a V shape.

Shift-use your own adult Gooby beside a free Create seat before assembling a
contraption. Create performs the passenger transfer during assembly and returns
Gooby on disassembly. Startup logs include one concise Create version and
integration-level diagnostic for bug reports.

## New in v3.9.0

- Gooby now has persistent, synchronized head, neck, and back slots. Tagged
  hats, a dyeable Gooby Scarf or Bowtie, and the Tiny Satchel remain visible
  to observers and survive reloads.
- Every small flower and all 16 wool carpets are hats through
  `#goobymod:gooby_hats`. Datapacks can extend that tag.
- Craft a scarf from three wool and Gooby Fluff. Vanilla armor dyeing supports
  all 16 colors; using dye on a worn scarf also makes a matching particle puff.
- At Best Friend, brushing has a 5% chance to drop Shimmer Fluff. Use four on
  your own adult Gooby to permanently unlock the next cream, cocoa, or spotted
  coat. Sneak-use the brush to cycle every unlocked coat.
- Shears return all equipped accessories at once. A complete three-slot outfit
  grants “Dressed to the Nines.”
- With Curios 9.5.1+ installed, the Gooby Whistle is accepted in a Charm slot.
  Curios remains optional and absent installations load without compatibility
  classes or log noise.

## Gooby's wardrobe

| Slot | Choices |
|---|---|
| Head | every item in `#goobymod:gooby_hats` |
| Neck | dyeable Gooby Scarf or Gooby Bowtie |
| Back | Tiny Satchel (four owner-only storage slots) |

The Shift-look status line shows compact wardrobe glyphs and the active coat.
Scarves and satchels use 3D attachment models on animated body anchors, so they
inherit hopping and sleeping motion rather than floating in world space.

## New in v3.8.0

- Use a Jar of Nutella on a placed vanilla Cake to prepare a **Nutella Cake**.
  It remains in the world until an eligible family is close enough.
- The ritual needs two adult, tamed Goobys. Each must have at least
  **Friend (50)** friendship with their own owner; the owners may differ.
- One successful ritual creates exactly one tamed baby. The same pair can
  welcome at most one baby per Minecraft day, even across reloads or
  replacement cakes.
- Babies use a dedicated big-headed, short-eared model at 55% scale, follow
  either persisted parent, play short tag bursts, and sleep around their
  family nest.
- Babies cannot ride, use Create seats, wear hats, perform tricks, or answer
  whistles. They grow up after 36,000 ticks (1.5 days); Training Treats shorten
  the remaining growth time.

## Offspring

1. Raise two tamed adult Goobys to Friend with their respective owners.
2. Place a Cake on solid ground with both Goobys within six blocks.
3. Use one Jar of Nutella on the cake. Hearts, nuzzles, and a baby confirm the
   successful ritual. If the requirements are not met, the prepared cake waits.
4. Let the baby follow its parents. Its age, both parent UUIDs, family nest, and
   pair cooldown are save-safe.

Baby squeaks are a separately rendered three-sound set, not only pitch-shifted
adult audio. A rare tumble has a hard one-minute cooldown. Training Treats used
by the baby's owner accelerate growth instead of opening trick training.

## New in v3.7.0

- The rabbit hutch now has an open entrance, visible interior, and three
  bedding levels. Right-click it with one wool block per level.
- Name a name tag on an anvil and use it on the hutch while an owned Gooby is
  within 16 blocks. The tag names and explicitly binds that Gooby to this home.
- Bound Goobys travel home from up to 96 blocks at dusk, use a tight interior
  sleep curl, and send Zzz through the doorway. A farther Gooby sleeps rough
  for that night without forgetting its hutch.
- Comfort levels 1–3 restore 15/20/25 satisfaction at dawn. Comfort 3 also has
  a chance to produce one morning gift per day.
- At dawn Gooby hops out, stretches, yawns, trills, and heads toward an online
  owner. Breaking an occupied hutch safely ejects its resident and returns
  every installed wool layer.

## A home for Gooby

1. Craft the hutch from eight planks around a hay bale and keep its doorway
   unobstructed.
2. Add one to three bedding levels by right-clicking with wool. The current
   warm comfort overlays normalize the color; breaking returns white wool.
3. Name a name tag exactly as Gooby should be named. Use it on the hutch: the
   nearest Gooby you own is named and bound.
4. Keep the dusk route open. A bound hutch beats every closer free hutch;
   `home.duskTravelRadius` controls the maximum journey.

An occupied hutch emits Zzz at its entrance. The nameplate survives save and
reload. If the hutch is broken during sleep, Gooby wakes outside its collision
area, forgets only that home, and remains unharmed.

## New in v3.6.0

- `Gooby Fluff + Sugar + Cocoa Beans` crafts three Training Treats. Sneak-use
  one on Gooby to cycle the training focus; normal use trains it. Three
  successful sessions earn all three stars.
- Request a trained trick with a quick empty-hand double-use: **Spin**,
  **High Five**, **Flop**, or **Speak**.
- Use the whistle in air to call the nearest owned Gooby. Beyond 32 blocks it
  pops to you through the existing safe-teleport checks. Sneak-air-use opens a
  clickable trick selector in chat.
- The in-game Gooby Handbook is granted once after first taming (configurable)
  and is also craftable from a Book plus Gooby Fluff.

## Training tricks

Since v5.2.0 Gooby knows six tricks: **Spin**, **High Five**, **Flop**,
**Speak**, **Roll**, and **Dance**.

1. Sneak-use a Training Treat until the desired trick appears, or select it
   on the selection screen.
2. Use the treat normally. Gooby needs a two-second breather after each
   successful round; only successful rounds consume a treat.
3. One star unlocks performance and three stars master the trick. Shift-look
   inspection shows the selected trick and its stars.
4. Double-use Gooby with an empty hand. **Speak** guarantees a voice and speech
   bubble; **Flop** ends with a soft plush landing. The **Roll** somersaults
   around the body center while staying completely above the ground; the
   **Dance** bounces with swinging ears and musical notes.

The sneak air-whistle opens the native selection screen: cards for all six
tricks with stars and status, usable via mouse, keyboard, and narrator.
**Done** confirms, **Cancel**/Esc discards — “Active” always reflects only
the truly saved state. Locked cards are visible but not selectable; their
tooltip explains the training path. Opening the menu and selecting work up
to **64 blocks** away; clients without the payload channel keep the
clickable chat menu.

The whistle remembers its most recent Wander/Follow/Stay mode in its tooltip.
Foreign and wild Goobys answer with a clearly lower denial cue.

## New in v3.5.0

- The existing friendship value derives four tiers without save migration.
  Tier-ups celebrate with a bounce, jingle, hearts, bubble, and actionbar.
- First feed, first pet, and tier-ups are stored as UUID-bound memories. After
  seven in-game days, Gooby recalls one with a special bubble.
- A custom-named Gooby perks its ears and looks at its owner when the owner
  says its name in chat (`bonding.nameRecognition`).
- Best Friends can sneak-right-click once per in-game day to snuggle: a long
  purr, golden hearts, and Regeneration I for ten seconds.

## Friendship tiers

| Tier | Value | Unlocks |
|---|---:|---|
| Stranger | 0–19 | meet, feed, and pet |
| Buddy | 20–49 | personal greeting and wave |
| Friend | 50–89 | gifts, riding, and brief tag-along when sprinting past |
| Best Friend | 90–100 | golden gifts and daily snuggle |

The old ride threshold of 30 is now unified: non-owners require **Friend (50)**.
The owner may still ride their own tamed Gooby regardless of personal value.
Progress appears only at tier crossings and crossed multiples of five, not
after every click.

## New in v3.4.0

- Hostiles within 12 blocks trigger Scared mood, upright ears, and a distinct
  alarm. When its owner is nearby, Gooby warns from a position between owner
  and threat; it never attacks.
- Gooby detects creepers four blocks earlier and calls more loudly. Short
  hysteresis prevents alarms flickering at the detection edge.
- Wild Goobys flee after damage. Fire, cactus, and powder snow carry high or
  impassable path costs.
- Rain sends Gooby to a roof or hutch. In thunder it hides behind its owner;
  once dry, it shakes water droplets from its fur.
- At midday Gooby strolls and digs more; in the evening it sits more often.

## Gooby watches your back

The sharp double alarm means Gooby has spotted a hostile. Its gaze and upright
ears point toward danger. A lower, louder call marks a creeper. This is a
warning, not an attack: Gooby is not a fighter, so move both of you to safety.
Follow teleports reject lava, fire, cactus, powder snow, world borders, and
unsafe build heights.

## New in v3.3.0

- Gooby synchronizes **Happy, Content, Hungry, Sleepy, Lonely,** or **Scared**.
  Each state dwells for at least 30 seconds to prevent flicker.
- Hunger follows the last feeding; loneliness builds during a long owner
  absence. Sleeping pauses satisfaction loss.
- Feeding a hungry Gooby grants +2 bonus friendship. Petting while lonely
  grants double satisfaction.
- Hold Shift and look at your own Gooby for one second to show
  `❤ satisfaction · mood · 🎁 charges` in the actionbar.
- Nutella thought particles, begging, drooped ears, happy bounce, hungry
  whines, and lonely sighs make needs readable without UI.

## Reading needs

Hungry Goobys beg when they can see held Nutella and talk about snacks. Lonely
Goobys droop their ears and especially appreciate petting. Sleepy Goobys do not
request pets at night and lose no satisfaction while asleep. The compact Shift
inspection is a confirmation, not the only way to read the creature.

## New in v3.2.0

- Every core Gooby sound now has two or three variants with subtle volume and
  pitch variation. Squeaks, purrs, boings, plops, munches, and snores no longer
  sound mechanically identical.
- Gooby's voice matches the situation: happy trills at high satisfaction,
  neutral daytime mumbles, and sleepy murmurs at night or very low
  satisfaction.
- Only the player doing the petting hears a soft fading purr loop; bystanders
  retain the short positional feedback.
- Wander, Follow, and Stay have clearly different whistle pitches. Brushing
  has its own soft fabric sound.
- `audio.goobyVolumeScale` controls every Gooby creature sound from 0.0–2.0.

## Reading Gooby's sounds

| Sound | Meaning |
|---|---|
| rising trill | Gooby is highly satisfied |
| gentle mumble | neutral, relaxed daytime mood |
| low sleepy murmur | night or very low satisfaction |
| low whistle | Wander |
| rising mid whistle | Follow |
| steady high whistle | Stay |
| long quiet purr | you are currently petting Gooby |
| soft brushing | grooming was accepted |

Every event has dedicated DE+EN subtitles. Sleeping Goobys play no normal
ambient event; their 90-tick positional snore remains softly attenuated.

## New in v3.1.0

- Gooby blinks every 3–7 seconds, wiggles its nose every 4–10 seconds, and
  performs randomized ear twitches. Happy Goobys can also wag their tails.
- After waking, Gooby stretches and audibly yawns. Animation keyframes play
  these sounds locally without server network traffic.
- Sitting down, standing up, falling asleep, and waking use dedicated bridge
  clips. A state machine lets each transition finish.
- A fall of more than two blocks ends with squash-and-stretch and a small
  cloud puff. Gooby still takes no fall damage.
- Closed eyelid planes make blinking and sleep clearly readable.
- Head tracking is eased. Speech bubbles no longer render through walls or on
  invisible Goobys.

## Reading Gooby's body language

| Motion | Meaning |
|---|---|
| quick blink | calm, attentive Gooby |
| alternating ear twitch | noticed a sound or movement |
| wiggling nose | comfortably exploring the surroundings |
| fast tail wag | high satisfaction |
| stretch and yawn | just woke up |
| soft landing squash | safe drop of more than two blocks |
| lowered ears | sad or startled state |

Micro motion has its own animation layer, so hopping remains active even when
a blink was due. Petting, eating, waving, and landing have priority and never
get cut off halfway through their clip.

## New in v3.0.0

- **Guardian Angel:** tamed Goobys lose no health to attacks from mobs. Several
  heavy hits cause panic; at 30% remaining protection pressure they flee to
  their owner. If the owner is not in the same dimension, their remembered
  rabbit hutch is the safe fallback.
- The owner receives a chat message when a Gooby has to escape.
- Servers can disable mob protection and escape separately in the config.
- The rabbit hutch now has a real open interior anchor. Gooby walks inside
  instead of sleeping beside a solid wall.
- Hats use a dedicated anchor attached to the animated head and follow sleep,
  eating, and petting poses.
- A dedicated sad whimper replaces the cheerful death squeak.
- Nutella jars keep the called Gooby's UUID lease for 15 minutes. Chunk
  unloads can no longer cause a duplicate spawn.

## Getting a Gooby

### Transform a wild rabbit

1. Shapelessly craft a jar of Nutella from three cocoa beans, one milk bucket,
   and sugar. The empty bucket is returned.
2. Right-click a wild rabbit with the jar.
3. The transformed Gooby is immediately tamed, belongs to you, and starts at
   40 friendship.

### Place a jar of Nutella

Place the jar on a grass block. At night it may call a wild Gooby from 5–8
blocks away. The jar reserves exactly that Gooby even while its chunk is
unloaded. Feed the wild Gooby another jar to tame it.

## Taming, friendship, and satisfaction

- **Feed Nutella:** tames a wild Gooby and grants +8 friendship, +30
  satisfaction, and one gift charge.
- **Pet:** right-click with an empty main hand; +15 satisfaction and +2
  friendship. Friendship can increase once per player every five seconds.
- Friendship is persisted separately for every player from 0–100.
- At 60 satisfaction, Gooby sparkles and hops faster.
- Player attacks are harmless. Satisfaction loss is now also limited to once
  per player every five seconds.

## Whistle and commands

Shapelessly craft the Gooby Whistle from two gold nuggets, string, and Gooby
Fluff. Only the owner can cycle its command:

1. **Wander:** Gooby explores freely.
2. **Follow:** Gooby follows its owner and teleports after falling far behind.
3. **Stay:** Gooby sits and guards the commanded position.

## Gifts

Each fed jar stores one gift charge (default maximum 3). While digging, Gooby
can spend exactly one charge for a nearby player with at least 50 friendship.
The default cooldown is five minutes. At 90 friendship, the gift may be a
golden carrot.

## Wardrobe safety

The owner equips any tagged hat, a neck accessory, and a back accessory.
All three slots are synchronized and survive restarts. Shears return the
complete outfit in one action. If `/kill`, the void, or disabled protection
still kills a Gooby, every equipped accessory safely drops as an item.

## Riding and Create

Shift-right-click with an empty hand to mount a tamed Gooby as its owner.
Other players need the Friend tier (50). Hold Nutella to steer. Joy hops now roll on
the server only, so the rider no longer hears doubled squeaks. With a
compatible Create 6.x installation, the owner can place Gooby on a free Create
seat; normal riding remains available without Create.

## Rabbit hutch and sleep

Craft the rabbit hutch from eight planks around a hay bale. Without a
nameplate, Gooby can still use a nearby free hutch. An anvil-named tag
permanently binds hutch and resident, and that binding has priority during the
night search. The route runs through the open doorway to the interior anchor.

Wool raises comfort through levels 1–3. Dawn restores 15/20/25 satisfaction;
at level 3, one small gift may appear per Minecraft day. The exit hop,
stretch, yawn, and trill sequence follows. Petting or feeding wakes Gooby and
prevents immediate resleeping for 30 seconds. Breaking returns bedding and
safely ejects a sleeping resident.

## Brush, fluff, and Gooby wool

A brush made from wool and a stick produces Gooby Fluff; Best Friends have a
5% chance to shed Shimmer Fluff instead. Four normal fluff craft a Gooby Wool
block that completely cancels fall damage. Four shimmer fluff used on an
owned adult Gooby unlock the next permanent coat.

## Server config

File: `serverconfig/goobymod-server.toml`

| Key | Default | Effect |
|---|---:|---|
| `protection.goobyMobProtection` | `true` | block mob damage to tamed Goobys |
| `protection.escapeToOwner` | `true` | flee to owner or hutch under pressure |
| `specialLines.enableSpecialLines` | `true` | cosmetic name-bound lines |
| `specialLines.specialLineChance` | `0.65` | chance for a matching special line |
| `bubbles.bubbleDistance` | `40` | speech-bubble render distance |
| `bubbles.idleLineMinTicks` | `2400` | minimum idle-line interval |
| `bubbles.idleLineMaxTicks` | `4800` | maximum idle-line interval |
| `gifts.giftCooldownTicks` | `6000` | gift cooldown |
| `gifts.maxGiftCharges` | `3` | stored gift charges |
| `audio.goobyVolumeScale` | `1.0` | master scale for all Gooby sounds (0.0–2.0) |
| `needs.hungerHours` | `1.5` | time until hungry (1.5 Minecraft days) |
| `needs.lonelyMinutes` | `10.0` | owner absence until lonely (minutes) |
| `awareness.creeperAlarm` | `true` | earlier and louder creeper warning |
| `awareness.alertRadius` | `12.0` | normal hostile detection range in blocks |
| `bonding.nameRecognition` | `true` | owned named Gooby reacts to its name in chat |
| `bonding.giveHandbookOnTame` | `true` | gives each player one in-game handbook after first taming |
| `home.duskTravelRadius` | `96` | maximum dusk journey to an explicitly bound hutch |
| `family.growthTicks` | `36000` | ticks before a baby Gooby grows up |
| `family.ritualCooldown` | `24000` | minimum ticks between babies from the same pair |
| `worldgen.wildSpawns` | `true` | allow rare natural wild Gooby spawns |
| `social.playChase` | `true` | allow bounded low-priority Gooby play chases |
| `social.emoteReactions` | `true` | allow deliberate bow and happy-jump reactions |
| `seek.allowOres` | `false` | allow shown ore blocks as Sniff & Seek targets |
| `seek.cooldown` | `6000` | ticks between seek scans, successful or empty |

## Client config

File: `config/goobymod-client.toml` — every value can also be adjusted on
the in-game config screen (mod list → Config).

| Key | Default | Effect |
|---|---:|---|
| `accessibility.reducedMotion` | `false` | stop cosmetic micro-animation and bubble motion |
| `accessibility.highContrastBubbles` | `false` | use opaque cream bubbles and darker text |
| `companionHud.showCompanionHud` | `true` | companion card for your nearest own Gooby |
| `companionHud.companionHudOffsetX` | `4` | horizontal card position in GUI pixels |
| `companionHud.companionHudOffsetY` | `4` | vertical card position in GUI pixels |
| `screenFx.screenEffects` | `true` | cuddle vignette and subtle alarm pulse |
| `screenFx.cameraShake` | `true` | gentle camera shake on a real alarm |

## Troubleshooting

First verify Minecraft 1.21.1, NeoForge 21.1.248, and GeckoLib 4.9.x. A useful
bug report includes the log, Gooby name, command mode, and relevant config.
Every player-facing string is available in both English and German.

---

Made with ❤ (and a great deal of Nutella) by Sonic0810 · **made by Sonic0810**
