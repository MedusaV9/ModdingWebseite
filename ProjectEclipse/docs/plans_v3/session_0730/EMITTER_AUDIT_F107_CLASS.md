# F-107-Klasse — Vollaudit aller Quasar-Emitter (Session 0730, Follow-up)

Anschluss an `F107_UMBRAL_QUAD_REPORT.md` (Teil 3) und `F107_RADICAL_REMOVAL_REPORT.md`
(Teil 4). Nachdem die Limbo-Producer der „harten lila Wände/Kapseln/Plus-Cluster"
ausgerottet waren, hatte Teil 2/3 `storm_godfinger` als Follow-up-Kandidaten derselben
Klasse notiert. Dieser Report ist der versprochene **Voll-Audit aller 100 Emitter** unter
`assets/eclipse/quasar/emitters/` gegen die vier F-107-Zutaten:

1. **Ungedämpfter `veil:wind`** — Veil 4.3.0 behandelt wind als per-Tick-Beschleunigung
   ohne Dämpfung (JSON-`strength` wird ignoriert, Teil-2-Bytecode-Beweis). Drift =
   a·N(N+1)/2, Endgeschwindigkeit a·N.
2. **Kleine Texturen (8×8 Haus-Wisps) auf großen Quads** — Nearest-Sampling
   (blur=false) macht jedes Texel zum harten Rechteck; die Plus-Alpha-Maske der Wisps
   IST das gemeldete Kreuz. **Neubefund dieses Audits:** `purple_wisp.png` und
   `wisp_white.png` haben **Rand-Alpha 26/255 (nicht 0)** — auf großen Quads zeichnet
   damit die Quad-Kante SELBST als hartes Rechteck.
3. **Additiv + hoher Alpha-Peak auf großen Quads** — quantisiert auf llvmpipe
   (8-bit-Target + Display-Gamma) zu harten Iso-Alpha-Konturen („Pille"/„Wand").
4. **Spawn-Shapes ohne Kamera-Clearance.**

**Offender-Kriterien des Auftrags:** (ungedämpfter Wind ≥ 0.005) ODER (Quad-Radius ≥ 4
mit ≤ 16-px-Textur) ODER (additiv + α-Peak ≥ 0.15 + Quad ≥ 3) ODER erkennbar fehlende
Kamera-Clearance.

## 1. Ergebnis (Executive Summary)

- **100 Emitter auditiert** (JSON-Parse: Textur + Pixelgröße, effektive max. Quad-Größe
  inkl. `veil:size`-Rampen, additiv, α-Peak, wind/drag, Shape, Java-Spawn-Kontext per rg).
- **7 Offender gefunden und konservativ gefixt** (§3): `storm_godfinger` (wie
  vorhergesagt — Dreifach-Treffer), `storm_rain_sheet`, `ferry_lantern_swarm`,
  `growth_dust_wall`, `impact_light`, `wand_soulbind_flash`, `sig_crown_verdict_halo`.
- **3 neue deterministische Soft-Texturen** + Generatoren nach dem
  `gen_limbo_fog_soft.py`-Muster (Rand-Alpha exakt 0, Zero-Slope-Falloff,
  deterministischer ±3-Stufen-Dither): `storm_godfinger_shaft.png` (64×256),
  `dust_wall_soft.png` (128×128), `flash_soft.png` (128×128).
- **Keine Java-Änderungen nötig** — kein Spawn-Ring braucht Clearance-Korrektur (§3.8).
- **Kein Emitter ist prinzipiell unrettbar** — keine Entfernungs-Vorschläge.
- Gates grün (§4); die `limbo_*`-Emitter wurden NICHT angefasst (Referenz in §2).

**Audit-Nebenbefund (Methodik):** `veil:size` SETZT den Partikel-Radius absolut pro Tick
(`TickSizeParticleModuleData` → `QuasarParticle.setRadius`, Bytecode verifiziert) —
`base_particle_size` zählt dann nur für den Spawn-Frame. Zwei Emitter
(`impact_light`, `sig_crown_verdict_halo`) haben dadurch deutlich größere effektive
Quads als base+variation suggeriert; ein reiner base+variation-Audit hätte sie verpasst.

## 2. Audit-Tabelle (Stand NACH den Fixes; Vorher-Werte der Offender in §3)

Quad-Radius = `base_particle_size + particle_size_variation` (Half-Edge) bzw. die
`veil:size`-Rampe. Spawn-Kontext = Java-Klassen mit Referenz auf den Emitter-Namen
(rg über `src/main/java`). „Empf. E*" verweist auf §5.

| Emitter | Textur (px) | max. Quad-Radius | additiv | α-Peak | wind_speed | drag | Spawn-Shape | Spawn-Kontext (Java) | Befund |
|---|---|---|---|---|---|---|---|---|---|
| `altar_afterglow` | `purple_wisp.png` (8x8) | 0.16 | ja | 0.5 | 0.012 | 0.05 | sphere[1.6, 1.0, 1.6] | AltarCeremonyFx | ok |
| `altar_beam` | `purple_wisp.png` (8x8) | 0.3 | ja | 0.95 | - | - | cylinder[0.45, 1.5, 0.45] | BeamEmitter, SupplyBeamClient, EndArrivalFxRows u.a. | ok |
| `altar_corona_ignite` | `purple_wisp.png` (8x8) | 0.42 | ja | 1.0 | - | 0.35 | sphere[1.4, 1.4, 1.4] | AltarCeremonyFx | ok |
| `altar_glyph_rain` | `purple_wisp.png` (8x8) | 0.26 | ja | 0.9 | - | 0.06 | cylinder[4.5, 0.3, 4.5] | AltarCeremonyFx | ok |
| `altar_halo_patch` | `purple_wisp.png` (8x8) | 1.1 | ja | 0.2 | 0.01 | 0.25 | sphere[0.8, 0.05, 0.8] | AltarIdleMotes | Quad 1.1 auf 8x8, Wind gedaempft (drag 0.25) — Empf. E2 |
| `altar_indraw` | `purple_wisp.png` (8x8) | 0.18 | ja | 0.75 | - | 0.14 | cylinder[3.2, 0.6, 3.2] | EndArrivalFxRows, AltarCeremonyFx, SignatureCompositions | ok |
| `altar_levelup_ring` | `purple_wisp.png` (8x8) | 0.22 | ja | 0.95 | - | 0.12 | cylinder[1.2, 0.2, 1.2] | EndArrivalFxRows, AltarBuyCeremony, S2CQuasarPayload | ok |
| `altar_orbit_burst` | `purple_wisp.png` (8x8) | 0.23 | ja | 0.9 | - | 0.1 | cylinder[5.5, 0.4, 5.5] | AltarCeremonyFx | ok |
| `altar_pillar` | `purple_wisp.png` (8x8) | 0.3 | ja | 0.95 | - | 0.04 | cylinder[0.55, 0.25, 0.55] | HeraldFerrymanFxRows, AltarBuyCeremony, AltarCeremonyFx u.a. | ok |
| `altar_reveal_burst` | `purple_wisp.png` (8x8) | 0.36 | ja | 1.0 | - | 0.93 | sphere[3.0, 2.2, 3.0] | IntroSequence | ok |
| `arm_wisps` | `purple_wisp.png` (8x8) | 0.13 | ja | 0.85 | - | - | sphere[0.35, 0.5, 0.35] | S2CQuasarPayload, ArmParticles, TheOtherEntity | ok |
| `border_first_contact_hairline` | `static_4x4.png` (64x64) | 0.4 | ja | 0.95 | - | - | cube[0.18, 14.0, 0.18] | AtmospherePhotonFxRows | ok |
| `border_glitch` | `purple_wisp.png` (8x8) | 0.32 | ja | 1.0 | - | - | plane[2.5, 3.0, 0.2] | DomeBeamRenderer, DomeShellRenderer, BorderFxRenderer u.a. | ok |
| `border_shard` | `border_glitch.png` (256x256) | 1.4 | ja | 1.0 | - | - | sphere[1.2, 1.2, 1.2] | BorderFxRenderer, FirstContactSeam | ok |
| `boss_slam` | `purple_wisp.png` (8x8) | 0.23 | ja | 1.0 | - | 0.96 | hemisphere[0.8, 0.6, 0.8] | HeraldFerrymanFxRows, SignaturePhotonFxRows, BossPhotonFxRows u.a. | ok |
| `breach_drift_cocoon_orbit` | `static_4x4.png` (64x64) | 0.2 | ja | 0.85 | - | 0.06 | sphere[1.1, 1.6, 1.1] | AtmospherePhotonFxRows | ok |
| `collection_tier_halo` | `purple_wisp.png` (8x8) | 0.15 | ja | 0.85 | - | 0.04 | cylinder[0.75, 0.15, 0.75] | ProgressionPhotonFxRows, FxCues | ok |
| `contract_omen_ring` | `wisp_white.png` (8x8) | 0.19 | ja | 0.9 | - | 0.05 | cylinder[1.6, 0.12, 1.6] | FerrymanFinaleFxRows, WorldEventPhotonFxRows | ok |
| `contract_omen_snuff` | `wisp_white.png` (8x8) | 0.24 | nein | 0.7 | - | 0.08 | sphere[2.4, 0.4, 2.4] | WorldEventPhotonFxRows | ok |
| `crater_updraft` | `purple_wisp.png` (8x8) | 0.11 | ja | 0.35 | 0.02 | 0.02 | cylinder[5.5, 0.5, 5.5] | GravityRiftFxRows, SanctumLightfall | ok |
| `cutscene_veil` | `purple_wisp.png` (8x8) | 0.29 | ja | 0.9 | 0.02 | 0.9 | hemisphere[2.4, 2.2, 2.4] | BreachClientFx, ExpansionSequence, S2CQuasarPayload u.a. | Terminal-v ~3.6 B/s (drag 0.9) = absichtliche Streaks — Empf. E1 |
| `dawn_toll_glint` | `purple_wisp.png` (8x8) | 0.18 | ja | 0.8 | - | 0.12 | sphere[2.4, 0.5, 2.4] | CeremonyPhotonFxRows | ok |
| `door_glow_motes` | `purple_wisp.png` (8x8) | 0.13 | ja | 0.68 | 0.02 | 0.04 | sphere[0.9, 1.1, 0.9] | FerrymanFinaleFxRows, AltarIdleMotes, LastHeartEmber u.a. | ok |
| `dungeon_maw_dust` | `wisp_white.png` (8x8) | 0.47 | nein | 0.5 | - | 0.06 | cylinder[1.2, 0.5, 1.2] | WorldEventPhotonFxRows | ok |
| `dungeon_maw_idle` | `wisp_white.png` (8x8) | 0.4 | nein | 0.35 | - | 0.05 | cylinder[1.0, 0.4, 1.0] | WorldEventPhotonFxRows, FxCues | ok |
| `eclipse_lightning_impact` | `purple_wisp.png` (8x8) | 0.3 | ja | 1.0 | - | 0.65 | sphere[1.2, 0.8, 1.2] | IntroLightningPhase | ok |
| `ferry_kneel_corona` | `wisp_white.png` (8x8) | 0.23 | ja | 0.5 | - | - | cylinder[1.3, 0.3, 1.3] | HeraldFerrymanFxRows, FxCues | ok |
| `ferry_lantern_swarm` | `wisp_white.png` (8x8) | 0.2 | ja | 0.85 | 0.0006 | 0.96 | cylinder[2.2, 0.4, 2.2] | FxCues, HeraldFerrymanFxRows | **GEFIXT** (s. §3) |
| `ghost_departure_wisp` | `wisp_white.png` (8x8) | 0.26 | ja | 0.55 | - | 0.02 | sphere[0.3, 0.4, 0.3] | FerrymanFinaleFxRows, CeremonyPhotonFxRows | ok |
| `glide_trail` | `purple_wisp.png` (8x8) | 0.14 | ja | 0.7 | - | 0.92 | sphere[0.3, 0.4, 0.3] | EdgeGlideService, GlideTrailFx, PlayerFxPhotonRows | ok |
| `glut_ash_flakes` | `wisp_white.png` (8x8) | 0.1 | nein | 0.85 | - | 0.3 | sphere[0.45, 0.35, 0.45] | WandPowers, QuasarSpawner | ok |
| `glut_cast_hand` | `wisp_white.png` (8x8) | 0.12 | ja | 1.0 | - | 0.75 | hemisphere[0.2, 0.25, 0.2] | WandPowers | ok |
| `glut_heat_column` | `wisp_white.png` (8x8) | 0.28 | ja | 0.4 | - | 0.15 | cylinder[0.55, 2.8, 0.55] | QuasarSpawner, WandPowers | ok |
| `glut_sprung_crater` | `wisp_white.png` (8x8) | 0.24 | ja | 1.0 | - | 0.12 | hemisphere[1.6, 1.0, 1.6] | WandPowers, WandPhotonFxRows, FxCues | ok |
| `glut_stoss_lance` | `wisp_white.png` (8x8) | 0.17 | ja | 1.0 | - | 0.35 | sphere[0.25, 0.25, 0.25] | WandPowers | ok |
| `glut_welle_ring` | `wisp_white.png` (8x8) | 0.22 | ja | 1.0 | - | 0.16 | cylinder[1.4, 0.45, 1.4] | HeraldFerrymanFxRows, WandTickService, WandPowers | ok |
| `glyph_danger` | `purple_wisp.png` (8x8) | 0.19 | ja | 1.0 | - | 0.92 | sphere[0.3, 0.2, 0.3] | GestureGlyphFx | ok |
| `glyph_follow` | `purple_wisp.png` (8x8) | 0.13 | ja | 0.75 | - | 0.93 | sphere[0.2, 0.2, 0.2] | GestureGlyphFx | ok |
| `glyph_greet` | `purple_wisp.png` (8x8) | 0.14 | ja | 0.9 | - | 0.9 | sphere[0.25, 0.2, 0.25] | GestureGlyphFx | ok |
| `growth_dust_wall` | `dust_wall_soft.png` (128x128) | 4.1 | nein | 0.38 | 0.02 | 0.06 | cube[6.0, 0.6, 6.0] | FerrymanFinaleFxRows, WorldEventPhotonFxRows, ExpansionSequence u.a. | **GEFIXT** (s. §3) |
| `heart_burst` | `heart_full.png` (9x9) | 0.19 | nein | 1.0 | - | 0.06 | sphere[0.3, 0.3, 0.3] | HeartBurstOverlay, HeartTheftService, PhotonBridge u.a. | ok |
| `impact_light` | `flash_soft.png` (128x128) | veil:size 1.0->3.2 | ja | 0.65 | - | - | sphere[0.2, 0.2, 0.2] | CombatFeedbackFx, WandPhaseService, IntroLightningPhase u.a. | **GEFIXT** (s. §3) |
| `landmark_flare` | `purple_wisp.png` (8x8) | 0.22 | ja | 0.8 | - | 0.05 | cylinder[2.1, 0.2, 2.1] | ProgressionPhotonFxRows, FxCues | ok |
| `limbo_embers` | `purple_wisp.png` (8x8) | 0.18 | ja | 0.45 | 0.025 | 0.015 | cylinder[1.4, 0.6, 1.4] | LimboAmbience | Referenz: F-107 Teil 2-4 (nicht angefasst) |
| `limbo_fog` | `limbo_fog_soft.png` (128x128) | 10.0 | nein | 0.13 | 0.0003 | - | sphere[7.0, 1.2, 7.0] | LimboAmbience | Referenz: F-107 Teil 2-4 (nicht angefasst) |
| `limbo_fogbank` | `limbo_fogbank_soft.png` (128x64) | 28.0 | nein | 0.1 | 0.002 | 0.96 | sphere[16.0, 1.8, 16.0] | LimboAmbience, EchoPhotonFxRows | Referenz: F-107 Teil 2-4 (nicht angefasst) |
| `limbo_motes` | `purple_wisp.png` (8x8) | 0.085 | ja | 0.05 | 0.0006 | 0.96 | sphere[8.0, 4.0, 8.0] | HearthAuraService, HeraldFerrymanFxRows, LimboAmbience u.a. | Referenz: F-107 Teil 2-4 (nicht angefasst) |
| `limbo_moths` | `purple_wisp.png` (8x8) | 0.2 | ja | 0.5 | - | 0.01 | sphere[0.9, 0.7, 0.9] | LimboAmbience | Referenz: F-107 Teil 2-4 (nicht angefasst) |
| `map_expand_materialize` | `-` (-) | 0.42 | ja | 0.95 | - | 0.25 | cube[1.5, 2.0, 1.5] | RiftFx, PhotonBridge, Wave13bPhotonFxRows u.a. | ok |
| `minigame_gate_collapse` | `purple_wisp.png` (8x8) | 0.15 | ja | 0.9 | - | 0.04 | sphere[1.8, 1.8, 1.8] | WorldEventPhotonFxRows | ok |
| `minigame_gate_ring` | `wisp_white.png` (8x8) | 0.17 | ja | 0.95 | - | 0.05 | cylinder[1.6, 1.9, 1.6] | WorldEventPhotonFxRows | ok |
| `offering_armed` | `purple_wisp.png` (8x8) | 0.19 | ja | 0.55 | - | 0.14 | cylinder[0.26, 1.4, 0.26] | AltarBlockEntity | ok |
| `offering_gutter_puff` | `wisp_white.png` (8x8) | 0.15 | nein | 0.7 | - | 0.25 | sphere[0.2, 0.15, 0.2] | AltarBlockEntity, CeremonyPhotonFxRows | ok |
| `offering_swallow` | `purple_wisp.png` (8x8) | 0.11 | ja | 0.9 | - | 0.35 | sphere[0.12, 0.12, 0.12] | OfferingSwallowFx, S2CQuasarPayload, EclipsePayloads | ok |
| `portal_draw_in_motes` | `purple_wisp.png` (8x8) | 0.17 | ja | 0.75 | - | 0.1 | sphere[4.0, 4.0, 4.0] | AtmospherePhotonFxRows | ok |
| `portal_surface_motes` | `purple_wisp.png` (8x8) | 0.1 | ja | 0.4 | - | 0.05 | sphere[2.6, 3.2, 2.6] | RiftFx | ok |
| `quest_sigil_ring` | `purple_wisp.png` (8x8) | 0.18 | ja | 0.95 | - | 0.12 | cylinder[0.6, 0.25, 0.6] | ProgressionPhotonFxRows | ok |
| `race_finish_ribbon` | `wisp_white.png` (8x8) | 0.21 | ja | 0.95 | - | 0.05 | cylinder[2.2, 0.3, 2.2] | WorldEventPhotonFxRows, FxCues | ok |
| `rebirth_ring` | `wisp_white.png` (8x8) | 0.23 | ja | 1.0 | - | 0.1 | cylinder[0.6, 0.25, 0.6] | CeremonyPhotonFxRows, RebirthService, FxCues | ok |
| `resonance_fail` | `wisp_white.png` (8x8) | 0.19 | ja | 0.9 | - | 0.04 | cylinder[1.6, 0.3, 1.6] | ResonancePhotonFxRows | ok |
| `resonance_finale` | `wisp_white.png` (8x8) | 0.32 | ja | 0.95 | - | 0.015 | cylinder[2.2, 1.0, 2.2] | ResonancePhotonFxRows | ok |
| `resonance_pulse` | `purple_wisp.png` (8x8) | 0.21 | ja | 0.9 | - | 0.05 | sphere[0.4, 0.4, 0.4] | ResonancePhotonFxRows | ok |
| `resonance_strike` | `wisp_white.png` (8x8) | 0.18 | ja | 0.95 | - | 0.06 | sphere[0.7, 0.7, 0.7] | ResonancePhotonFxRows | ok |
| `revive_thunderbloom_ring` | `purple_wisp.png` (8x8) | 0.21 | ja | 1.0 | - | 0.12 | cylinder[0.8, 0.15, 0.8] | GravityRiftFxRows, CeremonyPhotonFxRows | ok |
| `rift_spark` | `purple_wisp.png` (8x8) | 0.16 | ja | 0.95 | - | 0.08 | sphere[0.9, 0.9, 0.9] | GravityRiftFxRows, RiftFx, Wave4CombatFxRows u.a. | ok |
| `riss_blink_tear` | `purple_wisp.png` (8x8) | 0.16 | ja | 1.0 | - | 0.1 | sphere[0.9, 1.2, 0.9] | WandPowers, PhotonBridge | ok |
| `riss_cast_hand` | `purple_wisp.png` (8x8) | 0.1 | ja | 1.0 | - | 0.82 | sphere[0.22, 0.22, 0.22] | WandPowers | ok |
| `riss_maw_shimmer` | `purple_wisp.png` (8x8) | 0.14 | ja | 0.8 | - | 0.2 | torus[1.5, 0.6, 1.5] | WandPowers, QuasarSpawner, FerrymanFinaleFxRows u.a. | ok |
| `riss_schlag_maw` | `purple_wisp.png` (8x8) | 0.2 | ja | 1.0 | - | 0.08 | torus[1.7, 0.9, 1.7] | WandPowers, FxCues, PhotonBridge u.a. | ok |
| `riss_seam_scar` | `purple_wisp.png` (8x8) | 0.12 | ja | 0.85 | - | 0.9 | cube[2.4, 0.06, 0.06] | QuasarSpawner, WandPowers, PhotonBridge | ok |
| `riss_wave_front` | `purple_wisp.png` (8x8) | 0.15 | ja | 0.95 | - | 0.55 | cube[3.2, 0.15, 0.7] | WandPhaseService, WandPowers, FerrymanFinaleFxRows | ok |
| `roulette_flare` | `purple_wisp.png` (8x8) | 0.21 | ja | 1.0 | - | 0.92 | sphere[0.3, 0.3, 0.3] | AwardsOverlay | ok |
| `sanctum_lightfall` | `purple_wisp.png` (8x8) | 0.17 | ja | 0.78 | - | 0.02 | sphere[0.3, 0.15, 0.3] | SanctumLightfall | ok |
| `sig_crown_verdict_burst` | `purple_wisp.png` (8x8) | 0.19 | ja | 0.95 | - | 0.08 | sphere[0.6, 0.6, 0.6] | SignaturePhotonFxRows | ok |
| `sig_crown_verdict_halo` | `ring_soft.png` (256x256) | veil:size 1.4->6.0 | ja | 0.85 | - | - | sphere[0.05, 0.05, 0.05] | SignatureCompositions | **GEFIXT** (s. §3) |
| `sig_deep_rumble_motes` | `wisp_white.png` (8x8) | 0.1 | nein | 0.3 | - | 0.3 | cylinder[4.5, 0.4, 4.5] | SignaturePhotonFxRows | ok |
| `sig_gold_rush_glints` | `purple_wisp.png` (8x8) | 0.15 | ja | 0.9 | - | 0.1 | sphere[1.7, 1.2, 1.7] | SignatureCompositions | ok |
| `sig_sanctum_glyph` | `purple_wisp.png` (8x8) | 0.21 | ja | 0.7 | - | 0.25 | torus[0.85, 0.06, 0.85] | HeraldFerrymanFxRows, SignatureCompositions | ok |
| `sig_sanctum_orbit` | `purple_wisp.png` (8x8) | 0.16 | ja | 0.75 | - | 0.12 | cylinder[1.2, 0.5, 1.2] | SignatureCompositions | ok |
| `skill_spend_spark` | `wisp_white.png` (8x8) | 0.09 | ja | 0.95 | - | 0.3 | sphere[0.25, 0.25, 0.25] | ProgressionPhotonFxRows, FxCues | ok |
| `slam_debris` | `purple_wisp.png` (8x8) | 0.5 | ja | 1.0 | - | 0.35 | sphere[2.5, 1.5, 2.5] | ExpansionSequence, EndShatterSequence | ok |
| `stern_cast_hand` | `wisp_white.png` (8x8) | 0.1 | ja | 1.0 | - | 0.6 | sphere[0.25, 0.25, 0.25] | WandPowers | ok |
| `stern_constellation` | `wisp_white.png` (8x8) | 0.11 | ja | 0.95 | - | 0.12 | sphere[1.2, 0.8, 1.2] | WandPowers, QuasarSpawner | ok |
| `stern_funke_fall` | `wisp_white.png` (8x8) | 0.17 | ja | 1.0 | - | 0.06 | cylinder[0.35, 3.4, 0.35] | WandPowers, EndArrivalFxRows, PhotonBridge | ok |
| `stern_komet_core` | `wisp_white.png` (8x8) | 0.6 | ja | 1.0 | - | 0.1 | sphere[0.7, 0.7, 0.7] | WandPowers, PhotonBridge, WandPhotonFxRows | ok |
| `stern_schauer_field` | `wisp_white.png` (8x8) | 0.16 | ja | 0.9 | - | 0.04 | torus[2.6, 0.25, 2.6] | WandPowers | ok |
| `storm_arc` | `purple_wisp.png` (8x8) | 0.36 | ja | 1.0 | - | 0.14 | sphere[0.9, 0.9, 0.9] | StormFxClient | ok |
| `storm_godfinger` | `storm_godfinger_shaft.png` (64x256) | 4.2 | ja | 0.1 | 0.0004 | 0.96 | cylinder[1.4, 9.0, 1.4] | StormInteriorFx | **GEFIXT** (s. §3) |
| `storm_outrunner_wisp` | `purple_wisp.png` (8x8) | 1.2 | nein | 0.5 | - | 0.04 | sphere[0.5, 0.35, 0.5] | StormApproachFx, AtmospherePhotonFxRows | grenzwertig: 1.2 auf 8x8, n-add — Empf. E2 |
| `storm_rain_sheet` | `purple_wisp.png` (8x8) | 0.8 | ja | 0.31 | 0.001 | - | cube[7.0, 2.0, 7.0] | StormInteriorFx | **GEFIXT** (s. §3) |
| `structure_slam_dust` | `purple_wisp.png` (8x8) | 1.4 | nein | 0.9 | - | 0.7 | hemisphere[4.0, 1.0, 4.0] | BreachClientFx, ExpansionSequence | grenzwertig: 1.4 n-add a0.9 auf 8x8 — Empf. E2 |
| `summon_beacon_pillar` | `wisp_white.png` (8x8) | 0.28 | ja | 0.95 | - | 0.03 | cylinder[0.35, 0.4, 0.35] | WorldEventPhotonFxRows, GravityRiftFxRows | ok |
| `supply_herald_tear` | `wisp_white.png` (8x8) | 0.22 | ja | 0.95 | - | 0.04 | sphere[0.5, 0.5, 0.5] | WorldEventPhotonFxRows | ok |
| `supply_spark` | `purple_wisp.png` (8x8) | 0.22 | ja | 1.0 | - | - | sphere[0.4, 0.2, 0.4] | LastHeartEmber, SupplyBeamClient | ok |
| `totality_diamond_glint` | `wisp_white.png` (8x8) | 1.6 | ja | 1.0 | - | 0.08 | sphere[0.5, 0.5, 0.5] | AtmospherePhotonFxRows | grenzwertig: 1.6 additiv a1.0 auf 8x8 — Empf. E2 |
| `unlock_burst` | `purple_wisp.png` (8x8) | 0.18 | ja | 1.0 | - | 0.94 | hemisphere[0.4, 0.5, 0.4] | GravityRiftFxRows, WandPowers, SignatureCompositions u.a. | ok |
| `vortex_wisp` | `purple_wisp.png` (8x8) | 2.1 | nein | 0.42 | 0.03 | 0.05 | sphere[1.6, 1.6, 1.6] | StormFxClient, EndArrivalFxRows | grenzwertig: Quad 2.1 auf 8x8 (Wind gedaempft) — Empf. E2 |
| `wand_soulbind_flash` | `flash_soft.png` (128x128) | 2.9 | ja | 0.65 | - | - | sphere[0.15, 0.15, 0.15] | WandPowers, PhotonBridge | **GEFIXT** (s. §3) |
| `wand_soulbind_orbit` | `wisp_white.png` (8x8) | 0.13 | ja | 0.95 | - | 0.08 | torus[1.5, 0.35, 1.5] | QuasarSpawner, PhotonBridge, WandPowers | ok |
| `wizard_catalyst_indraw` | `purple_wisp.png` (8x8) | 0.15 | ja | 0.8 | - | 0.14 | sphere[1.5, 1.1, 1.5] | ProgressionPhotonFxRows, WizardFxRows | ok |

Die 5 `limbo_*`-Zeilen sind die in F-107 Teil 2–4 bereits behandelten Referenzen
(`limbo_godray`/`limbo_motes_near` existieren seit Teil 4 nicht mehr).

## 3. Offender — Diagnose und Fixes (alle konservativ, Look-erhaltend)

### 3.1 `storm_godfinger` — der vorhergesagte Dreifach-Treffer

Sphären-Sturm-Interior-Lichtschächte durchs Dom-Auge (`StormInteriorFx.tickGodFingers`,
≤ 2 welt-verankerte Loops bei 0.35·r um das Sturmzentrum, Spieler kann beliebig nah
heran). Anatomie identisch zum entfernten `limbo_godray`, nur grün: (a) ungedämpfter
Wind 0.006/t² → Drift ≤ 19.4 Blöcke, Endgeschwindigkeit ~9.6 B/s — wandernde
Kapsel-Queue; (b) 8×8-`purple_wisp` auf 6.4–14-Block-Quad-Kanten (Texel = harte
Rechtecke, Rand-α 26 zeichnet die Quad-Kante); (c) additiv; (d) bis 8 gestapelte Quads
im Ø-2.8-Zylinder (Steady-State 75/8 ≈ 9, additiv aufsummiert ≈ 0.8).

| Parameter | Vorher | Nachher | Begründung |
|---|---|---|---|
| `sprite` | `purple_wisp.png` (8×8) | **`storm_godfinger_shaft.png`** (64×256, NEU) | Power-Law-Falloff (1−\|nx\|)^1.5 mit Zero-Slope-Fuß, V-Fade 0.34 (Teil-3-Anti-Waist), determ. ±3-Dither, Rand exakt 0, vorverdunkelte Grün-Familie (JSON-Tint #D9FFE8→#6FA98C bleibt) |
| `wind_speed` / Richtung | 0.006 / (0.2, 0, 0.9) | **0.0004 / (0.15, −1.0, 0.25)** | Wind-Kur; Abwärts-Bias hält die `face_velocity`-Quads vertikal (sonst kippt der Schacht unter Drag zur Seite, sobald die Lateral-Komponente dominiert) |
| NEU `veil:drag` | — | **0.96** | Terminal-v = a·d/(1−d) ≈ 0.19 B/s — „hängende, langsam sinkende Schächte"; Drift ≤ ~0.8 statt 19.4 Blöcke |
| `base_particle_size` ± Var | 4.5 ± 2.5 (max 7.0) | **3.2 ± 1.0 (max 4.2)** | Größen-Ausreißer gekappt; Finger-Silhouette (~3 Blöcke sichtbare Schachtbreite × ~12 hoch) bleibt |
| `rate` / `max_particles` | 8 / 8 | **24 / 3** | De-Stack (Teil-3-Runde-2-Rezept): additiv max ≈ 3×0.1 statt 8×0.1 |
| α-Peak (JSON) | 0.1 | 0.1 (unverändert) | war schon leise; Einzelschacht ≈ 2 % Kern-Luminanz mit Textur-Peak 0.55 |

Doppelt gegated (Interior > 0.5, EyeDim > 0.3, ≤ 48 Blöcke vom Zentrum, Fog-Far ~24) —
kein Ambient-Dauerläufer wie die Limbo-Godrays, daher Retten statt Entfernen vertretbar.

### 3.2 `storm_rain_sheet` — Wind-Kur light

Interior-Regen-Sheets (`StormInteriorFx.tickRainSheets`, orbitieren die Kamera,
Spawn-Distanz 2–7 Blöcke, Fallrichtung −Y via `veil:initial_velocity` 10 + `veil:gravity`
0.5). Offender nur per Kriterium 1: Wind 0.01/t² ungedämpft → Lateral-Drift 1.7 Blöcke,
Ende ~3.6 B/s quer zur Fallrichtung.

| Parameter | Vorher | Nachher |
|---|---|---|
| `wind_speed` | 0.01 | **0.001** |

**Bewusst KEIN `veil:drag`:** Drag wirkt auf die Gesamt-Velocity und würde die
absichtlich hohe Fallgeschwindigkeit (Regen-Identität: Streak-Länge = v ×
`velocity_stretch` 2.2) pro Lebenszeit auf ~50 % abklingen lassen — „bremsender Regen"
wäre ein neuer Look-Bruch. Winziger Wind allein ist hier ausreichend (Drift ≤ 0.17
Blöcke, Lateral-Ende 0.36 B/s) — dasselbe Muster wie `limbo_fog` (0.0003, kein Drag).

### 3.3 `ferry_lantern_swarm` — der schlimmste Drift des Bestands

One-Shot-Laternen-Moten beim Ferryman-Kniefall (`FxCues.CUE_FERRY_LANTERN_SWARM` →
`HeraldFerrymanFxRows`, Boss-Anker). Wind 0.02/t² ungedämpft bei Lifetime bis 60 t:
**Drift ≤ 36.6 Blöcke, Endgeschwindigkeit ~24 B/s** — die „aufsteigenden Seelen-Glints"
beschleunigten zu Leuchtspurgeschossen quer durch die Boss-Arena (Quads klein, deshalb
las es als Streifen statt Wand — aber dieselbe Defektklasse).

| Parameter | Vorher | Nachher |
|---|---|---|
| `wind_speed` | 0.02 | **0.0006** |
| NEU `veil:drag` | — | **0.96** → Terminal ~0.29 B/s Aufwärts-Schweben, Drift ≤ ~0.9 Blöcke |

Richtung (0, 1, 0.1) und alles andere unverändert — langsam steigende Glints, wie gemeint.

### 3.4 `growth_dust_wall` — Kriterium 2 + designbedingt OHNE Kamera-Clearance

Expansions-Staubvorhang (`ExpansionSequence.ClientHooks` — spawnt beim Front-Crossing
DIREKT auf `player.position()`; außerdem `EndShatterSequence`, `rim_recede`-Cue).
Quads bis Radius 4.1 (Kante 8.2 Blöcke) mit dem 8×8-Wisp, nicht-additiv α 0.38: das
Kreuz/Plus in Violett-Grau, und weil die Front den Spieler designbedingt ÜBERROLLT,
schieben die Quads durch die Kamera — die Textur muss das aushalten.

| Parameter | Vorher | Nachher |
|---|---|---|
| `sprite` | `purple_wisp.png` (8×8) | **`dust_wall_soft.png`** (128×128, NEU): Gauss-Falloff + 5/3-Lobe-Waviness (Staub, kein Bokeh-Ball), Rand exakt 0, determ. Dither, vorverdunkeltes Violett-Grau (JSON-Tint #9D86C9→#241C38 bleibt) |

Größen, α 0.38, gedämpfter Wind (drag 0.06): unverändert — der Vorhang bleibt gleich
dicht/groß, er liest nur als Staub statt als Rechteck-Cluster. Kamera-Durchflug wird
zum weichen Vollbild-Haze-Puls (Fog-Muster aus Teil 2). Kein Java-Eingriff nötig.

### 3.5 `impact_light` — Kriterium 2 + 3 (versteckt hinter `veil:size`)

Der D12-Mikro-Flash (Combat-Crits `CombatFeedbackFx`, Wand-Re-Rez `WandPhaseService`,
Intro-Lightning `IntroLightningPhase`). `veil:size`-Rampe wuchs auf Radius 4.6 bei
additiv + α-Start 0.95 + count 3 — ein ~9-Block-Quad-Blitz aus dem 8×8-Wisp: das
hellste harte Plus im Spiel, ~0.45 s lang.

| Parameter | Vorher | Nachher |
|---|---|---|
| `sprite` | `purple_wisp.png` (8×8) | **`flash_soft.png`** (128×128, NEU): Bell-Falloff (1−r²)² — Zero-Slope an Kern UND Rand, Rand exakt 0, determ. Dither |
| `veil:size` | `1.2 + q.agePercent * 3.4` (→ 4.6) | **`1.0 + q.agePercent * 2.2` (→ 3.2)** |
| `base_particle_size` ± Var | 3.6 ± 0.8 | **1.0 ± 0.2** (nur Spawn-Frame; an Rampen-Start angeglichen — der alte Wert ließ Frame 1 auf 4.4 springen) |
| α-Punkte | 0.95 / 0.6 / 0.0 | **0.65 / 0.45 / 0.0** |

Beim α-15-%-Durchgang (agePercent ≈ 0.77) ist der Radius jetzt ~2.7 < 3 — Kriterium 3
sauber unterschritten; der Flash bleibt durch additive Sättigung (3 Partikel gestapelt)
wahrnehmbar hell, verliert aber Kontur statt Präsenz.

### 3.6 `wand_soulbind_flash` — Kriterium 3

D11-Soulbind-Zeremonie, ein weißer Flash (`WandPowers.handleChoosePath`). Radius
3.2–3.8, additiv, α 1.0, 8×8-`wisp_white` — gleiche Anatomie wie 3.5.

| Parameter | Vorher | Nachher |
|---|---|---|
| `sprite` | `wisp_white.png` (8×8) | **`flash_soft.png`** (geteilt mit 3.5 — beides weiße Licht-Flashes, Farbe kommt aus dem JSON-Tint) |
| `base_particle_size` ± Var | 3.2 ± 0.6 (max 3.8) | **2.3 ± 0.6 (max 2.9)** |
| α-Punkte | 1.0 / 0.55 / 0.0 | **0.65 / 0.45 / 0.0** |

### 3.7 `sig_crown_verdict_halo` — Kriterium 3, aber weiche Textur: nur α-Moderation

C11-Crown-Verdict-Signatur (`SignatureCompositions`, S-MAX-Moment): EIN Partikel,
expandierender Gold-Ring, `veil:size` 1.4 → 6.0 über 1.5 s, additiv, α 0.85 → 0.
Die Textur ist hier NICHT das Problem: `ring_soft.png` ist 256×256, weicher
Falloff, Rand-α ≈ 0 (max 2/255). Restrisiko ist allein die llvmpipe-Quantisierung des
glatten Ring-Gradienten bei großem Radius (α 0.45 bei Radius ≥ 3.9).

| Parameter | Vorher | Nachher |
|---|---|---|
| α-Mittelpunkt (percent 0.55) | 0.45 | **0.28** |

Peak 0.85 (bei Radius 1.4, unkritisch) und die 6.0-Expansion bleiben — der
Verdict-Punch ist der Moment-Kern; nur die große, leise Auslauf-Phase wird leiser.
Falls die nächste Abnahme hier noch Banding sieht: Empfehlung E4.

### 3.8 Kamera-Clearance-Prüfung (Kriterium 4) — kein Java-Fix nötig

- `storm_rain_sheet`: Spawn-Distanz ≥ 2.0 von der Kamera, Quad-Radius ≤ 0.8, Bewegung
  abwärts (nie auf die Kamera zu) → Clearance ≥ ~1.2. OK.
- `storm_godfinger`: welt-verankert am Sturmzentrum; nach der Wind-Kur quasi ortsfest —
  Hineinlaufen in einen Lichtschacht ist legitimes Verhalten, kein Durch-die-Kamera-Drift
  mehr. OK.
- `growth_dust_wall`: Spawn AUF dem Spieler ist die Design-Absicht (Front überrollt);
  mit weicher Textur akzeptabel (§3.4). OK.
- `ferry_lantern_swarm`: Boss-Anker, nach Drag-Fix ortsnah. OK.
- `cutscene_veil` (Hemisphäre um den Spieler, Terminal ~3.6 B/s): absichtliche
  Submerge-/Rim-Streaks unter Cutscene-Overlay — kein Fix, siehe E1.

## 4. Gates

- `./gradlew compileJava processResources --offline -q` → **exit 0 (grün)**; in
  `build/resources/main/...` verifiziert: alle 7 Emitter-JSONs tragen die neuen Werte,
  die 3 neuen PNGs sind kopiert.
- `python3 -m json.tool` auf allen 7 geänderten Emitter-JSONs: OK.
- Kein dediziertes Quasar-JSON-Validierungsskript in `tools/` vorhanden (geprüft per rg;
  `tools/photon/fxlib.py validate` validiert Photon-`.fx`, nicht Quasar). Trotzdem als
  Zusatz-Gate gelaufen: `python3 tools/photon/fxlib.py validate --lint` → 293 Dateien,
  **0 NEW error/warn** (erwartungsgemäß — keine `.fx`-Datei angefasst).
- Sprite-Generatoren doppellauf-**byteidentisch** (md5-Check beider Läufe); alle 3 PNGs:
  Rand-Alpha exakt 0, Peak-α (140/171/156) unter dem alten Wisp-Kern (189).
- Kein Client-Neustart nötig: Emitter-JSONs + Texturen laden über F3+T (Veil-Listener).

## 5. Geänderte Dateien

| Datei | Änderung |
|---|---|
| `quasar/emitters/storm_godfinger.json` | Sprite, Wind 0.006→0.0004 (+Richtung −Y-Bias), +drag 0.96, Größe 4.5±2.5→3.2±1.0, rate 8→24, max_particles 8→3 |
| `quasar/emitters/storm_rain_sheet.json` | Wind 0.01→0.001 (bewusst ohne Drag, §3.2) |
| `quasar/emitters/ferry_lantern_swarm.json` | Wind 0.02→0.0006, +drag 0.96 |
| `quasar/emitters/growth_dust_wall.json` | Sprite → `dust_wall_soft.png` |
| `quasar/emitters/impact_light.json` | Sprite → `flash_soft.png`, size-Rampe 1.2+3.4→1.0+2.2, base 3.6±0.8→1.0±0.2, α 0.95/0.6→0.65/0.45 |
| `quasar/emitters/wand_soulbind_flash.json` | Sprite → `flash_soft.png`, Größe 3.2±0.6→2.3±0.6, α 1.0/0.55→0.65/0.45 |
| `quasar/emitters/sig_crown_verdict_halo.json` | α-Mittelpunkt 0.45→0.28 |
| `textures/particle/storm_godfinger_shaft.png` | NEU (64×256) |
| `textures/particle/dust_wall_soft.png` | NEU (128×128) |
| `textures/particle/flash_soft.png` | NEU (128×128) |
| `tools/art/gen_storm_godfinger_shaft.py` | NEU (deterministischer Generator) |
| `tools/art/gen_dust_wall_soft.py` | NEU (deterministischer Generator) |
| `tools/art/gen_flash_soft.py` | NEU (deterministischer Generator) |

Keine Java-Änderungen. Keine `limbo_*`-JSONs angefasst. Nichts committet.

## 6. Offene Empfehlungen

- **E1 `cutscene_veil`:** Terminal-Geschwindigkeit ~3.6 B/s (wind 0.02, drag 0.9) ist
  absichtliche Streak-Optik in Submerge-/Rim-Momenten unter Cutscene-Overlay; Quads sind
  klein (≤ 0.29). Falls eine Abnahme die Streaks je als Artefakt liest: drag 0.9 → 0.85
  (Terminal ~2.3 B/s) — nicht jetzt ändern.
- **E2 Grenzfälle unter den harten Kriterien** (Quad ~1–2 auf 8×8-Wisps):
  `vortex_wisp` (2.1), `totality_diamond_glint` (1.6, additiv α 1.0),
  `structure_slam_dust` (1.4), `storm_outrunner_wisp` (1.2), `altar_halo_patch` (1.1).
  Alle klar unter den Auftrags-Schwellen und bewegungs-/distanzmaskiert — beobachten;
  bei Beanstandung ist `flash_soft.png`/`dust_wall_soft.png` das fertige Gegenmittel.
- **E3 Haus-Wisps haben Rand-Alpha 26 ≠ 0:** jedes ZUKÜNFTIGE Emitter-Design mit
  Quad-Radius ≳ 1 auf `purple_wisp`/`wisp_white` zeichnet die Quad-Kante mit. Eine
  Regeneration der beiden 8×8er mit Rand 0 wäre ein Ein-Zeilen-Fix pro Textur, berührt
  aber ~90 Emitter gleichzeitig → eigener Abnahme-Durchlauf, hier bewusst NICHT gemacht.
  → **AUSGEFÜHRT im Follow-up, siehe §8.**
- **E4 `sig_crown_verdict_halo`-Restrisiko:** glatter 256-px-Ring ohne Dither kann auf
  llvmpipe bei großem Radius konzentrisch banden (1.5-s-One-Shot, daher toleriert).
  Falls beanstandet: `ring_soft.png` mit deterministischem Dither regenerieren
  (Generator existiert nicht in `tools/art/` — müsste neu angelegt werden).
- **E5 Live-Abnahme:** Die Fixes sind parameter-/textur-mathematisch hergeleitet (gleiche
  Formeln wie Teil 2/3), aber NICHT im laufenden Client gesichtet (kein Sturm-/Boss-/
  Signatur-Szenario ohne längeres Live-Setup erreichbar). Empfohlener Smoke-Test:
  Sphären-Sturm betreten (`storm_godfinger` + Motes), `/eclipsefx emitter` für
  `impact_light`/`wand_soulbind_flash`/`growth_dust_wall`, Ferryman-Crew-Phase — je mit
  F3+T-Reload; Abnahme-Kriterium: keine harten Kanten/Kreuze/Kapseln, kein Drift-Marsch.

## 7. Follow-up: Death-Screen-Ash entkoppelt (`death_ash.json`)

Der in Teil 4 §1.3 dokumentierte und akzeptierte Nebeneffekt des `limbo_motes`-Alpha-Caps
(0.28 → 0.05) ist in der Live-Abnahme als **Regression der Design-Absicht** real geworden:
der `EclipseDeathScreen`-„slow ash"-Loop nutzte denselben Emitter und ist mit α 0.05
praktisch unsichtbar (Live-Screenshot: keine Asche mehr erkennbar). Der Cap galt der
Limbo-**Welt**-Ambience (llvmpipe-Wand-Klasse auf Distanz); auf dem Death-Screen war
α 0.28 nie das Problem — winzige Quads (0.055 ± 0.03), screen-nah um den Leichnam,
bewusste Melancholie-Asche.

**Fix (minimal-invasiv): Nutzungs-Entkopplung statt Re-Tune.**

- NEU `quasar/emitters/death_ash.json` — 1:1-Kopie von `limbo_motes.json` mit dem
  PRE-CAP-Alpha zurückgesetzt (Stützpunkte 0.3/0.7: 0.05 → **0.28**, per
  `git show 95a3d9b` verifiziert — das war der Cap-Commit). Die davon UNABHÄNGIGE
  Teil-3-Wind-Kur bleibt absichtlich drin: `wind_speed` **0.0006** (pre-cap war 0.015
  ungedämpft) + `veil:drag` **0.96**; Größe 0.055 ± 0.03, Sprite `purple_wisp` (8×8,
  unter Pixelgröße — Teil-3-§3.4-Begründung), alles andere identisch.
- `EclipseDeathScreen.ASH_EMITTER`: `eclipse:limbo_motes` → **`eclipse:death_ash`**
  (+ Javadoc-Historie). Einzige Java-Änderung.
- `LimboAmbience`s MOTES-Window bleibt bewusst auf dem gekappten `limbo_motes`
  (Teil-4-Zustand unangetastet, kein `limbo_*`-JSON berührt).

**Referenz-Audit der übrigen `limbo_motes`-Erwähnungen** (rg über `src/main/java`):
`S2CQuasarPayload.LIMBO_MOTES` wird nur von `LimboAmbience:306` gespawnt (Welt-Ambience,
korrekt gekappt); `HearthAuraService` und `HeraldFerrymanFxRows` erwähnen den Emitter nur
in Javadoc-Historien (keine Spawns); `FxDevCommands` führt ihn in der generischen
`/eclipsefx`-Vorschlagsliste (zählt per Teil-4-§1.1-Regel nicht als Referenz).
**Kein weiteres System nutzt `limbo_motes` screen-nah** — der Death-Screen war der
einzige Betroffene.

**Gates:** `python3 -m json.tool death_ash.json` OK;
`./gradlew compileJava processResources --offline -q` → exit 0 (grün); in
`build/resources/main/.../death_ash.json` verifiziert: α 0.28/0.28, wind 0.0006,
drag 0.96. Nicht committet.

## 8. E3 ausgeführt: Haus-Wisps Rand-Alpha 0

Systemischer Fix der in §6/E3 dokumentierten Restschuld: die beiden 8×8-Haus-Wisps
trugen auf dem äußersten Pixelring Alpha bis **26/255** (Kantenmitten; Ecken 0) —
jedes gestreckte Quad zeichnete dadurch seine eigene Geometrie-Kante als feine
Box-Kontur, und die 0-Ecken lasen als Plus-Clipping (F-107-Signatur).

**Inventar (rg über `quasar/emitters/*.json`, Feld `sprite`):** genau zwei
Haus-Wisp-Texturen, zusammen von **89 Emittern** referenziert —
`purple_wisp.png` (**58** Emitter) und `wisp_white.png` (**31** Emitter). Beide 8×8,
identische Alpha-Ebene (radiale Ringe 189/139/108/83/62/26/11), RGB als 7-stufiger
radialer Ramp (Lavendel 231/190/255 → 200/128/255 bzw. Weiß 255 → 220), 1:1 an die
Alpha-Stufen gekoppelt. Übrige Emitter-Sprites sind KEINE Haus-Wisps und blieben
unangetastet: die dedizierten Soft-Texturen (`limbo_fog_soft`, `limbo_fogbank_soft`,
`storm_godfinger_shaft`, `dust_wall_soft`, `flash_soft`, `ring_soft` — Rand bereits
0–2), die bewusst harten Glitch-Texturen (`static_4x4`, `border_glitch` — voll
deckender Rand ist dort Absicht) und `gui/heart_full` (§3.9-Empfehlung, separat).
Nebennutzer der Wisps: Vanilla-Partikel `particles/purple_wisp.json` (Atlas) und die
Photon-Generatoren in `tools/photon/` referenzieren nur den UV-normalisierten Pfad —
beides ist auflösungsagnostisch, kein `.mcmeta` vorhanden.

**Fix: NEU `tools/art/gen_house_wisps.py`** (deterministisch, Original-8×8-Pixeldaten
als Konstanten eingebacken und vor dem Überschreiben byte-genau gegen die Shipped-PNGs
verifiziert). Erzeugt beide Wisps als **16×16**:

- **Interieur** (inneres 6×6 des Originals): exakte 2×2-Block-Replikation — gleiche
  Farbtöne, gleiche Ringstufen, Peak-Alpha 189 exakt erhalten, Interieur-Delta 0.
- **Äußerster 16er-Ring:** EXAKT Alpha 0 → die Quad-Kante zeichnet nie wieder.
- **Fringe-Ring dazwischen** (Fußabdruck des alten 8×8-Randrings): radialer
  Piecewise-Linear-Falloff aus dem Original-Profil, global so skaliert, dass die
  Randzonen-Alpha-Masse erhalten bleibt (Faktor auf ≤ 1 gekappt; effektiv 1.0).
  Werteverlauf 1→8→17→29→38→42 zur Kantenmitte — die Ecken faden jetzt zirkulär
  statt als Plus zu clippen, und die Rest-Stufe (≤ 42, vor Tint-Multiplikation) liegt
  einen 16tel-Texel INNERHALB der Quad-Kante bei halber alter Texel-Pitch.

**Vorher/Nachher:**

| Textur | vorher | Rand-α (min–max) | Peak | α-Masse | nachher | Rand-α | Peak | α-Masse (8×8-Einheiten) | Interieur-Max-Delta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `purple_wisp.png` | 8×8 | 0–26 | 189 | 3860 | 16×16 | **0–0** | 189 | 3834 (−0.67 %) | **0** |
| `wisp_white.png` | 8×8 | 0–26 | 189 | 3860 | 16×16 | **0–0** | 189 | 3834 (−0.67 %) | **0** |

**Gates:** (a) Doppellauf byte-identisch (`md5sum -c` über beide PNGs nach zweitem
Lauf: OK); (b) Randring überall 0, Interieur-Max-Kanal-Delta 0 ≤ 8 (Messung im
Generator: 2×2-Mittel der 16×16-Subtexel gegen die eingebackenen Originalwerte, α und
RGB); (c) `./gradlew processResources --offline -q` → exit 0 (grün), PNG-Hashes in
`build/resources/main/.../particle/` identisch mit `src`. Keine Emitter-JSONs
geändert, keine anderen Texturen berührt, nicht committet.

**Restnotiz:** eine vollständige Zirkularisierung (Alpha-Träger als Inkreis) war
NICHT möglich, ohne die interioren Diagonal-Texel (α 26 bei d≈3.54 von 4.0) zu
verändern — die Vorgabe „Interieur visuell identisch" hat Vorrang. Die verbleibende
Fringe-Stufe ≤ 42 ist bei typischen Emitter-Tint-Alphas (≤ 0.35) ≤ ~6 % Endkontrast
und liegt nicht mehr auf der Quad-Kante.
