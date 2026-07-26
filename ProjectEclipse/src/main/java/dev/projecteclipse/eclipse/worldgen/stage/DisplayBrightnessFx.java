package dev.projecteclipse.eclipse.worldgen.stage;

import net.minecraft.nbt.CompoundTag;
import net.minecraft.world.entity.Display;

/**
 * BD-STRUCT brightness-override craft for cinematic {@code BLOCK_DISPLAY} pieces.
 *
 * <p>Displays sample light at their (fixed, often grounded) ENTITY anchor, so a piece
 * bursting out of a luminous sky rift renders ground-dim unless it carries an explicit
 * brightness override — and a dissolving debris chunk cannot fade without one. The
 * override then ramps: full-bright at the rift mouth, stepped toward ambient mid-flight,
 * CLEARED on landing so the settled piece matches the real block it precedes.</p>
 *
 * <p><b>Transport</b>: {@code Display.setBrightnessOverride} is private and NOT
 * accesstransformer-opened — and a new AT line is unusable here, because the cached
 * moddev merged-jar only reflects AT changes after a gradle rerun (forbidden in this
 * lane). The override therefore rides the vanilla NBT seam: a full
 * {@code saveWithoutId}/{@code load} round-trip with the {@code brightness} compound
 * present (set) or stripped (clear — {@code Display.readAdditionalSaveData}'s else
 * branch nulls the override). Every other key round-trips to its current value, which
 * {@code SynchedEntityData} treats as a no-op — the only wire delta is the brightness
 * itself, and the in-flight transformation interpolation is untouched.</p>
 *
 * <p><b>Craft law</b>: brightness syncs UN-interpolated (it snaps). Callers must step it
 * in a few coarse stages (≤ 3 per piece life) and hide each step inside motion — never
 * per-tick "ramps". The round-trip costs one NBT save+load, so the same restraint keeps
 * it off the tick budget.</p>
 *
 * <p><b>{@code view_range} rides the same seam.</b> {@code Display.setViewRange} is
 * private too, and its default of {@code 1.0} means
 * {@code Display.shouldRenderAtSqrDistance} stops drawing the display past
 * {@code 1.0 × 64} blocks — less than half the 160-block entity-tracking horizon. Any
 * cinematic prop meant to be seen from across a clearing (rim monoliths, sky pieces)
 * must raise it explicitly; the value is multiplied by 64 to get the render distance in
 * blocks.</p>
 */
public final class DisplayBrightnessFx {

    private DisplayBrightnessFx() {}

    /** Overrides the display's light to {@code block}/{@code sky} (0–15 each). */
    public static void set(Display display, int block, int sky) {
        CompoundTag tag = display.saveWithoutId(new CompoundTag());
        putBrightness(tag, block, sky);
        display.load(tag);
    }

    /**
     * Light override AND render distance in ONE round-trip: {@code viewRange × 64} is the
     * distance (in blocks) past which the client stops drawing this display.
     */
    public static void set(Display display, int block, int sky, float viewRange) {
        CompoundTag tag = display.saveWithoutId(new CompoundTag());
        putBrightness(tag, block, sky);
        tag.putFloat("view_range", viewRange);
        display.load(tag);
    }

    /** Render distance only ({@code viewRange × 64} blocks); leaves the light override alone. */
    public static void setViewRange(Display display, float viewRange) {
        CompoundTag tag = display.saveWithoutId(new CompoundTag());
        tag.putFloat("view_range", viewRange);
        display.load(tag);
    }

    private static void putBrightness(CompoundTag tag, int block, int sky) {
        CompoundTag brightness = new CompoundTag();
        brightness.putInt("block", block);
        brightness.putInt("sky", sky);
        tag.put("brightness", brightness);
    }

    /** Clears the override — the display resumes sampling light at its entity anchor. */
    public static void clear(Display display) {
        CompoundTag tag = display.saveWithoutId(new CompoundTag());
        tag.remove("brightness");
        display.load(tag);
    }
}
