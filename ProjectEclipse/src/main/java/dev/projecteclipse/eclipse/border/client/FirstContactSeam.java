package dev.projecteclipse.eclipse.border.client;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;

import javax.annotation.Nullable;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.AtmospherePhotonFxRows;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.multiplayer.ServerData;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.server.IntegratedServer;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.fml.loading.FMLPaths;

/**
 * NEWFX-D1 — <b>First-Contact Seam</b> (PLAN-NEWFX §2): the FIRST time this save's
 * camera closes within {@value #CONTACT_BLOCKS} blocks of the border ring (well before
 * the ~8-block {@code fxRange} datamosh patches exist), one floor-to-sky hairline of
 * static flickers at the ring bearing for ~2 s, sheds three drifting glitch shards and
 * vanishes — "the world has edges", said once, quietly.
 *
 * <p><b>Seam:</b> driven from {@link BorderFxRenderer#onClientTick} (the file that
 * already owns the per-tick ring math); this class holds the state so the renderer
 * stays a one-line call site. <b>Once per save:</b> a client-side latch keyed by level
 * id (singleplayer level name / multiplayer server address) persisted in
 * {@code config/eclipse/fx_latches.json} — the existing client config dir, the
 * {@code GoalConfig}/{@code EclipseConfig} directory law.</p>
 *
 * <p><b>Tech (plan row):</b> Photon one-shot {@code eclipse:border_first_contact} +
 * Quasar hairline, {@code Mode.LAYER} semantics spawned DIRECTLY through
 * {@link PhotonBridge#spawn}/{@link QuasarSpawner} — no cue crosses the wire, so no
 * registry row (see {@link AtmospherePhotonFxRows} for the package's lane table). The
 * three shard pops reuse the shipped {@code border_shard} asset on the border's own
 * 12 Hz-ish stagger (ticks 8/16/24 — quantized beats, GLITCH motion grammar §2).
 * <b>Budget:</b> BURST (hairline + shards ≤ 4 charges, once per save).
 * <b>reducedFx:</b> the moment is skipped AND deliberately NOT latched — a discovery
 * accent should still be discoverable after the player re-enables full FX; the
 * pushback patches teach the edge either way.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class FirstContactSeam {
    /** First-approach trigger distance to the ring (blocks) — plan-frozen. */
    static final double CONTACT_BLOCKS = 48.0D;
    /** Shipped blocky glitch-pop emitter (the {@link BorderFxRenderer} reseed asset). */
    private static final ResourceLocation BORDER_SHARD =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border_shard");
    /** Shard-shed beats after the hairline spawn (ticks) — snap cadence, not eased. */
    private static final int[] SHARD_BEATS = {8, 16, 24};
    /** Shards drift out of the hairline between knee and overhead height. */
    private static final double[] SHARD_HEIGHTS = {-1.0D, 1.5D, 4.0D};
    private static final String LATCH_FILE = "fx_latches.json";
    private static final String LATCH_KIND = "border_first_contact";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

    /** Latched level keys (lazy-loaded once per session; null = not loaded yet). */
    @Nullable
    private static Set<String> latched;
    /** Ring distance of the previous tick; NaN = no sample yet (fresh world/session). */
    private static double lastRingDist = Double.NaN;
    /** Live shard-shed schedule: countdowns in ticks, -1 = slot done (none pending). */
    private static final int[] shardCountdown = {-1, -1, -1};
    /** Anchor of the live hairline (shards shed along it); null = nothing pending. */
    @Nullable
    private static Vec3 hairlineAnchor;

    private FirstContactSeam() {}

    /**
     * Per-tick hook, called by {@link BorderFxRenderer#onClientTick} right after the ring
     * radius resolves (BEFORE the fxRange early-out — first contact happens far outside
     * it). {@code radius <= 0} means no ring in this dimension.
     */
    static void tick(ClientLevel level, LocalPlayer player, double radius) {
        tickShards();
        if (radius <= 0.0D) {
            lastRingDist = Double.NaN;
            return;
        }
        double dx = player.getX() - ClientStateCache.borderCenterX;
        double dz = player.getZ() - ClientStateCache.borderCenterZ;
        double dist = Math.sqrt(dx * dx + dz * dz);
        double ringDist = Math.abs(radius - dist);
        double previous = lastRingDist;
        lastRingDist = ringDist;
        if (ringDist > CONTACT_BLOCKS || (!Double.isNaN(previous) && previous <= CONTACT_BLOCKS)) {
            return; // not a fresh crossing of the contact band
        }
        // Skip-not-latch under reducedFx (plan row) — and skip silently without a level key
        // (realms/unknown connections): never risk replaying every session.
        if (EclipseClientConfig.reducedFx()) {
            return;
        }
        String key = levelKey();
        if (key == null || isLatched(key)) {
            return;
        }
        latch(key);
        play(level, player, radius, dist > 1.0E-4D ? dx / dist : 1.0D,
                dist > 1.0E-4D ? dz / dist : 0.0D);
    }

    /** Disconnect reset ({@link BorderFxRenderer}'s no-level branch): drop per-world state. */
    static void reset() {
        lastRingDist = Double.NaN;
        hairlineAnchor = null;
        shardCountdown[0] = -1;
        shardCountdown[1] = -1;
        shardCountdown[2] = -1;
    }

    // ------------------------------------------------------------------ the moment

    /**
     * The hairline: Photon leg layered over the Quasar column at the nearest ring point,
     * ground-anchored (the asset owns the floor-to-sky read). One quiet border-glitch
     * blip carries it — a sliver, not a sting (§0 "Quiet Eclipse").
     */
    private static void play(ClientLevel level, LocalPlayer player, double radius,
            double dirX, double dirZ) {
        Vec3 anchor = new Vec3(ClientStateCache.borderCenterX + dirX * radius,
                player.getEyeY() - 1.5D,
                ClientStateCache.borderCenterZ + dirZ * radius);
        // Full guard chain inside the bridge (mod present, toggles, executor cap).
        PhotonBridge.spawn(AtmospherePhotonFxRows.FX_BORDER_FIRST_CONTACT, anchor);
        // LAYER law: the Quasar hairline always plays (it IS the photon-less baseline).
        QuasarSpawner.spawn(AtmospherePhotonFxRows.QUASAR_FIRST_CONTACT_HAIRLINE, anchor,
                FxBudget.Channel.BURST);
        hairlineAnchor = anchor;
        shardCountdown[0] = SHARD_BEATS[0];
        shardCountdown[1] = SHARD_BEATS[1];
        shardCountdown[2] = SHARD_BEATS[2];
        level.playLocalSound(BlockPos.containing(anchor),
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.AMBIENT,
                0.5F, 0.85F, false);
    }

    /** The three staggered shard pops shed off the live hairline (snap beats 8/16/24). */
    private static void tickShards() {
        Vec3 anchor = hairlineAnchor;
        if (anchor == null) {
            return;
        }
        boolean anyPending = false;
        for (int i = 0; i < shardCountdown.length; i++) {
            if (shardCountdown[i] < 0) {
                continue;
            }
            if (--shardCountdown[i] == 0) {
                shardCountdown[i] = -1;
                QuasarSpawner.spawn(BORDER_SHARD,
                        anchor.add(0.0D, SHARD_HEIGHTS[i] + 1.5D, 0.0D),
                        FxBudget.Channel.BURST);
            } else {
                anyPending = true;
            }
        }
        if (!anyPending) {
            hairlineAnchor = null;
        }
    }

    // ------------------------------------------------------------------ per-save latch

    /**
     * Stable per-save key: the singleplayer level name or the multiplayer server address.
     * {@code null} when neither resolves (unknown transport) — caller skips silently.
     */
    @Nullable
    private static String levelKey() {
        Minecraft minecraft = Minecraft.getInstance();
        IntegratedServer singleplayer = minecraft.getSingleplayerServer();
        if (singleplayer != null) {
            return "sp:" + singleplayer.getWorldData().getLevelName();
        }
        ServerData server = minecraft.getCurrentServer();
        return server != null ? "mp:" + server.ip : null;
    }

    private static boolean isLatched(String key) {
        if (latched == null) {
            latched = load();
        }
        return latched.contains(key);
    }

    /** Marks the key and persists immediately (a crash must not replay the moment). */
    private static void latch(String key) {
        if (latched == null) {
            latched = load();
        }
        if (!latched.add(key)) {
            return;
        }
        try {
            Path file = latchFile();
            Files.createDirectories(file.getParent());
            JsonObject root = readRoot(file);
            JsonArray array = new JsonArray();
            for (String entry : latched) {
                array.add(entry);
            }
            root.add(LATCH_KIND, array);
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
        } catch (IOException e) {
            // Non-fatal: the in-memory latch still holds for this session.
            EclipseMod.LOGGER.warn("FirstContactSeam: could not persist fx latch", e);
        }
    }

    private static Set<String> load() {
        Set<String> keys = new HashSet<>();
        try {
            JsonObject root = readRoot(latchFile());
            JsonElement kind = root.get(LATCH_KIND);
            if (kind != null && kind.isJsonArray()) {
                for (JsonElement entry : kind.getAsJsonArray()) {
                    if (entry.isJsonPrimitive()) {
                        keys.add(entry.getAsString());
                    }
                }
            }
        } catch (Exception e) {
            // Corrupt/unreadable latch file: worst case the hairline replays once.
            EclipseMod.LOGGER.warn("FirstContactSeam: could not read fx latch file", e);
        }
        return keys;
    }

    /** Whole-file read that tolerates a missing file (first run) and foreign latch kinds. */
    private static JsonObject readRoot(Path file) throws IOException {
        if (!Files.isRegularFile(file)) {
            return new JsonObject();
        }
        JsonElement parsed = GSON.fromJson(Files.readString(file, StandardCharsets.UTF_8),
                JsonElement.class);
        return parsed != null && parsed.isJsonObject() ? parsed.getAsJsonObject() : new JsonObject();
    }

    private static Path latchFile() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve(LATCH_FILE);
    }
}
