# Gooby animation guide

Runtime target: GeckoLib 4.9.x at 20 Minecraft ticks per second. Animation
times are seconds; keyframes are authored directly in
`assets/goobymod/animations/gooby.animation.json`.

## Controller ownership

| Controller | Priority | Bones / purpose |
|---|---:|---|
| `movement` | base | stable locomotion loops and deterministic pose bridges |
| `micro` | additive | eyes, eyelids, ears, nose, tail, wake-up stretch |
| `actions` | highest | pet, eat, wave, and landing squash |

Action requests are ignored while another action clip owns the controller.
This preserves complete keyframe arcs rather than cutting between gestures.

## v3.1 clips

| Clip | Length | Nominal frames at 20 FPS | Notes |
|---|---:|---:|---|
| `blink` | 0.20 s | 4 | eyelid planes cover compressed eye planes |
| `ear_twitch_l/r` | 0.35 s | 7 | asymmetrical three-beat twitch |
| `nose_wiggle` | 0.50 s | 10 | client-local sniff keyframe |
| `stretch_yawn` | 1.40 s | 28 | post-wake stretch + client-local yawn |
| `tail_wiggle` | 0.80 s | 16 | happy-only flavor candidate |
| `sit_down` | 0.40 s | 8 | idle/hop to sit bridge |
| `stand_up` | 0.35 s | 7 | sit to neutral bridge |
| `sleep_down` | 0.65 s | 13 | closes eyes and lowers head |
| `wake_up` | 0.65 s | 13 | sleep to neutral bridge |
| `land` | 0.35 s | 7 | squash, rebound, settle after drops over 2 blocks |

Blink is scheduled every 3–7 seconds and nose wiggle every 4–10 seconds while
not moving, sleeping, or digging. Ear/tail flavor runs every 5–12 seconds.
Timers are per rendered entity and allocate nothing in the tick hot path.

## Attachment contract

`hat_anchor` remains a direct child of `head`. Clips may animate `head` but
must not animate `hat_anchor` independently. Eyelids are also children of
`head`, ensuring face motion and hats remain coherent through all bridges.

Made by Sonic0810.
