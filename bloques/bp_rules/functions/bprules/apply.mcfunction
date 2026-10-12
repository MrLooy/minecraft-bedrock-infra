# bp_rules — reglas del mundo (D-22). Se ejecuta UNA sola vez (bandera de
# scoreboard), la primera vez que el mundo carga tras instalar/actualizar el pack.
# D-22: PVP ACTIVADO. La protección es por zonas seguras (bloque B7 / bp_zonas),
# no global; gamerule pvp es booleano global y aquí queda encendido a propósito.
gamerule pvp true
gamerule keepinventory true
gamerule mobgriefing true
gamerule randomtickspeed 1
gamerule showcoordinates true
gamerule naturalregeneration true
tickingarea add circle 0 0 0 4 spawn
# Marca de "ya aplicado" + apaga el eco de comandos (los builds por consola lo
# vuelven a encender cuando lo necesitan).
scoreboard players set bprules_global bprules 1
gamerule sendcommandfeedback false
