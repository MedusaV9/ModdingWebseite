package dev.projecteclipse.eclipse.buffs;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.function.LongSupplier;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CBuffStatePayload;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Timed server buff engine (R16/R17): persistence, tick-down, bossbar, announcements,
 * and {@link S2CBuffStatePayload} sync. Registers as the live {@link TimedBuffApi} delegate.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class TimedBuffService implements TimedBuffApi {
    private static final int TICK_INTERVAL = 20;

    // statics reset on ServerStopped
    private static LongSupplier epochMillis = System::currentTimeMillis;
    @Nullable
    private static TimedBuffService instance;
    @Nullable
    private static ServerBossEvent bossEvent;
    private static int barNameIndex = 0;

    private TimedBuffService() {}

    public static TimedBuffService getInstance() {
        if (instance == null) {
            instance = new TimedBuffService();
        }
        return instance;
    }

    /** Test-only epoch clock (gametests). */
    public static void setEpochClockForTests(LongSupplier supplier) {
        epochMillis = supplier;
        BuffEffects.setEpochClockForTests(supplier);
    }

    public static void resetEpochClock() {
        epochMillis = System::currentTimeMillis;
        BuffEffects.resetEpochClock();
    }

    static long nowEpochMillis() {
        return epochMillis.getAsLong();
    }

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        TimedBuffService service = getInstance();
        TimedBuffApi.Holder.set(service);
        BuffEffects.bindService(service);
        BuffState state = BuffState.get(event.getServer());
        long now = nowEpochMillis();
        List<BuffMath.ActiveBuff> pruned = BuffMath.pruneExpired(state.active(), now);
        if (pruned.size() != state.active().size()) {
            state.setActive(pruned);
            service.syncAll(event.getServer(), pruned);
        } else {
            service.syncAll(event.getServer(), state.active());
        }
        service.refreshBossbar(event.getServer());
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        TimedBuffService service = getInstance();
        if (TimedBuffApi.Holder.get() != service) {
            return;
        }
        PacketDistributor.sendToPlayer(player, service.buildPayload(player.server, BuffState.get(player.server).active()));
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        TimedBuffService service = getInstance();
        if (TimedBuffApi.Holder.get() != service) {
            return;
        }
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % TICK_INTERVAL != 0) {
            return;
        }
        service.tick(server);
    }

    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        removeBossbar();
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        TimedBuffApi.Holder.reset();
        instance = null;
        removeBossbar();
        barNameIndex = 0;
        resetEpochClock();
    }

    private void tick(MinecraftServer server) {
        BuffState state = BuffState.get(server);
        long now = nowEpochMillis();
        List<BuffMath.ActiveBuff> before = state.active();
        List<BuffMath.ActiveBuff> after = BuffMath.pruneExpired(before, now);
        if (after.size() != before.size()) {
            List<String> ended = new ArrayList<>();
            for (BuffMath.ActiveBuff buff : before) {
                if (buff.endsAtEpochMillis() <= now) {
                    ended.add(buff.id());
                }
            }
            state.setActive(after);
            for (String id : ended) {
                announceEnd(server, id);
            }
            syncAll(server, after);
        }
        refreshBossbar(server);
    }

    void runPeriodicAndMagnet(MinecraftServer server, long now) {
        BuffState state = BuffState.get(server);
        var defs = BuffConfig.get().buffs();
        for (BuffMath.ActiveBuff buff : state.active()) {
            if (buff.endsAtEpochMillis() <= now) {
                continue;
            }
            BuffConfig.BuffDefinition def = defs.get(buff.id());
            if (def == null) {
                continue;
            }
            if (def.effect() instanceof BuffConfig.MagnetEffect magnet) {
                BuffEffects.pullExperienceOrbs(server.overworld(), magnet.radius());
            } else if (def.effect() instanceof BuffConfig.PeriodicEffect periodic
                    && "supply_drop".equals(periodic.action())) {
                long periodMillis = periodic.periodSeconds() * 1000L;
                long last = buff.lastPeriodicEpochMillis();
                if (last <= 0L || now - last >= periodMillis) {
                    BuffEffects.fireSupplyDrop(server);
                    state.updatePeriodicFire(buff.id(), now);
                }
            }
        }
    }

    @Override
    public boolean start(MinecraftServer server, String id, int minutesOverride, float magnitudeOverride) {
        BuffConfig.BuffDefinition def = BuffConfig.get().buffs().get(id);
        if (def == null) {
            return false;
        }
        BuffState state = BuffState.get(server);
        long now = nowEpochMillis();
        boolean wasActive = BuffMath.isActive(state.active(), id, now);
        List<BuffMath.ActiveBuff> next = BuffMath.applyStart(state.active(), def,
                BuffConfig.get().maxActive(), minutesOverride, magnitudeOverride, now);
        if (next == null) {
            return false;
        }
        state.setActive(next);
        if (!wasActive) {
            announceStart(server, def);
        }
        syncAll(server, next);
        refreshBossbar(server);
        return true;
    }

    @Override
    public boolean stop(MinecraftServer server, String id) {
        BuffState state = BuffState.get(server);
        long now = nowEpochMillis();
        List<BuffMath.ActiveBuff> next = BuffMath.applyStop(state.active(), id, now);
        if (next == null) {
            return false;
        }
        state.setActive(next);
        announceEnd(server, id);
        syncAll(server, next);
        refreshBossbar(server);
        return true;
    }

    @Override
    public List<String> active(MinecraftServer server) {
        long now = nowEpochMillis();
        return BuffMath.pruneExpired(BuffState.get(server).active(), now).stream()
                .map(BuffMath.ActiveBuff::id)
                .toList();
    }

    @Override
    public float multiplier(MinecraftServer server, String tag) {
        long now = nowEpochMillis();
        return BuffMath.multiplierProduct(BuffState.get(server).active(), BuffConfig.get().buffs(), tag, now);
    }

    @Override
    public boolean isActive(MinecraftServer server, String id) {
        return BuffMath.isActive(BuffState.get(server).active(), id, nowEpochMillis());
    }

    @Override
    public Collection<String> knownIds() {
        return BuffConfig.get().buffs().keySet();
    }

    private void syncAll(MinecraftServer server, List<BuffMath.ActiveBuff> active) {
        PacketDistributor.sendToAllPlayers(buildPayload(server, active));
    }

    private S2CBuffStatePayload buildPayload(MinecraftServer server, List<BuffMath.ActiveBuff> active) {
        var defs = BuffConfig.get().buffs();
        List<S2CBuffStatePayload.Buff> wire = new ArrayList<>();
        long now = nowEpochMillis();
        for (BuffMath.ActiveBuff buff : BuffMath.pruneExpired(active, now)) {
            BuffConfig.BuffDefinition def = defs.get(buff.id());
            if (def == null) {
                continue;
            }
            float magnitude = buff.magnitude() > 0.0F ? buff.magnitude()
                    : (def.effect() instanceof BuffConfig.MultiplierEffect m ? m.value() : 1.0F);
            wire.add(new S2CBuffStatePayload.Buff(
                    buff.id(),
                    def.title().en(),
                    def.title().de(),
                    buff.endsAtEpochMillis(),
                    magnitude));
        }
        return new S2CBuffStatePayload(wire);
    }

    private void announceStart(MinecraftServer server, BuffConfig.BuffDefinition def) {
        AnnouncementService.announce(server,
                "announce.eclipse.buff.start",
                def.title().en(),
                S2CAnnouncePayload.STYLE_UNLOCK);
    }

    private void announceEnd(MinecraftServer server, String id) {
        BuffConfig.BuffDefinition def = BuffConfig.get().buffs().get(id);
        String subtitle = def != null ? def.title().en() : id;
        AnnouncementService.announce(server,
                "announce.eclipse.buff.end",
                subtitle,
                S2CAnnouncePayload.STYLE_UNLOCK);
    }

    private void refreshBossbar(MinecraftServer server) {
        long now = nowEpochMillis();
        List<BuffMath.ActiveBuff> active = BuffMath.pruneExpired(BuffState.get(server).active(), now);
        if (active.isEmpty()) {
            removeBossbar();
            return;
        }
        ensureBossbar(server);
        if (bossEvent == null) {
            return;
        }

        BuffMath.ActiveBuff shown = active.get(barNameIndex % active.size());
        BuffConfig.BuffDefinition def = BuffConfig.get().buffs().get(shown.id());
        String title = def != null ? def.title().en() : shown.id();
        long remaining = shown.endsAtEpochMillis() - now;
        long total = Math.max(remaining, 1L);
        if (active.size() > 1 && server.getTickCount() % (TICK_INTERVAL * 5) == 0) {
            barNameIndex = (barNameIndex + 1) % active.size();
            shown = active.get(barNameIndex);
            def = BuffConfig.get().buffs().get(shown.id());
            title = def != null ? def.title().en() : shown.id();
            remaining = shown.endsAtEpochMillis() - now;
            total = Math.max(remaining, 1L);
        }

        bossEvent.setName(Component.literal(title + " — " + formatRemaining(remaining)));
        bossEvent.setProgress(Mth.clamp((float) remaining / (float) total, 0.0F, 1.0F));
    }

    private static void ensureBossbar(MinecraftServer server) {
        if (bossEvent != null) {
            return;
        }
        bossEvent = new ServerBossEvent(Component.literal("Buff"), BossEvent.BossBarColor.GREEN,
                BossEvent.BossBarOverlay.PROGRESS);
        bossEvent.setVisible(true);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            bossEvent.addPlayer(player);
            PacketDistributor.sendToPlayer(player,
                    new S2CBossbarStylePayload(bossEvent.getId(), S2CBossbarStylePayload.THEME_GOAL));
        }
    }

    private static void removeBossbar() {
        if (bossEvent != null) {
            bossEvent.removeAllPlayers();
            bossEvent.setVisible(false);
            bossEvent = null;
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedInBossbar(PlayerEvent.PlayerLoggedInEvent event) {
        if (bossEvent != null && event.getEntity() instanceof ServerPlayer player) {
            bossEvent.addPlayer(player);
            PacketDistributor.sendToPlayer(player,
                    new S2CBossbarStylePayload(bossEvent.getId(), S2CBossbarStylePayload.THEME_GOAL));
        }
    }

    private static String formatRemaining(long millis) {
        long seconds = Math.max(0L, millis / 1000L);
        long minutes = seconds / 60L;
        seconds = seconds % 60L;
        if (minutes > 0L) {
            return minutes + "m " + seconds + "s";
        }
        return seconds + "s";
    }
}
