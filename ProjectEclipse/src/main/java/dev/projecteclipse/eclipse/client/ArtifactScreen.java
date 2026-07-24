package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * v1 artifact popup, since W9 a thin alias for the Handbook 2.0
 * ({@link HandbookScreen}, "The Ledger of the Drowned"). Both v1 open paths still work
 * and now show the handbook: the server-sent {@code S2COpenArtifactPayload}
 * ({@link ArtifactScreenOpener}) and the {@code key.eclipse.menu} keybind
 * ({@link ArtifactKeyHandler}). The old 176x166 popup content lives on as the handbook's
 * Status tab; the v1 {@code RulesScreen} became the Rules tab (class deleted — this alias
 * was its only opener).
 *
 * @deprecated construct {@link HandbookScreen} directly; kept so any external reference to
 *             the v1 screen name keeps opening the current menu.
 */
@Deprecated
@OnlyIn(Dist.CLIENT)
public class ArtifactScreen extends HandbookScreen {
}
