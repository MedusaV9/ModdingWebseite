package dev.projecteclipse.eclipse.entity.wizard;

import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.structure.WizardObservatory;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.phys.AABB;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Presence/respawn service of Orin the Sun-Reader (W4-WIZARD): keeps exactly ONE live
 * hermit inside the mountain observatory whenever the wizard is enabled, and none when
 * he is not.
 *
 * <p><b>Ensure rules</b> (checked every {@value #ENSURE_INTERVAL_TICKS}t on the server
 * tick and once immediately after the observatory build completes):</p>
 * <ol>
 *   <li>The observatory must be built ({@link WizardObservatory#isBuilt}) and a home
 *       position stamped in {@link WizardData} — no hut, no hermit.</li>
 *   <li>{@link WizardData#isEnabled()} must be true; disabling ({@code /dev wizard
 *       disable}) despawns any live Orin and blocks the respawn path (the structure
 *       stays, IDEA-19 §3 "toggleable").</li>
 *   <li>After a death, the respawn waits for the NEXT overworld day
 *       ({@link WizardData#lastDeathDay()} — "respawns next day at his hut").</li>
 *   <li>The home chunk's <i>entity section</i> must actually be loaded before a
 *       missing-UUID verdict counts (Deckhand bug-4a lesson: entity sections load
 *       asynchronously after block chunks; trusting an early {@code getEntity(uuid) ==
 *       null} spawns duplicates). A near-home entity scan additionally re-adopts an
 *       Orin whose UUID record was lost.</li>
 * </ol>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WizardService {
    /** Cadence of the presence check (cheap: a few SavedData reads + one uuid lookup). */
    private static final int ENSURE_INTERVAL_TICKS = 100;
    /** Radius of the lost-UUID re-adoption scan around the home position. */
    private static final double ADOPT_SCAN_RADIUS = 32.0D;

    private WizardService() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % ENSURE_INTERVAL_TICKS != 0) {
            return;
        }
        ensureWizard(server.overworld());
    }

    /**
     * The single presence pass — also called directly by {@code WizardObservatory} when
     * the build completes and by the dev commands after an enable. Safe to call any
     * time on the server thread; every path is guarded and idempotent.
     */
    public static void ensureWizard(ServerLevel overworld) {
        if (!WizardEntities.WIZARD_ORIN.isBound()) {
            return; // Registrar not wired yet (docs/plans_v3/wiring/W4-WIZARD_wiring.md).
        }
        WizardData data = WizardData.get(overworld);
        BlockPos home = data.homePos();
        if (home == null || !WizardObservatory.isBuilt(overworld)) {
            return; // No hut, no hermit.
        }
        if (!data.isEnabled()) {
            despawnWizard(overworld);
            return;
        }
        if (data.lastDeathDay() >= 0 && currentDay(overworld) <= data.lastDeathDay()) {
            return; // He returns with the next dawn, not the same one that saw him fall.
        }
        if (!overworld.areEntitiesLoaded(ChunkPos.asLong(home))) {
            return; // Entity sections still streaming in — never judge a missing UUID now.
        }
        WizardOrinEntity live = resolve(overworld, data.wizardUuid());
        if (live != null && live.isAlive()) {
            return;
        }
        // Lost record (state reset, manual /summon adoption): scan before spawning.
        List<WizardOrinEntity> nearby = overworld.getEntitiesOfClass(WizardOrinEntity.class,
                new AABB(home).inflate(ADOPT_SCAN_RADIUS), WizardOrinEntity::isAlive);
        if (!nearby.isEmpty()) {
            WizardOrinEntity adopted = nearby.get(0);
            data.setWizardUuid(adopted.getUUID());
            adopted.initAsNpc(home);
            EclipseMod.LOGGER.info("WizardService adopted a live Orin ({}) near home {}",
                    adopted.getUUID(), home.toShortString());
            return;
        }
        spawnWizard(overworld, data, home);
    }

    /** Spawns Orin at his hut's home position with the NPC dressing + arrival sparkle. */
    private static void spawnWizard(ServerLevel overworld, WizardData data, BlockPos home) {
        WizardOrinEntity orin = WizardEntities.WIZARD_ORIN.get().create(overworld);
        if (orin == null) {
            EclipseMod.LOGGER.error("WizardService failed to instantiate eclipse:wizard_orin");
            return;
        }
        orin.moveTo(home.getX() + 0.5D, home.getY(), home.getZ() + 0.5D,
                overworld.getRandom().nextFloat() * 360.0F, 0.0F);
        orin.finalizeSpawn(overworld, overworld.getCurrentDifficultyAt(home),
                MobSpawnType.STRUCTURE, null);
        orin.initAsNpc(home);
        if (!overworld.addFreshEntity(orin)) {
            EclipseMod.LOGGER.warn("WizardService could not add Orin at {}", home.toShortString());
            return;
        }
        data.setWizardUuid(orin.getUUID());
        data.setLastDeathDay(-1L);
        overworld.sendParticles(ParticleTypes.END_ROD, orin.getX(), orin.getY() + 1.0D, orin.getZ(),
                24, 0.4D, 0.9D, 0.4D, 0.05D);
        overworld.playSound(null, home, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.NEUTRAL, 1.0F, 1.2F);
        EclipseMod.LOGGER.info("WizardService spawned Orin at {} ({})",
                home.toShortString(), orin.getUUID());
    }

    /** Discards any tracked live Orin (disable path); keeps the ledger + structure. */
    public static void despawnWizard(ServerLevel overworld) {
        WizardData data = WizardData.get(overworld);
        WizardOrinEntity live = resolve(overworld, data.wizardUuid());
        if (live != null) {
            overworld.sendParticles(ParticleTypes.POOF, live.getX(), live.getY() + 1.0D, live.getZ(),
                    12, 0.3D, 0.6D, 0.3D, 0.02D);
            live.discard();
            EclipseMod.LOGGER.info("WizardService despawned Orin (disabled)");
        }
        data.setWizardUuid(null);
    }

    /** Death bookkeeping — called from {@link WizardOrinEntity#die}. */
    public static void onWizardDied(ServerLevel level, WizardOrinEntity orin) {
        ServerLevel overworld = level.getServer().overworld();
        WizardData data = WizardData.get(overworld);
        if (orin.getUUID().equals(data.wizardUuid())) {
            data.setWizardUuid(null);
        }
        data.setLastDeathDay(currentDay(overworld));
        EclipseMod.LOGGER.info("WizardService: Orin fell on day {} — respawn on day {}",
                data.lastDeathDay(), data.lastDeathDay() + 1);
    }

    /** Erase-sweep hygiene — called by {@code WizardObservatory} when its site is erased. */
    public static void onObservatoryErased(ServerLevel overworld) {
        despawnWizard(overworld);
        WizardData.get(overworld).setHomePos(null);
    }

    /** The live Orin (if the tracked UUID resolves in loaded entity sections). */
    @Nullable
    public static WizardOrinEntity resolve(ServerLevel overworld, @Nullable UUID uuid) {
        return uuid != null && overworld.getEntity(uuid) instanceof WizardOrinEntity orin
                ? orin : null;
    }

    private static long currentDay(ServerLevel overworld) {
        return overworld.getDayTime() / 24000L;
    }
}
