import { world, system } from "@minecraft/server";

// bp_status v1.1.2 (D-39) - reporte al journal para el panel.
//   [STATUS] online=N
//   [PSTAT] seq|dim|x|y|z|hp|hpmax|food|foodmax|sat|satmax|fx|name
//   [TOTEM] name=<jugador>
// seq = Date.now(): monotono entre reinicios, el panel toma el ultimo lote.

var VERSION = "1.1.2";
var totemCache = new Map();

function num(v) {
  return (typeof v === "number" && isFinite(v)) ? Math.round(v * 10) / 10 : 0;
}

function field(comp, key) {
  try {
    if (comp) {
      var v = comp[key];
      if (typeof v === "number" && isFinite(v)) return v;
      if (v && typeof v.value === "number") return v.value;
    }
  } catch (e) {}
  return 0;
}

function holdsTotem(p) {
  var eq = null;
  try { eq = p.getComponent("minecraft:equippable"); } catch (e) { eq = null; }
  if (eq) {
    var slots = ["Mainhand", "Offhand"];
    for (var i = 0; i < slots.length; i++) {
      var it = null;
      try { it = eq.getEquipment(slots[i]); } catch (e) { it = null; }
      if (it && it.typeId === "minecraft:totem_of_undying") return true;
    }
    return false;
  }
  var c = null;
  try {
    var inv = p.getComponent("minecraft:inventory");
    c = inv ? inv.container : null;
  } catch (e) { c = null; }
  if (c) {
    var idxs = [0, p.selectedSlotIndex];
    for (var j = 0; j < idxs.length; j++) {
      var it2 = null;
      try { it2 = c.getItem(idxs[j]); } catch (e) { it2 = null; }
      if (it2 && it2.typeId === "minecraft:totem_of_undying") return true;
    }
  }
  return false;
}

function report() {
  console.log("[STATUS] online=" + world.getAllPlayers().length);
}

function sample() {
  var players = world.getAllPlayers();
  var seq = Date.now();
  for (var i = 0; i < players.length; i++) {
    var p = players[i];
    try {
      var hp = p.getComponent("minecraft:health");
      var hpc = field(hp, "currentValue");
      var hpm = field(hp, "effectiveMax") || field(hp, "defaultValue") || 20;
      var hun = p.getComponent("minecraft:player.hunger");
      var sat = p.getComponent("minecraft:player.saturation");
      var fx = "";
      try {
        var effs = p.getEffects() || [];
        var parts = [];
        for (var k = 0; k < effs.length; k++) {
          var e = effs[k];
          var id = String(e.typeId || "").replace("minecraft:", "");
          parts.push(id + "=" + (e.amplifier || 0) + "=" + Math.round(e.duration || 0));
        }
        fx = parts.join(";");
      } catch (e2) { fx = ""; }
      var loc = p.location;
      var dim = String((p.dimension && p.dimension.id) ? p.dimension.id : "?").replace("minecraft:", "");
      console.log("[PSTAT] " + seq + "|" + dim + "|" + num(loc.x) + "|" + num(loc.y) + "|" + num(loc.z)
        + "|" + num(hpc) + "|" + num(hpm)
        + "|" + num(field(hun, "currentValue")) + "|" + num(field(hun, "effectiveMax") || 20)
        + "|" + num(field(sat, "currentValue")) + "|" + num(field(sat, "effectiveMax") || 20)
        + "|" + fx + "|" + p.name);
      totemCache.set(p.id, { hp: hpc, hasTotem: holdsTotem(p), name: p.name });
    } catch (e3) {}
  }
  if (totemCache.size > players.length) {
    var present = {};
    for (var m = 0; m < players.length; m++) present[players[m].id] = true;
    var keys = [];
    totemCache.forEach(function (val, key) { keys.push(key); });
    for (var n = 0; n < keys.length; n++) {
      if (!present[keys[n]]) totemCache.delete(keys[n]);
    }
  }
}

world.afterEvents.entityHurt.subscribe(function (ev) {
  try {
    var e = ev.entity;
    if (!e || e.typeId !== "minecraft:player") return;
    var c = totemCache.get(e.id);
    if (!c || !c.hasTotem) return;
    if (ev.damage < c.hp) return;
    system.run(function () {
      try {
        var p = world.getEntity(e.id);
        if (!p || p.typeId !== "minecraft:player") return;
        if (holdsTotem(p)) return;
        var name = c.name || p.name;
        console.log("[TOTEM] name=" + name);
        world.sendMessage("\u00a76\u26a1 \u00a7e" + name + "\u00a7r\u00a76 uso un Totem de la Inmortalidad");
      } catch (e2) {}
    });
  } catch (e) {}
});

world.afterEvents.playerSpawn.subscribe(function () { report(); });
world.afterEvents.playerLeave.subscribe(function () { report(); });

system.runInterval(sample, 40);
system.runInterval(report, 100);
console.log("[bp_status] v" + VERSION + " cargado");
