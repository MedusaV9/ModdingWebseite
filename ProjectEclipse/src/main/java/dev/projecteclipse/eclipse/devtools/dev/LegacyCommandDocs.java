package dev.projecteclipse.eclipse.devtools.dev;

/**
 * Pre-seeds {@link DevCommandRegistry} with documentation for the existing {@code /eclipse} tree
 * (§1.1) and parallel planners' reference command roots. Invoked from {@link DevRoot} static init.
 */
public final class LegacyCommandDocs {
    private static boolean bootstrapped;

    private LegacyCommandDocs() {}

    /** Idempotent seed of legacy handbook docs into {@link DevCommandRegistry}. */
    public static void bootstrap() {
        if (bootstrapped) {
            return;
        }
        bootstrapped = true;
        registerCoreDev();
        registerEclipseTree();
        registerReferenceRoots();
    }

    /** W1-owned {@code /dev} root commands (also registered here so docs exist before Brigadier runs). */
    private static void registerCoreDev() {
        DevCommandRegistry.register(
                doc("dev.root", DevCategory.CONFIG, "/dev", "dev.eclipse.doc.dev.root", Danger.SAFE,
                        ClickAction.RUN, 2),
                doc("dev.help", DevCategory.CONFIG, "/dev help", "dev.eclipse.doc.dev.help", Danger.SAFE,
                        ClickAction.SUGGEST, 2),
                doc("dev.docs.export", DevCategory.CONFIG, "/dev docs export", "dev.eclipse.doc.dev.docs.export",
                        Danger.SAFE, ClickAction.RUN, 2),
                doc("dev.reload", DevCategory.CONFIG, "/dev reload", "dev.eclipse.doc.dev.reload", Danger.CAUTION,
                        ClickAction.RUN, 2));
    }

    private static void registerEclipseTree() {
        DevCommandRegistry.register(
                legacy("eclipse.start_event", "/eclipse start_event", "dev.eclipse.doc.eclipse.start_event",
                        Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.day.set", "/eclipse day set <day>", "dev.eclipse.doc.eclipse.day.set", Danger.CAUTION,
                        ClickAction.SUGGEST, 3),
                legacy("eclipse.day.goals", "/eclipse day goals", "dev.eclipse.doc.eclipse.day.goals", Danger.SAFE,
                        ClickAction.RUN, 3),
                legacy("eclipse.event.set", "/eclipse event set <event>", "dev.eclipse.doc.eclipse.event.set",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.boss.herald.summon", "/eclipse boss herald summon",
                        "dev.eclipse.doc.eclipse.boss.herald.summon", Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.boss.herald.kill", "/eclipse boss herald kill",
                        "dev.eclipse.doc.eclipse.boss.herald.kill", Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.boss.ferryman.summon", "/eclipse boss ferryman summon",
                        "dev.eclipse.doc.eclipse.boss.ferryman.summon", Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.boss.ferryman.kill", "/eclipse boss ferryman kill",
                        "dev.eclipse.doc.eclipse.boss.ferryman.kill", Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.boss.ferryman.phase", "/eclipse boss ferryman phase <phase>",
                        "dev.eclipse.doc.eclipse.boss.ferryman.phase", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.lives.set", "/eclipse lives set <player> <lives>", "dev.eclipse.doc.eclipse.lives.set",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.lives.add", "/eclipse lives add <player> <delta>",
                        "dev.eclipse.doc.eclipse.lives.add", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.altar.set", "/eclipse altar set <level>", "dev.eclipse.doc.eclipse.altar.set",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.ban", "/eclipse ban <player>", "dev.eclipse.doc.eclipse.ban", Danger.DESTRUCTIVE,
                        ClickAction.SUGGEST, 3),
                legacy("eclipse.revive", "/eclipse revive <player>", "dev.eclipse.doc.eclipse.revive", Danger.CAUTION,
                        ClickAction.SUGGEST, 3),
                legacy("eclipse.restore", "/eclipse restore <player> [index]", "dev.eclipse.doc.eclipse.restore",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.border.set", "/eclipse border set <size> [seconds]",
                        "dev.eclipse.doc.eclipse.border.set", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.border.ring.set", "/eclipse border ring set <radius> [seconds]",
                        "dev.eclipse.doc.eclipse.border.ring.set", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.border.fx.range", "/eclipse border fx range <blocks>",
                        "dev.eclipse.doc.eclipse.border.fx.range", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.modgate.lock", "/eclipse modgate lock <namespace>",
                        "dev.eclipse.doc.eclipse.modgate.lock", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.modgate.unlock", "/eclipse modgate unlock <namespace>",
                        "dev.eclipse.doc.eclipse.modgate.unlock", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.voicemute", "/eclipse voicemute <player> <on|off>",
                        "dev.eclipse.doc.eclipse.voicemute", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.stage.get", "/eclipse stage get", "dev.eclipse.doc.eclipse.stage.get", Danger.SAFE,
                        ClickAction.RUN, 3),
                legacy("eclipse.stage.set", "/eclipse stage set <overworld|nether> <n> [instant|animate]",
                        "dev.eclipse.doc.eclipse.stage.set", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3),
                legacy("eclipse.stage.rebuild", "/eclipse stage rebuild <dim> <n>",
                        "dev.eclipse.doc.eclipse.stage.rebuild", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3),
                legacy("eclipse.stage.save", "/eclipse stage save <n>", "dev.eclipse.doc.eclipse.stage.save",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.stage.load", "/eclipse stage load <n>", "dev.eclipse.doc.eclipse.stage.load",
                        Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3),
                legacy("eclipse.stage.revert", "/eclipse stage revert", "dev.eclipse.doc.eclipse.stage.revert",
                        Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.stage.status", "/eclipse stage status", "dev.eclipse.doc.eclipse.stage.status",
                        Danger.SAFE, ClickAction.RUN, 3),
                legacy("eclipse.stage.snapshot.save", "/eclipse stage snapshot save <name>",
                        "dev.eclipse.doc.eclipse.stage.snapshot.save", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.stage.snapshot.restore", "/eclipse stage snapshot restore <name>",
                        "dev.eclipse.doc.eclipse.stage.snapshot.restore", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3),
                legacy("eclipse.schedule.next", "/eclipse schedule next <spec>",
                        "dev.eclipse.doc.eclipse.schedule.next", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.schedule.list", "/eclipse schedule list", "dev.eclipse.doc.eclipse.schedule.list",
                        Danger.SAFE, ClickAction.RUN, 3),
                legacy("eclipse.schedule.clear", "/eclipse schedule clear", "dev.eclipse.doc.eclipse.schedule.clear",
                        Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.freeze", "/eclipse freeze <players> on [seconds]|off",
                        "dev.eclipse.doc.eclipse.freeze", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.invuln", "/eclipse invuln <players> on [seconds]|off",
                        "dev.eclipse.doc.eclipse.invuln", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.timeline", "/eclipse timeline", "dev.eclipse.doc.eclipse.timeline", Danger.SAFE,
                        ClickAction.RUN, 3),
                legacy("eclipse.tp_limbo", "/eclipse tp_limbo [player]", "dev.eclipse.doc.eclipse.tp_limbo",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.play", "/eclipse cutscene play <id> [players]",
                        "dev.eclipse.doc.eclipse.cutscene.play", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.abort", "/eclipse cutscene abort [players]",
                        "dev.eclipse.doc.eclipse.cutscene.abort", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.list", "/eclipse cutscene list", "dev.eclipse.doc.eclipse.cutscene.list",
                        Danger.SAFE, ClickAction.RUN, 3),
                legacy("eclipse.cutscene.enable", "/eclipse cutscene enable <id>",
                        "dev.eclipse.doc.eclipse.cutscene.enable", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.disable", "/eclipse cutscene disable <id>",
                        "dev.eclipse.doc.eclipse.cutscene.disable", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.skip", "/eclipse cutscene skip allow|deny <id>",
                        "dev.eclipse.doc.eclipse.cutscene.skip", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.preview", "/eclipse cutscene preview <id>",
                        "dev.eclipse.doc.eclipse.cutscene.preview", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.reloadpaths", "/eclipse cutscene reloadpaths",
                        "dev.eclipse.doc.eclipse.cutscene.reloadpaths", Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.cutscene.export", "/eclipse cutscene export <id>",
                        "dev.eclipse.doc.eclipse.cutscene.export", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.cutscene.edit", "/eclipse cutscene edit <id> …",
                        "dev.eclipse.doc.eclipse.cutscene.edit", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.goals.tick", "/eclipse goals tick <player> <index>",
                        "dev.eclipse.doc.eclipse.goals.tick", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.goals.edit", "/eclipse goals edit", "dev.eclipse.doc.eclipse.goals.edit",
                        Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.shards.set", "/eclipse shards set <player> <amount>",
                        "dev.eclipse.doc.eclipse.shards.set", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.shards.add", "/eclipse shards add <player> <delta>",
                        "dev.eclipse.doc.eclipse.shards.add", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.shards.pool.set", "/eclipse shards pool set <amount>",
                        "dev.eclipse.doc.eclipse.shards.pool.set", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse.supply.drop", "/eclipse supply drop", "dev.eclipse.doc.eclipse.supply.drop",
                        Danger.CAUTION, ClickAction.RUN, 3),
                legacy("eclipse.reload", "/eclipse reload", "dev.eclipse.doc.eclipse.reload", Danger.CAUTION,
                        ClickAction.RUN, 3),
                legacy("eclipse.status", "/eclipse status", "dev.eclipse.doc.eclipse.status", Danger.SAFE,
                        ClickAction.RUN, 3));
    }

    private static void registerReferenceRoots() {
        DevCommandRegistry.register(
                legacy("eclipsefx.root", "/eclipsefx …", "dev.eclipse.doc.eclipsefx.root", Danger.CAUTION,
                        ClickAction.SUGGEST, 3),
                legacy("eclipsefx.sequence", "/eclipsefx sequence intro|expansion <phase>",
                        "dev.eclipse.doc.eclipsefx.sequence", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipsefx.cutscene", "/eclipsefx cutscene play|stop|preview <id>",
                        "dev.eclipse.doc.eclipsefx.cutscene", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipsefx.viewdist", "/eclipsefx viewdist <n|reset>",
                        "dev.eclipse.doc.eclipsefx.viewdist", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse-rt.root", "/eclipse-rt …", "dev.eclipse.doc.eclipse_rt.root", Danger.CAUTION,
                        ClickAction.SUGGEST, 3),
                legacy("eclipse-buffs.root", "/eclipse-buffs …", "dev.eclipse.doc.eclipse_buffs.root", Danger.CAUTION,
                        ClickAction.SUGGEST, 3),
                legacy("eclipse-quests.root", "/eclipse-quests …", "dev.eclipse.doc.eclipse_quests.root",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse-worldgen.root", "/eclipse-worldgen …", "dev.eclipse.doc.eclipse_worldgen.root",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse-worldgen.refreeze", "/eclipse-worldgen refreeze <section>",
                        "dev.eclipse.doc.eclipse_worldgen.refreeze", Danger.CAUTION, ClickAction.SUGGEST, 3),
                legacy("eclipse-worldgen.ores.reload", "/eclipse-worldgen ores reload",
                        "dev.eclipse.doc.eclipse_worldgen.ores.reload", Danger.CAUTION, ClickAction.RUN, 3));
    }

    private static DevCommandDoc doc(String id, DevCategory category, String syntax, String descKey, Danger danger,
            ClickAction clickAction, int permission) {
        return new DevCommandDoc(id, category, syntax, descKey, danger, clickAction, permission, false);
    }

    private static DevCommandDoc legacy(String id, String syntax, String descKey, Danger danger,
            ClickAction clickAction, int permission) {
        return new DevCommandDoc(id, DevCategory.LEGACY, syntax, descKey, danger, clickAction, permission, true);
    }
}
