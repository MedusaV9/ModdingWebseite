package dev.projecteclipse.eclipse.skills;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.advancements.AdvancementHolder;
import net.minecraft.advancements.AdvancementProgress;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.AdvancementEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * R11 integration point: every earned {@code eclipse}-namespace advancement grants skill XP
 * from the {@code skills.json xp.advancements} table (exact id → id with the {@code event/}
 * folder stripped → default). Dedup is inherent — {@code AdvancementEarnEvent} fires once
 * per player+advancement for the save's lifetime.
 *
 * <p>The reverse direction: skill milestones (levels 10/25/40) award the data-side
 * advancements {@code eclipse:event/skill_10|skill_25|skill_40} (JSONs authored by P4-B3).
 * Missing advancements soft-fail with one log line per id — this class works headless
 * before B3's data lands.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AdvancementXpBridge {
    /** Skill levels that award a code-side advancement (plan §2.11). */
    private static final int[] MILESTONE_LEVELS = {10, 25, 40};

    // statics reset on ServerStopped
    private static final Set<String> WARNED_MISSING = ConcurrentHashMap.newKeySet();

    private AdvancementXpBridge() {}

    @SubscribeEvent
    static void onAdvancementEarned(AdvancementEvent.AdvancementEarnEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        ResourceLocation id = event.getAdvancement().id();
        if (!EclipseMod.MOD_ID.equals(id.getNamespace())) {
            return;
        }
        float xp = xpForAdvancement(id.toString());
        if (xp > 0.0F) {
            SkillsApi.addXp(player, SkillService.SOURCE_ADVANCEMENT, xp);
        }
    }

    /**
     * XP for an advancement id. Lookup: exact id → id with a leading {@code event/} path
     * segment stripped (the plan's table uses {@code eclipse:herald_slain} while B3's files
     * live at {@code eclipse:event/herald_slain}) → table default.
     */
    public static float xpForAdvancement(String fullId) {
        SkillConfig.ValueTable table = SkillConfig.get().advancements();
        ResourceLocation id = ResourceLocation.tryParse(fullId);
        if (id == null) {
            return table.defaultValue();
        }
        float exact = table.forKey(id.toString());
        if (exact != table.defaultValue()) {
            return exact;
        }
        if (id.getPath().startsWith("event/")) {
            String stripped = id.getNamespace() + ":" + id.getPath().substring("event/".length());
            return table.forKey(stripped);
        }
        return exact;
    }

    /** Called by the level-up sweep: award milestone advancements when defined. */
    static void onSkillLevelReached(ServerPlayer player, int level) {
        for (int milestone : MILESTONE_LEVELS) {
            if (level == milestone) {
                grantAdvancement(player, "eclipse:event/skill_" + milestone);
            }
        }
    }

    /** Soft advancement grant by id — awards all remaining criteria; absent id logs once. */
    public static void grantAdvancement(ServerPlayer player, String id) {
        ResourceLocation rl = ResourceLocation.tryParse(id);
        if (rl == null) {
            return;
        }
        AdvancementHolder holder = player.server.getAdvancements().get(rl);
        if (holder == null) {
            if (WARNED_MISSING.add(id)) {
                EclipseMod.LOGGER.debug("Skill milestone advancement {} not present yet (P4-B3 data)", id);
            }
            return;
        }
        AdvancementProgress progress = player.getAdvancements().getOrStartProgress(holder);
        if (progress.isDone()) {
            return;
        }
        for (String criterion : progress.getRemainingCriteria()) {
            player.getAdvancements().award(holder, criterion);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        WARNED_MISSING.clear();
    }
}
