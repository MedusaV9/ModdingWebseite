# 5.2.0 performance and reliability rubric

Touched surfaces: offline writes, app startup, authenticated media, WebSocket lifecycle, server persistence/health.

| Dimension | Score | Evidence |
|---|---:|---|
| R1 visual consistency | 9 | no visual token changes; optimistic state uses existing components |
| R2 motion | 9 | no new motion; startup work is instrumented |
| R3 haptics & sound | 9 | success feedback remains server-acknowledged |
| R4 state completeness | 10 | queued, attempting, acknowledged, retry and malformed-operation paths |
| R5 DE+EN | 10 | What's New, patchnotes, manuals and operational guidance bilingual |
| R6 accessibility | 9 | no semantic regressions; memory bounds protect assistive layouts |
| R7 performance | 10 | segmented writes, bounded image decoding, startup signposts |
| R8 resilience | 10 | stable ids, FIFO replay, lossless migration and jittered reconnect |
| R9 honesty | 10 | media and device-dependent timing limits stated explicitly |
| R10 coherence | 9 | health API, app outbox, docs and release discovery wired together |
