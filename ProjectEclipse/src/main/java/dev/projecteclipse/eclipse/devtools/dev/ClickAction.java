package dev.projecteclipse.eclipse.devtools.dev;

/**
 * How the Dev Handbook and {@code /dev help} treat a command entry when clicked.
 */
public enum ClickAction {
    /** Fixed command with no arguments — click runs it immediately. */
    RUN,
    /** Command has arguments — click suggests it in chat for editing. */
    SUGGEST
}
