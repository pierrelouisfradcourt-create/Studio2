extends RefCounted
## COMPÉTENCES NEUVES (combat V3, étape 4) — la FAÇADE : le reste de la simulation n'appelle
## qu'elle. Chargée par preload (pas de class_name). Une famille par classe :
##   sim/neuves_revenant.gd     sillage (braises), sceau (Stigmate), riposte (Contre-taille)
##   sim/neuves_bourreau.gd     faille, hachette (hache qui revient), garde (Garde de fer)
##   sim/neuves_chasseresse.gd  proie (marque), leurre (allié posé), trait (tir qui se bande)
## Étape 5, la quatrième de chaque classe, dans les mêmes fichiers : ombre (Ombre jumelle : alliée
## intangible qui répète ses coups), grace (Décollation : le coup qui tue se relance), grele (Grêle
## des Limbes : frappe de zone à retardement).
## Chaque compétence est une entrée de data/classes.json (`skills` : recharge ; `gadgets` :
## charges) et un nœud de data/arbres.json. Elles passent par les chemins communs : l'état 'cast'
## et sa recharge (player), les charges (kit_gadgets), les tirs et zones de la salle (kit_shots,
## kit_zones), les alliés de game.allies (ult_meute). Leurs dégâts portent la source « skill » ou
## « gadget » : bénédictions, objets et procs des compétences s'y appliquent sans rien savoir d'elles.
##
## Qui appelle quoi :
##   D6KitSkills.release_kit_skill → release        D6KitGadgets.use_kit_gadget → use_gadget
##   D6Game.step_game → tick                        D6Run (étage, reprise) → reset
##   D6Combat.damage_player → absorb                D6Combat.kill_enemy → on_kill
##   D6KitShots → mark_hit, update_shot             D6KitZones → zone
##   ult_meute.tick → tick_ally, prey               D6Player._press_slot → second_press
##   D6Loadout.slot_view → slot_extra               D6Player._update_attack → on_swing

const Revenant := preload("res://sim/neuves_revenant.gd")
const Bourreau := preload("res://sim/neuves_bourreau.gd")
const Chasseresse := preload("res://sim/neuves_chasseresse.gd")

const SKILLS := ["sceau", "riposte", "faille", "hachette", "proie", "trait"] # `kind` des compétences neuves à recharge
const GADGETS := ["sillage", "garde", "leurre"] # … et à charges
const SKILLS_2 := ["ombre", "grace", "grele"] # étape 5 : la quatrième de chaque classe (toutes à recharge)

## Effet d'une compétence neuve à la fin de son lancer. Rend l'angle du tir (le Trait vise au départ).
static func release(game: Dictionary, s: Dictionary, angle: float) -> float:
	match s.kind:
		"sceau":
			Revenant.release_sceau(game, s)
		"riposte":
			Revenant.release_riposte(game, s, angle)
		"faille":
			Bourreau.release_faille(game, s, angle)
		"hachette":
			Bourreau.release_hachette(game, s)
		"proie":
			Chasseresse.release_proie(game, s)
		"trait":
			return Chasseresse.release_trait(game, s)
		"ombre":
			Revenant.release_ombre(game, s)
		"grace":
			Bourreau.release_grace(game, s, angle)
		"grele":
			Chasseresse.release_grele(game, s)
	return angle

## Une compétence neuve à charges part. Rend false si rien n'a pu partir (charge à rendre).
static func use_gadget(game: Dictionary, g: Dictionary, aim_x: float, aim_y: float) -> bool:
	match g.kind:
		"sillage":
			Revenant.use_sillage(game, g)
		"garde":
			Bourreau.use_garde(game, g)
		"leurre":
			return Chasseresse.use_leurre(game, g, aim_x, aim_y)
	return true

## Un pas (après le héros) : braises semées, garde et parade qui s'usent, marques des ennemis.
static func tick(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	if p.state == "dead":
		reset(game)
		return
	Revenant.tick_sillage(game, dt)
	Revenant.tick_parry(game, dt)
	Bourreau.tick_guard(game, dt)
	for e in game.enemies:
		Revenant.tick_mark(e, dt)
		Chasseresse.tick_mark(e, dt)

## Mort, changement de salle, reprise : plus de sillage, de garde ni de parade en cours (les
## marques partent avec les ennemis, les leurres avec les alliés : D6KitSupers.reset).
static func reset(game: Dictionary) -> void:
	var p: Dictionary = game.player
	for key in ["sillage", "parry", "guard"]:
		if p.get(key) != null:
			p[key] = null

## Un coup de `amount` va toucher le héros (ni mort, ni invulnérable) : rend ce qu'il en reste —
## 0 : paré (Contre-taille), moins : réduit (Garde de fer), `amount` : rien ne s'interpose.
static func absorb(game: Dictionary, amount: float, src: Dictionary) -> float:
	if Revenant.parry(game, src):
		return 0.0
	return Bourreau.absorb(game, amount, src)

## Un ennemi vient de mourir : Stigmate qui explose, marque de proie qui saute.
static func on_kill(game: Dictionary, e: Dictionary) -> void:
	Revenant.on_kill(game, e)
	Chasseresse.on_kill(game, e)

## Un tir marqueur va toucher `e` (avant ses dégâts : un ennemi achevé par le trait est marqué).
static func mark_hit(game: Dictionary, s: Dictionary, e: Dictionary) -> void:
	if s.mark.kind == "stigmate":
		Revenant.brand(game, e, s.mark)
	else:
		Chasseresse.brand(game, e, s.mark)

## Tir qui ne vole pas tout droit (`custom` : la hache qui revient) : joué ici.
static func update_shot(game: Dictionary, s: Dictionary, dt: float) -> void:
	Bourreau.update_axe(game, s, dt)

## Zone posée par une compétence neuve (`faille`, `grele`).
static func zone(game: Dictionary, z: Dictionary) -> void:
	if z.kind == "grele":
		Chasseresse.zone_grele(game, z)
	else:
		Bourreau.zone_faille(game, z)

## Un pas d'un allié qui n'est pas un limier (le leurre, l'ombre).
static func tick_ally(game: Dictionary, h: Dictionary, dt: float) -> void:
	if h.kind == Revenant.SHADE:
		Revenant.tick_shade(game, h, dt)
	else:
		Chasseresse.tick_ally(game, h, dt)

## Un coup d'arme du héros commence à porter : l'Ombre jumelle le répète.
static func on_swing(game: Dictionary, a: Dictionary) -> void:
	Revenant.echo(game, a)

## La proie marquée (cible des limiers), ou null.
static func prey(game: Dictionary):
	return Chasseresse.prey(game)

static func second_press(game: Dictionary, slot: int) -> bool:
	return Chasseresse.second_press(game, slot) or Revenant.swap(game, slot)

## Ce que slot_view AJOUTE pour une compétence neuve : `charging` (le Trait se bande sur ce bouton),
## `chargeFrac` (0..1), `active` (son effet dure : sillage, garde, parade) et `activeFrac` (part qui reste).
static func slot_extra(game: Dictionary, index: int, def: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var out := {"charging": false, "chargeFrac": 0.0, "active": false, "activeFrac": 0.0}
	if def.kind == "trait" and Chasseresse.charging(game, index):
		out.charging = true
		out.chargeFrac = Chasseresse.charge_frac(game, def)
	if def.kind == Revenant.SHADE:
		var h = Revenant.shade(game)
		if h != null and is_same(h.def, def): # l'ombre debout : son temps qui reste
			out.active = true
			out.activeFrac = D6Geo.clampv(h.life / maxf(1e-6, h.lifeMax), 0.0, 1.0)
		return out
	var key = {"sillage": "sillage", "garde": "guard", "riposte": "parry"}.get(def.kind)
	var st = p.get(key) if key != null else null
	if st is Dictionary and is_same(st.def, def):
		out.active = true
		out.activeFrac = D6Geo.clampv(st.t / maxf(1e-6, def.window if def.kind == "riposte" else def.duration), 0.0, 1.0)
	return out
