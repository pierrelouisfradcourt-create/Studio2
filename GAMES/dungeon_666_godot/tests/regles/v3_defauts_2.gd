extends RefCounted
## DÉFAUTS DE RÈGLES CORRIGÉS LE 2026-10-02, second lot (constats : DEFAUTS.md, « Vu en passant »).
## Un test par défaut : rouge sur le code d'avant, vert après.
## Outils : v2_contenu.gd (autels).

const C = preload("res://tests/regles/v2_contenu.gd")

const WALL_GAP := 150.0 # u entre le héros et le mur est : la ruée a la place de finir au mur
const RUN_UP := 200.0 # u entre le chargeur et le héros, sur la même ligne
const CHARGE_TIMEOUT := 8.0 # s : télégraphe + traversée de la salle
const REATTACK_TIMEOUT := 6.0 # s : étourdissement au mur + recharge
## [autel, indice de l'option payée en PV]
const BLOOD_PRICED := [["pacte_ames", 1], ["clepsydre", 1], ["coffre_maudit", 0]]

static func _choose(g: Dictionary, index: float) -> bool:
	return D6Game.apply_command(g, {"type": "choose", "index": index})

# ---------------------------------------------------------------- 4. amélioration inconnue

static func _t_amelioration_inconnue(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.create_profile(t)
	p.souls = 1e6
	h.egal(D6Profile.buy_upgrade(p, t, "inconnue"), {"ok": false, "reason": "inconnu"})
	h.egal(p.souls, 1e6, "rien n'est débité")
	h.egal(p.upgrades.has("inconnue"), false, "rien n'est inscrit au profil")

# ---------------------------------------------------------------- 10. à 1 PV, rien ne se paie en PV

static func _t_un_pv(h) -> void:
	for cas in BLOOD_PRICED:
		var g: Dictionary = D6Game.create_game({"seed": 43.0, "startFloor": 5.0})
		g.player.hp = 1.0
		g.player.superCharge = 0.0
		var souls: float = g.meta.souls
		var ch: Dictionary = C.altar(h, g, cas[0])
		h.egal(ch.options[cas[1]].get("disabled"), true, "%s : à 1 PV, l'option payée en PV est grisée" % cas[0])
		h.egal(_choose(g, float(cas[1])), false, "%s : et refusée" % cas[0])
		h.egal([g.player.hp, g.meta.souls, g.player.superCharge], [1.0, souls, 0.0], "%s : rien n'est donné" % cas[0])
		# Avec 2 PV, elle coûte vraiment quelque chose : elle reste permise (jamais mortelle).
		var g2: Dictionary = D6Game.create_game({"seed": 43.0, "startFloor": 5.0})
		g2.player.hp = 2.0
		g2.player.superCharge = 0.0
		h.egal(C.altar(h, g2, cas[0]).options[cas[1]].get("disabled"), false, "%s : à 2 PV, permise" % cas[0])
		h.egal(_choose(g2, float(cas[1])), true)
		h.egal(g2.player.hp, 1.0)

# ---------------------------------------------------------------- 11. la ruée traverse le héros

## Le héros (invulnérable, immobile) est sur la ligne, entre le chargeur et le mur est.
static func _charge_game(h) -> Dictionary:
	var g: Dictionary = h.bac_a_sable({"seed": 9.0, "godMode": true})
	g.player.x = g.room.w - g.room.pad - WALL_GAP
	return g

## Avance jusqu'à l'événement « chargerWall » de `e` ; rend l'image, ou -1.
static func _until_wall(h, g: Dictionary, e: Dictionary) -> int:
	for i in h.ticks(CHARGE_TIMEOUT):
		D6Game.step_game(g, h.entree())
		var hit := false
		for ev in g.events:
			if ev.type == "chargerWall" and ev.get("id") == e.id:
				hit = true
		g.events.clear()
		if hit:
			return i
	return -1

static func _t_ruee_belier(h) -> void:
	var g := _charge_game(h)
	var e: Dictionary = D6Enemies.create_enemy(g, "charger", g.player.x - RUN_UP, g.player.y, {"spawnT": 0.0})
	e.cooldown = 0.0
	e.maxHp = 1e6
	e.hp = 1e6
	h.ok(_until_wall(h, g, e) >= 0, "le Bélier lancé sur le héros immobile finit sa ruée au mur (il est à x = %s, le héros à %s)" % [str(e.x), str(g.player.x)])
	h.egal(e.hitPlayer, true, "et il a touché le héros au passage")
	h.ok(e.x > g.player.x, "il est passé de l'autre côté")

static func _t_ruee_charon(h) -> void:
	var g := _charge_game(h)
	var e: Dictionary = D6Enemies.create_enemy(g, "gardien", g.player.x - RUN_UP, g.player.y, {"boss": true, "spawnT": 0.0})
	D6BossCommon.set_state(e, "charge")
	e.pattern = "charge"
	h.ok(_until_wall(h, g, e) >= 0, "Charon lancé sur le héros immobile finit sa ruée au mur (il est à x = %s, le héros à %s)" % [str(e.x), str(g.player.x)])
	h.egal(e.state, "stunned")
	h.egal(D6Js.truthy(e.get("hitPlayer")), true, "et il a touché le héros au passage")

# ---------------------------------------------------------------- 12. percuter un mur ne fait pas ré-attaquer plus tôt

static func _t_mur_belier(h) -> void:
	var g := _charge_game(h)
	var def: Dictionary = g.tuning.enemies.charger
	var e: Dictionary = D6Enemies.create_enemy(g, "charger", g.player.x - RUN_UP, g.player.y, {"spawnT": 0.0})
	e.cooldown = 0.0
	e.maxHp = 1e6
	e.hp = 1e6
	h.ok(_until_wall(h, g, e) >= 0, "le Bélier percute le mur")
	var wait := -1
	for i in h.ticks(REATTACK_TIMEOUT):
		D6Game.step_game(g, h.entree())
		g.events.clear()
		if e.state == "windup":
			wait = i
			break
	h.ok(wait >= 0, "il ré-attaque")
	var floor_ticks: int = h.ticks(def.recover + def.cooldown) - 2
	h.ok(wait >= floor_ticks, "après le mur il ré-attaque au bout de %d images ; sans mur, récupération + recharge = %d" % [wait, floor_ticks])
	h.ok(def.wallStun < def.recover + def.cooldown, "donnée : l'étourdissement au mur reste plus court que ce délai")

static func tests(h) -> void:
	h.test("défaut 4 · acheter une amélioration inconnue : refus « inconnu », rien n'est débité", func(): _t_amelioration_inconnue(h))
	h.test("défaut 10 · à 1 PV, aucune option d'autel payée en PV n'est gratuite (registre, clepsydre, coffre maudit)", func(): _t_un_pv(h))
	h.test("défaut 11 · la ruée du Bélier traverse le héros et finit au mur", func(): _t_ruee_belier(h))
	h.test("défaut 11 · la ruée de Charon traverse le héros et finit au mur", func(): _t_ruee_charon(h))
	h.test("défaut 12 · un Bélier qui percute un mur ne ré-attaque pas plus tôt que s'il n'avait rien percuté", func(): _t_mur_belier(h))
