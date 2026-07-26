package dev.projecteclipse.eclipse.client.wand;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.network.wand.S2CWandProgressPayload;
import dev.projecteclipse.eclipse.wand.WandSpell;
import dev.projecteclipse.eclipse.wand.WandSpells;
import dev.projecteclipse.eclipse.wand.WandTree;
import dev.projecteclipse.eclipse.wand.WandTreeService;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Client cache of the {@code S2CWandProgressPayload} sync (F-036 rework; the
 * {@code ClientRebirthState} pattern). The wand tab and the charge HUD read the
 * SERVER's per-player wand state from here — Wand-XP balance, rebirth counter, owned
 * tree nodes, effective charge max/regen/damage and per-spell effective costs — instead
 * of the client's own local {@code WandConfig} file, which only matched on singleplayer.
 * The tree STRUCTURE never syncs: {@code WandTree}/{@code WandSpells} are static shared
 * Java, so the client derives node costs, parents and the rebirth curve locally and
 * only the STATE rides the payload.
 *
 * <p>F-040: there is no cooldown state anymore — the old pinned-millis countdown cache
 * is gone with the mechanic.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class ClientWandProgress {
    /** False until the first payload lands — the panel renders its syncing hint. */
    public static volatile boolean synced = false;
    public static volatile int level = 1;
    /** Spendable Wand-XP-Punkte (the tree/rebirth currency). */
    public static volatile int xp = 0;
    public static volatile int rebirths = 0;
    public static volatile int charge = 0;
    public static volatile int chargeMax = 100;
    /** Effective held regen per second (server config × the player's regen nodes). */
    public static volatile float regenPerSecond = 0.0F;
    /** Effective spell-power multiplier (nodes + rebirths), for the header stat. */
    public static volatile float damageMult = 1.0F;
    public static volatile float xpPerCostPoint = 0.0F;
    public static volatile float xpKillBonus = 0.0F;
    private static volatile Set<String> nodes = Set.of();
    private static final Map<String, Integer> SPELL_COSTS = new ConcurrentHashMap<>();

    private ClientWandProgress() {}

    /** Payload-handler entry point ({@code WandPayloads.handleProgress}). */
    public static void update(S2CWandProgressPayload payload) {
        level = payload.level();
        xp = payload.xp();
        rebirths = payload.rebirths();
        charge = payload.charge();
        chargeMax = Math.max(1, payload.chargeMax());
        regenPerSecond = payload.regenPerSecond();
        damageMult = payload.damageMult();
        xpPerCostPoint = payload.xpPerCostPoint();
        xpKillBonus = payload.xpKillBonus();
        nodes = Set.copyOf(payload.nodes());
        SPELL_COSTS.clear();
        for (S2CWandProgressPayload.SpellRow row : payload.spells()) {
            SPELL_COSTS.put(row.key(), row.cost());
        }
        synced = true;
    }

    /** The player's owned wand-tree node ids (server truth snapshot). */
    public static Set<String> nodes() {
        return nodes;
    }

    public static boolean ownsNode(String nodeId) {
        return nodes.contains(nodeId);
    }

    /** Effective cast cost of a spell for THIS player (server-synced; authored fallback). */
    public static int spellCost(String key) {
        Integer cost = SPELL_COSTS.get(key);
        if (cost != null) {
            return cost;
        }
        WandSpell spell = WandSpells.byKey(key);
        return spell != null ? spell.defaultCost() : 0;
    }

    /**
     * The unlocked spells in canonical order, derived exactly like the server does
     * ({@code WandTreeService.unlockedSpells}): a spell is unlocked when its tree node
     * is in the synced owned set.
     */
    public static List<WandSpell> unlockedSpells() {
        Set<String> owned = nodes;
        List<WandSpell> unlocked = new ArrayList<>();
        for (WandSpell spell : WandSpells.all()) {
            if (owned.contains(WandTreeService.nodeIdOfSpell(spell))) {
                unlocked.add(spell);
            }
        }
        return unlocked;
    }

    /** Wand-XP cost of the player's NEXT rebirth (static curve × synced counter). */
    public static long nextRebirthCost() {
        return WandTree.rebirthCost(rebirths);
    }

    /** True when every tree node is owned — the rebirth precondition. */
    public static boolean treeMaxed() {
        return WandTree.isMaxed(nodes);
    }

    public static void reset() {
        synced = false;
        level = 1;
        xp = 0;
        rebirths = 0;
        charge = 0;
        chargeMax = 100;
        regenPerSecond = 0.0F;
        damageMult = 1.0F;
        xpPerCostPoint = 0.0F;
        xpKillBonus = 0.0F;
        nodes = Set.of();
        SPELL_COSTS.clear();
    }

    /** Disconnect reset ({@code ClientRebirthState.DisconnectReset} pattern). */
    @net.neoforged.fml.common.EventBusSubscriber(modid = dev.projecteclipse.eclipse.EclipseMod.MOD_ID,
            value = Dist.CLIENT)
    static final class DisconnectReset {
        private DisconnectReset() {}

        @net.neoforged.bus.api.SubscribeEvent
        static void onLoggingOut(net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent.LoggingOut event) {
            reset();
        }
    }
}
