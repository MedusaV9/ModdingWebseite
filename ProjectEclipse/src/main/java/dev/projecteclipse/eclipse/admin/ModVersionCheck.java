package dev.projecteclipse.eclipse.admin;

import java.util.Locale;

import org.apache.maven.artifact.versioning.DefaultArtifactVersion;
import org.apache.maven.artifact.versioning.InvalidVersionSpecificationException;
import org.apache.maven.artifact.versioning.VersionRange;

/**
 * Single source of truth for comparing a loaded mod version against a pack pin.
 *
 * <p>Mod authors do not agree on a version syntax: NeoForge metadata versions carry Maven
 * qualifiers ({@code 1.21.1-3.8.3}), SemVer build metadata ({@code 0.8.12+mc1.21.1}) or both,
 * and the same artifact can report a LONGER string at runtime than the coordinate it was
 * resolved by — EMI's {@code dev.emi:emi-neoforge:1.1.24+1.21.1} registers itself as
 * {@code 1.1.24+1.21.1+neoforge}. A plain string equality check therefore flagged a correctly
 * bundled mod as "wrong version", so the pins are matched through this ladder instead:</p>
 *
 * <ol>
 *   <li>{@code *} / blank — pin opted out of version checking.</li>
 *   <li>A Maven range ({@code [4.3.0,)}, {@code [1.0,2.0)}) — evaluated with maven-artifact,
 *       which NeoForge already puts on the classpath for {@code IModInfo#getVersion()}.</li>
 *   <li>A glob ({@code 3.25.71*}) — operator escape hatch, unchanged from the original pin
 *       syntax.</li>
 *   <li>Case-insensitive equality of the FULL strings.</li>
 *   <li>Build metadata tolerance (symmetric): one side is the other plus a trailing
 *       {@code +metadata} block. The common part must match EXACTLY, so
 *       {@code 1.1.24+1.21.1} accepts {@code 1.1.24+1.21.1+neoforge} and {@code 1.1.24},
 *       but never {@code 1.1.24+1.20.1} — a differing metadata block stays a mismatch
 *       because mods encode the target Minecraft version in it.</li>
 *   <li>Maven-normalized equality, which absorbs padding differences such as
 *       {@code 2.26.1} vs {@code 2.26.1.0}.</li>
 * </ol>
 *
 * <p>Everything else is a real mismatch. Both versions are always reported in full by the
 * caller — this class never shortens a version string.</p>
 */
public final class ModVersionCheck {
    /** Pin value that accepts every version. */
    public static final String ANY = "*";

    private ModVersionCheck() {}

    /** Whether {@code installed} satisfies the pack pin {@code expected}. */
    public static boolean matches(String installed, String expected) {
        String want = expected == null ? "" : expected.strip();
        if (want.isEmpty() || ANY.equals(want)) {
            return true;
        }
        String have = installed == null ? "" : installed.strip();
        if (have.isEmpty()) {
            return false;
        }
        if (have.equalsIgnoreCase(want)) {
            return true;
        }
        if (isRange(want)) {
            return inRange(have, want);
        }
        if (want.indexOf('*') >= 0) {
            return globMatches(have, want);
        }
        return isBuildMetadataSuffix(have, want)
                || isBuildMetadataSuffix(want, have)
                || normalizedEquals(have, want);
    }

    /** True for Maven range specs; those are the only pins that may bound several versions. */
    private static boolean isRange(String pin) {
        char first = pin.charAt(0);
        return first == '[' || first == '(';
    }

    private static boolean inRange(String installed, String pin) {
        try {
            return VersionRange.createFromVersionSpec(pin)
                    .containsVersion(new DefaultArtifactVersion(installed));
        } catch (InvalidVersionSpecificationException e) {
            return false;
        }
    }

    /** {@code *} is the only wildcard; every other regex metacharacter is matched literally. */
    private static boolean globMatches(String installed, String pin) {
        StringBuilder regex = new StringBuilder("^");
        for (int i = 0; i < pin.length(); i++) {
            char c = pin.charAt(i);
            if (c == '*') {
                regex.append(".*");
            } else {
                if ("\\.^$|?+()[]{}".indexOf(c) >= 0) {
                    regex.append('\\');
                }
                regex.append(c);
            }
        }
        return installed.toLowerCase(Locale.ROOT)
                .matches(regex.append('$').toString().toLowerCase(Locale.ROOT));
    }

    /**
     * True when {@code longer} is {@code shorter} followed by SemVer build metadata, i.e. the
     * two only differ by a trailing {@code +…} block (EMI's {@code +neoforge}, a jar's
     * {@code +mc1.21.1}). The {@code '+'} boundary keeps this from matching a mere prefix.
     */
    private static boolean isBuildMetadataSuffix(String longer, String shorter) {
        return longer.length() > shorter.length()
                && longer.charAt(shorter.length()) == '+'
                && longer.regionMatches(true, 0, shorter, 0, shorter.length());
    }

    private static boolean normalizedEquals(String installed, String expected) {
        return new DefaultArtifactVersion(installed)
                .compareTo(new DefaultArtifactVersion(expected)) == 0;
    }
}
