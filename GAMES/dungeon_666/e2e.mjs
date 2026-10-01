#!/usr/bin/env node
// E2E — navigateur RÉEL (Chromium/Playwright), conforme à forge/contracts/PLAYABLE_CONTRACT.md :
// téléphone émulé en paysage avec de VRAIS doigts tactiles (CDP, multi-touch), puis bureau
// avec de vraies touches clavier et de vrais clics. On observe window.__game / __d666.
// Les raccourcis de test (__game_debug.hit, __d666.killAll/teleport/start/giveSouls) ne servent
// qu'à atteindre vite un état (fin de salle, mort, Gardien, Âmes) : jamais à prouver qu'un geste
// marche — chaque écran, onglet et bouton est ensuite actionné par un vrai doigt ou un vrai clic.
//
// Flux V2 : titre → « Entrer dans Dité » (#enter-town) → onglets de la Ville → « Descendre »
// (#depart) → combat → mort → récapitulatif → « Repartir » (#restart) ou « Retour à la Ville »
// (#to-town) ; Sanctuaire (achat en Âmes), Labo du feel depuis la pause, portail du Gardien.
//
// Usage : node e2e.mjs        (HEADED=1 pour voir ; SHOTS=dossier pour les captures)
// Sortie : une ligne PASS/FAIL par vérification, code 1 si une seule échoue.

import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadChromium, startServer, createTouch, GAME_DIR } from './tools/pw.mjs';

const PORT = Number.parseInt(process.env.DUNGEON_666_E2E_PORT ?? '4667', 10);
const SHOTS = process.env.SHOTS ?? join(GAME_DIR, 'e2e-shots');
const PHONE = { viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 3 };
const PORTRAIT = { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 3 };
const DESKTOP = { viewport: { width: 1280, height: 720 }, hasTouch: false, isMobile: false, deviceScaleFactor: 1 };
// Positions des contrôles (mêmes constantes que src/input/input.mjs, sans zone de sécurité).
const ATTACK = { x: PHONE.viewport.width - 118, y: PHONE.viewport.height - 112 };
const around = (angleDeg, dist) => ({ x: ATTACK.x + Math.cos((angleDeg * Math.PI) / 180) * dist, y: ATTACK.y + Math.sin((angleDeg * Math.PI) / 180) * dist });
const DASH = around(186, 112);
const SKILL = around(228, 112);
const GADGET = around(318, 98);

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} — ${name}${detail ? ` (${detail})` : ''}`);
}

function watchErrors(page) {
  const errors = [];
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    // Les polices Google sont optionnelles (hors ligne, proxy) : leur échec n'est pas un bug.
    // « Ignored attempt to cancel a touchstart… » est un AVIS d'intervention de Chrome (toucher
    // reçu pendant que le fil principal est occupé : l'écouteur devient passif), pas une erreur
    // JavaScript du jeu ; l'effet du geste concerné est vérifié à part (ex. la pause s'ouvre).
    if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)|ERR_CERT|net::ERR_|Ignored attempt to cancel a touch(start|move)/.test(m.text())) errors.push(m.text());
  });
  return errors;
}

const state = (page) => page.evaluate(() => {
  const g = window.__d666.game;
  if (!g) return null;
  const t = g.telemetry;
  return {
    mode: g.mode, floor: g.run.floor, x: g.player.x, y: g.player.y, hp: g.player.hp, pstate: g.player.state,
    attacks: t.attacks, dashes: t.dashes, skills: t.skillCasts, gadgets: t.gadgetUses, kills: t.kills,
    cleared: g.room.cleared, interact: g.room.interact ? { x: g.room.interact.x, y: g.room.interact.y, used: g.room.interact.used, kind: g.room.interact.kind } : null,
    doors: g.room.doors.map((d) => ({ x: d.x + d.w / 2, y: d.y + d.h / 2, open: d.open })),
  };
});

async function shot(page, name) {
  await page.screenshot({ path: join(SHOTS, `${name}.png`) });
}

/** Vrai tap au centre de l'élément (doigt `id`). Rend false si l'élément est absent. */
async function tapEl(page, touch, selector, id, holdMs = 60) {
  // Le panneau défile (paysage de 390 px de haut) : on amène l'élément à l'écran, comme le pouce.
  await page.locator(selector).first().scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
  const box = await page.locator(selector).first().boundingBox({ timeout: 2000 }).catch(() => null);
  if (!box) return false;
  await touch.tap(id, box.x + box.width / 2, box.y + box.height / 2, holdMs);
  return true;
}

const TOWN_TABS = ['classe', 'armurerie', 'equipement', 'grimoire', 'sanctuaire', 'labo', 'portail'];

const appState = (page) => page.evaluate(() => {
  const a = window.__d666.app;
  let saved = null;
  try {
    saved = JSON.parse(localStorage.getItem('dungeon666.meta.v1'));
  } catch {
    saved = null;
  }
  let settings = null;
  try {
    settings = JSON.parse(localStorage.getItem('dungeon666.settings.v1'));
  } catch {
    settings = null;
  }
  return {
    screen: a.screen, paused: a.paused, tab: a.townTab, hasGame: !!a.game,
    souls: a.profile.souls, upgrades: { ...a.profile.upgrades }, checkpoints: [...a.profile.checkpoints],
    lab: { ...a.settings.lab }, saved, settings,
    tabs: [...document.querySelectorAll('#overlay [data-tab]')].map((b) => b.dataset.tab),
    activeTab: document.querySelector('#overlay [data-tab].on')?.dataset.tab ?? null,
    depart: document.querySelector('#depart')?.textContent ?? null,
    departCard: document.querySelector('#depart')?.closest('.card')?.textContent ?? null,
    overlay: document.querySelector('#overlay')?.textContent ?? '',
  };
});

async function phoneRun(browser, base) {
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=4242&tune=0`);
  await page.waitForTimeout(600);
  const touch = await createTouch(page);
  await shot(page, '01_titre_paysage');

  // Titre → Ville par un VRAI tap sur « Entrer dans Dité ».
  await tapEl(page, touch, '#enter-town', 9);
  await page.waitForTimeout(300);
  let a = await appState(page);
  check('titre → « Entrer dans Dité » ouvre la Ville (onglets, bouton « Descendre »)', a.screen === 'town' && TOWN_TABS.every((t) => a.tabs.includes(t)) && !!a.depart, `onglets : ${a.tabs.join(', ')}`);
  // Chaque onglet de la Ville s'ouvre au doigt.
  const opened = [];
  for (const [i, tab] of TOWN_TABS.entries()) {
    await tapEl(page, touch, `#overlay [data-tab="${tab}"]`, 20 + i);
    await page.waitForTimeout(120);
    a = await appState(page);
    if (a.activeTab === tab && a.tab === tab) opened.push(tab);
    if (tab === 'classe') await shot(page, '01b_ville_classe');
  }
  check('Ville : chaque onglet (Classe, Armurerie, Coffre, Grimoire, Sanctuaire, Labo, Portail) s\'ouvre au doigt', opened.length === TOWN_TABS.length, `ouverts : ${opened.join(', ')}`);
  await shot(page, '01c_ville_portail');
  // « Descendre » (#depart) lance la descente depuis le dernier checkpoint.
  await tapEl(page, touch, '#depart', 9);
  await page.waitForTimeout(700);
  let s = await state(page);
  check('le tap sur « Descendre » (#depart) lance la partie à l\'étage 1', s?.mode === 'play' && s.floor === 1);

  // Pouce posé IMMOBILE au bord bas-gauche (là où il repose) : le héros ne doit pas bouger.
  const still0 = await state(page);
  await touch.down(11, 40, 370);
  await page.waitForTimeout(400);
  const still1 = await state(page);
  await touch.up(11);
  check('pouce immobile au bord : aucun déplacement fantôme', Math.hypot(still1.x - still0.x, still1.y - still0.y) < 2, `Δ=${Math.hypot(still1.x - still0.x, still1.y - still0.y).toFixed(1)} u`);
  s = await state(page);

  // Joystick flottant : pouce gauche, glissé vers la droite.
  const x0 = s.x;
  await touch.down(1, 160, 250);
  await touch.move(1, 230, 250);
  await page.waitForTimeout(500);
  s = await state(page);
  check('joystick gauche : le héros se déplace vers la droite', s.x > x0 + 60, `dx=${(s.x - x0).toFixed(0)}`);

  // Multi-touch : on garde le déplacement ET on maintient l'attaque.
  await touch.down(2, ATTACK.x, ATTACK.y);
  await page.waitForTimeout(900);
  s = await state(page);
  check('attaque maintenue (pendant le déplacement) : le combo s\'enchaîne', s.attacks >= 3, `attaques=${s.attacks}`);
  await shot(page, '02_combat_multitouch');
  await touch.up(2);

  const before = await state(page);
  await touch.tap(3, DASH.x, DASH.y);
  await page.waitForTimeout(250);
  s = await state(page);
  check('bouton dash : un dash part, dans la direction du joystick', s.dashes === before.dashes + 1 && s.x > before.x + 80, `dx=${(s.x - before.x).toFixed(0)}`);
  await touch.up(1);

  // Compétence en glisser-relâcher (visée manuelle vers le haut).
  await page.waitForTimeout(200);
  const k0 = (await state(page)).skills;
  await touch.down(4, SKILL.x, SKILL.y);
  await touch.move(4, SKILL.x, SKILL.y - 60);
  await page.waitForTimeout(120);
  await shot(page, '03_visee_lance');
  await touch.up(4);
  await page.waitForTimeout(250);
  check('compétence : glisser-relâcher lance la Lance', (await state(page)).skills === k0 + 1);

  // Zone d'attaque flottante : un tap dans la moitié droite, hors des boutons, attaque.
  const a0 = (await state(page)).attacks;
  await touch.tap(8, PHONE.viewport.width * 0.6, PHONE.viewport.height * 0.3);
  await page.waitForTimeout(250);
  check('tap hors bouton dans la moitié droite : attaque (zone flottante)', (await state(page)).attacks > a0);

  const g0 = (await state(page)).gadgets;
  await touch.tap(5, GADGET.x, GADGET.y);
  await page.waitForTimeout(200);
  check('gadget : un tap consomme une charge', (await state(page)).gadgets === g0 + 1);

  // Fin de salle -> récompense -> menu tactile -> portes -> étage 2.
  await page.evaluate(() => window.__d666.killAll());
  await page.waitForTimeout(900);
  s = await state(page);
  check('salle nettoyée : une récompense apparaît', s.cleared && !!s.interact);
  // Le pouce gauche reste posé sur le joystick pendant tout le menu (cas réel).
  await touch.down(12, 120, 300);
  await page.evaluate(([x, y]) => window.__d666.teleport(x, y), [s.interact.x, s.interact.y]);
  await page.waitForTimeout(60);
  const card = page.locator('.panel button').first();
  const visible = await card.isVisible().catch(() => false);
  check('menu de récompense affiché', visible);
  if (visible) {
    // Tap immédiat (dash martelé) : le panneau est encore désarmé, rien n'est choisi.
    const bb0 = await card.boundingBox();
    await touch.tap(6, bb0.x + bb0.width / 2, bb0.y + bb0.height / 2, 30);
    await page.waitForTimeout(80);
    check('menu tout juste ouvert : un tap réflexe ne choisit rien', (await state(page)).mode === 'choice');
    // Le tap réflexe a relancé l'armement : on attend que le panneau réponde (classe .arming retirée).
    await page.waitForFunction(() => !document.querySelector('#overlay.arming'), null, { timeout: 3000 }).catch(() => {});
    await page.waitForTimeout(50);
    await shot(page, '04_menu_recompense');
    const bb = await card.boundingBox();
    await touch.tap(6, bb.x + bb.width / 2, bb.y + bb.height / 2);
    await page.waitForTimeout(400);
  }
  await touch.up(12);
  s = await state(page);
  check('choix validé au doigt (autre pouce posé) : retour au jeu, portes ouvertes', s.mode === 'play' && s.doors.length > 0 && s.doors.every((d) => d.open));
  await page.evaluate(([x, y]) => window.__d666.teleport(x, y + 20), [s.doors[0].x, s.doors[0].y]);
  await page.waitForTimeout(400);
  s = await state(page);
  check('franchir une porte mène à l\'étage 2', s.floor === 2);
  await page.waitForTimeout(1200);
  await shot(page, '05_etage_2');

  // Mort -> écran de mort -> reprise au checkpoint par un tap.
  await page.evaluate(() => window.__d666.hurt(99999));
  await page.waitForTimeout(2600);
  s = await state(page);
  check('mort : écran de mort après l\'agonie', s.mode === 'dead');
  a = await appState(page);
  check('mort : le récapitulatif dit ce qui est perdu (temporaire) et gardé (permanent)', /Perdu · temporaire/.test(a.overlay) && /Gardé · permanent/.test(a.overlay) && !!(await page.locator('#restart').count()) && !!(await page.locator('#to-town').count()));
  await shot(page, '06_mort');
  const again = await page.locator('.panel button.primary').boundingBox();
  await touch.tap(7, again.x + again.width / 2, again.y + again.height / 2);
  await page.waitForTimeout(600);
  s = await state(page);
  check('« Repartir » (#restart) : reprise au checkpoint, PV pleins', s.mode === 'play' && s.hp > 0 && s.floor === 1);
  // Seconde mort : « Retour à la Ville » (#to-town) termine le run.
  await page.evaluate(() => window.__d666.hurt(99999));
  await page.waitForTimeout(2600);
  await page.waitForFunction(() => !document.querySelector('#overlay.arming'), null, { timeout: 3000 }).catch(() => {});
  await tapEl(page, touch, '#to-town', 13);
  await page.waitForTimeout(400);
  a = await appState(page);
  check('« Retour à la Ville » (#to-town) depuis l\'écran de mort : la Ville, sans partie en cours', a.screen === 'town' && !a.hasGame && !!a.depart);

  const fps = await page.evaluate(() => window.__d666.fps());
  check('aucune erreur JavaScript (paysage tactile)', errors.length === 0, errors.slice(0, 3).join(' | '));
  console.log(`  i/s mesurées (Chromium sans GPU) : ${fps.toFixed(0)}`);
  await ctx.close();
}

async function portraitRun(browser, base) {
  const ctx = await browser.newContext(PORTRAIT);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=7&autostart=1&tune=0`);
  await page.waitForTimeout(1200);
  const touch = await createTouch(page);
  await touch.tap(1, 200, 600);
  await page.waitForTimeout(300);
  await shot(page, '07_portrait');
  // Pouce gauche dans le coin bas-gauche du portrait : il marche, il ne dashe pas.
  const p0 = await state(page);
  await touch.down(3, 150, 720);
  await touch.move(3, 150, 660);
  await page.waitForTimeout(400);
  await touch.up(3);
  const p1 = await state(page);
  check('portrait : le pouce gauche pilote le joystick (pas de dash parasite)', p1.dashes === p0.dashes && Math.hypot(p1.x - p0.x, p1.y - p0.y) > 30, `dash +${p1.dashes - p0.dashes}`);
  const s = await state(page);
  const inside = await page.evaluate(() => {
    const vw = innerWidth;
    const vh = innerHeight;
    return window.__d666.app.game ? [vw, vh] : null;
  });
  check('portrait : la partie tourne sans erreur', s?.mode === 'play' && errors.length === 0 && !!inside, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

async function desktopRun(browser, base) {
  const ctx = await browser.newContext(DESKTOP);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=99&autostart=1&tune=0`);
  await page.waitForTimeout(900);
  const s0 = await state(page);
  await page.keyboard.down('KeyD');
  await page.waitForTimeout(400);
  await page.keyboard.press('Space');
  await page.waitForTimeout(250);
  await page.keyboard.up('KeyD');
  const s1 = await state(page);
  check('clavier : D déplace, Espace dashe', s1.x > s0.x + 100 && s1.dashes === s0.dashes + 1);
  await page.mouse.move(800, 300);
  await page.mouse.down();
  await page.waitForTimeout(600);
  await page.mouse.up();
  const s2 = await state(page);
  check('souris : clic gauche maintenu = attaques', s2.attacks >= 2);
  // Clic droit PENDANT le clic gauche maintenu : la Lance part, et rien ne reste « collé ».
  await page.waitForTimeout(4200); // recharge de la Lance
  const k1 = (await state(page)).skills;
  await page.mouse.down({ button: 'left' });
  await page.waitForTimeout(150);
  await page.mouse.down({ button: 'right' });
  await page.waitForTimeout(100);
  await page.mouse.up({ button: 'left' });
  await page.mouse.up({ button: 'right' });
  await page.waitForTimeout(300);
  const a1 = (await state(page)).attacks;
  await page.waitForTimeout(700);
  const after = await state(page);
  check('souris : clic droit pendant le gauche = Lance ; boutons relâchés = plus d\'attaque', after.skills === k1 + 1 && after.attacks - a1 <= 1, `lances +${after.skills - k1}, attaques après relâche +${after.attacks - a1}`);
  await shot(page, '08_bureau');
  // Fin de partie forcée, puis VRAI clic sur #restart (vocabulaire du PLAYABLE_CONTRACT).
  await page.evaluate(() => window.__game_debug.hit());
  await page.waitForTimeout(2600);
  const over = await page.evaluate(() => window.__game.over && !document.querySelector('#overlay').classList.contains('hidden'));
  check('défaite : window.__game.over et #overlay visible', over);
  await page.click('#restart');
  await page.waitForTimeout(500);
  const back = await page.evaluate(() => !window.__game.over && window.__game.player.hp > 0);
  check('clic sur #restart : la partie reprend', back);
  check('aucune erreur JavaScript (bureau)', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

async function arenaRun(browser, base) {
  // Arène d'essai : lancée par un VRAI tap sur son bouton du titre ; vagues sans fin.
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=8&tune=0&god=1`);
  await page.waitForTimeout(600);
  const touch = await createTouch(page);
  const btn = await page.locator('button', { hasText: 'Arène' }).boundingBox();
  await touch.tap(1, btn.x + btn.width / 2, btn.y + btn.height / 2);
  await page.waitForTimeout(700);
  const sandbox = await page.evaluate(() => !!window.__d666.game?.sandbox);
  await page.evaluate(() => window.__d666.killAll());
  await page.waitForTimeout(1800);
  const s = await state(page);
  check('arène d\'essai : vagues sans fin, ni portes ni menus', sandbox && s.mode === 'play' && s.doors.length === 0 && errors.length === 0, errors.slice(0, 2).join(' | '));
  await shot(page, '09_arene');
  await ctx.close();
}

async function bundleRun(browser) {
  // Le fichier unique doit tourner en double-clic (file://), sans serveur.
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  const url = `${pathToFileURL(join(GAME_DIR, 'dist', 'dungeon_666.html')).href}?seed=5&autostart=1`;
  await page.goto(url);
  await page.waitForTimeout(1200);
  const s = await state(page);
  check('fichier unique dist/dungeon_666.html : jouable en file://', s?.mode === 'play' && errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

/** Dash martelé (4 Hz) en arrivant sur la récompense : le panneau s'ouvre, rien n'est choisi. */
async function mashRun(browser, base) {
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=4242&autostart=1&tune=0`);
  await page.waitForTimeout(800);
  await page.evaluate(() => window.__d666.killAll());
  await page.waitForTimeout(1200);
  const it = await page.evaluate(() => ({ x: window.__d666.game.room.interact.x, y: window.__d666.game.room.interact.y }));
  // Le héros fonce vers la récompense : le panneau s'ouvre au milieu de la rafale de dash.
  await page.evaluate(([x, y]) => { window.__d666.teleport(x - 200, y); window.__d666.game.player.facing = 0; }, [it.x, it.y]);
  await page.waitForTimeout(200);
  const touch = await createTouch(page);
  await touch.down(40, 120, 300);
  await touch.move(40, 170, 300);
  for (let i = 0; i < 8; i++) {
    await touch.tap(2 + i, DASH.x, DASH.y, 50);
    await page.waitForTimeout(200);
  }
  await touch.up(40);
  const s = await page.evaluate(() => ({ mode: window.__d666.game.mode, boons: window.__d666.game.run.boons.length }));
  check('dash martelé à l\'ouverture du menu : aucun choix à l\'aveugle', s.mode === 'choice' && s.boons === 0 && errors.length === 0, `mode=${s.mode} bénédictions=${s.boons}`);
  await ctx.close();
}

/**
 * La boucle V2 au doigt : Âmes (crochet de test) → achat au Sanctuaire → descente plus solide →
 * pause → Labo du feel (variante changée en pleine partie) → Gardien vaincu → portail de la
 * Ville → le checkpoint 19 est le nouveau point de départ.
 */
async function loopRun(browser, base) {
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=77&tune=0`);
  await page.waitForTimeout(600);
  const touch = await createTouch(page);
  await tapEl(page, touch, '#enter-town', 1);
  await page.waitForTimeout(250);

  // Sanctuaire : des Âmes offertes, puis un VRAI tap sur « Améliorer » de la Vitalité.
  await page.evaluate(() => window.__d666.giveSouls(100));
  await page.waitForTimeout(150); // la Ville se redessine avec les Âmes reçues
  await tapEl(page, touch, '#overlay [data-tab="sanctuaire"]', 2);
  await page.waitForTimeout(200);
  const before = await appState(page);
  const buy = page.locator('#overlay .card', { hasText: 'Vitalité' }).locator('button');
  const label = (await buy.textContent().catch(() => '')) ?? '';
  const price = Number((label.match(/◆\s*(\d+)/) ?? [])[1] ?? Number.NaN);
  await tapEl(page, touch, '#overlay .card:has-text("Vitalité") button', 3);
  await page.waitForTimeout(250);
  let a = await appState(page);
  check('Sanctuaire : Vitalité achetée au doigt avec des Âmes (prix payé, niveau 1, profil sauvegardé)',
    before.souls === 100 && a.upgrades.vitalite === 1 && a.souls === before.souls - price && a.saved?.upgrades?.vitalite === 1 && a.saved?.souls === a.souls,
    `Âmes ${before.souls} → ${a.souls}, prix ${price}, niveau ${a.upgrades.vitalite}`);
  await shot(page, '10_sanctuaire');

  // Descente : la Vitalité compte (permanent).
  await tapEl(page, touch, '#overlay [data-tab="portail"]', 4);
  await page.waitForTimeout(150);
  await tapEl(page, touch, '#depart', 5);
  await page.waitForTimeout(600);
  const hp = await page.evaluate(() => {
    const g = window.__d666.game;
    return { bonus: g.player.stats.maxHpBonus, per: g.tuning.town.upgrades.vitalite.perLevel, hp: g.player.hp, max: g.player.maxHp, mode: g.mode };
  });
  check('descente suivante : la Vitalité achetée en Ville donne ses PV max', hp.mode === 'play' && hp.bonus >= hp.per && hp.hp === hp.max, `bonus ${hp.bonus}, PV ${hp.hp}/${hp.max}`);

  // Pause (bouton du HUD) → Labo du feel → gel LOCAL, en pleine partie.
  const vw = PHONE.viewport.width;
  await touch.tap(6, vw - 32, 26);
  await page.waitForTimeout(250);
  a = await appState(page);
  const paused = a.paused;
  await tapEl(page, touch, '#overlay button:has-text("Labo du feel")', 7);
  await page.waitForTimeout(200);
  await tapEl(page, touch, '#overlay [data-lab="hitstop:local"]', 8);
  await page.waitForTimeout(200);
  await shot(page, '11_labo_pause');
  const lab = await page.evaluate(() => ({ mode: window.__d666.game.tuning.hitstopMode, choice: window.__d666.game.tuning.lab.hitstop }));
  a = await appState(page);
  check('pause → Labo du feel : la variante D8 « Local » s\'applique à la partie en cours et est retenue',
    paused && lab.mode === 'local' && lab.choice === 'local' && a.lab.hitstop === 'local' && a.settings?.lab?.hitstop === 'local',
    `pause=${paused}, partie=${lab.mode}, réglages=${a.settings?.lab?.hitstop}`);
  await tapEl(page, touch, '#overlay button:has-text("Retour")', 9);
  await page.waitForTimeout(150);
  await tapEl(page, touch, '#overlay button:has-text("Reprendre")', 10);
  await page.waitForTimeout(250);
  a = await appState(page);
  check('labo fermé, « Reprendre » : la partie repart', a.screen === 'game' && !a.paused && (await state(page)).mode === 'play');

  // Gardien (crochet : étage 18, Gardien abattu d'office), puis portail de la Ville au doigt… de pied.
  await page.evaluate(() => window.__d666.start(18));
  await page.waitForTimeout(500);
  const boss = await page.evaluate(() => window.__d666.game.enemies.some((e) => e.boss));
  await page.evaluate(() => window.__d666.killAll());
  await page.waitForTimeout(1800);
  let s = await state(page);
  const rewards = await page.evaluate(() => window.__d666.game.room.doors.map((d) => d.reward));
  check('Gardien de l\'étage 18 vaincu : checkpoint 19 ouvert, portes [suite, Ville]', boss && s.cleared && rewards.length === 2 && rewards[1] === 'town' && (await appState(page)).checkpoints.includes(19), `portes : ${rewards.join(', ')}`);
  await shot(page, '12_portail_gardien');
  await page.evaluate(([x, y]) => window.__d666.teleport(x, y + 20), [s.doors[1].x, s.doors[1].y]);
  await page.waitForTimeout(500);
  a = await appState(page);
  check('portail du Gardien : retour en Ville, checkpoint 19 sauvegardé, « Descendre » part de l\'étage 19',
    a.screen === 'town' && !a.hasGame && a.saved?.checkpoints?.includes(19) && /Étage 19/.test(a.departCard ?? ''),
    `écran ${a.screen}, carte : ${(a.departCard ?? '').slice(0, 60)}`);
  await shot(page, '13_ville_apres_gardien');
  await tapEl(page, touch, '#depart', 11);
  await page.waitForTimeout(600);
  s = await state(page);
  const boons = await page.evaluate(() => window.__d666.game?.run.boons.length ?? -1);
  check('nouvelle descente depuis le checkpoint 19 : aucune bénédiction (le temporaire est reparti de zéro)', s?.mode === 'play' && s.floor === 19 && boons === 0, `étage ${s?.floor}`);
  check('aucune erreur JavaScript (boucle Ville → Gardien → Ville)', errors.length === 0, errors.slice(0, 3).join(' | '));
  await ctx.close();
}

async function main() {
  await mkdir(SHOTS, { recursive: true });
  const server = await startServer(PORT);
  const chromium = loadChromium();
  const browser = await chromium.launch({ headless: !process.env.HEADED });
  const base = `http://localhost:${PORT}`;
  try {
    await phoneRun(browser, base);
    await loopRun(browser, base);
    await mashRun(browser, base);
    await portraitRun(browser, base);
    await desktopRun(browser, base);
    await arenaRun(browser, base);
    await bundleRun(browser);
  } catch (err) {
    check('déroulé e2e sans exception', false, err.message);
  } finally {
    await browser.close();
    server.kill();
  }
  const failed = results.filter((r) => !r.ok);
  console.log(`\nRESULT: ${failed.length === 0 ? 'PASS' : 'FAIL'} — ${results.length - failed.length}/${results.length} vérifications`);
  process.exit(failed.length === 0 ? 0 : 1);
}

main();
