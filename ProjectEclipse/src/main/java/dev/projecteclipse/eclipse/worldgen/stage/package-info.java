/**
 * World stage system (v2): the disc grows ring-by-ring at runtime.
 * {@link dev.projecteclipse.eclipse.worldgen.stage.WorldStageService} is the single stage
 * commit entry point (persist → chunkgen seam → payload → sweep);
 * {@link dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService} performs the
 * tick-budgeted annulus rewrite (angular sweep, erase mode, restart-resume cursor);
 * {@code FusionSequence} is the special stage 0 → 1 intro sweep where the main disc and
 * the eight player discs fuse into one.
 * Stage radii/triggers/structures come from {@code config/eclipse/stages.json}.
 */
package dev.projecteclipse.eclipse.worldgen.stage;
