# BLOQUES — catálogo evaluado (D-08)

Un **bloque** = un add-on (behavior/resource pack) o script que se enciende/apaga
copiando una línea en `world_behavior_packs.json` / `world_resource_packs.json`.
Nunca se edita código de otro bloque: si algo hay que cambiar, se desenchufa.

## Lista final (evaluada)

| ID | Bloque | Tipo | Origen | Función | Coste | Estado |
|----|--------|------|--------|---------|-------|--------|
| B1 | `bp_status` | BP propio | este repo | Reporta a consola el contador de jugadores (respaldo de Q1 + fuente del panel) | ~0 MB | ✅ incluido |
| B2 | `bp_rules` | BP propio | este repo | Reglas del mundo **v1.0.1**: PVP on (D-22), keepInventory, randomtickspeed, showcoordinates, naturalregeneration + ticking area `spawn`. Se aplican **una sola vez al cargar** vía `functions/tick.json` + bandera de scoreboard (Bedrock **no** soporta el tag Java `load`, D-42) | ~0 MB | ✅ **en producción** 2026-10-11 (D-42) |
| B3 | Advanced Gravestone (tumbas) | BP+RP | MCPEDL/CurseForge 1471818 (v1.3.0, 26.50) | Cofre-tumba al morir | ~1 MB | ✅ **en producción** 2026-10-08 |
| B4 | Travel Backpacks (mochilas) | BP+RP | CurseForge 1595055 (v0.3.0, 26.40) | Mochilas 15-27 huecos | ~1 MB | ✅ **en producción** 2026-10-08 |
| B5 | Glowing Ores+ (minerales brillantes) | RP puro | CurseForge 1682841 (v1.0, 26.50) | Resalta vetas; coste cero (no coloca bloques de luz) | ~0.5 MB | ✅ **en producción** 2026-10-08 |
| B6 | Adventures Structures | BP | MCPEDL/CurseForge 1544887 (V.10, 26.50) | Estructuras + mazmorras en el mundo ya generado | ~2 MB | ✅ **en producción** 2026-10-08 (¡generar mundo D-04 ANTES!) |
| B7 | The Land Claim Addon 4.0 | BP+RP | CurseForge 1314585 (file 8581433) | Zonas reclamadas: protección de bloques/contenedores (PvP **queda normal** dentro — así lo aprobó Elías Canaquiri (MrLooy) 2026-10-07) | ~2 MB | ✅ **en producción** 2026-10-07 (parche de manifest, ver abajo) |
| B8 | Mob Variants | BP+RP | CurseForge 1356602 (file 8956792), MIT | Variantes de mobs por bioma/cueva/nether | ~0.4 MB / <30 MB RAM | ✅ **en producción** 2026-10-07 |
| B9 | Weapons Plus | BP+RP | CurseForge 1252430 (files 7443197/7443200) | 26 armas (D-15) | ~1 MB | ✅ **en producción** 2026-10-07 |
| B10 | `bp_dyeable` | BP propio | futuro | `minecraft:is_dyeable` en mobs | ~0 MB | 📋 posterior (P-05) |
| B12 | ExtraBiomes | BP+RP | CurseForge 918166 (file 8411875, v3.0.0) | 24 biomas nuevos (charred_forest, mystic_forest, glacier…) | ~10 MB | ✅ **en producción** 2026-10-08 (manifest saneado + parches, ver abajo) |
| B13 | More Crazy Wands | BP+RP | CurseForge 1230004 (file 8690984, v2.9.8) | 13 báculos mágicos (dragon, poison, lightning, lifesteal, freezing, fire, xp, summoning, nightskeeper, mining, magnetic, fly, ender) + bolsa guardabáculos | ~0.05 MB | ✅ **en producción** 2026-10-09 (saneado: 9 recetas rotas + campos de entidad, ver abajo) |
| B16 | Aplok Guns (pistolas) | BP+RP | CurseForge 1125776 (file 7306900, v1.1.8) | Pistolas con munición, estilo vanilla, survival craftable, sin experimentos | ~2 MB | ✅ **en producción** 2026-10-10 (saneado, ver abajo) |
| B17 | PG's More Armor and Tools | BP+RP | CurseForge 1559395 (file 8884283, v1.0.1) | 19 sets + 19 materiales nuevos, achievements-friendly | ~3 MB | ✅ **en producción** 2026-10-10 (saneado, ver abajo) |
| B18 | Elytra+ Fx | RP puro | CurseForge 1451340 (file 8265359, v1.1.0) | 10 estilos de elytra con FX, selector de subpack | ~0.1 MB | ✅ **en producción** 2026-10-10 |
| B20 | Tame A Chicken! | BP+RP | CurseForge 1624415 (file 8574364, v1.9.0) | Gallinas domesticables (taming con semillas, crías heredan dueño) | ~0.1 MB | ✅ **en producción** 2026-10-10 (D-36) |
| B21 | Animal Fun Zoo (Land + Birds) | BP+RP | CurseForge 1638111 (file 9013486, v1.61.1) + 1638171 (file 9015664, v1.15.12) | **96 animales terrestres + 67 aves** (mapache, castor, nutria, águilas, búhos…) con taming/cría/montar/zoo | ~19 MB | ✅ **en producción** 2026-10-10 (D-37; RAM +~180 MB) |
| B22 | Lynx More Weapons | BP+RP | CurseForge 1667566 (file 9085732, v1.3.1) | **50 armas** (7 tipos × 7 materiales), sin scripts, achievements-friendly | ~0.1 MB | ✅ **en producción** 2026-10-10 (D-38) |
| B23 | Weapon Combiner Revamp | BP+RP | CurseForge 1500902 (file 7906497, v1.0.0) | Bloque *Materia Conflux*: **fusiona armas + materiales → habilidades** (p. ej. onda de fuego al recibir daño); API estable `@minecraft/server` 2.6.0 | ~0.3 MB | ✅ **en producción** 2026-10-10 (D-38) |
| B24 | Arcane Enchantment | BP+RP | CurseForge 1700826 (file 8965618, v1.0.1) | *Blank Tome* → menú para **crear libros de encantamiento a elección** por XP; API estable `@minecraft/server` 2.10.0 | ~0.2 MB | ✅ **en producción** 2026-10-10 (D-38) |
| B26 | `bp_spawn` | BP propio | este repo | **Spawn indestructible** (radio 32 en X/Z, centro = spawn real) + aviso de bienvenida + **kit inicial** (una vez por jugador) + vestíbulo 23×23; cancela romper/colocar/explosiones en la zona (exentos OP y tag `staff`); dep `@minecraft/server` 1.14.0 | ~0 MB | ✅ **en producción** 2026-10-11 (D-41) |
| B11 | Q1 cola Discord | fuera del server | `modules/status.sh` | Contador en Discord (D-16) | — | ✅ incluido (no es bloque) |

**Descartados:** tinte de armas (no existe para 26.x), Pterodactyl (RAM), Q2 nativa
(no hay cola en BDS), `chunk-radius` (no existe en Bedrock).

**D-22 (revisión 2026-10-07, decisión de Elías Canaquiri (MrLooy)):** el PvP está **encendido** y
**sigue activo dentro de las zonas de B7** — la zona solo protege bloques y
contenedores ajenos. La opción `pvp` por zona del addon queda disponible por si
más adelante se quiere apagar dentro de alguna zona.

**D-23:** B6/B7 se aplican **sobre el mundo ya generado en BDS** (generación nativa,
sin Chunker — D-23 revisado 2026-10-08). **B6 se instaló ANTES de la regeneración**
(2026-10-08) con densidad ×3 (spacing/separation de `structure_sets`), así que las
estructuras nacen desde el primer chunk.

**B12 (ExtraBiomes) parches 2026-10-08:** manifest original con comentarios `//`
(lo rechazaba BDS) → saneado a JSON válido; 44 bloques con `minecraft:liquid_detection`
subidos a `format_version: 1.21.60` (sin eso BDS exige el toggle experimental
"Upcoming Creator Features", y por actualización de mundo no se podía); y
`menu_category.group` con namespace `minecraft:itemGroup.name.*` donde format ≥
1.21.60 y `itemGroup.name.*` (sin namespace) donde format < 1.21.60 (BDS antepone
`minecraft:` y `minecraft:minecraft:itemGroup…` es inválido). Empaquetado limpio:
`blocks.d/b10_extrabiomes/ExtraBiomes_3.0.0_limpio.mcaddon`. Quedan 34 avisos
benignos `[FeatureRegistry] No definition found for feature 'minecraft:*'`
(fern_feature, select_oak_tree_feature…) — inherentes al addon (referencia features
vanilla que BDS no registra); los biomas cargan y no impiden el arranque.

**B13 (More Crazy Wands) saneo 2026-10-09:** el addon traía de fábrica **9 recetas
rotas** (7 apuntaban a báculos que no existen en esta versión — `farmin`, `invisible`,
`magicpath`, `revive`, `teleport`, `weather`, `zooming` — y 2 JSON vacíos `{}`:
`zc_miner_ban`, `zc_temporary_path`) y la entidad `zc:szombile` con `max_dist`/`target_dist`
inválidos en `minecraft:behavior.melee_attack`. Quité solo eso (parches mínimos, mismos
patrones que B12), dejando los **13 báculos funcionales**. Empaquetado limpio:
`blocks.d/b13_crazy_wands/MCWand2.9.8_fixed.mcaddon` (originales guardados como `.orig`).
Staging verde tras 2 rondas de saneo: primero recetas (ROJO recetas), luego entidad
(VERDE). En producción arranca sin errores; quedan 3 WARN benignos
`[Scripting] Component 'zc_*:trigger' was not registered in script` (lifesteal, pouch,
`zc_wban`) — son custom_components declarados pero no usados; su efecto se dispara por
`itemUse` en los scripts del propio addon.

**B16/B17/B18 saneo 2026-10-10 (D-31, Elías Canaquiri (MrLooy) eligió "pistolas, armaduras, elytra"):**
- **B16 Aplok Guns:** ambos manifest originales traían comentarios `/* ... */` de licencia al principio
  (JSON inválido para BDS) → saneado a `blocks.d/b16_pistolas/aplok_guns_fixed.mcaddon` (original en
  `.mcaddon.orig`). WARN benigno: receta duplicada `trenbankai:glock18`.
- **B17 PG's More Armor:** además de los comentarios `/* */`, traía `format_version: 3` en el manifest
  → **BDS 1.26.52.3 lo rechaza** (mismo fallo que B15): `[Packs] -> header -> version: invalid string`
  + `Configured pack (id: …) was not found and was ignored`. Y `header.version: "1.0.1"` como **string**
  (el instalador `install_block.sh` exige lista `[m,n,p]` → `ValueError: invalid literal for int()`).
  Fix: `format_version: 2` + versión normalizada a `[1,0,1]`. Empaquetado en
  `blocks.d/b17_armor_more/pg_more_armor_fixed.mcaddon` (original en `.mcaddon.orig`).
- **B18 Elytra+ Fx:** RP puro (format 2), sin saneo; se instala el `.mcpack` tal cual.
- **Lección (D-32): los manifest con `format_version: 3` NO cargan en BDS 1.26.52.3.**
  Todo pack del catálogo debe usar `format_version` 1 o 2.
- **B15 FPS Optimizer arreglado 2026-10-10:** mismo saneo (`fmt 3` → 2) en
  `blocks.d/b15_fps_optimizer/FPS_Optimizer_v2.9.1_fixed.mcpack` — arrastraba ROJO en staging
  (pre-existente; no era parte de D-31).
- Prod resultante: **Pack Stack 12 BP + 11 RP, 0 errores** (bp_status/bp_rules antes del slot 5 por orden
  del JSON). Backup previo de los JSON interruptor en `/opt/mcserver/backups/20261010-0820/`.

## Cómo se enciende/apaga

```bash
# añadir (copia + escribe línea)
modules/install_block.sh add /ruta/al/pack bp

# apagar sin borrar (solo borra la línea)
modules/install_block.sh disable <pack_id>

# encender de nuevo
modules/install_block.sh enable  <pack_id>

# ver estado
modules/install_block.sh list
```

Después de tocar esto: `sudo systemctl restart mc` (los packs se leen al arrancar).

## Reglas

1. Un bloque = una carpeta autónoma. Prohibido que un bloque edite a otro.
2. Todo cambio de bloques **se apaga en staging primero** (D-11: gate de Elías Canaquiri (MrLooy)).
3. Los `.mcaddon` se instalan igual: `install_block.sh add archivo.mcaddon bp`.
4. Descargas manuales: van a `blocks.d/<nombre>/` en el VPS; el repo solo guarda
   la ficha (licencia, versión, enlace) — no redistribuimos archivos de terceros.
5. `B6` (estructuras): solo ANTES de generar el mundo o el mapa queda con huecos.

## Staging de bloques (gate de Elías Canaquiri (MrLooy))

```bash
modules/stage_bloques.sh start    # monta BDS de prueba en el puerto 19134 con TODO lo staged
modules/stage_bloques.sh status   # pack stack + errores
modules/stage_bloques.sh stop
```

- Descargas viven en `$MC_BLOCKS_DIR` (`/opt/mcserver/blocks.d/<nombre>/`);
  `stage_bloques.sh` extrae `.mcaddon`/`.mcpack`/`.zip` (recursivo) a
  `staging/staged/` y los enciende SOLO en staging (prod no se toca).
- El mundo de staging se conserva entre arranques; el resto del binario se
  reconstruye (mismo BDS que prod, mismos packs vanilla, config/default copiado).
- **B7 requiere parche**: su manifest pide `@minecraft/server 2.10.0-beta` +
  `@minecraft/server-ui 2.2.0-beta`, que BDS 1.26.52 **no acepta** ("invalid
  version"; solo hay UNA beta por release: `2.11.0-beta`, y estables `≤2.10.0`).
  El archivo en `blocks.d/b7_land_claim/*.mcaddon` quedó **parcheado a
  `2.10.0` + `2.2.0` (estables)** — original guardado en `*.mcaddon.orig`.
  Así B7 NO necesita el experimento "Beta APIs" (nivel de mundo / level.dat).
- Ruido conocido al arrancar staging: 31 líneas `ERROR [FeatureRegistry] world |
  No definition found for feature 'minecraft:*'` durante la generación de chunks
  nuevos. NO viene de los bloques (se reprodujo con 0 bloques staged) y
  producción no las muestra porque sus chunks ya están generados; packs de
  staging y prod son idénticos byte a byte (`diff -rq`).

## Plantillas

- `templates/world_behavior_packs.json` → dentro del nivel activo (`$MC_WORLD/` = `worlds/<level-name>/`)
- `templates/world_resource_packs.json` → dentro del nivel activo (`$MC_WORLD/`)

Versión del Script API: si BDS 1.26 reclama otra versión de `@minecraft/server`,
la consola lo dice al arrancar y se ajusta en `manifest.json` del bloque.

## Candidatos D-31 (investigación 2026-10-10) — RESUELTOS: instalados B16/B17/B18

Petición de Elías Canaquiri (MrLooy): **pistolas, armaduras nuevas, skins de elytra, shaders**.
Elegidos y en producción (B16/B17/B18, ver arriba); shaders no existen en Bedrock (C-4).

### C-1 Pistolas (BP+RP)

| Opción | Origen | Notas | Riesgo |
|--------|--------|-------|--------|
| **Aplok Guns** ✅ **instalado (B16)** | CurseForge 1125776 (994K desc.) | Estilo vanilla, **sin experimentos**, optimizado para dispositivos bajos, survival craftable | Actualizado a 1.21.51: verificar soporte 26.x en staging |
| **Actual Guns 2** | CurseForge "actual-guns-addon" (1.8M desc., mayo 2026) | 34 armas 3D, muy pulido | Usa **player.json** → conflicto probable con otros addons de jugador; remake grande en curso |
| **ACT LEGACY** | CurseForge "fully-survival-friendly" | 4 armas profundas (adjuntos, balística), 100% survival | Poco contenido; nicho |
| **Peters Guns** | CurseForge | 50+ armas | **Requiere experimentos (Beta APIs)** → descartado para prod |

⚠️ **Ojo:** ya tenemos B9 Weapons Plus (26 armas cuerpo a cuerpo) + B13 More Crazy Wands.
Las pistolas son de disparo con munición — añaden latencia por proyectiles/partículas;
probar RAM/CPU en staging con 2-3 jugadores simulados antes de decidir.

### C-2 Armaduras nuevas (BP+RP)

| Opción | Origen | Notas |
|--------|--------|-------|
| **PG's More Armor and Tools** ✅ **instalado (B17)** | CurseForge (sep 2026) | 19 sets + 19 materiales nuevos, achievements-friendly, activo |
| **Armor+** | CurseForge (sep 2026, hasta 26.40) | 20 espadas + 20 sets con habilidades |
| **New Armors Overhaul** | CurseForge (oct 2026) | 7 sets con habilidades activas (Shift+click) |
| **R&A Armory** | CurseForge (ago 2026) | Táctica modular (placas, cascos); pesado, estilo shooter — encaja si van a por lo militar con pistolas |

### C-3 Skins de elytra (RP puro — coste ~0)

| Opción | Origen | Notas |
|--------|--------|-------|
| **Elytra+ Fx** ✅ **instalado (B18)** | CurseForge "elytra-fx" (jun 2026) | 10 estilos (dragón, allay, angelical…) con FX, selector de subpack |
| **Cosmetic Elytra** | enchanted.games | 13+ overlays, selector por subpack |
| **Elytra Trails** | CurseForge (ago 2026, 26.40) | Estelas de colores al volar; RP puro, sin BP |

RP puro = no toca lógica del server; el más barato en riesgo de todos.

### C-4 Shaders — SIN EQUIVALENTE EN BEDROCK

- **Los shaders de Java (Optifine/Iris) NO existen en Bedrock.** No hay forma de
  instalarlos en el server.
- Lo máximo disponible:
  - **RTX / Deferred rendering**: solo Windows (GPU RTX) y ahora "Vibrant Visuals"
    en algunos dispositivos; es **client-side** — el server no lo instala, cada
    jugador lo activa en su cliente si su dispositivo lo soporta.
  - **Resource packs "fake shaders"** (cielos, agua, sombras texturizadas): RP puro,
    solo cambia lo visual para quien los active en su cliente.
- **Decisión:** si Elías Canaquiri (MrLooy) quiere "que el server tenga shaders", la respuesta es
  "no se puede forzar"; sí se puede recomendar a los jugadores un RP visual o
  habilitar Vibrant Visuals si su cliente lo soporta. → **A TRATAR CON Elías Canaquiri (MrLooy)**

## Candidatos fauna/domesticación (investigación 2026-10-10)

Petición de Elías Canaquiri (MrLooy): **más variedad de animales (castores, mapaches, aves…) y domesticación**.
Todo candidato debe pasar el gate de staging (D-11) con 2-3 jugadores antes de producción.

> ### ⚑ RESULTADO (2026-10-10) — ver D-36
> Tras probar en staging y decidir con Elías Canaquiri (MrLooy) (**solo Tame A Chicken + buscar alternativas**):
> - ✅ **Tame A Chicken! V1.9 — INSTALADO en producción** (B20; BP `4bfc1665-12b5-4886-95de-ad2406871a1d` +
>   RP `1cbd2403-d4cf-42f4-b6e4-3bf6478e6a87`; Pack Stack [07]). Staging VERDE, 0 errores.
>   Backup `world_*_packs.json` en `/opt/mcserver/backups/d36-tamechicken-20261010-220711/`.
> - 🅿️ **Aurorian Animals — PARKEADO, no instalado** (ROJO en staging): sus aves usan
>   `minecraft:damage_sensor` con `cause: "fatal"` que BDS 1.26.52.3 ya no reconoce
>   (`Damage Source not found: fatal`) **y sobreescribe `minecraft:player` entero** → choca con
>   Aplok Guns (B16). Movido a `/opt/mcserver/blocks.parked/b19_aurorian_animals/`.
> - ❌ **VanillA Animals — INVIABLE**: única fuente (modbem) con host de descarga roto
>   (sirve una app Vue alemana); sin mirror en CF/MCPEDL.
> - ✅ **Animal Fun Zoo (Land + Birds) — INSTALADO en producción** (B21; ver D-37):
>   base **Animal Fun - Land v1.61.1** (CF `1638111`/`9013486`, BP `e00762d5-…` + RP `8981cf51-…`)
>   + **Animal Fun: Birds v1.15.12** (CF `1638171`/`9015664`, BP `25306524-…` + RP `ef40bd73-…`).
>   **96 terrestres** (mapache, castor, nutria, tejón…) + **67 aves** con taming/cría/montar/zoo.
>   Sin experimentos (script API estable 2.1.0), `format_version 2`, min_engine 1.26.0,
>   **no sobreescribe entidades/recetas vanilla** (no toca `player.json`). Staging VERDE (30 bloques),
>   Pack Stack **[13]/[14]**, 0 errores, RAM ~621 MB (subió ~180 MB) → **a vigilar**.
>   Backup en `/opt/mcserver/backups/d37-animalfun-20261010-223338/`.
> - ❌ **The More Animals Project — descartado**: el autor avisa "everything broke, remaking from scratch".

⚠️ **Filtros de descarte (reglas del proyecto):**
- Debe cargar en BDS 1.26.52.3 → manifest **`format_version ≤ 2`** (D-32); si trae
  `format_version: 3` hay que sanearlo o descartarlo.
- **Sin experimentos / Beta APIs** (por lo de B7). Si exige "Experimental Gameplay" → descartar para prod.
- Evitar los que tocan **`player.json`** (conflicto con otros addons de jugador).
- Vigilar **RAM/CPU**: el VPS llegó a ~393 MB RSS; muchos mobs con IA/scripts suben el consumo.
- Nota: los mobs nuevos **no requieren regenerar el mundo** (a diferencia de B6): nacen en
  chunks ya generados según reglas de spawn del bioma.

### F-1 Fauna realista (especies nuevas, tamicables) — candidatos fuertes

| Opción | Origen | Contenido | Notas | Riesgo |
|--------|--------|-----------|-------|--------|
| **VanillA Animals** | modbem / Hams22 (oct 2025) | 9 especies: **castor, mapache**, panda rojo, loros/macaw, alce, zorro… | Ligero, **sin scripts**, estilo vanilla; castores construyen presas, mapaches hurgan | **Bajo** |
| **Aurorian Animals** | CurseForge / VictaoSigma | Fauna con breeding + ciclo de sueño, **tamicables** (aves: pato, pavo, faisán, pavo real, guineafowl…) | **Sin experimentos**; ideal para **aves + domesticación** | Bajo-Medio |
| **The More Animals Project** | CurseForge / Mateosaurio_rex | ~86 especies (águilas, búho, colibrí, paloma, shoebill…) | Máxima variedad de aves; 22.5 MB; manifest 1.21.0+; autor en mantenimiento ("fixed") | Medio |
| **World Animals** | CurseForge MrNido / remaster GitHub shaiku | 70+ animales, **domesticación con "hueso de oro"**, montables, DNA/mamuts | Remaster 1.21.20+ **sin Holiday Creator Features**; grande y script-heavy | **Alto (RAM)** |
| Entity Taiga / Immersive Fauna Taiga | MCModsHub / CurseForge | moose, búho, castor, mapache, pato, ciervo, oso (7-11) | **Requiere experimentos** | ❌ descartado prod |
| Animal Pack 500+ | mcpeuday | 500+ mobs | **Todos los experimentos + ≥3 GB RAM** | ❌ descartado prod |

### F-2 Domesticación (addons pequeños y seguros)

| Opción | Origen | Qué hace | Riesgo |
|--------|--------|----------|--------|
| **Tame A Chicken!** | CurseForge / MrDavid13 | Tamicar gallinas con semillas (follow, no despawn, crías heredan dueño); **sin experimentos** | Muy bajo |
| **Tamed & Bound** | CurseForge / FlintZephyr | Los mobs ya domados (caballo, burro, llama, caballo zombie) te siguen (toggle agacharse+interactuar) | Muy bajo |
| **Purrfect Companions** | CurseForge / pellzor | 6 gatos tamicables/montables + ropa | Bajo |
| **World Animals** | ver F-1 | Domesticación amplia (golden bone) a cambio de RAM | Alto |

### Recomendación (cuando Elías Canaquiri (MrLooy) apruebe)

1. Empezar por **VanillA Animals** (castor+mapache+aves, muy ligero) **+ Aurorian Animals**
   (aves+domesticación) y, como extra barato, **Tame A Chicken!**.
2. Descartar para producción todo lo que exija experimentos (Entity Taiga, Animal Pack 500+).
3. **World Animals** solo si Elías Canaquiri (MrLooy) quiere domesticación total y se acepta el coste de RAM → staging medido.
4. Flujo: descargar → revisar manifest (`format_version ≤ 2`, sin experimentos, sin `player.json`) →
   staging con 2-3 jugadores (RAM/CPU + smoke test) → gate → producción con backup/rollback (D-04).

## Candidatos armas/fusión elemental/libros (investigación 2026-10-10)

Petición de Elías Canaquiri (MrLooy): **más variedad de armas + poder "fusionar" armas con poderes de
elementos + nuevos libros para encantarlas y tener atributos**. Gate de staging (D-11).

> ### ⚑ RESULTADO (2026-10-10) — ver D-38
> Instalados 3 **(todos API estable, sin experimentos, `format_version 2`, sin `player.json`)**:
> - ✅ **Lynx More Weapons v1.3.1** (B22; CF `1667566`/file `9085732`) — **50 armas** (7 tipos × 7
>   materiales), BP+RP sin scripts. BP `861efb5b-e633-4264-8568-6ec7f3642d90` + RP `235c287d-…`,
>   Pack Stack **[16]**.
> - ✅ **Weapon Combiner Revamp v1.0.0** (B23; CF `1500902`/file `7906497`) — bloque *Materia
>   Conflux*: **fusiona armas + materiales → habilidades** (onda de fuego al recibir daño, etc.),
>   API estable `@minecraft/server` 2.6.0. BP `e629a65f-…` + RP `4a6ffa69-…`, Pack Stack **[08]**.
>   → cubre la "fusión con poderes" **sin experimentos**.
> - ✅ **Arcane Enchantment v1.0.1** (B24; CF `1700826`/file `8965618`) — *Blank Tome* → menú para
>   **crear libros de encantamiento a elección** (vanilla) por XP; API estable 2.10.0 + `-ui` 2.2.0.
>   BP `f569ee16-…` + RP `369bd183-…`, Pack Stack **[17]**.
> - 🅿️ **NovaRunes - Elemental Socketing** (CF `1670003`/file `8744093`) — sockets elementales
>   (fuego/hielo/rayo/trueno/naturaleza/sombra) — **ROJO en staging** → **Parkeada**
>   en `/opt/mcserver/blocks.parked/b25_novarunes/`. (NovaGlyphs, mismo autor, mismo problema probable.)
>   **Corrección (D-39):** no fue por la API — NovaRunes declara `@minecraft/server` 1.9.0, pero
>   `bp_status` con **1.14.0** carga bien; el `.mcpack` empaqueta la ruta con **backslash**
>   (`scripts\main.js`), que Linux ve como un archivo literal → `could not load main`. **Reenvasable.**
> - ❌ Descartados por exigir **Beta APIs**: *Elemental Weapons*, *Enchant Plus*, *RR Weapon Forge*.
> - 🧩 **Gotcha (nuevo):** Lynx y Arcane traen `header.name = "pack.name"` → `install_block.sh`
>   nombra la carpeta por el header name → **colisión en `pack.name`** (Arcane sobrescribió Lynx).
>   Corregido instalando cada pack en carpeta única; **BDS localiza el pack por `uuid`, no por carpeta**.
>
> Producción: reinicio `[OK]`, Pack Stack **18 BP**, **0 errores reales**, `[STATUS]` vivo,
> BDS RSS **~842 MB**. Backup `/opt/mcserver/backups/d38-weapons-20261010-174532/`.
> **Pendiente/opcional:** *Medieval Weapons* (28 armas con efecto al golpe; slug CF dio 404).

## Telemetría del panel (D-39, 2026-10-10)

`bp_status` **v1.1.2** (uuid `9c1f0a7e-…f01`) emite al journal:
- `[STATUS] online=N` (cada 5 s) — se mantiene.
- `[PSTAT] seq|dim|x|y|z|hp|hpmax|food|foodmax|sat|satmax|fx|name` (**cada 2 s**, por jugador).
- `[TOTEM] name=<jugador>` al usar un **Tótem de la Inmortalidad** (detección por `entityHurt`,
  daño ≥ vida en caché y el tótem ya no está en la mano) → además `world.sendMessage` (§6) a todos.

El panel (`panel/app.py` → `live_players()`, endpoint `/api/players`) consume `[PSTAT]`/`[TOTEM]`;
la tarjeta **"Jugadores en vivo"** muestra vida/hambre/saturación/efectos/coords (refresco 2 s) y
los últimos tótems. `[PSTAT]` se filtra de la consola.

> **Gotcha (v1.1.2):** el motor de scripting de BDS **no parsea** constructs ES modernos en scripts
> propios (spread `[...]`, `for...of`, template literals, emoji literal) aunque `node` sí
> (`SyntaxError: expecting ','`). Escribir `bp_status`/scripts propios en **subconjunto conservador**
> (`var`, concatenación de strings, loops indexados, `\uXXXX` para §/emoji).

→ **Estado (2026-10-10): Tame A Chicken! instalada (D-36); Animal Fun Zoo (Land+Birds) instalado (D-37);
armas/fusión/libros instalados (B22/B23/B24, D-38); NovaRunes parkeada (repack pendiente);
telemetría de jugadores + tótem en el panel (D-39); Aurorian parkeada; VanillA Animals y
The More Animals Project descartados.**
