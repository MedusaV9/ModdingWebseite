package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.authlib.GameProfile;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyTrick;
import de.sonic0810.goobymod.network.GoobyNetwork;
import de.sonic0810.goobymod.network.TrickMenuPayload;
import de.sonic0810.goobymod.network.TrickSelectPayload;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import io.netty.buffer.Unpooled;
import io.netty.handler.codec.DecoderException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.function.Consumer;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Vollversions-Gameplay-Wave: nativer Trick-Selection-Screen ueber den neuen
 * Custom-Payload-Layer plus die zwei neuen Kunststuecke ROLL und DANCE.
 *
 * <p>Abgedeckt: Payload-Codecs inkl. harter Bounds (unbekannte Enum-Ids,
 * falsche Eintragszahl, Sterne ausserhalb, ueberlange Namen, Surrogate-
 * Grenzen), die komplette serverseitige Autorisierung (fremder Spieler,
 * Distanz, Baby, untrainiert, unbekannte/tote Ziele, No-op-Wiederholung),
 * die Spam-Drosselung samt hartem Speicher-Limit und Logout-Cleanup, die
 * {@code /goobytrick}-Command-Route ueber dieselbe Autorisierung, das
 * gesperrte Chat-Fallback-Menue, die Persistenz-Migration alter
 * Vier-Trick-Saves, Training und Vorfuehrung aller sechs Kunststuecke,
 * deterministische Menuedaten sowie Animations-/Sprach-Assets der neuen
 * Clips.</p>
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyTrickWaveTests {
    private static final String ARENA = "arena";
    /** Eigener Batch: isoliert die globale Nearest-Suche des Pfeifen-Pfads. */
    private static final String TRICK_MENU_BATCH = "goobyTrickMenu";

    // ------------------------------------------------------------------
    // Helfer
    // ------------------------------------------------------------------

    private static FakePlayer fakePlayer(GameTestHelper helper, String name) {
        return FakePlayerFactory.get(helper.getLevel(),
                new GameProfile(UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)), name));
    }

    private static void placeFloor(GameTestHelper helper) {
        for (int x = 0; x < 5; x++) {
            for (int z = 0; z < 5; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.DIRT);
            }
        }
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyTrickWaveTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    /** Erwartet eine {@link DecoderException} beim Decoden des praeparierten Buffers. */
    private static void assertMenuDecodeFails(GameTestHelper helper, String label,
            Consumer<FriendlyByteBuf> writer) {
        FriendlyByteBuf buf = new FriendlyByteBuf(Unpooled.buffer());
        try {
            writer.accept(buf);
            boolean rejected = false;
            try {
                TrickMenuPayload.STREAM_CODEC.decode(buf);
            } catch (DecoderException exception) {
                rejected = true;
            }
            helper.assertTrue(rejected, "Fehlerhafter Menue-Payload wurde akzeptiert: " + label);
        } finally {
            buf.release();
        }
    }

    /** Schreibt einen gueltigen Menue-Header (UUID, Name, Auswahl) in den Buffer. */
    private static void writeValidMenuHeader(FriendlyByteBuf buf) {
        buf.writeUUID(UUID.randomUUID());
        buf.writeUtf("Gooby", TrickMenuPayload.MAX_NAME_LENGTH);
        buf.writeVarInt(GoobyTrick.SPIN.ordinal());
    }

    // ------------------------------------------------------------------
    // Payload-Codecs und Bounds
    // ------------------------------------------------------------------

    /** Beide Payloads ueberleben den Roundtrip byte-genau und konsumieren den Buffer voll. */
    @GameTest(template = ARENA)
    public static void trick_payload_codecs_roundtrip(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.SPIN, 3);
        gooby.setTrickProficiency(GoobyTrick.FLOP, 1);
        gooby.setTrickProficiency(GoobyTrick.DANCE, 2);
        helper.assertTrue(gooby.selectTrick(owner, GoobyTrick.DANCE), "Setup-Auswahl scheiterte");

        TrickMenuPayload menu = TrickMenuPayload.of(gooby);
        FriendlyByteBuf buf = new FriendlyByteBuf(Unpooled.buffer());
        try {
            TrickMenuPayload.STREAM_CODEC.encode(buf, menu);
            TrickMenuPayload decoded = TrickMenuPayload.STREAM_CODEC.decode(buf);
            helper.assertTrue(menu.equals(decoded), "Menue-Payload-Roundtrip veraenderte Daten");
            helper.assertTrue(buf.readableBytes() == 0, "Menue-Decode liess Bytes uebrig");
        } finally {
            buf.release();
        }

        TrickSelectPayload select = new TrickSelectPayload(gooby.getUUID(), GoobyTrick.ROLL);
        FriendlyByteBuf selectBuf = new FriendlyByteBuf(Unpooled.buffer());
        try {
            TrickSelectPayload.STREAM_CODEC.encode(selectBuf, select);
            TrickSelectPayload decoded = TrickSelectPayload.STREAM_CODEC.decode(selectBuf);
            helper.assertTrue(select.equals(decoded), "Select-Payload-Roundtrip veraenderte Daten");
            helper.assertTrue(selectBuf.readableBytes() == 0, "Select-Decode liess Bytes uebrig");
        } finally {
            selectBuf.release();
        }
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Unbekannte Enum-Ids, falsche Zaehler, Bounds-Verstoesse und Riesen-Namen fliegen raus. */
    @GameTest(template = ARENA)
    public static void trick_payload_rejects_malformed(GameTestHelper helper) {
        int trickCount = GoobyTrick.values().length;

        assertMenuDecodeFails(helper, "unbekannte Auswahl-Id", buf -> {
            buf.writeUUID(UUID.randomUUID());
            buf.writeUtf("Gooby", TrickMenuPayload.MAX_NAME_LENGTH);
            buf.writeVarInt(99);
        });
        assertMenuDecodeFails(helper, "negative Auswahl-Id", buf -> {
            buf.writeUUID(UUID.randomUUID());
            buf.writeUtf("Gooby", TrickMenuPayload.MAX_NAME_LENGTH);
            buf.writeVarInt(-1);
        });
        assertMenuDecodeFails(helper, "zu wenige Eintraege", buf -> {
            writeValidMenuHeader(buf);
            buf.writeVarInt(2);
        });
        assertMenuDecodeFails(helper, "zu viele Eintraege", buf -> {
            writeValidMenuHeader(buf);
            buf.writeVarInt(trickCount + 1);
        });
        assertMenuDecodeFails(helper, "Sterne ausserhalb der Bounds", buf -> {
            writeValidMenuHeader(buf);
            buf.writeVarInt(trickCount);
            buf.writeVarInt(GoobyTrick.SPIN.ordinal());
            buf.writeByte(GoobyEntity.MAX_TRICK_PROFICIENCY + 4);
            buf.writeBoolean(true);
        });
        assertMenuDecodeFails(helper, "Eintraege ausser der Reihe", buf -> {
            writeValidMenuHeader(buf);
            buf.writeVarInt(trickCount);
            buf.writeVarInt(GoobyTrick.HIGH_FIVE.ordinal());
            buf.writeByte(1);
            buf.writeBoolean(true);
        });
        assertMenuDecodeFails(helper, "ueberlanger Name", buf -> {
            buf.writeUUID(UUID.randomUUID());
            buf.writeUtf("x".repeat(TrickMenuPayload.MAX_NAME_LENGTH + 16));
            buf.writeVarInt(GoobyTrick.SPIN.ordinal());
        });

        FriendlyByteBuf selectBuf = new FriendlyByteBuf(Unpooled.buffer());
        try {
            selectBuf.writeUUID(UUID.randomUUID());
            selectBuf.writeVarInt(GoobyTrick.values().length + 7);
            boolean rejected = false;
            try {
                TrickSelectPayload.STREAM_CODEC.decode(selectBuf);
            } catch (DecoderException exception) {
                rejected = true;
            }
            helper.assertTrue(rejected, "Select-Payload mit unbekannter Trick-Id wurde akzeptiert");
        } finally {
            selectBuf.release();
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Serverseitige Autorisierung
    // ------------------------------------------------------------------

    /** Fremder Spieler, Distanz, Baby, untrainiert und unbekannte Ziele werden abgelehnt. */
    @GameTest(template = ARENA)
    public static void trick_select_server_authorization(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        FakePlayer stranger = fakePlayer(helper, "trick_stranger");
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.ROLL, 1);
        GoobyTrick initialSelection = gooby.getSelectedTrick();

        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, UUID.randomUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.INVALID_TARGET,
                "Unbekannte UUID wurde nicht abgelehnt");
        stranger.moveTo(gooby.getX() + 1.0, gooby.getY(), gooby.getZ(), 0.0F, 0.0F);
        helper.assertTrue(GoobyNetwork.trySelectTrick(stranger, gooby.getUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.NOT_OWNER,
                "Fremder Spieler durfte auswaehlen");
        gooby.setAge(-24000);
        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, gooby.getUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.BABY,
                "Baby-Gooby nahm eine Auswahl an");
        gooby.setAge(0);
        Vec3 nearOwnerPos = owner.position();
        owner.moveTo(nearOwnerPos.x + GoobyNetwork.TRICK_MENU_RANGE + 40.0, nearOwnerPos.y,
                nearOwnerPos.z, 0.0F, 0.0F);
        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, gooby.getUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.TOO_FAR,
                "Distanzpruefung fehlt");
        owner.moveTo(nearOwnerPos.x, nearOwnerPos.y, nearOwnerPos.z, 0.0F, 0.0F);
        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, gooby.getUUID(), GoobyTrick.DANCE)
                        == GoobyNetwork.SelectResult.UNTRAINED,
                "Untrainiertes Kunststueck wurde ausgewaehlt");
        helper.assertTrue(gooby.getSelectedTrick() == initialSelection,
                "Abgelehnte Anfragen veraenderten die Auswahl");

        GoobyEntity dead = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        dead.tame(owner);
        UUID deadId = dead.getUUID();
        dead.discard();
        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, deadId, GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.INVALID_TARGET,
                "Entfernte Entity wurde nicht abgelehnt");

        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, gooby.getUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.SUCCESS,
                "Gueltige Auswahl wurde abgelehnt");
        helper.assertTrue(gooby.getSelectedTrick() == GoobyTrick.ROLL,
                "Erfolgreiche Auswahl setzte das Kunststueck nicht");
        helper.assertTrue(GoobyNetwork.trySelectTrick(owner, gooby.getUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.UNCHANGED,
                "Wiederholung der aktiven Auswahl war kein stiller No-op");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Sneak-Luftpfiff geht in den Menue-Pfad (kein Air-Call) und validiert das Oeffnen. */
    @GameTest(template = ARENA, batch = TRICK_MENU_BATCH)
    public static void whistle_sneak_opens_native_menu(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        // NeoForge reuses one embedded-player UUID across structures. Remove owned
        // Goobys left by completed batches so the global nearest search is ours.
        for (var entity : helper.getLevel().getAllEntities()) {
            if (entity instanceof GoobyEntity stale && stale.isOwnedBy(owner)) {
                stale.discard();
            }
        }
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_WHISTLE.get()));
        owner.setShiftKeyDown(true);
        ModItems.GOOBY_WHISTLE.get().use(helper.getLevel(), owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.WANDER,
                "Sneak-Pfiff loeste faelschlich den Air-Call aus");

        // Mock-Spieler haben keinen Payload-Kanal — openTrickMenu muss trotzdem
        // erfolgreich sein und still auf das Chat-Menue zurueckfallen.
        helper.assertTrue(gooby.openTrickMenu(owner), "Menue-Oeffnung fuer Besitzer scheiterte");
        gooby.setAge(-24000);
        helper.assertFalse(gooby.openTrickMenu(owner), "Baby-Gooby oeffnete das Trick-Menue");
        gooby.setAge(0);
        Vec3 ownerPos = owner.position();
        owner.moveTo(ownerPos.x + GoobyNetwork.TRICK_MENU_RANGE + 40.0, ownerPos.y, ownerPos.z,
                0.0F, 0.0F);
        helper.assertFalse(gooby.openTrickMenu(owner), "Menue oeffnete ueber die Distanzgrenze hinaus");
        owner.moveTo(ownerPos.x, ownerPos.y, ownerPos.z, 0.0F, 0.0F);
        gooby.discard();
        helper.assertFalse(gooby.openTrickMenu(owner), "Menue oeffnete fuer einen entfernten Gooby");
        owner.setShiftKeyDown(false);
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Spam-Drosselung, No-op-Wiederholung und Command-Route
    // ------------------------------------------------------------------

    /** Zweitanfrage im Cooldown wird still verworfen; gleiche Auswahl ist stiller No-op. */
    @GameTest(template = ARENA)
    public static void trick_select_rate_limit_and_noop(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.ROLL, 1);
        gooby.setTrickProficiency(GoobyTrick.DANCE, 2);
        // Frisches Budget: der eingebettete Testspieler teilt seine UUID mit anderen Tests.
        GoobyNetwork.forgetSelectSender(owner.getUUID());

        helper.assertTrue(GoobyNetwork.handleSelectRequest(owner, gooby.getUUID(), GoobyTrick.ROLL)
                        == GoobyNetwork.SelectResult.SUCCESS,
                "Erste Anfrage wurde nicht verarbeitet");
        helper.assertTrue(GoobyNetwork.handleSelectRequest(owner, gooby.getUUID(), GoobyTrick.DANCE)
                        == GoobyNetwork.SelectResult.THROTTLED,
                "Spam im Cooldown-Fenster wurde nicht gedrosselt");
        helper.assertTrue(gooby.getSelectedTrick() == GoobyTrick.ROLL,
                "Gedrosselte Anfrage veraenderte die Auswahl");

        helper.runAfterDelay(GoobyNetwork.SELECT_COOLDOWN_TICKS + 2, () -> {
            GoobyNetwork.SelectResult repeat =
                    GoobyNetwork.handleSelectRequest(owner, gooby.getUUID(), GoobyTrick.ROLL);
            helper.assertTrue(repeat == GoobyNetwork.SelectResult.UNCHANGED,
                    "Wiederholte Auswahl war kein No-op: " + repeat);
            helper.assertTrue(repeat.accepted(), "UNCHANGED muss als akzeptiert gelten");
            helper.assertTrue(gooby.getSelectedTrick() == GoobyTrick.ROLL,
                    "No-op veraenderte die Auswahl");
            TestPlayers.remove(helper, owner);
            helper.succeed();
        });
    }

    /** Der Throttle-Speicher ist hart gedeckelt (LRU) und wird beim Logout geraeumt. */
    @GameTest(template = ARENA)
    public static void trick_select_throttle_bounded_and_cleaned(GameTestHelper helper) {
        int tick = helper.getLevel().getServer().getTickCount();
        for (int i = 0; i < GoobyNetwork.MAX_TRACKED_SELECT_SENDERS + 64; i++) {
            GoobyNetwork.tryAcquireSelectBudget(UUID.randomUUID(), tick);
        }
        helper.assertTrue(
                GoobyNetwork.trackedSelectSenderCount() <= GoobyNetwork.MAX_TRACKED_SELECT_SENDERS,
                "Throttle-Speicher ueberschritt das harte Limit: "
                        + GoobyNetwork.trackedSelectSenderCount());

        // Cooldown-Semantik deterministisch ueber explizit gesetzte Ticks.
        UUID sender = UUID.randomUUID();
        helper.assertTrue(GoobyNetwork.tryAcquireSelectBudget(sender, tick),
                "Erstes Budget wurde verweigert");
        helper.assertFalse(GoobyNetwork.tryAcquireSelectBudget(sender,
                        tick + GoobyNetwork.SELECT_COOLDOWN_TICKS - 1),
                "Cooldown-Fenster wurde nicht durchgesetzt");
        helper.assertTrue(GoobyNetwork.tryAcquireSelectBudget(sender,
                        tick + GoobyNetwork.SELECT_COOLDOWN_TICKS),
                "Budget nach Ablauf des Cooldowns verweigert");
        GoobyNetwork.forgetSelectSender(sender);

        // Logout raeumt den Eintrag auf: PlayerList.remove feuert PlayerLoggedOutEvent.
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyNetwork.forgetSelectSender(owner.getUUID());
        helper.assertTrue(GoobyNetwork.tryAcquireSelectBudget(owner.getUUID(), tick),
                "Setup-Budget wurde verweigert");
        helper.assertFalse(GoobyNetwork.tryAcquireSelectBudget(owner.getUUID(), tick),
                "Eintrag fehlte unmittelbar vor dem Logout");
        TestPlayers.remove(helper, owner);
        helper.assertTrue(GoobyNetwork.tryAcquireSelectBudget(owner.getUUID(), tick),
                "Logout raeumte den Throttle-Eintrag nicht auf");
        GoobyNetwork.forgetSelectSender(owner.getUUID());
        helper.succeed();
    }

    /** /goobytrick laeuft durch exakt dieselbe Netzwerk-Autorisierung (keine Divergenz). */
    @GameTest(template = ARENA)
    public static void goobytrick_command_uses_network_authorization(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setTrickProficiency(GoobyTrick.ROLL, 1);
        gooby.setTrickProficiency(GoobyTrick.SPIN, 2);
        GoobyTrick before = gooby.getSelectedTrick();

        // Untrainiert: der Command-Pfad lehnt genauso ab wie der native Screen.
        GoobyNetwork.forgetSelectSender(owner.getUUID());
        runGoobyTrickCommand(helper, owner, gooby.getUUID() + " dance");
        helper.assertTrue(gooby.getSelectedTrick() == before,
                "Command waehlte ein untrainiertes Kunststueck aus");

        // Distanzgrenze gilt auch fuer den Command.
        GoobyNetwork.forgetSelectSender(owner.getUUID());
        Vec3 pos = owner.position();
        owner.moveTo(pos.x + GoobyNetwork.TRICK_MENU_RANGE + 40.0, pos.y, pos.z, 0.0F, 0.0F);
        runGoobyTrickCommand(helper, owner, gooby.getUUID() + " roll");
        helper.assertTrue(gooby.getSelectedTrick() == before,
                "Command ignorierte die Distanzgrenze");
        owner.moveTo(pos.x, pos.y, pos.z, 0.0F, 0.0F);

        // Gueltige Auswahl klappt; unmittelbarer Command-Spam bleibt wirkungslos.
        GoobyNetwork.forgetSelectSender(owner.getUUID());
        runGoobyTrickCommand(helper, owner, gooby.getUUID() + " roll");
        runGoobyTrickCommand(helper, owner, gooby.getUUID() + " spin");
        helper.assertTrue(gooby.getSelectedTrick() == GoobyTrick.ROLL,
                "Gueltige Command-Auswahl scheiterte oder Spam kam durch");

        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    private static void runGoobyTrickCommand(GameTestHelper helper, ServerPlayer player,
            String arguments) {
        helper.getLevel().getServer().getCommands().performPrefixedCommand(
                player.createCommandSourceStack(), "goobytrick " + arguments);
    }

    /** Chat-Fallback: untrainierte Kunststuecke sind nicht klickbar und erklaeren das Training. */
    @GameTest(template = ARENA)
    public static void trick_chat_menu_locks_untrained(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setTrickProficiency(GoobyTrick.ROLL, 2);

        Component trained = gooby.buildTrickMenuLine(GoobyTrick.ROLL);
        ClickEvent click = trained.getStyle().getClickEvent();
        helper.assertTrue(click != null
                        && click.getValue().equals("/goobytrick " + gooby.getUUID() + " roll"),
                "Trainierter Eintrag traegt kein korrektes Click-Kommando");

        Component locked = gooby.buildTrickMenuLine(GoobyTrick.DANCE);
        helper.assertTrue(locked.getStyle().getClickEvent() == null,
                "Untrainierter Eintrag ist faelschlich klickbar");
        boolean hasTrainingHint = locked.getSiblings().stream().anyMatch(part ->
                part.getContents() instanceof TranslatableContents translatable
                        && "screen.goobymod.trick_select.state.locked".equals(translatable.getKey()));
        helper.assertTrue(hasTrainingHint, "Untrainierter Eintrag erklaert das Training nicht");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Persistenz-Migration
    // ------------------------------------------------------------------

    /** Alte Vier-Trick-Saves laden verlustfrei; neue Kunststuecke starten bei null Sternen. */
    @GameTest(template = ARENA)
    public static void trick_persistence_migrates_legacy_saves(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);

        CompoundTag legacyLevels = new CompoundTag();
        legacyLevels.putByte("spin", (byte) 3);
        legacyLevels.putByte("high_five", (byte) 2);
        legacyLevels.putByte("flop", (byte) 1);
        legacyLevels.putByte("speak", (byte) 0);
        saved.put("TrickProficiency", legacyLevels);
        saved.putByte("SelectedTrick", (byte) GoobyTrick.SPEAK.ordinal());

        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        reloaded.load(saved);
        helper.assertTrue(reloaded.getTrickProficiency(GoobyTrick.SPIN) == 3
                        && reloaded.getTrickProficiency(GoobyTrick.HIGH_FIVE) == 2
                        && reloaded.getTrickProficiency(GoobyTrick.FLOP) == 1
                        && reloaded.getTrickProficiency(GoobyTrick.SPEAK) == 0,
                "Alte Trainingsstaende gingen bei der Migration verloren");
        helper.assertTrue(reloaded.getTrickProficiency(GoobyTrick.ROLL) == 0
                        && reloaded.getTrickProficiency(GoobyTrick.DANCE) == 0,
                "Neue Kunststuecke starteten nicht bei null Sternen");
        helper.assertTrue(reloaded.getSelectedTrick() == GoobyTrick.SPEAK,
                "Persistierte Auswahl ging bei der Migration verloren");

        // Ordinal ausserhalb des Enums (z. B. Downgrade) faellt sicher auf SPIN zurueck.
        saved.putByte("SelectedTrick", (byte) 99);
        reloaded.load(saved);
        helper.assertTrue(reloaded.getSelectedTrick() == GoobyTrick.SPIN,
                "Unbekannte Auswahl-Ordinale fielen nicht auf SPIN zurueck");

        // Neue Saves schreiben alle sechs Kunststuecke inklusive der neuen Staende.
        reloaded.setTrickProficiency(GoobyTrick.ROLL, 2);
        reloaded.setTrickProficiency(GoobyTrick.DANCE, 3);
        CompoundTag resaved = new CompoundTag();
        reloaded.saveWithoutId(resaved);
        CompoundTag levels = resaved.getCompound("TrickProficiency");
        for (GoobyTrick trick : GoobyTrick.values()) {
            helper.assertTrue(levels.contains(trick.serializedName()),
                    "Neuer Save ohne Eintrag fuer " + trick.serializedName());
        }
        helper.assertTrue(levels.getByte("roll") == 2 && levels.getByte("dance") == 3,
                "Neue Trainingsstaende wurden nicht persistiert");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Alle sechs Kunststuecke
    // ------------------------------------------------------------------

    /** Jedes der sechs Kunststuecke laesst sich auswaehlen, trainieren und vorfuehren. */
    @GameTest(template = ARENA)
    public static void all_six_tricks_train_and_perform(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);

        GoobyTrick[] tricks = GoobyTrick.values();
        helper.assertTrue(tricks.length == 6, "Erwartet sechs Kunststuecke, gefunden: " + tricks.length);
        ItemStack treats = new ItemStack(ModItems.TRAINING_TREAT.get(), tricks.length);
        long gameTime = 0L;
        int performed = 0;
        for (GoobyTrick trick : tricks) {
            helper.assertTrue(gooby.selectTrick(owner, trick), "Auswahl scheiterte: " + trick);
            gameTime += GoobyEntity.TRAINING_COOLDOWN_TICKS;
            helper.assertTrue(gooby.trainSelectedTrick(owner, treats, gameTime),
                    "Training scheiterte: " + trick);
            helper.assertTrue(gooby.getTrickProficiency(trick) == 1,
                    "Training vergab keinen Stern: " + trick);
            helper.assertTrue(gooby.requestSelectedTrick(owner), "Vorfuehrung scheiterte: " + trick);
            performed++;
            helper.assertTrue(gooby.getPerformedTrickCount() == performed,
                    "Vorfuehrungszaehler stimmt nicht nach " + trick);
        }
        helper.assertTrue(treats.isEmpty(), "Sechs Trainingssitzungen verbrauchten nicht sechs Happen");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Deterministische Menuedaten und Assets
    // ------------------------------------------------------------------

    /** Menuedaten sind deterministisch, vollstaendig, in Enum-Reihenfolge und namensbegrenzt. */
    @GameTest(template = ARENA)
    public static void trick_menu_payload_deterministic(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setTrickProficiency(GoobyTrick.HIGH_FIVE, 2);
        gooby.setTrickProficiency(GoobyTrick.DANCE, 1);
        gooby.setCustomName(Component.literal("G".repeat(TrickMenuPayload.MAX_NAME_LENGTH + 30)));

        TrickMenuPayload first = TrickMenuPayload.of(gooby);
        TrickMenuPayload second = TrickMenuPayload.of(gooby);
        helper.assertTrue(first.equals(second), "Menuedaten sind nicht deterministisch");
        List<TrickMenuPayload.TrickEntry> entries = first.entries();
        helper.assertTrue(entries.size() == GoobyTrick.values().length,
                "Menue enthaelt nicht alle Kunststuecke");
        for (int i = 0; i < entries.size(); i++) {
            TrickMenuPayload.TrickEntry entry = entries.get(i);
            helper.assertTrue(entry.trick().ordinal() == i, "Menue-Eintraege nicht in Enum-Reihenfolge");
            helper.assertTrue(entry.stars() == gooby.getTrickProficiency(entry.trick()),
                    "Sterne im Menue stimmen nicht: " + entry.trick());
            helper.assertTrue(entry.unlocked() == (entry.stars() > 0),
                    "Unlock-Status inkonsistent: " + entry.trick());
        }
        helper.assertTrue(first.goobyName().length() <= TrickMenuPayload.MAX_NAME_LENGTH,
                "Menue-Name ueberschreitet die harte Grenze");
        helper.assertTrue(first.goobyId().equals(gooby.getUUID()), "Menue traegt falsche Gooby-UUID");

        // Codepoint-sicherer Truncate: ein Surrogate-Paar genau auf der Grenze
        // wird komplett entfernt statt zerschnitten — Roundtrip bleibt byte-treu.
        gooby.setCustomName(Component.literal(
                "G".repeat(TrickMenuPayload.MAX_NAME_LENGTH - 1) + "\uD83D\uDE3A\uD83D\uDE3A"));
        TrickMenuPayload surrogate = TrickMenuPayload.of(gooby);
        helper.assertTrue(surrogate.goobyName().length() <= TrickMenuPayload.MAX_NAME_LENGTH,
                "Surrogate-Name ueberschreitet die harte Grenze");
        helper.assertFalse(Character.isHighSurrogate(
                        surrogate.goobyName().charAt(surrogate.goobyName().length() - 1)),
                "Name endet mit einem halben Surrogate-Paar");
        FriendlyByteBuf surrogateBuf = new FriendlyByteBuf(Unpooled.buffer());
        try {
            TrickMenuPayload.STREAM_CODEC.encode(surrogateBuf, surrogate);
            helper.assertTrue(surrogate.equals(TrickMenuPayload.STREAM_CODEC.decode(surrogateBuf)),
                    "Surrogate-Name ueberlebte den Roundtrip nicht byte-treu");
        } finally {
            surrogateBuf.release();
        }
        helper.succeed();
    }

    /** Clips, Timings, Anticipation/Follow-through-Easings und DE+EN-Keys sind paketiert. */
    @GameTest(template = ARENA)
    public static void trick_wave_assets_complete(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (GoobyTrick trick : GoobyTrick.values()) {
            String clipName = "animation.gooby." + trick.animation();
            helper.assertTrue(animations.has(clipName), "Trick-Clip fehlt: " + clipName);
            JsonObject clip = animations.getAsJsonObject(clipName);
            helper.assertFalse(clip.has("loop") && clip.get("loop").getAsBoolean(),
                    "Trick-Clip darf nicht loopen: " + clipName);
            double clipTicks = clip.get("animation_length").getAsDouble() * 20.0;
            helper.assertTrue(trick.durationTicks() >= clipTicks,
                    "Action-Layer-Dauer kuerzer als der Clip: " + clipName);
        }
        for (String clipName : List.of("animation.gooby.trick_roll", "animation.gooby.trick_dance")) {
            String raw = animations.getAsJsonObject(clipName).toString();
            helper.assertTrue(raw.contains("easeInQuad") || raw.contains("easeInBack"),
                    "Anticipation-Easing fehlt: " + clipName);
            helper.assertTrue(raw.contains("easeOutBack"),
                    "Follow-through-Easing fehlt: " + clipName);
        }
        for (String langFile : List.of("en_us", "de_de")) {
            JsonObject lang = loadAssetJson(helper, "assets/goobymod/lang/" + langFile + ".json");
            for (GoobyTrick trick : GoobyTrick.values()) {
                helper.assertTrue(lang.has(trick.translationKey())
                                && lang.has(trick.descriptionKey()),
                        "Sprachdatei " + langFile + " ohne Eintrag fuer "
                                + trick.name().toLowerCase(Locale.ROOT));
            }
            for (String key : List.of("screen.goobymod.trick_select.title",
                    "screen.goobymod.trick_select.subtitle",
                    "screen.goobymod.trick_select.state.active",
                    "screen.goobymod.trick_select.state.available",
                    "screen.goobymod.trick_select.state.locked",
                    "screen.goobymod.trick_select.state.selected",
                    "screen.goobymod.trick_select.locked_hint",
                    "screen.goobymod.trick_select.narration",
                    "msg.goobymod.trick_menu_too_far")) {
                helper.assertTrue(lang.has(key), "Sprachdatei " + langFile + " ohne Key " + key);
            }
        }
        helper.succeed();
    }
}
