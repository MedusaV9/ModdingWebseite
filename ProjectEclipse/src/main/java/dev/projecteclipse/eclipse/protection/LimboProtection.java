package dev.projecteclipse.eclipse.protection;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.ferryman.ArenaFight;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.BucketItem;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.material.Fluids;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Limbo house rules (user decree): {@code eclipse:limbo} is a stage, not a build site and
 * not an arena. Sibling of {@link LandmarkProtection} / {@link SpawnProtectionRules} in
 * this package — a separate file per protected space keeps each owner's event surface
 * disjoint (the same reason {@code LandmarkProtection} is not folded into
 * {@code SanctumProtection}).
 *
 * <ul>
 *   <li><b>No terraforming</b> — {@link BlockEvent.BreakEvent} and
 *       {@link BlockEvent.EntityPlaceEvent} (which {@code EntityMultiPlaceEvent} extends,
 *       so doors/beds are covered) are cancelled in limbo, plus bucket fluid placement,
 *       which never reaches the place event. Mod-driven writes go through
 *       {@code Level.setBlock} and are untouched, so {@code GhostShipBuilder},
 *       {@code LimboSeascape}, {@code OarAnimator} and the {@code ShipLanterns} re-light
 *       keep working.</li>
 *   <li><b>No PvP</b> — {@link LivingIncomingDamageEvent} is cancelled when the source's
 *       owning entity is another player ({@code getEntity()}, so arrows/splash potions
 *       resolve to the shooter, not the projectile).</li>
 * </ul>
 *
 * <p>Three bypasses, in order of the check:</p>
 * <ol>
 *   <li>{@link DevMode#isExempt} — the PROGFIX #5 law: ops and creative players obey
 *       until they toggle {@code /devmode}. The ONLY way to build in limbo.</li>
 *   <li>{@code /dev limbo pvp on} — the persisted {@link Data#pvpAllowed} operator
 *       toggle ({@code DevLimboCommands}); PvP only.</li>
 *   <li>An ACTIVE boss fight ({@link #bossFightActive}) — the Ferryman afloat in limbo
 *       (the legacy on-ship fight) or the arena crossing's live fight flag; PvP only.
 *       Deliberately narrow: an armed-but-not-started crossing gate is NOT a fight.</li>
 * </ol>
 *
 * <p>Denials answer with a localized action-bar line plus a muffled chime, rate-limited
 * per player to {@value #HINT_COOLDOWN_MILLIS} ms — a held left mouse button fires
 * {@code BreakEvent} many times a second and would otherwise strobe the action bar.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LimboProtection {
    /** Same violet as {@link SpawnProtectionRules}' hints — one protection voice. */
    private static final int HINT_COLOR = 0xB98CFF;
    /** Anti-spam window for the action-bar deny line (per player). */
    private static final long HINT_COOLDOWN_MILLIS = 2_000L;

    /** Last hint timestamp per player (server thread only, transient by design). */
    private static final Map<UUID, Long> HINT_COOLDOWNS = new HashMap<>();

    private LimboProtection() {}

    // ------------------------------------------------------------------ public surface

    /** Whether PvP is currently permitted in limbo by the operator toggle. */
    public static boolean isPvpAllowed(MinecraftServer server) {
        return Data.get(server).pvpAllowed();
    }

    /** Sets the persisted {@code /dev limbo pvp} toggle. */
    public static void setPvpAllowed(MinecraftServer server, boolean allowed) {
        Data.get(server).setPvpAllowed(allowed);
    }

    /**
     * Whether a boss fight the limbo crowd belongs to is REALLY running: a living
     * Ferryman on the ghost ship (legacy limbo fight, the same probe
     * {@code ShipLanterns} uses to protect its counter) or the arena crossing's
     * persisted fight flag. An armed gate, the arrival flyaround and the transformation
     * beat all report {@code false}.
     */
    public static boolean bossFightActive(ServerLevel limbo) {
        if (!limbo.getEntities(EclipseEntities.FERRYMAN.get(), FerrymanEntity::isAlive).isEmpty()) {
            return true;
        }
        MinecraftServer server = limbo.getServer();
        return server != null && ArenaFight.isFightRunning(server);
    }

    // ------------------------------------------------------------------ no terraforming

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !isLimbo(level)) {
            return;
        }
        Player player = event.getPlayer();
        if (DevMode.isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        hint(player, "message.eclipse.limbo.no_break");
    }

    /** Covers {@code EntityMultiPlaceEvent} too (it extends this event). */
    @SubscribeEvent
    public static void onBlockPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !isLimbo(level)) {
            return;
        }
        Entity entity = event.getEntity();
        if (entity instanceof Player player && DevMode.isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof Player player) {
            hint(player, "message.eclipse.limbo.no_place");
        }
    }

    /**
     * Buckets empty through {@code BucketItem} rather than {@code BlockItem.place}, so
     * they never reach {@link BlockEvent.EntityPlaceEvent} — the same interact-level
     * guard {@link SpawnProtectionRules} uses for the sanctum.
     */
    @SubscribeEvent
    public static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !isLimbo(level)
                || !(event.getEntity() instanceof ServerPlayer player)
                || !isFluidPlacement(event.getItemStack())
                || DevMode.isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        hint(player, "message.eclipse.limbo.no_place");
    }

    // ------------------------------------------------------------------ no PvP

    @SubscribeEvent
    public static void onLivingIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim) || !isLimbo(victim.serverLevel())) {
            return;
        }
        // getEntity() is the OWNING entity: the shooter behind an arrow, the thrower
        // behind a splash potion. getDirectEntity() would only ever see the projectile.
        if (!(event.getSource().getEntity() instanceof ServerPlayer attacker) || attacker == victim) {
            return;
        }
        ServerLevel limbo = victim.serverLevel();
        if (isPvpAllowed(victim.server) || bossFightActive(limbo)
                || DevMode.isExempt(attacker) || DevMode.isExempt(victim)) {
            return;
        }
        event.setCanceled(true);
        hint(attacker, "message.eclipse.limbo.no_pvp");
    }

    // ------------------------------------------------------------------ helpers

    private static boolean isLimbo(ServerLevel level) {
        return level.dimension().equals(LimboDimension.LIMBO);
    }

    private static boolean isFluidPlacement(ItemStack stack) {
        if (stack.getItem() instanceof BucketItem bucket) {
            return bucket.content != Fluids.EMPTY;
        }
        return stack.is(Items.WATER_BUCKET) || stack.is(Items.LAVA_BUCKET)
                || stack.is(Items.POWDER_SNOW_BUCKET);
    }

    /**
     * Action bar + muffled chime, at most once every {@value #HINT_COOLDOWN_MILLIS} ms
     * per player: block breaking re-fires the event every few ticks while the button is
     * held, and a strobing action bar reads as a bug rather than as a rule.
     */
    private static void hint(@Nullable Player player, String key) {
        if (!(player instanceof ServerPlayer serverPlayer)) {
            return;
        }
        long now = System.currentTimeMillis();
        Long last = HINT_COOLDOWNS.get(serverPlayer.getUUID());
        if (last != null && now - last < HINT_COOLDOWN_MILLIS) {
            return;
        }
        HINT_COOLDOWNS.put(serverPlayer.getUUID(), now);
        serverPlayer.displayClientMessage(
                ServerLang.tr(serverPlayer, key).withColor(HINT_COLOR), true);
        serverPlayer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.7F, 0.6F);
    }

    // ------------------------------------------------------------------ lifecycle hygiene

    @SubscribeEvent
    public static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        HINT_COOLDOWNS.remove(event.getEntity().getUUID());
    }

    /** Statics must never leak into the next world a singleplayer client opens. */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        HINT_COOLDOWNS.clear();
    }

    /**
     * Persisted limbo rule state ({@code eclipse_limbo_rules.dat}). Only the PvP override
     * lives here — building is devmode-only by decree and has no operator switch.
     */
    public static final class Data extends SavedData {
        public static final String DATA_NAME = "eclipse_limbo_rules";

        private static final String TAG_PVP_ALLOWED = "pvpAllowed";

        private boolean pvpAllowed;

        public Data() {}

        public static Data get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_NAME,
                    new SavedData.Factory<>(Data::new, Data::load));
        }

        public static Data load(CompoundTag tag, HolderLookup.Provider registries) {
            Data data = new Data();
            data.pvpAllowed = tag.getBoolean(TAG_PVP_ALLOWED);
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putBoolean(TAG_PVP_ALLOWED, this.pvpAllowed);
            return tag;
        }

        boolean pvpAllowed() {
            return this.pvpAllowed;
        }

        void setPvpAllowed(boolean allowed) {
            if (this.pvpAllowed != allowed) {
                this.pvpAllowed = allowed;
                setDirty();
            }
        }
    }
}
