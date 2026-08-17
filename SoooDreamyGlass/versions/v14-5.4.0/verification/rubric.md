# 5.4.0 full-app polish rubric

| Dimension | Score | Evidence |
|---|---:|---|
| R1 visual consistency | 9 | Theme/palette tokens drive app, chat, widgets, games, and rituals. |
| R2 motion | 9 | Executable timing budget is 150–450 ms; reduced-motion paths remain static. |
| R3 haptics & sound | 9 | Existing bounded engines and quiet behavior are reused; no new feedback source. |
| R4 state completeness | 10 | Twelve surfaces × five states are inventoried and enforced as pure logic. |
| R5 DE+EN | 10 | Table parity, literal-key scan, plain-Text scan, and fixed invite/settings copy. |
| R6 accessibility | 9 | 44-point controls, semantic styles, non-color status, and reduced effects remain gated. |
| R7 performance | 9 | Bounded images, reconnect backoff, segmented storage, and compact state policy. |
| R8 resilience | 10 | Outbox scoping, cached-content error states, retry, and restart suites remain green. |
| R9 honesty | 10 | Unsigned/device-only limits and stale/offline states are explicit. |
| R10 coherence | 9 | What’s New, API, manuals, release evidence, widgets, and event paths are audited. |

Gate: PASS — no category below 8; average 9.4.
