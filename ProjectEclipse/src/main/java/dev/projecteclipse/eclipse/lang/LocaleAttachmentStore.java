package dev.projecteclipse.eclipse.lang;

import java.util.function.Supplier;

import com.mojang.serialization.Codec;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.attachment.AttachmentType;
import net.neoforged.neoforge.registries.DeferredRegister;
import net.neoforged.neoforge.registries.NeoForgeRegistries;

/**
 * Self-contained {@code eclipse:locale_override} attachment ({@code docs/plans_v3/P3_ui.md} P3-W4).
 * W4 registers this directly so parallel workers do not block on the {@code EclipseAttachments}
 * integrator ledger; the integrator should dedupe if the hub copy is also added.
 */
final class LocaleAttachmentStore {
    static final DeferredRegister<AttachmentType<?>> ATTACHMENTS =
            DeferredRegister.create(NeoForgeRegistries.ATTACHMENT_TYPES, EclipseMod.MOD_ID);

    static final Supplier<AttachmentType<String>> LOCALE_OVERRIDE = ATTACHMENTS.register(
            "locale_override",
            () -> AttachmentType.builder(() -> "").serialize(Codec.STRING).copyOnDeath().build());

    static {
        ATTACHMENTS.register(net.neoforged.fml.ModLoadingContext.get().getActiveContainer().getEventBus());
    }

    private LocaleAttachmentStore() {}

    static void set(ServerPlayer player, String locale) {
        player.setData(LOCALE_OVERRIDE, locale);
    }

    static void clear(ServerPlayer player) {
        player.setData(LOCALE_OVERRIDE, "");
    }

    static String read(ServerPlayer player) {
        if (!player.hasData(LOCALE_OVERRIDE)) {
            return "";
        }
        String value = player.getData(LOCALE_OVERRIDE);
        return value != null ? value : "";
    }
}
