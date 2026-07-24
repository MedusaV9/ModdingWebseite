package dev.projecteclipse.eclipse.lives;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.contracts.ContractService;
import dev.projecteclipse.eclipse.contracts.ContractState;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.skills.XpGates;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * D4 heart theft: the OUT-OF-EVENT PvP kill economy. The killer steals one permanent Leben
 * from the victim (the {@code LifecycleEvents.onLivingDeath} transfer routed through
 * {@link #evaluate}) — but ONLY when no active REAL contract window covers the kill (the
 * contract pair resolves through the D3 contract economy instead; non-pair kills during a
 * window remain normal steals, the wrong-kill Blutschuld already punishes the hunter case).
 *
 * <p><b>Safeguards</b> ({@code config/eclipse/hearts.json}, {@code heartTheft} block):</p>
 * <ul>
 *   <li><b>Pair cooldown</b> (default {@code cooldownMinutes} 30, either direction,
 *       persisted in {@code data/eclipse_heart_theft.dat}): within cooldown the victim
 *       still dies but NO Leben moves in either direction — no farming the same victim.</li>
 *   <li><b>Victim floor</b> ({@code floorLives} 1): a victim at the floor loses NOTHING to
 *       a PvP kill (and the killer gains nothing) — murder can never ghost/ban a player
 *       outside events. PvE/environment deaths keep the normal 0 → ban flow untouched.</li>
 *   <li><b>Ghost/spectator exceptions</b>: banned "ghost players" (either side) and
 *       spectators never steal or get stolen from.</li>
 *   <li><b>Limbo/pre-event/event-dimension exceptions</b>: no theft before the start
 *       event and none inside limbo, the minigame arenas or the xbox worlds
 *       ({@code XpGates.isEventDimension}, the D2 predicate).</li>
 * </ul>
 *
 * <p><b>Ceremony</b> ({@link #celebrate}): boss-style title for killer and victim, a global
 * named announce ("X hat Y ein Leben gestohlen"), deep bell + the {@code theft.steal} heart
 * pulse, a camera shake for everyone, and the purple-heart drift via the existing
 * {@code eclipse:heart_burst} Quasar emitter at the victim's corpse. The victim's own loss
 * burst still rides the {@code PENDING_HEART_LOSSES} respawn handoff in
 * {@code LifecycleEvents}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HeartTheftService {

    /** Why a PvP kill did or did not steal a Leben. */
    public enum Verdict {
        /** Move one Leben victim → killer (umbral-blade bonus still applies, capped). */
        STEAL(false),
        /** {@code heartTheft.enabled=false} (config or {@code /dev contract theft off}). */
        NO_STEAL_DISABLED(false),
        /** Killer or victim is an event-banned ghost player. */
        NO_STEAL_GHOST(false),
        /** Killer or victim is a spectator. */
        NO_STEAL_SPECTATOR(false),
        /** The start event has not completed yet (pre-event lobby/limbo phase). */
        NO_STEAL_PRE_EVENT(false),
        /** Limbo / minigame arena / xbox world — theft is off in every event dimension. */
        NO_STEAL_EVENT_DIMENSION(false),
        /** Killer and victim are the pair of an ACTIVE REAL contract window (D3 economy). */
        NO_STEAL_CONTRACT_PAIR(false),
        /** Victim sits at the Leben floor: NOTHING moves — theft can never ghost anyone. */
        NO_STEAL_FLOOR(true),
        /** The pair traded a steal within the cooldown: NOTHING moves in either direction. */
        NO_STEAL_COOLDOWN(true);

        private final boolean freezesDeathLoss;

        Verdict(boolean freezesDeathLoss) {
            this.freezesDeathLoss = freezesDeathLoss;
        }

        public boolean steals() {
            return this == STEAL;
        }

        /**
         * Whether even the victim's NORMAL death loss is suppressed (anti-farm + the
         * never-ghost-from-theft law). Only floor and cooldown freeze the loss; every
         * other exception keeps the standard death economy and merely denies the gain.
         */
        public boolean freezesDeathLoss() {
            return freezesDeathLoss;
        }
    }

    /** Immutable {@code heartTheft} config snapshot. */
    public record Values(boolean enabled, int cooldownMinutes, int floorLives, boolean ceremony) {

        public long cooldownMillis() {
            return cooldownMinutes * 60_000L;
        }
    }

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "hearts.json";
    private static final float SHAKE_STRENGTH = 0.35F;
    private static final int SHAKE_TICKS = 16;
    private static final double DRIFT_FX_RANGE = 64.0D;

    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();
    private static volatile Values values;

    private HeartTheftService() {}

    // ================================================================== lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("hearts", HeartTheftService::reload);
        }
        reload();
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        values = null;
    }

    // ================================================================== verdict

    /**
     * The theft policy — pure, no state mutation. Called by
     * {@code LifecycleEvents.onLivingDeath} for every PvP kill (killer != victim).
     */
    public static Verdict evaluate(ServerPlayer killer, ServerPlayer victim) {
        Values cfg = config();
        MinecraftServer server = victim.server;
        if (!cfg.enabled()) {
            return Verdict.NO_STEAL_DISABLED;
        }
        if (isGhost(killer) || isGhost(victim)) {
            return Verdict.NO_STEAL_GHOST;
        }
        if (killer.isSpectator() || victim.isSpectator()) {
            return Verdict.NO_STEAL_SPECTATOR;
        }
        if (!EclipseWorldState.get(server).isStartEventDone()) {
            return Verdict.NO_STEAL_PRE_EVENT;
        }
        if (XpGates.isEventDimension(victim.level().dimension())
                || XpGates.isEventDimension(killer.level().dimension())) {
            return Verdict.NO_STEAL_EVENT_DIMENSION;
        }
        if (isActiveContractPair(server, killer.getUUID(), victim.getUUID())) {
            return Verdict.NO_STEAL_CONTRACT_PAIR;
        }
        if (LivesApi.get(victim) <= cfg.floorLives()) {
            return Verdict.NO_STEAL_FLOOR;
        }
        if (cooldownRemainingMillis(server, killer.getUUID(), victim.getUUID(),
                EclipseClock.epochMillis()) > 0L) {
            return Verdict.NO_STEAL_COOLDOWN;
        }
        return Verdict.STEAL;
    }

    /** Mirrors {@code ContractService.isEligible}'s ghost check. */
    private static boolean isGhost(ServerPlayer player) {
        return player.getData(EclipseAttachments.BANNED)
                || EclipseWorldState.get(player.server).isBanned(player.getUUID());
    }

    /** Whether an ACTIVE REAL contract window covers this killer/victim pair (either role). */
    private static boolean isActiveContractPair(MinecraftServer server, UUID a, UUID b) {
        ContractState state = ContractService.stateOf(server);
        if (state.phase() != ContractState.Phase.ACTIVE || state.mode() != ContractState.Mode.REAL) {
            return false;
        }
        UUID hunter = state.hunter();
        UUID target = state.target();
        return (a.equals(hunter) && b.equals(target)) || (a.equals(target) && b.equals(hunter));
    }

    // ================================================================== cooldown ledger

    /** Records a completed steal (pair cooldown, both directions block). */
    public static void recordSteal(ServerPlayer killer, ServerPlayer victim) {
        TheftState.get(killer.server).record(killer.getUUID(), victim.getUUID(),
                EclipseClock.epochMillis(), config().cooldownMillis());
    }

    /**
     * Remaining pair-cooldown millis at {@code now} ({@code 0} = free). Checked in BOTH
     * directions — a traded kill-back cannot restart the farm either.
     */
    public static long cooldownRemainingMillis(MinecraftServer server, UUID a, UUID b, long now) {
        long last = TheftState.get(server).lastStealBetween(a, b);
        if (last <= 0L) {
            return 0L;
        }
        return Math.max(0L, last + config().cooldownMillis() - now);
    }

    /** Human-readable active cooldown rows ({@code /dev contract theft status}). */
    public static List<String> describeCooldowns(MinecraftServer server) {
        List<String> lines = new ArrayList<>();
        long now = EclipseClock.epochMillis();
        long cooldown = config().cooldownMillis();
        for (TheftState.StealRecord record : TheftState.get(server).records()) {
            long remaining = record.atEpochMillis() + cooldown - now;
            if (remaining > 0L) {
                lines.add(nameOf(server, record.killer()) + " -> " + nameOf(server, record.victim())
                        + ": " + mmss(remaining) + " left");
            }
        }
        return lines;
    }

    /** Gametest reset: drops every cooldown record. */
    public static void clearCooldowns(MinecraftServer server) {
        TheftState.get(server).clear();
    }

    // ================================================================== ceremony

    /**
     * The theft ceremony: titles for both parties, the named global announce, deep bell +
     * heart-pulse cue, a global shake and the purple-heart drift at the corpse. All lines
     * are baked per receiver through {@link ServerLang} so locales stay correct.
     */
    public static void celebrate(ServerPlayer killer, ServerPlayer victim) {
        if (!config().ceremony()) {
            return;
        }
        MinecraftServer server = killer.server;
        String killerName = killer.getScoreboardName();
        String victimName = victim.getScoreboardName();

        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            String subtitle;
            if (online == killer) {
                subtitle = ServerLang.tr(online, "eclipse.theft.taken", victimName).getString();
            } else if (online == victim) {
                subtitle = ServerLang.tr(online, "eclipse.theft.lost", killerName).getString();
            } else {
                // The one deliberate anonymity breach of this system: the global
                // "X hat Y ein Leben gestohlen" announce (v5 user ask).
                subtitle = ServerLang.tr(online, "message.eclipse.theft.global",
                        killerName, victimName).getString();
            }
            PacketDistributor.sendToPlayer(online, new S2CAnnouncePayload(
                    "announce.eclipse.theft.title", subtitle, S2CAnnouncePayload.STYLE_BOSS));
            // Deep bell + heart pulse (theft.steal aliases a shipped ogg, the P2 pattern).
            online.playNotifySound(SoundEvents.BELL_RESONATE, SoundSource.AMBIENT, 0.8F, 0.5F);
            online.playNotifySound(EclipseSounds.THEFT_STEAL.get(), SoundSource.AMBIENT, 0.9F, 0.85F);
        }
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(SHAKE_STRENGTH, SHAKE_TICKS));

        // Purple-heart drift out of the corpse (existing eclipse:heart_burst emitter —
        // purple heart sprites with gravity+drag) for everyone near the scene.
        if (victim.level() instanceof ServerLevel level) {
            PacketDistributor.sendToPlayersNear(level, null,
                    victim.getX(), victim.getY(), victim.getZ(), DRIFT_FX_RANGE,
                    new S2CQuasarPayload(S2CQuasarPayload.HEART_BURST,
                            victim.position().add(0.0D, 1.2D, 0.0D)));
        }
        EclipseMod.LOGGER.info("Heart theft: {} stole a Leben from {} ({} -> {} Leben)",
                killerName, victimName, LivesApi.get(victim), LivesApi.get(killer));
    }

    // ================================================================== config

    /** Live config (loads defaults on first access). */
    public static Values config() {
        Values snapshot = values;
        if (snapshot == null) {
            reload();
            snapshot = values;
        }
        return snapshot;
    }

    /** {@code /dev contract theft on|off}: mutates the LIVE snapshot (transient until reload). */
    public static void setEnabledLive(boolean enabled) {
        Values v = config();
        values = new Values(enabled, v.cooldownMinutes(), v.floorLives(), v.ceremony());
    }

    /** Re-reads {@code config/eclipse/hearts.json}, creating it with defaults when missing. */
    public static synchronized void reload() {
        reloadFromDir(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Injectable-directory variant for gametests. */
    public static synchronized void reloadFromDir(Path dir) {
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }
        Path file = dir.resolve(FILE_NAME);
        if (!Files.exists(file)) {
            try {
                Files.writeString(file, GSON.toJson(defaultsJson()), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8))
                    .getAsJsonObject();
            values = parse(root);
            EclipseMod.LOGGER.info("Heart-theft config loaded: enabled={}, cooldown={} min, floor={} Leben",
                    values.enabled(), values.cooldownMinutes(), values.floorLives());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Failed to parse {}; keeping previous values (or defaults)", file, e);
            if (values == null) {
                values = parse(defaultsJson());
            }
        }
    }

    /** Pure parser — gametests feed synthetic JSON here. Unknown keys are ignored. */
    public static Values parse(JsonObject root) {
        JsonObject theft = root.has("heartTheft") && root.get("heartTheft").isJsonObject()
                ? root.getAsJsonObject("heartTheft") : new JsonObject();
        return new Values(
                asBool(theft, "enabled", true),
                Math.max(0, asInt(theft, "cooldownMinutes", 30)),
                Math.max(0, asInt(theft, "floorLives", 1)),
                asBool(theft, "ceremony", true));
    }

    /** Canonical default config JSON (public for gametest pinning). */
    public static JsonObject defaultsJson() {
        JsonObject root = new JsonObject();
        JsonObject doc = new JsonObject();
        doc.addProperty("heartTheft", "D4 out-of-event PvP kill economy: the killer steals one "
                + "permanent Leben from the victim, ONLY outside an active REAL contract window "
                + "covering the pair. cooldownMinutes = per-pair anti-farm window (within it a PvP "
                + "kill moves NO Leben in either direction); floorLives = a victim at or below this "
                + "count loses nothing to PvP (theft can never ghost anyone); enabled=false turns "
                + "off ALL PvP Leben movement to the killer (the victim still pays the normal death "
                + "cost); ceremony toggles the titles/announce/sound/shake/FX.");
        root.add("_doc", doc);

        JsonObject theft = new JsonObject();
        theft.addProperty("enabled", true);
        theft.addProperty("cooldownMinutes", 30);
        theft.addProperty("floorLives", 1);
        theft.addProperty("ceremony", true);
        root.add("heartTheft", theft);
        return root;
    }

    private static int asInt(JsonObject obj, String key, int fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsInt() : fallback;
    }

    private static boolean asBool(JsonObject obj, String key, boolean fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsBoolean() : fallback;
    }

    // ================================================================== helpers

    private static String nameOf(MinecraftServer server, UUID uuid) {
        ServerPlayer online = server.getPlayerList().getPlayer(uuid);
        if (online != null) {
            return online.getScoreboardName();
        }
        var cached = server.getProfileCache() != null
                ? server.getProfileCache().get(uuid).orElse(null) : null;
        return cached != null ? cached.getName() : uuid.toString();
    }

    private static String mmss(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        return String.format(Locale.ROOT, "%02d:%02d", totalSeconds / 60L, totalSeconds % 60L);
    }

    // ================================================================== SavedData

    /**
     * Pair-cooldown ledger ({@code data/eclipse_heart_theft.dat}). Records prune
     * themselves past the cooldown horizon on every write. Public for gametests.
     */
    public static final class TheftState extends SavedData {
        static final String DATA_NAME = "eclipse_heart_theft";

        /** One completed steal: killer took a Leben from victim at {@code atEpochMillis}. */
        public record StealRecord(UUID killer, UUID victim, long atEpochMillis) {}

        private final List<StealRecord> records = new ArrayList<>();

        public static TheftState get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_NAME,
                    new SavedData.Factory<>(TheftState::new, TheftState::load));
        }

        public TheftState() {}

        public static TheftState load(CompoundTag tag, HolderLookup.Provider registries) {
            TheftState state = new TheftState();
            for (Tag element : tag.getList("records", Tag.TAG_COMPOUND)) {
                CompoundTag row = (CompoundTag) element;
                if (row.hasUUID("killer") && row.hasUUID("victim")) {
                    state.records.add(new StealRecord(row.getUUID("killer"), row.getUUID("victim"),
                            row.getLong("at")));
                }
            }
            return state;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (StealRecord record : records) {
                CompoundTag row = new CompoundTag();
                row.putUUID("killer", record.killer());
                row.putUUID("victim", record.victim());
                row.putLong("at", record.atEpochMillis());
                list.add(row);
            }
            tag.put("records", list);
            return tag;
        }

        public List<StealRecord> records() {
            return List.copyOf(records);
        }

        /** Adds one steal and prunes rows older than the cooldown horizon. */
        public void record(UUID killer, UUID victim, long atEpochMillis, long horizonMillis) {
            records.removeIf(r -> atEpochMillis - r.atEpochMillis() > horizonMillis);
            records.add(new StealRecord(killer, victim, atEpochMillis));
            setDirty();
        }

        /** Latest steal epoch between the two, EITHER direction ({@code 0} = never). */
        public long lastStealBetween(UUID a, UUID b) {
            long latest = 0L;
            for (StealRecord record : records) {
                boolean match = (record.killer().equals(a) && record.victim().equals(b))
                        || (record.killer().equals(b) && record.victim().equals(a));
                if (match && record.atEpochMillis() > latest) {
                    latest = record.atEpochMillis();
                }
            }
            return latest;
        }

        void clear() {
            if (!records.isEmpty()) {
                records.clear();
                setDirty();
            }
        }
    }
}
