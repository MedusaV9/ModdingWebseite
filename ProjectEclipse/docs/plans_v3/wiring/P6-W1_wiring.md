# P6-W1 wiring (GeckoLib foundation + Drift Lantern pilot)

Integrator-applied hub changes. Nothing else in P6-W1 needs wiring — attributes and
renderer registration are `@EventBusSubscriber`-annotated and guarded by
`DeferredHolder.isBound()`, so the build and both run configs stay green whether or not
this line has landed (before it lands, `eclipse:drift_lantern` simply does not exist and
the attribute listener logs one warning at boot).

## EclipseMod.java — constructor registrar block

Add alongside the existing `*.register(modEventBus);` lines:

```java
AmbientEntities.register(modEventBus);
```

import: `dev.projecteclipse.eclipse.entity.ambient.AmbientEntities`

## Not wiring, but integrator-visible notes

- `build.gradle` / `gradle.properties` / `src/main/templates/META-INF/neoforge.mods.toml`
  now carry the GeckoLib 4.9.2 lines (P6-W1 was the single sanctioned editor this wave,
  coordinating P5 per plan §4.5 — P5 must NO-OP its geckolib gradle/toml step and only
  keep its README server-pack mention).
- Langdrop: `docs/plans_v3/langdrop/P6-W1.json` (1 key en+de:
  `entity.eclipse.drift_lantern`).
- Sibling P6 workers: read `docs/plans_v3/handoff/P6_geckolib_conventions.md` before
  authoring models; extend the frozen bases in `entity/geo/` + `client/entity/geo/`.
