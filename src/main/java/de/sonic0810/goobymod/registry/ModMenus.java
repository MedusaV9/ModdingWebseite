package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.menu.GoobySatchelMenu;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.inventory.MenuType;
import net.neoforged.neoforge.common.extensions.IMenuTypeExtension;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Container menus owned by Gooby entities. */
public final class ModMenus {
    public static final DeferredRegister<MenuType<?>> MENUS =
            DeferredRegister.create(Registries.MENU, GoobyMod.MODID);

    public static final DeferredHolder<MenuType<?>, MenuType<GoobySatchelMenu>> GOOBY_SATCHEL =
            MENUS.register("gooby_satchel", () -> IMenuTypeExtension.create(GoobySatchelMenu::new));

    private ModMenus() {
    }
}
