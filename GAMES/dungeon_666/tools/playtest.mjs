#!/usr/bin/env node
// Playtest automatique : fait jouer les bots (tools/bots.mjs) sur N graines et mesure le
// « feel » du combat — survie, dégâts subis, rythme, valeur du dash.
//
//   node tools/playtest.mjs [--seeds 20] [--floors 6] [--minutes 12]
//                           [--json out.json] [--md out.md] [--policies skilled,noDash,masher]
//                           [--no-dash-audit] [--help]
//
// Pour chaque politique et chaque graine : createGame({seed}), boucle stepGame, événements
// vidés à chaque pas (et comptés), menus résolus par le bot. Arrêt quand l'étage floors + 1
// est atteint (section battue), à la première mort (pas de reprise) ou après `minutes` de
// temps simulé. Rapport markdown (français) + JSON ; résumé court sur stdout.
//
// Salles comptées : seules les salles JOUÉES (étage <= floors). L'étage floors + 1, ouvert
// puis aussitôt abandonné quand la section est battue, n'est pas une salle de combat.
//
// Audit des dash (politique skilled) : à chaque dash, la situation est rejouée DEUX fois
// depuis un clone de la partie, pendant DASH_AUDIT_SECONDS : avec le dash, puis sans ce dash
// et avec la meilleure esquive à pied (bot noDash). Un dash est « décisif » si seule la
// version sans dash prend un coup. Mesure ce que vaut réellement chaque dash, pas leur nombre.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createGame, stepGame, DT } from '../src/sim/game.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { POLICIES, resolveChoice, cloneMemory } from './bots.mjs';

const GAME_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULTS = {
  seeds: 20,
  floors: 18, // une section complète (Gardien compris)
  minutes: 30,
  json: null, // JSON brut (~500 Ko) : seulement sur demande (--json), jamais versionné par défaut
  md: 'reports/playtest.md',
  policies: Object.keys(POLICIES),
  dashAudit: true,
};
const USAGE = `Usage : node tools/playtest.mjs [--seeds N] [--floors N] [--minutes N]
                              [--json chemin] [--md chemin] [--policies a,b,c]
                              [--no-dash-audit] [--help]
Politiques disponibles : ${Object.keys(POLICIES).join(', ')}`;
const NUMERIC_OPTIONS = ['seeds', 'floors', 'minutes'];
const AUDITED_POLICY = 'skilled'; // la seule politique qui dashe « exprès »
const COUNTERFACTUAL_POLICY = 'noDash'; // meilleure esquive à pied
const DASH_AUDIT_SECONDS = 1; // fenêtre de comparaison des deux futurs
const SECONDS_PER_MINUTE = 60;
const MAX_CHOICE_ATTEMPTS = 8; // menus consécutifs sans progrès => run bloqué
const STALL_SECONDS = 30; // salle nettoyée depuis si longtemps sans changer d'étage => blocage
const COMBAT_KINDS = new Set(['combat', 'elite', 'boss']);
const PERCENT = 100;

// ---------------------------------------------------------------- une partie

function newRecorder() {
  return {
    events: {}, rooms: [], current: null, stall: null, stallRoom: null, stallTick: -1,
    audit: { dashes: 0, decisive: 0, harmful: 0, bothHit: 0, idle: 0, skipped: 0 },
  };
}

function openRoom(rec, game, ev) {
  rec.current = { floor: ev.floor, kind: ev.kind, damage0: game.telemetry.damageTaken, hits0: game.telemetry.hitsTaken, tick0: game.tick, time0: game.time, clearTime: null };
}

function closeRoom(rec, game) {
  const c = rec.current;
  if (!c) return;
  rec.rooms.push({
    floor: c.floor,
    kind: c.kind,
    damage: game.telemetry.damageTaken - c.damage0,
    hits: game.telemetry.hitsTaken - c.hits0,
    seconds: (game.tick - c.tick0) * DT,
    // Temps de combat (temps de sim, gel d'impact exclu) : de l'entrée au nettoyage, ou à la fin du run.
    combatSeconds: (c.clearTime ?? game.time) - c.time0,
  });
  rec.current = null;
}

function consumeEvents(game, rec) {
  for (const ev of game.events) {
    rec.events[ev.type] = (rec.events[ev.type] ?? 0) + 1;
    if (ev.type === 'floorEnter') {
      closeRoom(rec, game);
      openRoom(rec, game, ev);
    } else if (ev.type === 'roomClear' && rec.current) {
      rec.current.clearTime = game.time;
    }
  }
  game.events.length = 0;
}

// ---------------------------------------------------------------- audit contrefactuel des dash

/** Dégâts subis pendant `ticks` pas, depuis un clone, en jouant `first` puis la politique. */
function rollout(game, mem, first, policyName, ticks) {
  const g = structuredClone(game);
  const m = cloneMemory(mem);
  g.events.length = 0;
  const before = g.telemetry.damageTaken;
  stepGame(g, first);
  for (let i = 1; i < ticks && g.mode === 'play'; i++) {
    stepGame(g, POLICIES[policyName](g, m));
    g.events.length = 0;
  }
  return g.telemetry.damageTaken - before;
}

/** Classe le dash que le bot s'apprête à faire : décisif, nuisible, inutile, ou coup inévitable. */
function auditDash(game, mem, input, policyName, audit) {
  let withDash;
  let withoutDash;
  try {
    const ticks = Math.round(DASH_AUDIT_SECONDS / DT);
    withDash = rollout(game, mem, input, policyName, ticks);
    withoutDash = rollout(game, mem, { ...input, dashPressed: false }, COUNTERFACTUAL_POLICY, ticks);
  } catch {
    audit.skipped++; // état non clonable : on n'invente pas de résultat
    return;
  }
  audit.dashes++;
  if (withoutDash > 0 && withDash === 0) audit.decisive++;
  else if (withDash > withoutDash) audit.harmful++;
  else if (withDash > 0) audit.bothHit++;
  else audit.idle++;
}

/**
 * Blocage : salle nettoyée depuis STALL_SECONDS sans sortie. Rend un diagnostic (disposition,
 * objet d'interaction inaccessible ?) ou null si la partie avance.
 */
function detectStall(game, rec) {
  const room = game.room;
  if (rec.stallRoom !== room) {
    rec.stallRoom = room;
    rec.stallTick = -1;
  }
  if (!room.cleared) return null;
  if (rec.stallTick < 0) rec.stallTick = game.tick;
  if ((game.tick - rec.stallTick) * DT < STALL_SECONDS) return null;
  const it = room.interact;
  return {
    floor: game.run.floor,
    layout: room.layout,
    doorsOpen: room.doors.some((d) => d.open),
    interact: it ? { kind: it.kind, used: it.used, x: it.x, y: it.y, blocked: pointBlocked(room, it.x, it.y, 0) } : null,
    player: { x: Math.round(game.player.x), y: Math.round(game.player.y) },
  };
}

/** Résout le menu ouvert ; rend false si le bot n'arrive pas à en sortir. */
function settleChoice(game, policyName) {
  for (let i = 0; i < MAX_CHOICE_ATTEMPTS && game.mode === 'choice'; i++) {
    if (!resolveChoice(game, policyName)) return false;
  }
  return game.mode !== 'choice';
}

/** Boucle de jeu jusqu'à l'issue ; rend 'section' | 'dead' | 'victory' | 'timeout' | 'stuck' | 'softlock'. */
function playUntilOutcome(game, policyName, rec, targetFloor, maxTicks, dashAudit) {
  const policy = POLICIES[policyName];
  const mem = {};
  for (;;) {
    if (game.mode === 'choice' && !settleChoice(game, policyName)) return 'stuck';
    if (game.run.floor >= targetFloor) return 'section';
    if (game.mode === 'dead') return 'dead';
    if (game.mode === 'victory') return 'victory';
    if (game.tick >= maxTicks) return 'timeout';
    rec.stall = detectStall(game, rec);
    if (rec.stall) return 'softlock';
    const input = policy(game, mem);
    if (dashAudit && input.dashPressed && game.player.dashCharges >= 1) auditDash(game, mem, input, policyName, rec.audit);
    stepGame(game, input);
    consumeEvents(game, rec);
  }
}

/**
 * Joue une partie complète avec une politique. Rend le résumé mesuré de la partie.
 * options : { floors, minutes, tuning, dashAudit } — dashAudit (défaut false) n'audite que
 * la politique skilled.
 */
export function runEpisode(policyName, seed, options = {}) {
  const floors = options.floors ?? DEFAULTS.floors;
  const minutes = options.minutes ?? DEFAULTS.minutes;
  if (!POLICIES[policyName]) throw new Error(`politique inconnue : ${policyName}`);
  const game = createGame({ seed, tuning: options.tuning });
  const rec = newRecorder();
  consumeEvents(game, rec);
  const maxTicks = Math.round((minutes * SECONDS_PER_MINUTE) / DT);
  const dashAudit = !!options.dashAudit && policyName === AUDITED_POLICY;
  const outcome = playUntilOutcome(game, policyName, rec, floors + 1, maxTicks, dashAudit);
  closeRoom(rec, game);
  return summarize(game, rec, { policy: policyName, seed, outcome, floors, dashAudit });
}

function summarize(game, rec, meta) {
  const tel = game.telemetry;
  const minutes = Math.max(1e-9, (game.tick * DT) / SECONDS_PER_MINUTE);
  // Salles jouées seulement : l'étage floors + 1 (atteint = section battue) n'a pas été joué.
  const playedRooms = rec.rooms.filter((r) => r.floor <= meta.floors);
  const combatRooms = playedRooms.filter((r) => COMBAT_KINDS.has(r.kind));
  const combatDamage = combatRooms.reduce((s, r) => s + r.damage, 0);
  const combatSeconds = combatRooms.reduce((s, r) => s + r.combatSeconds, 0);
  const bossTime = tel.roomTimes.find((r) => r.kind === 'boss')?.time ?? null;
  const actions = tel.attacks + tel.dashes + tel.skillCasts + tel.gadgetUses + tel.superUses;
  return {
    ...meta,
    sectionCleared: game.run.floor > meta.floors,
    floorReached: game.run.floor,
    simSeconds: game.tick * DT,
    hpLeft: game.player.hp,
    deaths: tel.deaths,
    deathCauses: { ...tel.deathCauses },
    combatRooms: combatRooms.length,
    combatDamage,
    combatSeconds,
    combatHits: combatRooms.reduce((s, r) => s + r.hits, 0),
    damageTaken: tel.damageTaken,
    damagePerRoom: combatRooms.length ? combatDamage / combatRooms.length : null,
    hitsTakenPerMin: tel.hitsTaken / minutes,
    dodges: tel.dodges,
    dodgesPerMin: tel.dodges / minutes,
    dashesPerMin: tel.dashes / minutes,
    actionsPerMin: actions / minutes,
    hitsToKill: tel.kills ? tel.hitsLanded / tel.kills : null,
    kills: tel.kills,
    superUses: tel.superUses,
    gadgetUses: tel.gadgetUses,
    skillCasts: tel.skillCasts,
    wallSlams: tel.wallSlams,
    deflects: tel.deflects,
    roomTimes: tel.roomTimes.filter((r) => r.kind !== 'boss').map((r) => r.time),
    bossFightSeconds: bossTime,
    killTimes: tel.killTimes.map((k) => ({ kind: k.kind, life: k.life })),
    eventsPerMin: Object.values(rec.events).reduce((a, n) => a + n, 0) / minutes,
    eventCounts: rec.events,
    rooms: playedRooms, // détail par salle jouée : dégâts, coups reçus, durées
    stall: rec.stall,
    dashAudit: meta.dashAudit ? { ...rec.audit } : null,
  };
}

// ---------------------------------------------------------------- agrégats

function quantile(sorted, q) {
  if (!sorted.length) return null;
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

/** {n, mean, median, p10, p90} d'une liste de nombres (null ignorés). */
export function stats(values) {
  const v = values.filter((x) => x !== null && x !== undefined && Number.isFinite(x)).sort((a, b) => a - b);
  if (!v.length) return { n: 0, mean: null, median: null, p10: null, p90: null };
  const mean = v.reduce((s, x) => s + x, 0) / v.length;
  return { n: v.length, mean, median: quantile(v, 0.5), p10: quantile(v, 0.1), p90: quantile(v, 0.9) };
}

const RUN_METRICS = [
  ['floorReached', 'Étage atteint'],
  ['damagePerRoom', 'Dégâts subis / salle de combat (par run)'],
  ['hitsTakenPerMin', 'Coups reçus / min'],
  ['dodgesPerMin', 'Esquives (dash) / min'],
  ['dashesPerMin', 'Dash / min'],
  ['actionsPerMin', 'Actions / min'],
  ['hitsToKill', 'Coups pour tuer (mêlée / kills)'],
  ['bossFightSeconds', 'Durée du boss (s)'],
  ['simSeconds', 'Durée du run (s)'],
  ['skillCasts', 'Compétences (Lance)'],
  ['gadgetUses', 'Gadgets'],
  ['superUses', 'Supers'],
  ['wallSlams', 'Wall slams'],
  ['deflects', 'Déviations'],
  ['eventsPerMin', 'Événements de sim / min'],
];

function sumOf(runs, key) {
  return runs.reduce((s, r) => s + (r[key] ?? 0), 0);
}

/**
 * Valeurs AGRÉGÉES sur toutes les salles de combat de la politique (et non moyenne des
 * moyennes par run, qui surpondère les runs courts — morts tôt, peu de salles).
 */
function pooledMetrics(runs) {
  const rooms = sumOf(runs, 'combatRooms');
  const minutes = sumOf(runs, 'combatSeconds') / SECONDS_PER_MINUTE;
  const damage = sumOf(runs, 'combatDamage');
  return {
    combatRooms: rooms,
    combatMinutes: minutes,
    damagePerRoom: rooms ? damage / rooms : null,
    damagePerCombatMinute: minutes > 0 ? damage / minutes : null,
    hitsPerCombatMinute: minutes > 0 ? sumOf(runs, 'combatHits') / minutes : null,
  };
}

function aggregateAudit(runs) {
  const audited = runs.filter((r) => r.dashAudit);
  if (!audited.length) return null;
  const total = { dashes: 0, decisive: 0, harmful: 0, bothHit: 0, idle: 0, skipped: 0 };
  for (const r of audited) for (const k of Object.keys(total)) total[k] += r.dashAudit[k];
  const minutes = sumOf(audited, 'combatSeconds') / SECONDS_PER_MINUTE;
  return {
    ...total,
    decisiveShare: total.dashes ? total.decisive / total.dashes : null,
    decisivePerCombatMinute: minutes > 0 ? total.decisive / minutes : null,
  };
}

function aggregatePolicy(runs) {
  const playable = runs.filter((r) => r.outcome !== 'softlock');
  const agg = {
    runs: runs.length,
    sectionRate: runs.filter((r) => r.sectionCleared).length / runs.length,
    // Taux de section sur les seuls runs non bloqués par un défaut de la sim (jouabilité du combat).
    sectionRatePlayable: playable.length ? playable.filter((r) => r.sectionCleared).length / playable.length : null,
    deathRate: runs.filter((r) => r.outcome === 'dead').length / runs.length,
    timeouts: runs.filter((r) => r.outcome === 'timeout').length,
    stuck: runs.filter((r) => r.outcome === 'stuck').length,
    softlocks: runs.filter((r) => r.outcome === 'softlock').map((r) => ({ seed: r.seed, ...r.stall })),
    deathCauses: {},
    metrics: {},
    roomTimes: stats(runs.flatMap((r) => r.roomTimes)),
    killTimes: {},
    pooled: pooledMetrics(runs),
    dashAudit: aggregateAudit(runs),
  };
  for (const [key] of RUN_METRICS) agg.metrics[key] = stats(runs.map((r) => r[key]));
  for (const r of runs) {
    for (const [cause, n] of Object.entries(r.deathCauses)) agg.deathCauses[cause] = (agg.deathCauses[cause] ?? 0) + n;
  }
  const byKind = {};
  for (const r of runs) for (const k of r.killTimes) (byKind[k.kind] ??= []).push(k.life);
  for (const [kind, list] of Object.entries(byKind)) agg.killTimes[kind] = stats(list);
  return agg;
}

// ---------------------------------------------------------------- rapport

function fmt(v, digits = 1) {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  return v.toFixed(digits);
}

function pct(v) {
  return `${fmt(v * PERCENT, 0)} %`;
}

function dist4(s, digits = 1) {
  return `${fmt(s.mean, digits)} | ${fmt(s.median, digits)} | ${fmt(s.p10, digits)} | ${fmt(s.p90, digits)}`;
}

function summaryTable(report) {
  const rows = ['| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |', '|---|---|---|---|---|---|---|---|---|---|---|---|'];
  for (const [name, a] of Object.entries(report.policies)) {
    const m = a.metrics;
    const pl = a.pooled;
    rows.push(`| ${name} | ${pct(a.sectionRate)} | ${a.sectionRatePlayable === null ? '—' : pct(a.sectionRatePlayable)} | ${pct(a.deathRate)} | ${a.softlocks.length} | ${fmt(m.floorReached.mean, 2)} | ${fmt(pl.damagePerRoom)} | ${fmt(pl.damagePerCombatMinute)} | ${fmt(pl.hitsPerCombatMinute, 2)} | ${fmt(m.dodgesPerMin.mean, 2)} | ${fmt(m.dashesPerMin.mean)} | ${fmt(m.actionsPerMin.mean)} |`);
  }
  return rows.join('\n');
}

function auditSection(report) {
  const a = report.policies[AUDITED_POLICY]?.dashAudit;
  if (!a) return 'Audit désactivé (ou politique skilled absente).';
  return `Chaque dash du bot ${AUDITED_POLICY} est rejoué ${DASH_AUDIT_SECONDS} s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot ${COUNTERFACTUAL_POLICY}).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| ${a.dashes}${a.skipped ? ` (+${a.skipped} non clonables)` : ''} | ${a.decisive} (${a.decisiveShare === null ? '—' : pct(a.decisiveShare)}) | ${a.harmful} | ${a.bothHit} | ${a.idle} | ${fmt(a.decisivePerCombatMinute, 2)} |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.`;
}

function metricTable(a) {
  const rows = ['| Mesure | Moyenne | Médiane | p10 | p90 |', '|---|---|---|---|---|'];
  for (const [key, label] of RUN_METRICS) rows.push(`| ${label} | ${dist4(a.metrics[key], 2)} |`);
  rows.push(`| Durée d'une salle de combat (s, toutes salles) | ${dist4(a.roomTimes, 2)} |`);
  return rows.join('\n');
}

function killTable(report) {
  const kinds = [...new Set(Object.values(report.policies).flatMap((a) => Object.keys(a.killTimes)))].sort();
  const names = Object.keys(report.policies);
  const rows = [`| Ennemi | ${names.map((n) => `${n} (moy / méd / p90, n)`).join(' | ')} |`, `|---|${names.map(() => '---').join('|')}|`];
  for (const k of kinds) {
    const cells = names.map((n) => {
      const s = report.policies[n].killTimes[k];
      return s ? `${fmt(s.mean, 2)} / ${fmt(s.median, 2)} / ${fmt(s.p90, 2)} (${s.n})` : '—';
    });
    rows.push(`| ${k} | ${cells.join(' | ')} |`);
  }
  return rows.join('\n');
}

function causesTable(report) {
  const rows = ['| Politique | Causes de mort |', '|---|---|'];
  for (const [name, a] of Object.entries(report.policies)) {
    const list = Object.entries(a.deathCauses).sort((x, y) => y[1] - x[1]).map(([c, n]) => `${c} ×${n}`);
    rows.push(`| ${name} | ${list.join(', ') || 'aucune'} |`);
  }
  return rows.join('\n');
}

function softlockTable(report) {
  const rows = ['| Politique | Graine | Étage | Disposition | Objet d\'interaction | Dans un obstacle ? | Portes ouvertes |', '|---|---|---|---|---|---|---|'];
  for (const [name, a] of Object.entries(report.policies)) {
    for (const s of a.softlocks) {
      const it = s.interact;
      rows.push(`| ${name} | ${s.seed} | ${s.floor} | ${s.layout} | ${it ? `${it.kind} (${Math.round(it.x)}, ${Math.round(it.y)})` : '—'} | ${it ? (it.blocked ? 'oui' : 'non') : '—'} | ${s.doorsOpen ? 'oui' : 'non'} |`);
    }
  }
  return rows.length > 2 ? rows.join('\n') : 'Aucun blocage.';
}

function runsTable(report) {
  const rows = ['| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |', '|---|---|---|---|---|---|---|---|'];
  for (const [name, a] of Object.entries(report.runs)) {
    for (const r of a) rows.push(`| ${name} | ${r.seed} | ${r.outcome} | ${r.floorReached} | ${fmt(r.simSeconds, 0)} | ${fmt(r.damagePerRoom)} | ${r.dodges} | ${fmt(r.bossFightSeconds)} |`);
  }
  return rows.join('\n');
}

export function renderMarkdown(report) {
  const p = report.params;
  const ratio = report.dashValueRatio;
  return `# Playtest automatique — Dungeon 666

Généré par \`node tools/playtest.mjs\` le ${report.generatedAt}. Graines 1 à ${p.seeds}, objectif : étage ${p.floors + 1} (section 1 battue, boss au ${p.floors}e), limite ${p.minutes} min de temps simulé par run, arrêt à la première mort. Durée d'exécution : ${fmt(report.runtimeSeconds, 1)} s.

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

${summaryTable(report)}

Valeurs agrégées sur toutes les salles de combat jouées (étage <= ${p.floors}) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **${fmt(ratio, 2)}**${ratio === null ? ' (données insuffisantes)' : ''} ; par minute de combat = **${fmt(report.dashValueRatioPerMinute, 2)}**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

${auditSection(report)}

## Causes de mort

${causesTable(report)}

## Blocages (salle nettoyée, aucune sortie possible pendant ${STALL_SECONDS} s)

${softlockTable(report)}

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

${killTable(report)}

${Object.entries(report.policies).map(([name, a]) => `## Distribution — ${name}\n\n${metricTable(a)}`).join('\n\n')}

## Détail des runs

${runsTable(report)}
`;
}

// ---------------------------------------------------------------- CLI

function readValue(argv, i) {
  const val = argv[i + 1];
  if (val === undefined || val.startsWith('--')) throw new Error(`valeur manquante après ${argv[i]}\n${USAGE}`);
  return val;
}

function parseArgs(argv) {
  const opts = { ...DEFAULTS };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i].replace(/^--/, '');
    if (key === 'help' || key === 'h') return { ...opts, help: true };
    if (key === 'no-dash-audit') {
      opts.dashAudit = false;
      continue;
    }
    if (NUMERIC_OPTIONS.includes(key)) {
      const n = Number(readValue(argv, i++));
      if (!Number.isInteger(n) || n < 1) throw new Error(`--${key} attend un entier >= 1\n${USAGE}`);
      opts[key] = n;
    } else if (key === 'json' || key === 'md') {
      opts[key] = readValue(argv, i++);
    } else if (key === 'policies') {
      opts.policies = readValue(argv, i++).split(',');
      const unknown = opts.policies.filter((n) => !POLICIES[n]);
      if (unknown.length) throw new Error(`politique inconnue : ${unknown.join(', ')}\n${USAGE}`);
    } else {
      throw new Error(`option inconnue : ${argv[i]}\n${USAGE}`);
    }
  }
  return opts;
}

/** noDash ÷ skilled sur une valeur agrégée ; null si l'une manque ou si skilled vaut 0. */
function ratioOf(policies, key) {
  const sk = policies.skilled?.pooled[key];
  const nd = policies.noDash?.pooled[key];
  return sk && nd !== null && nd !== undefined ? nd / sk : null;
}

export function runPlaytest(opts) {
  const t0 = performance.now();
  const runs = {};
  const policies = {};
  for (const name of opts.policies) {
    runs[name] = [];
    for (let seed = 1; seed <= opts.seeds; seed++) runs[name].push(runEpisode(name, seed, opts));
    policies[name] = aggregatePolicy(runs[name]);
  }
  return {
    generatedAt: new Date().toISOString(),
    params: { seeds: opts.seeds, floors: opts.floors, minutes: opts.minutes, policies: opts.policies, dashAudit: opts.dashAudit },
    runtimeSeconds: (performance.now() - t0) / 1000,
    dashValueRatio: ratioOf(policies, 'damagePerRoom'),
    dashValueRatioPerMinute: ratioOf(policies, 'damagePerCombatMinute'),
    policies,
    runs,
  };
}

function writeOut(path, content) {
  const abs = resolve(GAME_DIR, path);
  mkdirSync(dirname(abs), { recursive: true });
  writeFileSync(abs, content);
  return abs;
}

function printSummary(report, files) {
  const lines = [`Playtest : ${report.params.seeds} graines × ${report.params.policies.length} politiques en ${fmt(report.runtimeSeconds, 1)} s`];
  for (const [name, a] of Object.entries(report.policies)) {
    const m = a.metrics;
    lines.push(`  ${name.padEnd(8)} section ${pct(a.sectionRate).padStart(5)} (hors blocages ${a.sectionRatePlayable === null ? '—' : pct(a.sectionRatePlayable)}) | blocages ${a.softlocks.length} | morts ${pct(a.deathRate).padStart(5)} | étage moy ${fmt(m.floorReached.mean, 2)} | dégâts/salle ${fmt(a.pooled.damagePerRoom)} | dégâts/min combat ${fmt(a.pooled.damagePerCombatMinute)} | coups/min ${fmt(m.hitsTakenPerMin.mean, 2)} | esquives/min ${fmt(m.dodgesPerMin.mean, 2)} | dash/min ${fmt(m.dashesPerMin.mean)} | boss ${fmt(m.bossFightSeconds.median)} s`);
  }
  lines.push(`  valeur du dash (noDash ÷ skilled) : ${fmt(report.dashValueRatio, 2)} par salle, ${fmt(report.dashValueRatioPerMinute, 2)} par minute de combat`);
  const audit = report.policies[AUDITED_POLICY]?.dashAudit;
  if (audit) lines.push(`  audit des dash (${AUDITED_POLICY}) : ${audit.decisive}/${audit.dashes} décisifs (${audit.decisiveShare === null ? '—' : pct(audit.decisiveShare)}), ${audit.harmful} nuisibles, ${audit.bothHit} coups inévitables, ${audit.idle} sans effet`);
  lines.push(`  rapports : ${files.join(', ')}`);
  console.log(lines.join('\n'));
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(USAGE);
    return;
  }
  const report = runPlaytest(opts);
  const files = [opts.json ? writeOut(opts.json, JSON.stringify(report, null, 2)) : null, writeOut(opts.md, renderMarkdown(report))].filter(Boolean);
  printSummary(report, files);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    main();
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  }
}
