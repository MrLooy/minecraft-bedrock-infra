import { world, system, ItemStack } from "@minecraft/server";

// bp_spawn v1.0.3 (D-41)
//   - Zona del spawn indestructible: no se rompe ni se construye dentro del radio.
//   - Aviso: mensaje de bienvenida + aviso al intentar romper/construir.
//   - Kit inicial: se entrega una sola vez por jugador (dynamic property).
// El centro de la zona es el spawn por defecto del mundo (getDefaultSpawnLocation);
// el radio se mide en X/Z (cubre todas las alturas, la Y del spawn puede ser 32767).
// Ademas, dentro de la zona NO se puede morir (v1.0.4): se mantiene la vida al maximo
// y se aplican resistencia + regeneracion solo mientras el jugador esta dentro.

var VERSION = "1.0.4";
var RADIUS = 32;                 // radio en bloques (X/Z)
var SPAWN = { x: 0, y: 64, z: 0 };

var MSG_ROMPER = "\u00a7c[Zona segura] No puedes romper bloques aqui.";
var MSG_CONSTRUIR = "\u00a7c[Zona segura] No puedes construir aqui.";
var MSG_PROTEGIDO = "\u00a7a[Zona segura] Estas a salvo: no puedes morir aqui.";
var WELCOME = "\u00a76\u00a7lBienvenido a Gansitos MC\u00a7r"
  + "\n\u00a7eEl spawn es \u00a7lzona segura\u00a7r\u00a7e: no se rompe, no se construye y \u00a7lno se puede morir\u00a7r\u00a7e."
  + "\n\u00a7aKit inicial entregado.";

var KIT = [
  { id: "minecraft:stone_sword", n: 1 },
  { id: "minecraft:stone_pickaxe", n: 1 },
  { id: "minecraft:stone_axe", n: 1 },
  { id: "minecraft:stone_shovel", n: 1 },
  { id: "minecraft:bread", n: 8 },
  { id: "minecraft:torch", n: 32 },
  { id: "minecraft:oak_planks", n: 32 },
  { id: "minecraft:crafting_table", n: 1 }
];

var lastNote = new Map();

function readSpawn() {
  try {
    var s = world.getDefaultSpawnLocation();
    if (s) { SPAWN.x = s.x; SPAWN.z = s.z; if (s.y !== undefined) SPAWN.y = s.y; }
    console.log("[SPAWN] centro x=" + SPAWN.x + " y=" + (s ? s.y : "?") + " z=" + SPAWN.z + " radio=" + RADIUS);
  } catch (e) {
    console.log("[SPAWN] no se pudo leer el spawn por defecto");
  }
}

var probeHandle = null;
var probeErr = "";
var probeErrDone = false;

// Mide (una sola vez, con reintentos) la altura del terreno en el spawn.
function probeGround() {
  var tries = 0;
  probeHandle = system.runInterval(function () {
    tries++;
    var gy = -999;
    try {
      var dim = world.getDimension("overworld");
      for (var yy = 319; yy >= -64; yy--) {
        try {
          var bb = dim.getBlock({ x: SPAWN.x, y: yy, z: SPAWN.z });
          if (bb && bb.typeId && bb.typeId !== "minecraft:air") { gy = yy; break; }
        } catch (e3) {
          if (!probeErrDone) { probeErr = String(e3); probeErrDone = true; }
        }
      }
    } catch (e2) {
      if (!probeErrDone) { probeErr = String(e2); probeErrDone = true; }
    }
    if (gy !== -999) {
      console.log("[SPAWN] suelo y=" + gy);
      system.clearRun(probeHandle);
    } else if (tries >= 25) {
      console.log("[SPAWN] suelo sin medir (" + tries + " intentos) " + probeErr);
      system.clearRun(probeHandle);
    }
  }, 20);
}

function inSpawn(loc) {
  if (!loc) return false;
  var dx = loc.x - SPAWN.x;
  var dz = loc.z - SPAWN.z;
  return (dx * dx + dz * dz) <= (RADIUS * RADIUS);
}

function isExempt(p) {
  try { if (p.isOp && p.isOp()) return true; } catch (e) {}
  try { if (p.hasTag("staff")) return true; } catch (e) {}
  return false;
}

function notify(p, msg) {
  try {
    var id = p.id;
    var now = Date.now();
    var prev = lastNote.get(id);
    if (prev && (now - prev) < 1500) return;
    lastNote.set(id, now);
    system.run(function () {
      try { p.onScreenDisplay.setActionBar(msg); } catch (e) {}
    });
  } catch (e) {}
}

function giveKit(p) {
  try {
    var inv = p.getComponent("minecraft:inventory");
    var cont = inv ? inv.container : null;
    if (!cont) return;
    for (var i = 0; i < KIT.length; i++) {
      try { cont.addItem(new ItemStack(KIT[i].id, KIT[i].n)); } catch (e) {}
    }
  } catch (e) {}
}

// --- Romper bloques ---------------------------------------------------------
// Antes (cancelar) si el evento esta disponible; si no, restaurar en el "after".
try {
  if (world.beforeEvents && world.beforeEvents.playerBreakBlock) {
    world.beforeEvents.playerBreakBlock.subscribe(function (ev) {
      try {
        if (isExempt(ev.player)) return;
        if (inSpawn(ev.block ? ev.block.location : null)) {
          ev.cancel = true;
          notify(ev.player, MSG_ROMPER);
        }
      } catch (e) {}
    });
  }
} catch (e) {}

try {
  world.afterEvents.playerBreakBlock.subscribe(function (ev) {
    try {
      if (isExempt(ev.player)) return;
      var loc = ev.block ? ev.block.location : null;
      if (!inSpawn(loc)) return;
      var perm = ev.brokenBlockPermutation;
      system.run(function () {
        try {
          var b = ev.dimension.getBlock(loc);
          if (perm) b.setPermutation(perm); else b.setType("minecraft:air");
        } catch (e) {}
        notify(ev.player, MSG_ROMPER);
      });
    } catch (e) {}
  });
} catch (e) {}

// --- Colocar bloques (revertir) ---------------------------------------------
try {
  world.afterEvents.playerPlaceBlock.subscribe(function (ev) {
    try {
      if (isExempt(ev.player)) return;
      var loc = ev.block ? ev.block.location : null;
      if (!inSpawn(loc)) return;
      var dim = ev.dimension;
      system.run(function () {
        try { var b = dim.getBlock(loc); if (b) b.setType("minecraft:air"); } catch (e) {}
        notify(ev.player, MSG_CONSTRUIR);
      });
    } catch (e) {}
  });
} catch (e) {}

// --- Explosiones dentro de la zona (TNT, creeper, etc.) ---------------------
try {
  if (world.beforeEvents && world.beforeEvents.explosion) {
    world.beforeEvents.explosion.subscribe(function (ev) {
      try {
        var blocks = ev.getImpactedBlocks ? ev.getImpactedBlocks() : null;
        if (!blocks) return;
        for (var i = 0; i < blocks.length; i++) {
          if (inSpawn(blocks[i])) { ev.cancel = true; return; }
        }
      } catch (e) {}
    });
  }
} catch (e) {}

// --- Zona segura: no se puede morir -----------------------------------------
// (1) Efectos SOLO dentro de la zona (visibles en el HUD): resistencia + regeneracion.
// (2) Red de seguridad: vida al maximo cada tick + evitar la caida al vacio.
// (3) Feedback al recibir dano dentro de la zona.
system.runInterval(function () {
  try {
    var ps = world.getAllPlayers();
    for (var i = 0; i < ps.length; i++) {
      var p = ps[i];
      if (!inSpawn(p.location)) continue;
      try { p.addEffect("resistance", 60, { amplifier: 4, showParticles: false }); } catch (eA) {}
      try { p.addEffect("regeneration", 60, { amplifier: 4, showParticles: false }); } catch (eB) {}
    }
  } catch (e) {}
}, 20);

system.runInterval(function () {
  try {
    var ps = world.getAllPlayers();
    for (var i = 0; i < ps.length; i++) {
      var p = ps[i];
      if (!inSpawn(p.location)) continue;
      try {
        var hc = p.getComponent("minecraft:health");
        if (hc && hc.currentValue < hc.effectiveMax) hc.setCurrentValue(hc.effectiveMax);
      } catch (eH) {}
      if (p.location.y < -60) {
        try { p.teleport({ x: SPAWN.x, y: (SPAWN.y || 64) + 2, z: SPAWN.z }); } catch (eT) {}
      }
    }
  } catch (e) {}
}, 1);

try {
  if (world.afterEvents && world.afterEvents.entityHurt) {
    world.afterEvents.entityHurt.subscribe(function (ev) {
      try {
        var e = ev.hurtEntity;
        if (!e || e.typeId !== "minecraft:player") return;
        if (!inSpawn(e.location)) return;
        notify(e, MSG_PROTEGIDO);
        var hc = e.getComponent("minecraft:health");
        if (hc && hc.currentValue < hc.effectiveMax) hc.setCurrentValue(hc.effectiveMax);
      } catch (er) {}
    });
  }
} catch (e) {}

// --- Entrada / kit ----------------------------------------------------------
world.afterEvents.playerSpawn.subscribe(function (ev) {
  try {
    var p = ev.player;
    if (!ev.initialSpawn) return;
    try { p.sendMessage(WELCOME); } catch (e) {}
    if (p.getDynamicProperty("kit_dado")) return;
    giveKit(p);
    try { p.setDynamicProperty("kit_dado", true); } catch (e) {}
  } catch (e) {}
});

readSpawn();
probeGround();
console.log("[bp_spawn] v" + VERSION + " cargado");
