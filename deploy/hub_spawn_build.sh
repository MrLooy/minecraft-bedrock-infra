#!/usr/bin/env bash
# D-41: construir el vestibulo del spawn (Redstone Peru).
# Centro del spawn=(100,156), suelo y=64 (medido por bp_spawn). Radio protegido=32.
# Se ejecuta con la consola del servidor (no dispara eventos de jugador).
set -uo pipefail
source /opt/mcserver/config/mc.conf
CONS="$MC_HOME/modules/consola.sh"

cmds=(
  # base solida (2 capas) + piso
  "fill 89 62 145 111 63 167 minecraft:stone"
  "fill 89 64 145 111 64 167 minecraft:polished_andesite"
  "fill 97 64 153 103 64 159 minecraft:smooth_stone"
  # despejar el volumen interior
  "fill 89 65 145 111 70 167 minecraft:air"
  # antepecho / muro bajo (y65-66)
  "fill 89 65 145 111 66 145 minecraft:stone_bricks"
  "fill 89 65 167 111 66 167 minecraft:stone_bricks"
  "fill 89 65 145 89 66 167 minecraft:stone_bricks"
  "fill 111 65 145 111 66 167 minecraft:stone_bricks"
  # puerta (lado sur, centro)
  "fill 99 65 167 101 66 167 minecraft:air"
  # columnas en las 4 esquinas
  "fill 89 65 145 89 69 145 minecraft:stripped_oak_log"
  "fill 111 65 145 111 69 145 minecraft:stripped_oak_log"
  "fill 89 65 167 89 69 167 minecraft:stripped_oak_log"
  "fill 111 65 167 111 69 167 minecraft:stripped_oak_log"
  # techo
  "fill 89 70 145 111 70 167 minecraft:dark_oak_slab"
  # luces en el techo
  "setblock 94 70 150 minecraft:glowstone"
  "setblock 106 70 150 minecraft:glowstone"
  "setblock 94 70 162 minecraft:glowstone"
  "setblock 106 70 162 minecraft:glowstone"
  # escalera de salida (sur): SOLO 2 escalones tras la puerta (umbral y=65),
  # ya que el terreno al sur esta a nivel (~y=65-66). Ancho x=99..101.
  "fill 99 65 168 101 65 168 minecraft:stone_bricks"
  "fill 99 66 169 101 66 169 minecraft:stone_bricks"
  "fill 99 66 168 101 70 168 minecraft:air"
  "fill 99 67 169 101 70 169 minecraft:air"
  # punto de aparicion en el centro del vestibulo
  "setworldspawn 100 65 156"
)

"$CONS" "gamerule sendcommandfeedback true"
sleep 0.4
for c in "${cmds[@]}"; do
  "$CONS" "$c"
  sleep 0.4
done
"$CONS" "gamerule sendcommandfeedback false"
echo "VESTIBULO LISTO"
