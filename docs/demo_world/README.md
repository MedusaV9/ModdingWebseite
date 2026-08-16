# Gooby v5 showcase world blueprint

This directory is the source-controlled, reproducible form of the trailer
showcase. It avoids committing volatile region/session/player data.

1. Create a **Creative / Superflat** Minecraft 1.21.1 world with Gooby Mod
   v5.0.0 loaded.
2. Copy `datapacks/gooby_showcase` into that world's `datapacks/` directory.
3. Open the world and run `/function goobymod:setup`.

The function sets stable daylight/weather, builds a soft display pad, places
the core home blocks, summons a named Gooby group, and gives the presenter the
items needed to demonstrate taming, care, commands, training, fashion,
family, and treasure trails.

The blueprint is intentionally deterministic and contains no personal UUIDs,
cached chunks, or client options. Camera paths and optional Create machinery
remain presenter-controlled so the same source works with and without Create.

Made by Sonic0810.
