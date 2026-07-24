package dev.projecteclipse.eclipse.client.drama;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * W4-CEREMONY / IDEA-10 #2 — client half of the sneak-gesture glyphs: on an
 * {@code FX_GLYPH} event ({@code a} = glyph index), attach the matching Quasar emitter
 * ({@code eclipse:glyph_greet} / {@code glyph_danger} / {@code glyph_follow} — rising
 * wisps that hover above the head) to the nearest player for {@value #GLYPH_TICKS} ticks.
 * The attach/expire loop is the exact {@code client.ArmParticles} pattern
 * ({@link QuasarSpawner#ensureAttached}/{@link QuasarSpawner#removeAttached}); every spawn
 * rides the AMBIENT {@code FxBudget} channel, so {@code reducedFx} tier 0 silently drops
 * glyphs like every other ambient loop.
 *
 * <p>Entry point {@link #show} is dispatched from {@code FxPayloads.handleFxEvent} (the
 * one-line wiring ask in {@code W4-CEREMONY_wiring.md}); the payload carries a position,
 * not an entity id, so the emitter matches the nearest player exactly like the frozen
 * glide-trail events do.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GestureGlyphFx {
    /** Glyph display time (2 s). */
    private static final int GLYPH_TICKS = 40;
    /** How far the event position may be from a player to attach the glyph to them. */
    private static final double MATCH_RANGE_SQ = 8.0D * 8.0D;

    private static final ResourceLocation[] GLYPH_EMITTERS = {
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glyph_greet"),
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glyph_danger"),
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glyph_follow"),
    };

    private record ActiveGlyph(int entityId, ResourceLocation emitter) {}

    /** Live glyphs → client game time they expire at. Client thread only. */
    private static final Map<ActiveGlyph, Long> ACTIVE = new HashMap<>();

    private GestureGlyphFx() {}

    /** {@code FX_GLYPH} dispatch: pos = gesturing player, glyph = 0 greet / 1 danger / 2 follow. */
    public static void show(Vec3 pos, int glyph) {
        if (glyph < 0 || glyph >= GLYPH_EMITTERS.length) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        Player nearest = null;
        double bestDistSq = MATCH_RANGE_SQ;
        for (Player player : level.players()) {
            double distSq = player.distanceToSqr(pos);
            if (distSq < bestDistSq) {
                bestDistSq = distSq;
                nearest = player;
            }
        }
        if (nearest == null) {
            return;
        }
        ResourceLocation emitter = GLYPH_EMITTERS[glyph];
        // Restarting the expiry on a re-gesture keeps exactly one loop alive (ensureAttached
        // dedupes per (entity, emitter) key), so spam can never stack emitters.
        ACTIVE.put(new ActiveGlyph(nearest.getId(), emitter), level.getGameTime() + GLYPH_TICKS);
    }

    /** ArmParticles attach pattern: keep live glyph loops attached, detach expired ones. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (ACTIVE.isEmpty()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            ACTIVE.clear(); // QuasarSpawner clears the attached emitters on logout itself
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        long now = level.getGameTime();
        Iterator<Map.Entry<ActiveGlyph, Long>> iterator = ACTIVE.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<ActiveGlyph, Long> entry = iterator.next();
            ActiveGlyph glyph = entry.getKey();
            var entity = level.getEntity(glyph.entityId());
            if (entity == null || now >= entry.getValue()) {
                if (entity != null) {
                    QuasarSpawner.removeAttached(glyph.emitter(), entity);
                }
                iterator.remove();
                continue;
            }
            QuasarSpawner.ensureAttached(glyph.emitter(), entity);
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        ACTIVE.clear();
    }
}
