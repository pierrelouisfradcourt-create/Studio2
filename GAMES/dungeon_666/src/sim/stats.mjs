// Statistiques dérivées du héros : base + équipement + bénédictions. Recalculées à chaque
// changement de build (jamais à chaque image). Produit aussi la liste des procs.

import { baseStats } from './state.mjs';
import { boonDef, boonValue } from './boons.mjs';
import { LEGENDARY_POWERS } from './loot.mjs';

const LEVEL_STEP = 0.5; // chaque niveau supplémentaire d'une bénédiction : +50 % de sa valeur

function addStat(st, stat, v) {
  if (stat.endsWith('Mult')) st[stat] += v; // multiplicateurs additifs entre eux (1 + somme)
  else st[stat] = (st[stat] ?? 0) + v;
}

export function recomputeStats(game) {
  const p = game.player;
  const run = game.run;
  const st = baseStats();
  st.superDamageMult = 1;
  st.superDurationBonus = 0;
  st.extraGoldOnKill = 0;
  const procs = [];

  const t = game.tuning;
  st.weaponDamage = run.items.arme?.base?.damage ?? t.weaponBase;
  st.armorHp = run.items.armure ? run.items.armure.base?.hp ?? t.armorBase : 0;
  for (const item of Object.values(run.items)) {
    if (!item) continue;
    for (const a of item.affixes) addStat(st, a.stat, a.value);
    if (item.power) {
      const pw = LEGENDARY_POWERS.find((x) => x.id === item.power);
      if (pw?.stats) for (const [k, v] of Object.entries(pw.stats)) addStat(st, k, v);
      if (pw?.procs) for (const pr of pw.procs) procs.push({ chance: 1, ...pr });
    }
  }

  for (const b of run.boons) {
    const def = boonDef(b.id);
    if (!def) continue;
    const lv = 1 + LEVEL_STEP * (b.level - 1);
    const raw = boonValue(def, b.rarity) * lv;
    const v = def.pct ? raw / 100 : raw;
    if (def.stat) addStat(st, def.stat, def.negative ? -v : v);
    if (def.superDurationBonus) st.superDurationBonus += def.superDurationBonus;
    if (def.extraGoldOnKill) st.extraGoldOnKill += def.extraGoldOnKill;
    if (def.proc) {
      const pr = { chance: 1, ...def.proc, boon: def.id };
      if (pr.effect === 'gold') {
        pr.chance = Math.min(1, v);
        pr.value = def.proc.valueFixed;
      } else if (pr.effect === 'chill' || pr.effect === 'vuln' || pr.effect === 'execute' || pr.effect === 'fullHpBonus') {
        pr.value = def.pct ? v : raw;
      } else {
        pr.value = raw;
      }
      procs.push(pr);
    }
  }

  // Bornes de sécurité : aucune combinaison ne peut casser la boucle de jeu.
  st.dashRechargeMult = Math.max(0.35, st.dashRechargeMult);
  st.skillCooldownMult = Math.max(0.35, st.skillCooldownMult);
  st.critChance = Math.min(0.75, st.critChance);
  st.lifesteal = Math.min(0.15, st.lifesteal);

  const oldMax = p.maxHp;
  p.stats = st;
  p.procs = procs;
  p.maxHp = Math.round(t.player.innateHp + st.armorHp + st.maxHpBonus);
  if (p.maxHp > oldMax) p.hp += p.maxHp - oldMax;
  p.hp = Math.min(p.hp, p.maxHp);
  const maxDash = game.tuning.dash.charges + st.dashChargesBonus;
  p.dashCharges = Math.min(p.dashCharges, maxDash);
  const maxGadget = game.tuning.gadget.chargesPerSection + st.gadgetChargesBonus;
  p.gadgetCharges = Math.min(p.gadgetCharges, maxGadget);
}
