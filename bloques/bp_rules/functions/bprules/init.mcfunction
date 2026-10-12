# bp_rules — inicializador (se ejecuta cada tick vía functions/tick.json).
# Bedrock NO soporta el tag Java "load" (solo functions/tick.json), así que
# corremos cada tick con una bandera de scoreboard para aplicar SOLO UNA VEZ.
scoreboard objectives add bprules dummy
execute unless score bprules_global bprules matches 1 run function bprules/apply
