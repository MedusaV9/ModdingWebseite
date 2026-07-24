package dev.projecteclipse.eclipse.veilfx;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.fml.ModList;

/**
 * D12 — optional bridge to the <b>Photon</b> VFX mod (Modrinth {@code photon-editor},
 * Low Drag MC): when the {@code photon} mod is installed on the client, 1–2 flagship
 * moments get an EXTRA editor-authored Photon effect layered over the existing Quasar
 * visuals; without Photon (or without the effect assets) every call is a silent no-op and
 * the shipped Quasar/vanilla path is exactly what it was before this class existed.
 *
 * <p><b>Deliberately reflection-based, no compile-time dependency.</b> The Modrinth maven
 * coordinate {@code maven.modrinth:photon-editor:mc1.21.1-2.1.5-neoforge} verifiably
 * resolves (pom + jar HTTP 200, checked 2026-07), but this repo's build must stay buildable
 * with zero new remote dependencies, so the three touched API points are reflected against
 * signatures verified from the published 2.1.5 jar (javap):</p>
 * <ul>
 *   <li>{@code FXHelper.getFX(ResourceLocation)} — loads/caches an {@code FX} from
 *       {@code assets/<ns>/fx/<path>.fx} (compressed-NBT files authored in Photon's
 *       in-game editor);</li>
 *   <li>{@code new BlockEffectExecutor(FX, Level, BlockPos)} + {@code start()} — plays the
 *       effect anchored at a block position.</li>
 * </ul>
 *
 * <p><b>Guards</b> (all must pass, in order): {@code ModList.get().isLoaded("photon")}
 * (checked once, the mod set is frozen after load), the {@code photonFx} client toggle,
 * NOT {@code reducedFx}, reflection handles resolved. A reflection failure disables the
 * bridge for the session (one WARN); a missing {@code .fx} asset skips that effect id for
 * the session (one INFO) — Photon owners author the assets in-game via {@code /photon fx}
 * and ship them in a resource pack, see docs/BUNDLING.md. Photon draws through its own
 * renderer (not Veil/Quasar), so spawns are NOT charged to {@link FxBudget} — the
 * {@code reducedFx} gate is the budget-equivalent kill switch here.</p>
 *
 * <p>Effect ids consumed today (drop-in {@code assets/eclipse/fx/<id>.fx}):
 * {@link #ALTAR_LEVELUP} (altar milestone level-up, layered over the
 * {@code altar_levelup_ring} Quasar cue) and {@link #EXPANSION_RIFT_GLOW} (expansion
 * structure-drop rift open, layered over {@code RiftFx}'s tear).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class PhotonBridge {
    /** Extra glow/burst for the altar milestone level-up moment. */
    public static final ResourceLocation ALTAR_LEVELUP = fx("altar_levelup");
    /** Extra glow for expansion (structure-drop) rift tears. */
    public static final ResourceLocation EXPANSION_RIFT_GLOW = fx("expansion_rift_glow");

    private static final int UNRESOLVED = 0;
    private static final int READY = 1;
    private static final int DISABLED = 2;

    private static volatile int state = UNRESOLVED;
    private static Method getFxMethod;
    private static Constructor<?> blockExecutorCtor;
    private static Method startMethod;

    /** Effect ids whose {@code .fx} asset failed to load — skipped for the session. */
    private static final Set<ResourceLocation> MISSING_FX = new HashSet<>();

    private PhotonBridge() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    /** Whether the Photon layer may run right now (mod present + toggles). Cheap. */
    public static boolean available() {
        return state != DISABLED
                && ModList.get().isLoaded("photon")
                && EclipseClientConfig.photonFx()
                && !EclipseClientConfig.reducedFx();
    }

    /**
     * {@code S2CQuasarPayload} seam (called from {@code EclipsePayloads.handleQuasar} on the
     * client main thread): layers the Photon enhancement over cues that have one. Always
     * returns without consuming the payload — the Quasar path still runs.
     */
    public static void enhanceQuasarCue(ResourceLocation emitterId, Vec3 pos) {
        if (S2CQuasarPayload.ALTAR_LEVELUP_RING.equals(emitterId)) {
            spawn(ALTAR_LEVELUP, pos);
        }
    }

    /**
     * Plays the Photon effect {@code fxId} anchored at {@code pos}'s block position.
     * @return {@code true} only when a Photon effect actually started; every failure path
     *         (photon absent, toggles off, missing asset, reflection breakage) is a no-op.
     */
    public static boolean spawn(ResourceLocation fxId, Vec3 pos) {
        if (!available() || MISSING_FX.contains(fxId)) {
            return false;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || !resolve()) {
            return false;
        }
        try {
            Object fxObject = getFxMethod.invoke(null, fxId);
            if (fxObject == null) {
                missing(fxId);
                return false;
            }
            Object executor = blockExecutorCtor.newInstance(fxObject, level, BlockPos.containing(pos));
            startMethod.invoke(executor);
            return true;
        } catch (Throwable t) {
            // Asset-load failures surface here as InvocationTargetExceptions; executor
            // breakage would too. Either way: skip the id for the session, one WARN.
            if (MISSING_FX.add(fxId)) {
                EclipseMod.LOGGER.warn("Photon effect {} failed; skipping it for this session", fxId, t);
            }
            return false;
        }
    }

    /** Lazily resolves the reflection handles once. @return {@code true} when READY. */
    private static boolean resolve() {
        if (state == READY) {
            return true;
        }
        if (state == DISABLED) {
            return false;
        }
        synchronized (PhotonBridge.class) {
            if (state != UNRESOLVED) {
                return state == READY;
            }
            try {
                Class<?> fxHelper = Class.forName("com.lowdragmc.photon.client.fx.FXHelper");
                Class<?> fxClass = Class.forName("com.lowdragmc.photon.client.fx.FX");
                Class<?> blockExecutor = Class.forName("com.lowdragmc.photon.client.fx.BlockEffectExecutor");
                getFxMethod = fxHelper.getMethod("getFX", ResourceLocation.class);
                blockExecutorCtor = blockExecutor.getConstructor(
                        fxClass, net.minecraft.world.level.Level.class, BlockPos.class);
                startMethod = blockExecutor.getMethod("start");
                state = READY;
                EclipseMod.LOGGER.info("Photon detected — flagship-effect enhancement layer active");
                return true;
            } catch (Throwable t) {
                disable(t);
                return false;
            }
        }
    }

    private static void missing(ResourceLocation fxId) {
        if (MISSING_FX.add(fxId)) {
            EclipseMod.LOGGER.info(
                    "Photon is loaded but assets/{}/fx/{}.fx is absent — cue stays Quasar-only "
                            + "(author it in Photon's editor, see docs/BUNDLING.md)",
                    fxId.getNamespace(), fxId.getPath());
        }
    }

    private static void disable(Throwable t) {
        if (state != DISABLED) {
            state = DISABLED;
            EclipseMod.LOGGER.warn(
                    "Photon bridge disabled for this session (API mismatch or load failure)", t);
        }
    }
}
