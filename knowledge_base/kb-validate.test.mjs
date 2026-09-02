// Tests du validateur de catalogue KB — écrits AVANT l'implémentation (TDD).
// Un test (au moins) par règle R1..R12 du contrat docs/forge/KB_INGESTION_CONTRACT.md.
// Fixtures : répertoires temporaires jetables (mkdtemp + rm en teardown — rien ne reste).
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

import { validateCatalog, loadCatalog } from "./kb-validate.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

// Construit un faux repo-root avec une knowledge_base peuplée de VRAIS fichiers.
function makeRoot(t) {
  const root = mkdtempSync(join(tmpdir(), "kbtest-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const kb = join(root, "knowledge_base");
  for (const d of [
    "assets/characters", "systems/combat", "patterns/tactical_combat",
    "templates/tactical", "proofs", "roles",
  ]) mkdirSync(join(kb, d), { recursive: true });

  const files = {};
  // asset ingéré : vrai en-tête PNG (magic bytes) + charge factice pour la taille.
  const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const png = Buffer.concat([PNG_SIG, Buffer.from("fake-png-payload".repeat(60))]);
  writeFileSync(join(kb, "assets/characters/hero.png"), png);
  files.asset = { path: "knowledge_base/assets/characters/hero.png", sha: sha256(png), kb: Math.max(1, Math.round(png.length / 1024)) };
  // pattern (fiche md)
  const md = Buffer.from("# Pattern damage floor\nSource citee. Zero code.\n");
  writeFileSync(join(kb, "patterns/tactical_combat/damage_floor.md"), md);
  files.pattern = { path: "knowledge_base/patterns/tactical_combat/damage_floor.md", sha: sha256(md) };
  // system (module pur) + tests
  const sys = Buffer.from("export function damage(atk, def) { return Math.max(1, atk - def); }\n");
  writeFileSync(join(kb, "systems/combat/damage_floor.mjs"), sys);
  files.system = { path: "knowledge_base/systems/combat/damage_floor.mjs", sha: sha256(sys) };
  const tst = Buffer.from("import { test } from 'node:test';\n");
  writeFileSync(join(kb, "systems/combat/damage_floor.test.mjs"), tst);
  files.tests = { path: "knowledge_base/systems/combat/damage_floor.test.mjs" };
  // une preuve d'usage (fichier réel)
  writeFileSync(join(kb, "proofs/run-green.log"), "exit 0\n");
  files.proof = { path: "knowledge_base/proofs/run-green.log" };
  // un rôle (fichier YAML réel, contenu non parsé par kb-validate — seul le path compte)
  writeFileSync(join(kb, "roles/pursuer-mobile.yaml"), "role_id: role-pursuer-mobile\n");
  files.role = { path: "knowledge_base/roles/pursuer-mobile.yaml" };
  return { root, kb, files };
}

function baseAsset(f) {
  return {
    entry_type: "asset", asset_id: "asset-hero-stand", source: "Kenney — Top-down Shooter",
    license: "CC0-1.0", provenance_url: "https://www.kenney.nl/assets/top-down-shooter",
    style: "flat-top-down", genre: ["tactical"], biome: null, format: "2D",
    size_kb: f.asset.kb, sha256: f.asset.sha, runtime: "html", ingested: true,
    path: f.asset.path, usage_examples: [], tier: "candidate",
  };
}
function basePattern(f) {
  return {
    entry_type: "brick", brick_id: "pat-damage-floor", kind: "pattern",
    function: "degats = max(1, atk - def) — anti-stalemate",
    source: "Battle for Wesnoth (concept cite)",
    provenance_url: "https://wiki.wesnoth.org/CombatMechanics",
    license: "GPL-2.0-or-later", runtime: "agnostic", dependencies: [], parameters: {},
    genre_compatible: ["tactical"], invariants: ["tout coup inflige >= 1"],
    proof_of_use: null, tier: "candidate", path: f.pattern.path, sha256: f.pattern.sha,
    tests: null, advisory_only: true, affordances: {},
  };
}
function baseSystem(f) {
  return {
    entry_type: "brick", brick_id: "sys-damage-floor", kind: "system",
    function: "fonction pure de degats plancher",
    source: "reecriture propre inspiree de pat-damage-floor",
    provenance_url: null, license: "MIT", runtime: "html",
    dependencies: ["pat-damage-floor"], parameters: {},
    genre_compatible: ["tactical"], invariants: ["degats >= 1", "deterministe"],
    proof_of_use: null, tier: "candidate", path: f.system.path, sha256: f.system.sha,
    tests: f.tests.path, advisory_only: false,
    // couvre la capacite par defaut de baseRole() (Tier 1 #4, R14) — un pont VRAI
    // par defaut ; les tests qui veulent une couverture absente l'ecrasent explicitement.
    affordances: { movement: { type: "fn(pos,targetPos,speed)->pos", description: "se deplace vers la cible" } },
  };
}
function baseRole(f) {
  return {
    entry_type: "role", role_id: "role-pursuer-mobile",
    archetype: "poursuivant mobile qui rattrape une cible fuyante en terrain ouvert",
    requires: {
      movement: { type: "fn(pos,targetPos,speed)->pos", description: "se deplace vers la cible" },
    },
    fulfilled_by: ["sys-damage-floor"], // brick_id EXISTANT dans les fixtures partagees
    tier: "candidate", license: "MIT", path: f.role.path, proof_of_use: null,
  };
}
function manifestOnly3D() {
  return {
    entry_type: "asset", asset_id: "asset-kaykit-dungeon-pack", source: "KayKit — Dungeon Pack",
    license: "CC0-1.0", provenance_url: "https://kaylousberg.itch.io/kaykit-dungeon",
    style: "lowpoly", genre: ["rpg"], biome: "dungeon", format: "3D",
    size_kb: null, sha256: null, runtime: "godot", ingested: false,
    path: null, usage_examples: [], tier: "candidate",
  };
}
function makeCatalog(entries) {
  return { catalog_version: 1, entries };
}

// ---------- Cas nominal ----------
test("catalogue conforme -> ok, zero erreur", (t) => {
  const { root, files } = makeRoot(t);
  const cat = makeCatalog([baseAsset(files), basePattern(files), baseSystem(files), manifestOnly3D()]);
  const res = validateCatalog(cat, { root });
  assert.deepEqual(res.errors, []);
  assert.equal(res.ok, true);
});

// ---------- R1 schéma ----------
test("R1: champ manquant (provenance_url) -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); delete a.provenance_url;
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.equal(res.ok, false);
  assert.ok(res.errors.some((e) => e.rule === "R1" && e.id === "asset-hero-stand"));
});
test("R1: prefixe d'id incoherent avec kind -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const p = basePattern(files); p.brick_id = "sys-damage-floor-pattern";
  const res = validateCatalog(makeCatalog([p]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1"));
});
test("R1: ids dupliques -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const res = validateCatalog(makeCatalog([basePattern(files), basePattern(files)]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /dupli/i.test(e.msg)));
});
test("R1: catalog_version invalide -> rejet", (t) => {
  const { root } = makeRoot(t);
  const res = validateCatalog({ catalog_version: 2, entries: [] }, { root });
  assert.ok(res.errors.some((e) => e.rule === "R1"));
});

// ---------- R2 SPDX ----------
test("R2: licence hors liste fermee ('GPLv3' non-SPDX) -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const p = basePattern(files); p.license = "GPLv3";
  const res = validateCatalog(makeCatalog([p]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R2"));
});

// ---------- R3 provenance ----------
test("R3: provenance_url non http(s) -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.provenance_url = "ftp://example.org/x";
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R3"));
});

// ---------- R4 GPL en code ----------
test("R4: system sous GPL -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.license = "GPL-3.0-only";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R4" && e.id === "sys-damage-floor"));
});

// ---------- R5 pattern ----------
test("R5: pattern GPL avec advisory_only=false -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const p = basePattern(files); p.advisory_only = false;
  const res = validateCatalog(makeCatalog([p]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R5"));
});
test("R5: pattern dont le path n'est pas un .md -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const p = basePattern(files); p.path = files.system.path; p.sha256 = files.system.sha;
  const res = validateCatalog(makeCatalog([p]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R5"));
});

// ---------- R6 godot/3D manifest-only ----------
test("R6: asset godot/3D avec ingested=true -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = { ...manifestOnly3D(), ingested: true, path: files.asset.path, sha256: files.asset.sha, size_kb: files.asset.kb };
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R6"));
});
// Amendement etape 0 (2026-07-21) : R6 "manifest-only" ne s'applique plus au CODE godot
// (seulement aux assets 3D non ingeres, cf. validateAsset ci-dessus, inchange). Un system
// runtime:godot avec un vrai path/sha256/tests suit desormais exactement le meme regime
// de preuve qu'un system non-godot -> plus de rejet R6 automatique.
test("R6 amende: brick system runtime godot avec path/sha256/tests reels -> plus de rejet R6", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.runtime = "godot";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors.filter((e) => e.rule === "R6"), []);
  assert.equal(res.ok, true);
});

// Fabrique une brick "system" godot avec un vrai fichier .gd sur disque (meme convention
// que systemWith() plus bas : ecrit un fichier reel dans la temp knowledge_base/, calcule
// son sha256 reel). Reutilise le fichier de tests partage (files.tests.path) : un system
// godot suit le meme regime de preuve qu'un system non-godot, y compris R12 (tests).
function godotSystemBrick(kb, files, name = "sys-godot-trial", brickId = "sys-godot-trial") {
  const body = "extends Node\n\nfunc _ready() -> void:\n\tpass\n";
  const p = `knowledge_base/systems/combat/${name}.gd`;
  writeFileSync(join(kb, "systems/combat", `${name}.gd`), body);
  const s = baseSystem(files);
  s.brick_id = brickId; s.runtime = "godot"; s.path = p; s.sha256 = sha256(Buffer.from(body));
  s.dependencies = ["pat-damage-floor"];
  return s;
}

// Fabrique une brick "system" godot dont le CONTENU .gd est fourni par l'appelant (au lieu
// du corps fixe de godotSystemBrick ci-dessus) — meme convention que systemWith() (JS) mais
// pour un fichier .gd reel sur disque, sha256 reel. Sert les tests R10/GDScript ci-dessous.
function godotBrickWithSource(kb, files, src, name = "sys-godot-src", brickId = "sys-godot-src") {
  const p = `knowledge_base/systems/combat/${name}.gd`;
  writeFileSync(join(kb, "systems/combat", `${name}.gd`), src);
  const s = baseSystem(files);
  s.brick_id = brickId; s.runtime = "godot"; s.path = p; s.sha256 = sha256(Buffer.from(src));
  s.dependencies = ["pat-damage-floor"];
  return s;
}

// ---------- R10 GDScript (amendement etape 0, spec 2026-07-21 §8b) ----------
test("R10 GDScript: randi() dans une brique godot -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = godotBrickWithSource(kb, files, "var x = randi()\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10" && /randi/.test(e.msg)), JSON.stringify(res.errors));
});
test("R10 GDScript: Time.get_ticks_msec() -> rejet R10 (non deterministe)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = godotBrickWithSource(kb, files, "var t = Time.get_ticks_msec()\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});
test("R10 GDScript: FileAccess.open() -> rejet R10 (I/O)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = godotBrickWithSource(kb, files, 'var f = FileAccess.open("x", 1)\n');
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});
test("R10 GDScript: du .gd pur ne declenche AUCUN R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const src = "func step(pos: Vector2i, dir: Vector2i) -> Vector2i:\n\treturn pos + dir\n";
  const s = godotBrickWithSource(kb, files, src);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors.filter((e) => e.rule === "R10"), []);
});
test("R10 GDScript: le mot randi en COMMENTAIRE ne declenche pas R10 (pas de faux positif)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const src = "# ne jamais utiliser randi() ici\nfunc f() -> int:\n\treturn 1\n";
  const s = godotBrickWithSource(kb, files, src);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors.filter((e) => e.rule === "R10"), []);
});

// ---------- Correctif de revue : '#' DANS une chaine n'est pas un commentaire ----------
// stripGdscriptCommentsAndStrings retirait les commentaires AVANT les chaines : un '#'
// a l'interieur d'un litteral de chaine etait pris pour un debut de commentaire, effacant
// tout le reste de la ligne — y compris de l'impurete reelle (randi() invisible). Ces 5 tests
// verifient l'analyseur en une seule passe (correctif de revue, gate contre-verifie).
test("R10 GDScript: '#' DANS une chaine de format idiomatique -> rejet R10 (randi visible)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const src = 'var label := "#%d" % randi()\n';
  const s = godotBrickWithSource(kb, files, src);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10" && /randi/.test(e.msg)), JSON.stringify(res.errors));
});
test("R10 GDScript: '#' dans une chaine suivi d'un vrai appel non-deterministe -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const src = 'var s = "hp: #"; var d = randi_range(1, 3)\n';
  const s = godotBrickWithSource(kb, files, src);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10" && /randi_range/.test(e.msg)), JSON.stringify(res.errors));
});
test("R10 GDScript: guillemet DANS un commentaire n'ouvre pas de fausse chaine (code suivant reste visible)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const src = "# n'utilise pas randi\nfunc f() -> int:\n\treturn 1\n";
  const s = godotBrickWithSource(kb, files, src);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors.filter((e) => e.rule === "R10"), []);
});
test("R10 GDScript: chaine triple-guillemets contenant randi() -> AUCUN R10 (c'est du texte)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const src = 'var doc := """\nExemple: randi() retourne un entier.\n"""\nfunc f() -> int:\n\treturn 1\n';
  const s = godotBrickWithSource(kb, files, src);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors.filter((e) => e.rule === "R10"), []);
});

test("R6: brick system runtime godot avec path .gd + tests + sha256 -> ACCEPTEE", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = godotSystemBrick(kb, files);
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors.filter((e) => e.rule === "R6"), []);
  assert.equal(res.ok, true);
});

test("R6: brick system runtime godot SANS path -> rejet R7 (pas d esquive de preuve)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = godotSystemBrick(kb, files);
  s.path = null; s.sha256 = null; s.tests = null;
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.equal(res.ok, false);
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});

test("R6 INCHANGEE: asset 3D/godot ingere reste rejete (manifest-only)", (t) => {
  const { root, files } = makeRoot(t);
  const a = { ...manifestOnly3D(), ingested: true, path: files.asset.path, sha256: files.asset.sha, size_kb: files.asset.kb };
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.equal(res.ok, false);
  assert.ok(res.errors.some((e) => e.rule === "R6"));
});

// ---------- R7 réalité disque ----------
test("R7: sha256 declare != sha reel -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.sha256 = "0".repeat(64);
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7" && /sha/i.test(e.msg)));
});
test("R7: path hors de knowledge_base/ -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.path = "games/leviathan/public/assets/manBlue_stand.png";
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});
test("R7: path avec '..' -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.path = "knowledge_base/../secrets.png";
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});
test("R7: fichier absent du disque -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.path = "knowledge_base/assets/characters/ghost.png";
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});
test("R7: size_kb incoherent (hors tolerance) -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.size_kb = files.asset.kb + 500;
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7" && /size/i.test(e.msg)));
});

// ---------- R8 tier ----------
test("R8: brick validated sans proof_of_use -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = null;
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});
test("R8: brick validated avec proof_of_use inexistant sur disque -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = "knowledge_base/proofs/nope.log";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});
test("R8: brick validated avec preuve reelle -> ok", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = files.proof.path;
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors, []);
});
test("R8: asset validated sans usage_examples -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.tier = "validated";
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});

// ---------- R9 dépendances ----------
test("R9: dependance vers un id inconnu -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.dependencies = ["sys-inexistant"];
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R9"));
});
test("R9: cycle de dependances -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s1 = baseSystem(files);
  const s2 = { ...baseSystem(files), brick_id: "sys-autre", dependencies: ["sys-damage-floor"] };
  s1.dependencies = ["sys-autre"];
  const res = validateCatalog(makeCatalog([basePattern(files), s1, s2]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R9" && /cycl/i.test(e.msg)));
});

// ---------- R10 pureté ----------
test("R10: system contenant Math.random -> rejet", (t) => {
  const { root, kb, files } = makeRoot(t);
  const impure = Buffer.from("export function roll() { return Math.random(); }\n");
  writeFileSync(join(kb, "systems/combat/impure.mjs"), impure);
  const s = baseSystem(files);
  s.brick_id = "sys-impure"; s.path = "knowledge_base/systems/combat/impure.mjs"; s.sha256 = sha256(impure);
  s.dependencies = [];
  const res = validateCatalog(makeCatalog([s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});

// ---------- R11 patterns jamais injectés ----------
test("R11: system qui importe depuis patterns/ -> rejet", (t) => {
  const { root, kb, files } = makeRoot(t);
  const bad = Buffer.from("import { x } from '../../patterns/tactical_combat/damage_floor.md';\nexport const y = 1;\n");
  writeFileSync(join(kb, "systems/combat/bad_import.mjs"), bad);
  const s = baseSystem(files);
  s.brick_id = "sys-bad-import"; s.path = "knowledge_base/systems/combat/bad_import.mjs"; s.sha256 = sha256(bad);
  s.dependencies = [];
  const res = validateCatalog(makeCatalog([s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R11"));
});

// ---------- R12 tests des systems ----------
test("R12: system sans fichier de tests -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.tests = null;
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R12"));
});

// ---------- entry_type "role" (Tier 1 #3) ----------
test("role conforme, fulfilled_by pointe une brique reelle -> ok", (t) => {
  const { root, files } = makeRoot(t);
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), baseRole(files)]), { root });
  assert.deepEqual(res.errors, []);
});
test("R1: role_id sans prefixe 'role-' -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.role_id = "pursuer-mobile";
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /role_id/.test(e.msg)));
});
test("R1: requires vide -> rejet (un role exige au moins une capacite)", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.requires = {};
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /requires/.test(e.msg)));
});
test("R1: capacite requires mal formee (description manquante) -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.requires = { movement: { type: "fn()->pos" } };
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /requires/.test(e.msg)));
});
test("R13: fulfilled_by reference une brique inexistante -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.fulfilled_by = ["sys-n-existe-pas"];
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R13"));
});
test("R14: brique existante mais affordances ne couvre pas requires -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.affordances = {};
  const r = baseRole(files); // requires: { movement: {...} }
  const res = validateCatalog(makeCatalog([basePattern(files), s, r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R14" && /movement/.test(e.msg)));
});
test("R14: brique dont affordances couvre requires -> ok (le pont est vrai)", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); // affordances par defaut couvre deja "movement"
  const r = baseRole(files);
  const res = validateCatalog(makeCatalog([basePattern(files), s, r]), { root });
  assert.deepEqual(res.errors, []);
});
test("R14: affordances couvre PARTIELLEMENT requires (2 capacites, 1 seule fournie) -> rejet, nomme la manquante", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); // affordances par defaut ne fournit QUE "movement"
  const r = baseRole(files);
  r.requires = {
    movement: { type: "fn(pos,targetPos,speed)->pos", description: "se deplace" },
    distance_metric: { type: "fn(a,b)->number", description: "distance" },
  };
  const res = validateCatalog(makeCatalog([basePattern(files), s, r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R14" && /distance_metric/.test(e.msg)));
  assert.ok(!res.errors.some((e) => e.rule === "R14" && e.msg.includes("movement,")));
});
test("R7: role avec path absent du disque -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.path = "knowledge_base/roles/ghost.yaml";
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});
test("R8: role validated sans proof_of_use -> rejet", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.tier = "validated"; r.proof_of_use = null;
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});
test("R8: role validated avec preuve reelle -> ok", (t) => {
  const { root, files } = makeRoot(t);
  const r = baseRole(files); r.tier = "validated"; r.proof_of_use = files.proof.path;
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.deepEqual(res.errors, []);
});
test("RT: champ inconnu sur un role -> rejet R1 (schema ferme)", (t) => {
  const { root, files } = makeRoot(t);
  const r = { ...baseRole(files), backdoor: true };
  const res = validateCatalog(makeCatalog([basePattern(files), baseSystem(files), r]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /inconnu/.test(e.msg)));
});

// ---------- affordances (brick, Tier 1 #3) ----------
test("brick sans affordances -> rejet R1 (schema ferme, champ mandatoire)", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); delete s.affordances;
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /affordances/.test(e.msg)));
});
test("brick avec affordances bien formees -> ok", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files);
  s.affordances = { heal: { type: "fn(hp,amount)->hp", description: "soigne, borne au max" } };
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors, []);
});
test("brick avec affordances mal formees (cle surnumeraire) -> rejet R1", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files);
  s.affordances = { heal: { type: "fn(hp,amount)->hp", description: "x", extra: "surnumeraire" } };
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /affordances/.test(e.msg)));
});

// ---------- Brique-contrôle anti-théâtre (§6 du contrat) ----------
test("controle anti-theatre: brique mal indexee (GPL system + validated sans preuve + sha faux) -> REJETEE avec >=3 violations", (t) => {
  const { root, files } = makeRoot(t);
  const broken = baseSystem(files);
  broken.brick_id = "sys-control-broken";
  broken.license = "GPL-3.0-only";
  broken.tier = "validated"; broken.proof_of_use = null;
  broken.sha256 = "f".repeat(64);
  broken.dependencies = [];
  const res = validateCatalog(makeCatalog([broken]), { root });
  assert.equal(res.ok, false);
  const rules = new Set(res.errors.filter((e) => e.id === "sys-control-broken").map((e) => e.rule));
  assert.ok(rules.size >= 3, `attendu >=3 regles violees, obtenu: ${[...rules].join(",")}`);
});

// ---------- loadCatalog + codes de sortie CLI ----------
test("loadCatalog: JSON illisible -> {error}", (t) => {
  const { root } = makeRoot(t);
  const p = join(root, "knowledge_base", "catalog.json");
  writeFileSync(p, "{ pas du json");
  const r = loadCatalog(p);
  assert.ok(r.error);
});
test("CLI: exit 0 sur catalogue conforme, 1 sur violation, 2 sur illisible", (t) => {
  const { root, files } = makeRoot(t);
  const catPath = join(root, "knowledge_base", "catalog.json");
  const cli = join(__dirname, "kb-validate.mjs");
  // conforme
  writeFileSync(catPath, JSON.stringify(makeCatalog([baseAsset(files)])));
  assert.equal(spawnSync(process.execPath, [cli, catPath], { encoding: "utf-8" }).status, 0);
  // violation
  const bad = baseAsset(files); bad.license = "GPL-3.0-only";
  writeFileSync(catPath, JSON.stringify(makeCatalog([bad])));
  assert.equal(spawnSync(process.execPath, [cli, catPath], { encoding: "utf-8" }).status, 1);
  // illisible
  writeFileSync(catPath, "###");
  assert.equal(spawnSync(process.execPath, [cli, catPath], { encoding: "utf-8" }).status, 2);
});

// =====================================================================================
// Tests de NON-RÉGRESSION issus du red-team claude-blind (KB_REDTEAM_ADJUDICATION.md).
// Chaque cas = un exploit confirmé qui passait sur v1 et DOIT échouer sur v2.
// =====================================================================================

// RT-F1/F3 : proof_of_use bidon (racine repo, absolu, dossier, chaine vide) -> REJET R8.
test("RT-F1: proof_of_use hors knowledge_base/proofs (racine repo) -> rejet R8", (t) => {
  const { root, kb, files } = makeRoot(t);
  writeFileSync(join(root, "NOT_A_GATE.txt"), "x");
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = "NOT_A_GATE.txt";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"), JSON.stringify(res.errors));
});
test("RT-F1: proof_of_use = '.' (dossier racine) -> rejet R8", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = ".";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});
test("RT-F1: proof_of_use dossier existant sous kb -> rejet R8 (pas un fichier)", (t) => {
  const { root, kb, files } = makeRoot(t);
  mkdirSync(join(kb, "proofs", "adir"), { recursive: true });
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = "knowledge_base/proofs/adir";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});
test("RT-F1: proof_of_use fichier reel sous knowledge_base/proofs -> accepte", (t) => {
  const { root, kb, files } = makeRoot(t);
  writeFileSync(join(kb, "proofs", "run-green.log"), "exit 0\n");
  const s = baseSystem(files); s.tier = "validated"; s.proof_of_use = "knowledge_base/proofs/run-green.log";
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors, []);
});
test("RT-F2: usage_examples = chaine vide -> rejet R8", (t) => {
  const { root, files } = makeRoot(t);
  const a = baseAsset(files); a.tier = "validated"; a.usage_examples = [""];
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R8"));
});

// RT-F2/F3 pureté : formes d'import STANDARD (non obfusquees) doivent etre bloquees.
function systemWith(kb, files, body, name = "sys-x", brickId = "sys-x") {
  const p = `knowledge_base/systems/combat/${name}.mjs`;
  writeFileSync(join(kb, "systems/combat", `${name}.mjs`), body);
  const s = baseSystem(files); s.brick_id = brickId; s.path = p; s.sha256 = sha256(Buffer.from(body)); s.dependencies = ["pat-damage-floor"];
  return s;
}
test("RT-F2: import { readFileSync } from \"fs\" (specificateur nu) -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "import { readFileSync } from \"fs\";\nexport const y=1;\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"), JSON.stringify(res.errors));
});
test("RT-F2: import fs from\"node:fs\" (sans espace apres from) -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "import fs from\"node:fs\";\nexport const y=1;\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});
test("RT-F2: await import('node:child_process') dynamique -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "export async function f(){ const cp = await import('node:child_process'); return cp; }\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});
test("RT-F2: Math['random'] (notation crochet) -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "export const r = () => Math['random']();\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});
test("RT-F2: eval(...) -> rejet R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "export const r = () => eval('1+1');\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R10"));
});
test("RT-F5: window. en COMMENTAIRE ne doit PAS declencher R10 (faux positif)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "// voir window.location dans la doc\nexport const y=1;\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(!res.errors.some((e) => e.rule === "R10"), JSON.stringify(res.errors));
});
test("RT-F5: document. dans une CHAINE ne doit PAS declencher R10", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "export const msg = \"ouvre document.pdf svp\";\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(!res.errors.some((e) => e.rule === "R10"));
});

// RT-F1 : path = dossier ne doit plus CRASHER, mais rendre un verdict propre.
test("RT-F1: path pointant un dossier -> verdict {ok:false} (pas de crash)", (t) => {
  const { root, kb, files } = makeRoot(t);
  const a = baseAsset(files); a.path = "knowledge_base/assets/characters"; // un dossier
  let res;
  assert.doesNotThrow(() => { res = validateCatalog(makeCatalog([a]), { root }); });
  assert.equal(res.ok, false);
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});

// RT-F7 : system non-godot avec path:null -> rejet (esquive purete/tests).
test("RT-F7: system non-godot path:null -> rejet R7", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files); s.path = null; s.sha256 = null;
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R7"));
});

// RT-F8 : octets non-raster dans un asset 2D ingere -> rejet R6.
test("RT-F8: asset 2D ingere dont les octets ne sont pas un raster -> rejet R6", (t) => {
  const { root, kb } = makeRoot(t);
  const fake3d = Buffer.from("glTF    binary model data here");
  writeFileSync(join(kb, "assets/characters/model.png"), fake3d);
  const a = {
    entry_type: "asset", asset_id: "asset-fake-3d", source: "x", license: "CC0-1.0",
    provenance_url: "https://example.org/x", style: "s", genre: ["g"], biome: null,
    format: "2D", size_kb: Math.max(1, Math.round(fake3d.length / 1024)),
    sha256: sha256(fake3d), runtime: "html", ingested: true,
    path: "knowledge_base/assets/characters/model.png", usage_examples: [], tier: "candidate",
  };
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R6"), JSON.stringify(res.errors));
});

// RT-F8b : marqueur GPL dans un system declare MIT -> rejet R4.
test("RT-F8b: marqueur 'GNU General Public License' dans un system MIT -> rejet R4", (t) => {
  const { root, kb, files } = makeRoot(t);
  const s = systemWith(kb, files, "// GNU General Public License v3\nexport const y=1;\n");
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R4"));
});

// RT-F6 : champ inconnu (schema ferme) -> rejet R1.
test("RT-F6: champ inconnu 'backdoor' -> rejet R1", (t) => {
  const { root, files } = makeRoot(t);
  const a = { ...baseAsset(files), backdoor: true };
  const res = validateCatalog(makeCatalog([a]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /inconnu/.test(e.msg)));
});

// ---------- R8 (Forge V2 §4-A, arbitrage Pierre) : BRICK_SPEC::usage_examples FACULTATIF ----------
// Miroir d'ASSET_SPEC::usage_examples mais optionnel (une brick preexistante sans ce champ reste
// valide). Trois cas exiges par l'arbitrage : (a) mal type -> FAIL, (b) schema toujours ferme pour
// tout AUTRE champ inconnu -> FAIL, (c) absent -> PASS.

// (a) brick avec usage_examples mal type (pas un tableau) -> FAIL.
test("R8-a: brick avec usage_examples: \"pas-un-tableau\" -> rejet R1 (mal type)", (t) => {
  const { root, files } = makeRoot(t);
  const s = { ...baseSystem(files), usage_examples: "pas-un-tableau" };
  const res = validateCatalog(makeCatalog([s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /mal type: usage_examples/.test(e.msg)));
});

// (b) le schema reste FERME pour tout AUTRE champ inconnu sur une brick (miroir de RT-F6, mais sur
// BRICK_SPEC precisement, pour prouver que rendre UN champ facultatif n'a pas ouvert le schema).
test("R8-b: champ inconnu quelconque sur une brick -> toujours rejet R1 (schema reste ferme)", (t) => {
  const { root, files } = makeRoot(t);
  const s = { ...baseSystem(files), totally_unknown_field: 42 };
  const res = validateCatalog(makeCatalog([s]), { root });
  assert.ok(res.errors.some((e) => e.rule === "R1" && /inconnu/.test(e.msg) && /totally_unknown_field/.test(e.msg)));
});

// (c) brick SANS usage_examples (cle absente) -> PASS (facultatif — le comportement historique,
// exerce par toute brick preexistante du catalogue reel, doit rester valide).
test("R8-c: brick sans usage_examples -> ok, zero erreur (facultatif)", (t) => {
  const { root, files } = makeRoot(t);
  const s = baseSystem(files);
  assert.ok(!("usage_examples" in s), "fixture de depart : la cle est bien absente");
  // basePattern(files) est inclus car baseSystem depend de "pat-damage-floor" (R9) — inchange
  // par rapport au cas nominal, seul le point teste ici est usage_examples absent.
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors, []);
});

// Positif complementaire : brick AVEC usage_examples valide (tableau de chaines) -> PASS. Preuve
// que le champ, une fois rempli (fill_usage_examples.mjs), valide reellement.
test("R8-d: brick avec usage_examples valide (tableau de chaines) -> ok, zero erreur", (t) => {
  const { root, files } = makeRoot(t);
  const s = { ...baseSystem(files), usage_examples: ["games/kb_tactics/game.mjs"] };
  const res = validateCatalog(makeCatalog([basePattern(files), s]), { root });
  assert.deepEqual(res.errors, []);
});

// ---------- learned_from (Task 7) ----------
test("learned_from absent -> brick valide (facultatif, retrocompatible)", (t) => {
  const { root, files } = makeRoot(t);
  const b = baseSystem(files);
  delete b.learned_from;
  const { errors } = validateCatalog(makeCatalog([basePattern(files), b]), { root });
  assert.deepEqual(errors.filter((e) => /learned_from/.test(e.msg)), []);
});

test("learned_from bien forme -> accepte", (t) => {
  const { root, files } = makeRoot(t);
  const b = baseSystem(files);
  b.learned_from = { game: "01_grid_nav_probe", reference: "Pac-Man (1980)" };
  const { errors } = validateCatalog(makeCatalog([basePattern(files), b]), { root });
  assert.deepEqual(errors.filter((e) => /learned_from/.test(e.msg)), []);
});

test("learned_from avec une cle inconnue -> rejet R1 (schema ferme)", (t) => {
  const { root, files } = makeRoot(t);
  const b = baseSystem(files);
  b.learned_from = { game: "x", reference: "y", extra: "z" };
  const { ok } = validateCatalog(makeCatalog([basePattern(files), b]), { root });
  assert.equal(ok, false);
});

test("learned_from avec un champ manquant -> rejet R1", (t) => {
  const { root, files } = makeRoot(t);
  const b = baseSystem(files);
  b.learned_from = { game: "x" };
  const { ok } = validateCatalog(makeCatalog([basePattern(files), b]), { root });
  assert.equal(ok, false);
});
