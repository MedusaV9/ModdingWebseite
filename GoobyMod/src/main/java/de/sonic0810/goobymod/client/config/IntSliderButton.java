package de.sonic0810.goobymod.client.config;

import java.util.function.IntConsumer;
import net.minecraft.client.InputType;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.AbstractSliderButton;
import net.minecraft.client.gui.navigation.CommonInputs;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import org.lwjgl.glfw.GLFW;

/**
 * Integer slider with keyboard steps that make sense for pixel offsets:
 * vanilla's {@link AbstractSliderButton} moves by one slider-pixel per arrow
 * press (~20 config pixels over a 0..4096 range), this widget moves by exactly
 * 1 (or {@value #SHIFT_STEP} with Shift held). Narration comes from the
 * vanilla slider ("gui.narrate.slider" plus usage hints).
 */
final class IntSliderButton extends AbstractSliderButton {
    private static final int SHIFT_STEP = 16;

    private final Component name;
    private final int min;
    private final int max;
    private final IntConsumer onChange;
    /** Mirrors vanilla's private canChangeValue arrow-key activation state. */
    private boolean arrowStepping;

    IntSliderButton(int width, int height, Component name, int min, int max, int initialValue,
            IntConsumer onChange) {
        super(0, 0, width, height, CommonComponents.EMPTY, 0.0);
        this.name = name;
        this.min = min;
        this.max = max;
        this.onChange = onChange;
        setIntValue(initialValue);
    }

    int intValue() {
        return this.min + (int) Math.round(this.value * (this.max - this.min));
    }

    void setIntValue(int newValue) {
        int clamped = Mth.clamp(newValue, this.min, this.max);
        this.value = (clamped - this.min) / (double) (this.max - this.min);
        this.onChange.accept(clamped);
        updateMessage();
    }

    @Override
    protected void updateMessage() {
        setMessage(CommonComponents.optionNameValue(this.name,
                Component.translatable("config.goobymod.hud.pixels", intValue())));
    }

    @Override
    protected void applyValue() {
        this.onChange.accept(intValue());
    }

    @Override
    public void setFocused(boolean focused) {
        super.setFocused(focused);
        if (!focused) {
            this.arrowStepping = false;
            return;
        }
        InputType inputType = Minecraft.getInstance().getLastInputType();
        if (inputType == InputType.MOUSE || inputType == InputType.KEYBOARD_TAB) {
            this.arrowStepping = true;
        }
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (CommonInputs.selected(keyCode)) {
            this.arrowStepping = !this.arrowStepping;
            // Keep the superclass' internal activation flag (and thereby the
            // focus sprite) in sync with our own.
            super.keyPressed(keyCode, scanCode, modifiers);
            return true;
        }
        boolean left = keyCode == GLFW.GLFW_KEY_LEFT;
        if (this.arrowStepping && (left || keyCode == GLFW.GLFW_KEY_RIGHT)) {
            int step = Screen.hasShiftDown() ? SHIFT_STEP : 1;
            setIntValue(intValue() + (left ? -step : step));
            return true;
        }
        return false;
    }
}
