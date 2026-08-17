# SoooDreamy 5.2.0 — Performance & Reliability

- Offline outbox for chat, reactions, daily answers, quest checks, and ratings with stable idempotency ids.
- Lossless startup migration from `store.json` to atomic couple segments; storage/media quota in `/api/health`.
- Exponential jittered WebSocket backoff instead of a reconnect storm.
- Cold-start signposts to the dashboard and pixel-bounded decoding for large images.

Honestly: media uploads still need an active connection and startup time depends
on the device. The IPA is unsigned.

SoooDreamy — made by Sonic0810.
