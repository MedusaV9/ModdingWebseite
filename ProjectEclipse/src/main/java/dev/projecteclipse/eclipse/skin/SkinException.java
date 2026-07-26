package dev.projecteclipse.eclipse.skin;

/**
 * A skin pipeline failure that already knows how to explain itself to the command sender:
 * every throw site carries a lang key plus its arguments, so the async worker never has to
 * ship a raw stack trace or an English-only string back to the operator.
 */
public class SkinException extends Exception {
    private static final long serialVersionUID = 1L;

    private final String langKey;
    private final transient Object[] args;

    public SkinException(String langKey, Object... args) {
        super(langKey);
        this.langKey = langKey;
        this.args = args;
    }

    public String langKey() {
        return langKey;
    }

    public Object[] args() {
        return args.clone();
    }
}
