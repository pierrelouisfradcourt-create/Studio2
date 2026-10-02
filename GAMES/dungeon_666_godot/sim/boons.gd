class_name D6Boons
extends RefCounted
## Portage de src/sim/boons.mjs.
## Bénédictions infernales — les 7 péchés capitaux comme familles (équivalent des dieux de
## Hades). Une bénédiction est une DONNÉE : des modificateurs de stats et/ou des procs que
## combat.mjs interprète. Emplacements exclusifs (attack, dash, skill) : une nouvelle
## bénédiction du même emplacement remplace l'ancienne. Les passifs s'empilent.
##
## Rareté : commun ×1, rare ×1,4, épique ×1,8 sur les valeurs.
## Tables FAMILIES, RARITIES, BOONS, DUOS, PACTS : D6Data.tables().boons (jamais modifiées).
## PACTS : bénédictions à contrepartie, jamais tirées par une offre — un autel les accorde (run).

static func _t() -> Dictionary:
	return D6Data.tables().boons

static func boon_def(id):
	var t := _t()
	for b in t.BOONS:
		if b.id == id:
			return b
	for b in t.DUOS:
		if b.id == id:
			return b
	for b in t.PACTS:
		if b.id == id:
			return b
	return null

static func _rarity_def(rarity) -> Dictionary:
	var rarities: Array = _t().RARITIES
	for x in rarities:
		if x.id == rarity:
			return x
	return rarities[0]

static func boon_value(def: Dictionary, rarity) -> float:
	var r := _rarity_def(rarity)
	if D6Js.truthy(def.get("noScale")):
		return def.value
	return D6Js.jround(def.value * r.mult * 10.0) / 10.0

## String.replace de JavaScript avec un motif texte : seule la 1re occurrence est remplacée.
static func boon_text(def: Dictionary, rarity) -> String:
	var text: String = def.text
	var at := text.find("{v}")
	if at < 0:
		return text
	return text.substr(0, at) + D6Js.num_str(boon_value(def, rarity)) + text.substr(at + 3)

static func _find_boon(run: Dictionary, id):
	for b in run.boons:
		if b.id == id:
			return b
	return null

static func _owned_families(run: Dictionary) -> Array:
	var s: Array = []
	for b in run.boons:
		var d = boon_def(b.id)
		if d != null and D6Js.truthy(d.get("family")) and not s.has(d.family):
			s.append(d.family)
	return s

## Duos éligibles pour la famille offerte : non possédés, dont toutes les familles sont réunies
## (celle qu'on offre comprise) et dont au moins une AUTRE famille est déjà possédée.
static func _eligible_duos(owned: Array, fams: Array, family) -> Array:
	return _t().DUOS.filter(func(d):
		return not owned.has(d.id) and d.families.has(family) \
			and d.families.all(func(f): return fams.has(f) or f == family) \
			and d.families.any(func(f): return fams.has(f) and f != family))

## Les offres d'une famille : boons.offerSize bénédictions ; un duo éligible prend la dernière
## place avec la probabilité boons.duoChance. Jamais une bénédiction déjà possédée marquée `unique`.
static func roll_boon_offer(game: Dictionary, family) -> Array:
	var run: Dictionary = game.run
	var owned: Array = run.boons.map(func(b): return b.id)
	var fams := _owned_families(run)
	var candidates: Array = _t().BOONS.filter(func(b):
		return b.family == family and not (D6Js.truthy(b.get("unique")) and owned.has(b.id)))
	D6Rng.shuffle(game.rng.gen, candidates)
	# Réglages de la partie ; les défauts pour un appelant qui n'a qu'un run et un générateur.
	var tb: Dictionary = D6Js.nz(game.get("tuning"), D6Data.default_tuning()).boons
	var picks: Array = candidates.slice(0, int(tb.offerSize))
	var duos := _eligible_duos(owned, fams, family)
	if duos.size() > 0 and D6Rng.rand(game.rng.gen) < tb.duoChance:
		if picks.size() > 0: # tableau vide : JavaScript écrit la clé « -1 », que map ignore
			picks[picks.size() - 1] = duos[0]
	var rarities: Array = _t().RARITIES
	var out: Array = []
	for def in picks:
		var rarity = D6Rng.weighted_pick(game.rng.gen, rarities, func(r): return r.weight).id
		var existing = _find_boon(run, def.id)
		var level: float = D6Js.nz(existing.get("level"), 0.0) if existing != null else 0.0
		out.append({"id": def.id, "rarity": rarity, "level": level + 1.0})
	return out

## Ajoute (ou améliore) une bénédiction dans le run.
static func add_boon(run: Dictionary, offer: Dictionary) -> void:
	var def = boon_def(offer.id)
	if def == null:
		return
	var existing = _find_boon(run, offer.id)
	if existing != null:
		existing.level += 1.0
		existing.rarity = best_rarity(existing.rarity, offer.rarity)
		return
	if def.slot != "passive":
		run.boons = run.boons.filter(func(b):
			var d = boon_def(b.id)
			return d == null or d.slot != def.slot)
	run.boons.append({"id": offer.id, "rarity": offer.rarity, "level": 1.0})

## La meilleure de deux raretés (rang dans RARITIES) ; `a` à égalité.
static func best_rarity(a, b):
	return a if _rank_rarity(a) >= _rank_rarity(b) else b

static func _rank_rarity(id) -> int:
	var rarities: Array = _t().RARITIES
	for i in rarities.size():
		if rarities[i].id == id:
			return i
	return -1

static func random_family(game: Dictionary) -> String:
	var keys: Array = _t().FAMILIES.keys()
	return keys[int(floorf(D6Rng.rand(game.rng.gen) * keys.size()))]
