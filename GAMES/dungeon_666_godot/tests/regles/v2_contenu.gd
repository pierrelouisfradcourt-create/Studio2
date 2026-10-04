extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_contenu.test.mjs (1/4 : outils, inventaire et textes,
## dispositions de salle, partie réelle). Suite : v2_contenu_benedictions.gd (bénédictions et
## duos), v2_contenu_pouvoirs.gd (pouvoirs légendaires), v2_contenu_autels.gd (autels).
##
## CONTENU AJOUTÉ LE 2026-10-01 — 14 bénédictions (2 par famille), 4 duos, 6 pouvoirs légendaires,
## 4 événements d'autel, 4 dispositions de salle. Un test par élément : l'effet se produit dans
## une vraie partie (create_game + step_game, le seul chemin de dégâts), il vaut ce que son texte
## annonce (les nombres sont lus dans les données, jamais recopiés), il ne casse pas le
## déterminisme. Plus : tout texte {v} se résout, tout libellé d'autel est chiffré.
##
## Les outils du fichier web (arena, give, wear, dummy…) sont ici des fonctions statiques sans
## tiret bas : les trois autres fichiers du lot les appellent par preload.

const Bots = preload("res://outils/bots/bots.gd")

# ---------------------------------------------------------------- le contenu sous test

const NEW_BOONS := {
	"colere": ["represailles", "coup_de_sang"],
	"paresse": ["baillement", "mur_du_sommeil"],
	"avarice": ["prime_de_risque", "tresor_de_guerre"],
	"gourmandise": ["bouchee_double", "ripaille"],
	"luxure": ["baiser_vole", "ivresse"],
	"envie": ["eclair_de_depit", "mauvais_oeil"],
	"orgueil": ["invaincu", "mepris"],
}
const NEW_DUOS := ["passion_brulante", "faire_les_poches", "trop_plein", "foudre_du_dedain"]
const NEW_POWERS := ["eperons_alastor", "marteau_belial", "dard_lilith", "main_de_gloire", "fracas_moloch", "linceul_abaddon"]
const NEW_EVENTS := ["pacte_ames", "forge", "miroir", "clepsydre"]
const NEW_LAYOUTS := ["colonnade", "chicane", "goulet", "ilots"]
const EPS := 1e-9
const ROOM_SEARCH_SEEDS := 120 # valeur web : 120 (graines essayées par Cercle pour trouver une disposition)

# ---------------------------------------------------------------- outils

static func boons_t() -> Dictionary:
	return D6Data.tables().boons

static func powers_t() -> Array:
	return D6Data.tables().loot.LEGENDARY_POWERS

static func events_t() -> Array:
	return D6Data.tables().run.EVENTS

static func by_id(table: Array, id):
	for x in table:
		if x.id == id:
			return x
	return null

static func no_braces(text: String) -> bool:
	return not ("{" in text or "}" in text)

## Partie de test : salle vidée (aucune vague), héros au centre, jamais de critique de base.
static func arena(h, boons: Array = [], opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": 11.0}
	o.merge(opts, true)
	var g: Dictionary = D6Game.create_game(o)
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.room.waveIndex = 0.0
	g.room.obstacles = []
	g.room.cleared = true
	g.room.interact = null
	g.room.doors = []
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h / 2.0
	g.tuning.combat.critChance = 0.0 # les montants attendus sont exacts
	for b in boons:
		give(h, g, b)
	g.events.clear()
	return g

static func give(h, g: Dictionary, id: String, rarity: String = "commun") -> void:
	h.ok(D6Boons.boon_def(id), "bénédiction inconnue : %s" % id)
	D6Boons.add_boon(g.run, {"id": id, "rarity": rarity})
	D6Stats.recompute_stats(g)

## Équipe un talisman légendaire portant le pouvoir `id` (le chemin réel : recompute_stats).
static func wear(h, g: Dictionary, id: String) -> void:
	h.ok(by_id(powers_t(), id) != null, "pouvoir inconnu : %s" % id)
	g.run.items.talisman = {"id": 9001.0, "slot": "talisman", "rarity": "legendaire", "name": "Relique d'essai", "level": 1.0, "affixes": [], "power": id, "base": {}, "score": 0.0}
	D6Stats.recompute_stats(g)

## Avance de n pas SANS vider les événements (les tests lisent game.events après coup).
static func steps(h, g: Dictionary, n: int, over: Dictionary = {}) -> void:
	for i in n:
		D6Game.step_game(g, h.entree(over))

static func step1(h, g: Dictionary, over: Dictionary = {}) -> void:
	D6Game.step_game(g, h.entree(over))

## Lance l'ultime comme un joueur (combat V3 : attaque tenue jusqu'à ce qu'il parte), SANS vider
## les événements.
static func ultime(h, g: Dictionary) -> void:
	h.ultime(g, {}, false)

## Ennemi d'essai : ne riposte pas ; `hp` (facultatif) le rend increvable ou fragile.
static func dummy(g: Dictionary, dx: float, dy: float, kind: String = "brute", hp: float = 0.0) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 99.0
	if hp != 0.0:
		e.maxHp = hp
		e.hp = hp
	return e

static func V(id: String, rarity: String = "commun") -> float:
	return D6Boons.boon_value(D6Boons.boon_def(id), rarity)

static func proc_of(g: Dictionary, id: String):
	for pr in g.player.procs:
		if pr.get("boon") == id:
			return pr
	return null

static func power_proc(id: String) -> Dictionary:
	return by_id(powers_t(), id).procs[0]

static func events(g: Dictionary, type: String) -> Array:
	return g.events.filter(func(ev): return ev.type == type)

## Esquive parfaite réelle : un dash, puis un coup reçu pendant ses i-frames.
static func perfect_dodge(h, g: Dictionary, id: float = 4242.0) -> void:
	step1(h, g, {"moveX": -1.0, "dashPressed": true})
	h.egal(g.player.state, "dash")
	var landed: bool = D6Combat.damage_player(g, 10.0, {"kind": "test", "id": id, "x": g.player.x, "y": g.player.y})
	h.egal(landed, false)
	h.egal(events(g, "dodge").size() >= 1, true, "esquive parfaite comptée")

## Dégâts d'un coup d'arme de 100 sur `e` (le chemin unique : damage_enemy).
static func hit100(g: Dictionary, e: Dictionary, kind: String = "melee") -> float:
	return D6Combat.damage_enemy(g, e, {"kind": kind, "amount": 100.0, "canCrit": false})

## Projette `e` contre le mur de gauche (vrai knockback, vraie collision) ; rend true s'il a percuté.
static func slam(h, g: Dictionary, e: Dictionary) -> bool:
	e.x = g.room.pad + e.r + 30.0
	e.y = g.room.h / 2.0
	g.player.x = e.x + 300.0
	g.player.y = e.y
	e.kvx = -900.0
	var before: float = g.telemetry.wallSlams
	var i := 0
	while i < 12 and g.telemetry.wallSlams == before:
		step1(h, g)
		i += 1
	return g.telemetry.wallSlams > before

## Nettoie la salle de combat en cours par le vrai flux (vagues, update_waves, on_room_clear).
static func clear_room(h, g: Dictionary) -> void:
	var i := 0
	while i < 4000 and not g.room.cleared:
		var k := 0
		while k < g.enemies.size():
			var e: Dictionary = g.enemies[k]
			if not e.dead and e.spawnT <= 0.0:
				D6Combat.kill_enemy(g, e, {"kind": "melee"})
			k += 1
		step1(h, g)
		i += 1
	h.ok(g.room.cleared, "salle nettoyée")

## Tient l'attaque contre un ennemi increvable ; rend les coups portés {finishers, hits}.
static func combo_on(h, g: Dictionary, seconds: float, e: Dictionary) -> Dictionary:
	var combo: Array = g.tuning.combo
	var fin: float = combo[combo.size() - 1].damage
	var from: int = g.events.size()
	steps(h, g, h.ticks(seconds), {"attack": true})
	steps(h, g, h.ticks(0.3)) # les explosions à retardement partent
	var hits: Array = g.events.slice(from).filter(func(ev): return ev.type == "hit" and ev.get("id") == e.id)
	return {"finishers": hits.filter(func(x): return x.get("kind") == "melee" and x.get("amount") == fin).size(), "hits": hits}

## Frappe de dash réelle sur l'ennemi placé à droite du héros.
static func dash_strike(h, g: Dictionary) -> void:
	var t: Dictionary = g.tuning.dash
	step1(h, g, {"moveX": 1.0, "dashPressed": true})
	steps(h, g, h.ticks(t.duration * (1.0 - t.strikeCancelFrom)) + 1, {"moveX": 1.0})
	step1(h, g, {"attackPressed": true})
	var atk = g.player.get("attack")
	h.egal(atk.get("strike") if atk is Dictionary else null, true, "frappe de dash partie")
	steps(h, g, h.ticks(0.4))

## Ouvre l'autel `id` par le vrai flux (porte « Autel », objet touché) ; rend le panneau.
static func altar(h, g: Dictionary, id: String) -> Dictionary:
	D6Run.enter_floor(g, g.run.floor + 1.0, {"reward": "event"})
	h.egal(g.room.kind, "event")
	g.room.interact.event = id
	D6Run.open_interact(g)
	h.egal(g.mode, "choice")
	var ch = g.get("choice")
	h.egal(ch.get("kind") if ch is Dictionary else null, "event")
	return ch if ch is Dictionary else {"options": []}

static func _deterministic_play(h, boons: Array, power, seconds: float, floor_num: float) -> Array:
	var g: Dictionary = D6Game.create_game({"seed": 77.0, "startFloor": floor_num})
	for b in boons:
		D6Boons.add_boon(g.run, {"id": b, "rarity": "rare"})
	if power != null:
		wear(h, g, power)
	D6Stats.recompute_stats(g)
	var mem := {}
	var marks: Array = []
	for i in h.ticks(seconds):
		if g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
		elif g.mode == "play":
			D6Game.step_game(g, Bots.play("skilled", g, mem))
		g.events.clear()
		if i % 30 == 0:
			marks.append([D6Game.state_hash(g), g.rng.combat.s, g.rng.gen.s, g.player.superCharge, g.run.gold])
	return marks

## Même graine, mêmes entrées (bot), même build : même état, image par image.
## opts : {power = null, seconds = 6, floor = 5}.
static func assert_deterministic(h, boons: Array, opts: Dictionary = {}) -> void:
	var power = opts.get("power")
	var seconds: float = D6Js.nz(opts.get("seconds"), 6.0)
	var floor_num: float = D6Js.nz(opts.get("floor"), 5.0)
	var names: Array = boons.duplicate()
	if power != null:
		names.append(power)
	h.egal(_deterministic_play(h, boons, power, seconds, floor_num), _deterministic_play(h, boons, power, seconds, floor_num), "déterminisme : %s" % ", ".join(names))

# ---------------------------------------------------------------- inventaire et textes

static func _all_defs() -> Array:
	return boons_t().BOONS + boons_t().DUOS + boons_t().PACTS

static func _t_inventaire(h) -> void:
	var t := boons_t()
	for fam in NEW_BOONS:
		h.ok(t.FAMILIES.get(fam))
		for id in NEW_BOONS[fam]:
			var b = by_id(t.BOONS, id)
			h.egal(b.get("family") if b != null else null, fam, "%s : famille %s" % [id, fam])
		h.egal(t.BOONS.filter(func(b): return b.get("family") == fam).size(), 5, "%s : 3 d'origine + 2" % fam)
	for id in NEW_DUOS:
		var d = by_id(t.DUOS, id)
		h.egal(d.families.size() if d != null else null, 2, "duo %s" % id)
	var pairs := {}
	for d in t.DUOS:
		var fams: Array = d.families.duplicate()
		fams.sort()
		pairs["+".join(fams)] = true
	h.egal(pairs.size(), t.DUOS.size(), "chaque duo unit une paire de familles différente")
	for id in NEW_POWERS:
		h.ok(by_id(powers_t(), id) != null, "pouvoir %s" % id)
	for id in NEW_EVENTS:
		h.ok(by_id(events_t(), id) != null, "autel %s" % id)
	for id in NEW_LAYOUTS:
		h.ok(D6Data.tables().room.LAYOUT_IDS.has(id), "disposition %s" % id)
	var ids := {}
	for b in _all_defs():
		ids[b.id] = true
	h.egal(ids.size(), _all_defs().size(), "identifiants uniques")

# Ce que la partie applique : la stat ou la valeur du proc, au même nombre que le texte.
static func _text_case(h, def: Dictionary, rarity: String) -> void:
	var shown: float = D6Boons.boon_value(def, rarity)
	var text: String = D6Boons.boon_text(def, rarity)
	var tag := "%s (%s)" % [def.id, rarity]
	h.ok(no_braces(text), "%s : accolade restante dans « %s »" % [tag, text])
	if "{v}" in def.text:
		h.ok(D6Js.num_str(shown) in text, "%s : %s absent de « %s »" % [tag, shown, text])
	var g := arena(h)
	D6Boons.add_boon(g.run, {"id": def.id, "rarity": rarity})
	var base: Dictionary = D6Js.clone(g.player.stats)
	D6Stats.recompute_stats(g)
	var expect: float = shown / 100.0 if D6Js.truthy(def.get("pct")) else shown
	if def.get("proc") is Dictionary:
		var pr = proc_of(g, def.id)
		h.ok(pr != null, "%s : proc présent" % def.id)
		if pr == null:
			return
		var applied: float = pr.chance if def.proc.has("valueFixed") else pr.value
		h.ok(absf(applied - expect) < EPS, "%s : la partie applique %s, le texte dit %s" % [tag, applied, shown])
	elif D6Js.truthy(def.get("stat")):
		var delta: float = g.player.stats[def.stat] - base[def.stat]
		h.ok(absf(absf(delta) - expect) < EPS, "%s : stat %s %s, le texte dit %s" % [tag, def.stat, delta, shown])

static func _t_textes(h) -> void:
	for def in _all_defs():
		var text: String = def.text
		var wanted := 0 if D6Js.truthy(def.get("noScale")) and not ("{v}" in text) else 1
		h.egal(text.count("{v}"), wanted, "%s : un seul {v}" % def.id)
		for r in boons_t().RARITIES:
			_text_case(h, def, r.id)

## String(n).replace('.', ',').
static func _fr(n: float) -> String:
	var s := D6Js.num_str(n)
	var at := s.find(".")
	return s if at < 0 else s.substr(0, at) + "," + s.substr(at + 1)

static func _t_textes_pouvoirs(h) -> void:
	for id in NEW_POWERS:
		var pw: Dictionary = by_id(powers_t(), id)
		var text: String = pw.text
		h.ok(text.length() > 0 and no_braces(text), "%s : texte" % id)
		for pr in pw.procs:
			h.ok(_fr(pr.value) in text, "%s : %s absent de « %s »" % [id, pr.value, text])
			for k in ["radius", "bounces"]:
				if pr.has(k):
					h.ok(_fr(pr[k]) in text, "%s : %s %s absent du texte" % [id, k, pr[k]])
		# Affiché par ses données sur la carte d'objet (describe_item), nommé par generate_item.
		var g := arena(h)
		wear(h, g, id)
		h.egal(D6Run.describe_item(g.run.items.talisman).power, text)
		var first: Dictionary = pw.procs[0]
		h.ok(g.player.procs.any(func(pr): return pr.get("effect") == first.get("effect") and pr.get("on") == first.get("on")), "%s : proc actif une fois porté" % id)
	# Les nouveaux pouvoirs tombent vraiment (tirage de generate_item).
	var g2 := arena(h)
	var seen := {}
	for i in 300:
		seen[D6Loot.generate_item(g2, {"rarity": "legendaire"}).get("power")] = true
	for id in NEW_POWERS:
		h.ok(seen.has(id), "%s : jamais tiré en 300 objets légendaires" % id)

static func _duo_offered(h, id: String) -> bool:
	var duo: Dictionary = D6Boons.boon_def(id)
	var g := arena(h)
	for b in boons_t().BOONS:
		if b.family == duo.families[0]:
			give(h, g, b.id)
			break
	for i in 200:
		if D6Boons.roll_boon_offer(g, duo.families[1]).any(func(o): return o.id == id):
			return true
	return false

static func _t_offres(h) -> void:
	var g := arena(h)
	var offered := {}
	for i in 400:
		for fam in boons_t().FAMILIES.keys():
			for o in D6Boons.roll_boon_offer(g, fam):
				offered[o.id] = true
	for fam in NEW_BOONS:
		for id in NEW_BOONS[fam]:
			h.ok(offered.has(id), "%s : jamais offerte" % id)
	for p in boons_t().PACTS:
		h.ok(not offered.has(p.id), "%s : un pacte ne s'offre pas" % p.id)
	for id in NEW_DUOS:
		h.ok(_duo_offered(h, id), "%s : jamais offert avec %s" % [id, " + ".join(D6Boons.boon_def(id).families)])

# ---------------------------------------------------------------- dispositions de salle

static func _layout_weight(circle: Dictionary, id: String) -> float:
	return float(D6Js.nz(circle.layouts.get(id), 0.0))

## Première partie (graine, étage) dont la salle de départ tire la disposition `id`.
static func _find_room(tuning: Dictionary, id: String):
	for ci in tuning.circles.size():
		if not (_layout_weight(tuning.circles[ci], id) > 0.0):
			continue
		var floor_num: float = minf(tuning.floors.total - 20.0, ci * tuning.floors.circleLength + 3.0)
		for seed in range(1, ROOM_SEARCH_SEEDS + 1):
			var g: Dictionary = D6Game.create_game({"seed": float(seed), "startFloor": floor_num})
			if g.room.layout == id:
				return g
	return null

# Une vraie partie s'y joue (bot), sans blocage ni perte de déterminisme.
static func _layout_run(h, g: Dictionary) -> Array:
	var game: Dictionary = D6Game.create_game({"seed": g.seed, "startFloor": g.run.floor, "godMode": true})
	var mem := {}
	var kills := 0.0
	# 45 s : à un étage profond avec l'équipement de départ, le premier ennemi peut mettre plus de 20 s à tomber.
	var i := 0
	while i < h.ticks(45.0) and game.run.floor == g.run.floor:
		if game.mode == "choice":
			Bots.resolve_choice(game, "skilled")
		else:
			D6Game.step_game(game, Bots.play("skilled", game, mem))
		game.events.clear()
		kills = game.telemetry.kills
		i += 1
	return [D6Game.state_hash(game), kills, game.room.layout, game.run.floor]

static func _layout_geometry(h, id: String, g: Dictionary) -> void:
	var room: Dictionary = g.room
	h.egal(room.obstacles.size(), D6Data.tables().room.LAYOUTS[id].size())
	for o in room.obstacles:
		h.ok(o.x0 >= room.pad and o.x1 <= room.w - room.pad and o.y0 >= room.pad and o.y1 <= room.h - room.pad, "%s : obstacle dans les murs" % id)
		h.ok(o.y0 > room.pad + 40.0 + 2.0 * g.player.r + 60.0, "%s : le haut (portes) reste libre" % id)
	var start: Dictionary = D6Room.player_start(room)
	h.ok(not D6Physics.point_blocked(room, start.x, start.y, 60.0), "%s : entrée dégagée (60 u)" % id)
	# La récompense tombe à sa place naturelle (centre), sans avoir à être déplacée par un obstacle.
	h.egal(D6Room.reward_spot(room), {"x": room.w / 2.0, "y": room.h * 0.45}, "%s : centre libre pour la récompense" % id)
	for fx in [0.32, 0.68]:
		h.ok(not D6Physics.point_blocked(room, room.w * fx, room.pad + 40.0, g.player.r + 20.0), "%s : porte dégagée" % id)

static func _t_disposition(h, id: String) -> void:
	var tuning: Dictionary = D6Data.create_tuning()
	h.ok(not D6Data.tables().room.COMBAT_LAYOUTS.has(id))
	h.ok(not tuning.circles[0].layouts.has(id), "les Limbes gardent les six dispositions d'origine")
	var themed: Array = tuning.circles.filter(func(c): return _layout_weight(c, id) > 0.0)
	h.ok(themed.size() >= 2, "%s : au moins deux Cercles" % id)
	var g = _find_room(tuning, id)
	h.ok(g != null, "%s : jamais tirée" % id)
	if g == null:
		return
	_layout_geometry(h, id, g)
	h.ok(D6Floors.floor_info(tuning, g.run.floor).circle >= 2.0)
	var a := _layout_run(h, g)
	h.egal(a, _layout_run(h, g), "%s : déterminisme" % id)
	h.ok(a[1] > 0.0, "%s : le bot y combat (%s ennemis tués)" % [id, a[1]])

# ---------------------------------------------------------------- le tout, en partie réelle

static func _real_ids() -> Array:
	var ids: Array = []
	for fam in NEW_BOONS:
		ids.append_array(NEW_BOONS[fam])
	return ids + NEW_DUOS + ["jalousie", "festin"]

static func _real_play(h) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 91.0, "startFloor": 7.0})
	for id in _real_ids():
		D6Boons.add_boon(g.run, {"id": id, "rarity": "commun"})
	wear(h, g, "linceul_abaddon")
	var mem := {}
	var seen := {}
	var marks: Array = []
	for i in h.ticks(40.0):
		if g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
		elif g.mode == "play":
			D6Game.step_game(g, Bots.play("skilled", g, mem))
		else:
			break
		for ev in g.events:
			var key: String = "hazard:%s" % ev.get("kind") if ev.type == "hazard" else ev.type
			seen[key] = seen.get(key, 0) + 1
		g.events.clear()
		if i % 60 == 0:
			marks.append([D6Game.state_hash(g), g.rng.combat.s])
	return {"marks": marks, "seen": seen, "tel": g.telemetry}

static func _t_partie_reelle(h) -> void:
	var a := _real_play(h)
	var b := _real_play(h)
	h.egal(a.marks, b.marks)
	var seen: Dictionary = a.seen
	h.ok(a.tel.kills > 5.0, "le bot se bat (%s ennemis tués)" % a.tel.kills)
	h.ok(seen.get("chain", 0) > 0, "des éclairs sont partis (dash, mort d'un ennemi)")
	h.ok(seen.get("hazard:sinBlast", 0) > 0, "des explosions sont parties (dernier coup du combo, ennemis tués)")
	h.ok(seen.get("gold", 0) > 0, "une prime est tombée (salle nettoyée sans être touché)")
	h.ok(seen.get("super", 0) > 0 and seen.get("dashNova", 0) > 0, "le Super lancé a embrasé les alentours")

# ---------------------------------------------------------------- les tests

static func tests(h) -> void:
	h.test("contenu : 2 bénédictions nouvelles par famille, 4 duos, 6 pouvoirs, 4 autels, 4 dispositions — tous présents dans les tables", func(): _t_inventaire(h))
	h.test("textes : chaque {v} se résout, à toute rareté, en le nombre que la partie applique", func(): _t_textes(h))
	h.test("textes : les pouvoirs légendaires nouveaux annoncent les nombres de leurs données", func(): _t_textes_pouvoirs(h))
	h.test("offres : les nouvelles bénédictions sont proposées, les duos nouveaux aussi une fois les deux familles réunies ; un pacte jamais", func(): _t_offres(h))
	for id in NEW_LAYOUTS:
		h.test("disposition %s : pondérée dans les thèmes (jamais dans les Limbes), tirée en descente, entrée / portes / récompense dégagées" % id, func(): _t_disposition(h, id))
	h.test("partie réelle : un build fait des 14 bénédictions nouvelles et des 4 duos se joue 40 s — les effets se déclenchent, la partie reste déterministe", func(): _t_partie_reelle(h))
