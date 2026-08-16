gamemode creative @s
time set day
weather clear
gamerule doDaylightCycle false
gamerule doWeatherCycle false
fill ~-8 ~-1 ~-8 ~8 ~-1 ~8 goobymod:gooby_wool
fill ~-8 ~ ~-8 ~8 ~5 ~8 air
setblock ~-5 ~ ~-4 goobymod:rabbit_hutch
setblock ~-2 ~ ~-4 goobymod:nutella_jar
setblock ~2 ~ ~-4 goobymod:nutella_cake
summon goobymod:gooby ~-4 ~ ~1 {CustomName:'{"text":"Mochi"}',PersistenceRequired:1b}
summon goobymod:gooby ~ ~ ~1 {CustomName:'{"text":"Truffle"}',PersistenceRequired:1b}
summon goobymod:gooby ~4 ~ ~1 {CustomName:'{"text":"Pip"}',PersistenceRequired:1b}
give @s goobymod:nutella 16
give @s goobymod:gooby_brush 1
give @s goobymod:gooby_whistle 1
give @s goobymod:training_treat 16
give @s goobymod:gooby_handbook 1
give @s goobymod:gooby_scarf 1
give @s goobymod:gooby_bowtie 1
give @s goobymod:tiny_satchel 1
give @s goobymod:torn_map_scrap 4
give @s minecraft:name_tag 3
tellraw @s {"translate":"handbook2.goobymod.title","color":"gold"}
