// Tests de l'ingestion 3D (kb-validate v4, 2026-08-06 — Asset Library V1).
//
// Avant v4, R6 interdisait STRUCTURELLEMENT d'ingerer un asset 3D
// (« godot/3D = manifest-only »), ce qui rendait toute bibliotheque 3D impossible.
// v4 leve l'interdiction mais la remplace par une CONTREPARTIE : le verdict de
// l'Asset Geometry Oracle. Ces tests verifient que la contrepartie tient — un .glb
// present ne doit JAMAIS suffire.
//
// Fichier separe de kb-validate.test.mjs (non modifie).
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { validateCatalog } from "./kb-validate.mjs";

const ORIGINAL = "ORIGINAL — aucune inspiration externe citee";

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

// Racine jetable contenant un VRAI fichier aux octets GLB (magic "glTF").
function makeRoot(t) {
  const root = mkdtempSync(join(tmpdir(), "kb3d-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const kb = join(root, "knowledge_base");
  mkdirSync(join(kb, "assets/props3d"), { recursive: true });

  const glb = Buffer.concat([
    Buffer.from("glTF"),                       // magic, spec glTF 2.0 §4.4.1
    Buffer.from([2, 0, 0, 0]),                 // version 2
    Buffer.from([0, 0, 0, 0]),                 // longueur (non verifiee ici)
    Buffer.from("charge-factice".repeat(80)),
  ]);
  writeFileSync(join(kb, "assets/props3d/crate.glb"), glb);
  writeFileSync(join(kb, "assets/props3d/crate.glb.geometry.json"), '{"meshes":[]}');
  // un fichier qui n'est PAS un GLB, mais porte l'extension
  writeFileSync(join(kb, "assets/props3d/menteur.glb"), Buffer.from("ceci n'est pas un glb"));

  return {
    root,
    glb: {
      path: "knowledge_base/assets/props3d/crate.glb",
      sha: sha256(glb),
      kb: Math.max(1, Math.round(glb.length / 1024)),
      manifest: "knowledge_base/assets/props3d/crate.glb.geometry.json",
    },
  };
}

function base3D(f, over = {}) {
  return {
    entry_type: "asset", asset_id: "asset-gen-crate-01",
    source: ORIGINAL + " — scripts/forge/asset_producer/build_asset.py",
    license: "CC0-1.0", provenance_url: null, style: "lowpoly",
    genre: ["generic"], biome: null, format: "3D",
    size_kb: f.kb, sha256: f.sha, runtime: "godot", ingested: true,
    path: f.path, usage_examples: [], tier: "candidate",
    category: "prop", geometry_status: "OK",
    consumer: ["obstacle destructible"], variants: [],
    ...over,
  };
}

const cat = (entries) => ({ catalog_version: 1, entries });

// ---------------------------------------------------------------- contrepartie

test("3D ingere sans geometry_status -> rejet (un .glb present n'est pas une preuve)", (t) => {
  const { root, glb } = makeRoot(t);
  const e = base3D(glb);
  delete e.geometry_status;
  const { ok, errors } = validateCatalog(cat([e]), { root });
  assert.equal(ok, false);
  assert.match(JSON.stringify(errors), /geometry_status/);
});

test("3D ingere avec geometry_status BLOCKED -> rejet", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, { geometry_status: "BLOCKED" })]), { root });
  assert.equal(ok, false);
});

test("3D ingere avec geometry_status FAIL -> rejet", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, { geometry_status: "FAIL" })]), { root });
  assert.equal(ok, false);
});

test("3D ingere sans consumer -> rejet (pas d'asset sans consommateur)", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok, errors } = validateCatalog(cat([base3D(glb, { consumer: [] })]), { root });
  assert.equal(ok, false);
  assert.match(JSON.stringify(errors), /consumer/);
});

test("3D avec variantes mais sans geometry_manifest -> rejet", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok, errors } = validateCatalog(
    cat([base3D(glb, { variants: ["lid_open"] })]), { root });
  assert.equal(ok, false);
  assert.match(JSON.stringify(errors), /geometry_manifest/);
});

test("3D avec variantes ET geometry_manifest reel -> accepte", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, {
    variants: ["lid_open"], geometry_manifest: glb.manifest,
  })]), { root });
  assert.equal(ok, true);
});

test("prop 3D propre sans variantes ni manifeste -> accepte", (t) => {
  const { root, glb } = makeRoot(t);
  // Exiger un manifeste ici rendrait BLOCKED a vie tout asset genere sain :
  // la regle KB doit rester coherente avec `manifest_present` cote oracle.
  const { ok, errors } = validateCatalog(cat([base3D(glb)]), { root });
  assert.equal(ok, true, JSON.stringify(errors));
});

test("geometry_manifest pointant hors knowledge_base/assets -> rejet (garde de chemin)", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, {
    variants: ["x"], geometry_manifest: "../../etc/passwd",
  })]), { root });
  assert.equal(ok, false);
});

// ---------------------------------------------------------------- octets

test("fichier non-GLB declare 3D ingere -> rejet sur les octets", (t) => {
  const { root, glb } = makeRoot(t);
  const faux = Buffer.from("ceci n'est pas un glb");
  const { ok, errors } = validateCatalog(cat([base3D(glb, {
    path: "knowledge_base/assets/props3d/menteur.glb",
    sha256: sha256(faux), size_kb: 1,
  })]), { root });
  assert.equal(ok, false);
  assert.match(JSON.stringify(errors), /GLB/);
});

// ---------------------------------------------------------------- provenance

test("asset ORIGINAL avec provenance_url null -> accepte", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok, errors } = validateCatalog(cat([base3D(glb)]), { root });
  assert.equal(ok, true, JSON.stringify(errors));
});

test("asset ORIGINAL avec une provenance_url quand meme -> rejet R3", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, {
    provenance_url: "https://example.org/x",
  })]), { root });
  assert.equal(ok, false);
});

test("asset NON original sans provenance_url -> rejet R3", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, {
    source: "KayKit — Adventurers", provenance_url: null,
  })]), { root });
  assert.equal(ok, false);
});

// ---------------------------------------------------------------- taxonomie

test("category hors enumeration fermee -> rejet", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, { category: "truc-cool" })]), { root });
  assert.equal(ok, false);
});

test("geometry_status hors enumeration -> rejet", (t) => {
  const { root, glb } = makeRoot(t);
  const { ok } = validateCatalog(cat([base3D(glb, { geometry_status: "PROBABLY_FINE" })]), { root });
  assert.equal(ok, false);
});

// ---------------------------------------------------------------- retrocompat

test("3D manifest-only (non ingere) reste valide sans aucun champ v4", (t) => {
  const { root } = makeRoot(t);
  const { ok, errors } = validateCatalog(cat([{
    entry_type: "asset", asset_id: "asset-quaternius-pack",
    source: "Quaternius — Ultimate Modular Men Pack", license: "CC0-1.0",
    provenance_url: "https://quaternius.com/packs/ultimatemodularmen.html",
    style: "lowpoly", genre: ["rpg"], biome: null, format: "3D",
    size_kb: null, sha256: null, runtime: "godot", ingested: false,
    path: null, usage_examples: [], tier: "candidate",
  }]), { root });
  assert.equal(ok, true, JSON.stringify(errors));
});
