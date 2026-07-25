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
 */
public final class DisplayBrightnessFx {

    private DisplayBrightnessFx() {}

    /** Overrides the display's light to {@code block}/{@code sky} (0–15 each). */
    public static void set(Display display, int block, int sky) {
        CompoundTag tag = display.saveWithoutId(new CompoundTag());
        CompoundTag brightness = new CompoundTag();
        brightness.putInt("block", block);
        brightness.putInt("sky", sky);
        tag.put("brightness", brightness);
        display.load(tag);
    }

    /** Clears the override — the display resumes sampling light at its entity anchor. */
    public static void clear(Display display) {
        CompoundTag tag = display.saveWithoutId(new CompoundTag());
        tag.remove("brightness");
        display.load(tag);
    }
}
