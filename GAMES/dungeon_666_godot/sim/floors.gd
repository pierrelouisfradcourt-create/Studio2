class_name D6Floors
extends RefCounted
## Portage de src/sim/floors.mjs.
## Structure des 666 étages — fonctions pures sur le numéro d'étage (1..666). Aucun étage n'est
## écrit à la main : chaque étage est COMPOSÉ à la volée à partir de briques réutilisables
## (plan de section, sections.mjs : type d'étage, portes, vagues, budget, dispositions, thème du
## Cercle ; salle, room.mjs : dispositions et vagues ; archétypes et élites, enemies.mjs ;
## Gardien de la section, ci-dessous et bosses ; salles calmes, calm_rooms.mjs).
##
##   section  = 18 étages (tuning.floors.sectionLength) ; le 18e est un GARDIEN : le battre
##              ouvre un checkpoint et un point de téléportation (l'étage suivant).
##   Cercle   = 72 étages (4 sections) — 9 Cercles de l'Enfer = 648 étages,
##   finale   = 18 étages (1 section) « L'Abîme » = 666. Soit 37 sections, 37 Gardiens.

## Math.floor(v) de JavaScript sur une valeur quelconque : un texte est lu comme un nombre
## (« 12 » vaut 12, « abc » vaut NaN), un booléen vaut 0 ou 1.
static func _floor_number(v) -> float:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			return floorf(float(v))
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(v).strip_edges()
			if s == "":
				return 0.0
			return floorf(s.to_float()) if s.is_valid_float() else NAN
	return NAN

## Numéro d'étage borné à 1..total ; une valeur non numérique (lien `?floor=abc`) vaut l'étage 1.
static func _clamp_floor(tuning: Dictionary, floor) -> float:
	var n := _floor_number(floor)
	return maxf(1.0, minf(tuning.floors.total, n)) if is_finite(n) else 1.0

static func floor_info(tuning: Dictionary, floor) -> Dictionary:
	var f: Dictionary = tuning.floors
	var n := _clamp_floor(tuning, floor)
	var section := ceilf(n / f.sectionLength) # 1..37
	var index_in_section: float = n - (section - 1.0) * f.sectionLength # 1..18
	var circle_count := float(f.circleNames.size())
	var in_finale: bool = n > circle_count * f.circleLength
	var circle: float = circle_count + 1.0 if in_finale else ceilf(n / f.circleLength) # 1..10
	var circle_name = f.finaleName if in_finale else f.circleNames[int(circle - 1.0)]
	var is_boss: bool = index_in_section == f.sectionLength
	var is_circle_boss: bool = is_boss and (n == f.total if in_finale else fmod(n, f.circleLength) == 0.0)
	return {
		"floor": n,
		"section": section,
		"sectionCount": ceilf(f.total / f.sectionLength),
		"indexInSection": index_in_section,
		"circle": circle,
		"circleName": circle_name,
		"inFinale": in_finale,
		"isBoss": is_boss,
		"isCircleBoss": is_circle_boss,
		"isFinal": n == f.total,
	}

## Premier étage de la section qui suit le boss de l'étage `boss_floor` : le point de reprise.
static func checkpoint_after_boss(tuning: Dictionary, boss_floor: float) -> float:
	return minf(tuning.floors.total, boss_floor + 1.0)

## Multiplicateurs de difficulté de l'étage, définis jusqu'à 666 (k = étage − 1, i = index dans
## la section 1..18). Le jeu sépare le PERMANENT (classe, équipement, Ville) du TEMPORAIRE
## (bénédictions, effacées à chaque mort, la reprise se faisant au début d'une section) ; la
## difficulté suit la même séparation :
##   L  = 1 + itemGrowth·k                          niveau d'objet (l'équipement trouvé suit la même pente)
##   Bp = 1 + permBuildCap·(1 − e^(−k/permBuildScale))  ce que la progression PERMANENTE apporte en plus
##                                                  du niveau (raretés, affixes, Sanctuaire)
##   Bs = 1 + sectionBuildCap·(i − 1)/(longueur − 1)    build TEMPORAIRE réuni depuis le checkpoint :
##                                                  1 au début de chaque section, maximal au Gardien
##   C  = 1 + driftAt666·k/665                       dérive de difficulté
##   H  = (PV innés + armure·L)/(PV innés + armure)  PV d'un héros équipé à niveau (armure, même pente)
##   D  = 1 + dmgCurve·(1 − e^(−k/dmgScale))         part des PV que pèse un coup, en plus
##   PV ennemis = L·Bp·Bs·C · dégâts = H·D · densité = 1 + densityCurve·(1 − e^(−k/densityScale)).
## Les PV montent donc en dents de scie : ils croissent dans une section (jusqu'au Gardien), le
## début de section redescend au niveau de ce qu'un héros SANS bénédiction peut affronter, et
## chaque début de section reste plus dur que le précédent. Les télégraphes ne changent jamais.
static func floor_scaling(tuning: Dictionary, floor) -> Dictionary:
	var f: Dictionary = tuning.floors
	var n := _clamp_floor(tuning, floor)
	var k := n - 1.0
	var index := fmod(k, f.sectionLength) # 0..17
	var L: float = 1.0 + f.itemGrowth * k
	var Bp: float = 1.0 + f.permBuildCap * (1.0 - D6Trig.exp(-k / f.permBuildScale))
	var Bs: float = 1.0 + (f.sectionBuildCap * index) / maxf(1.0, f.sectionLength - 1.0)
	var C: float = 1.0 + (f.driftAt666 * k) / maxf(1.0, f.total - 1.0)
	var H := player_hp_growth(tuning, L)
	var D: float = 1.0 + f.dmgCurve * (1.0 - D6Trig.exp(-k / f.dmgScale))
	var density: float = 1.0 + f.densityCurve * (1.0 - D6Trig.exp(-k / f.densityScale))
	return {"hp": L * Bp * Bs * C, "damage": H * D, "density": density, "level": L, "permBuild": Bp, "sectionBuild": Bs, "drift": C, "hpGrowth": H, "lethality": D}

## PV d'un héros équipé d'une armure de niveau L, relatifs au niveau 1 (PV innés + armure).
static func player_hp_growth(tuning: Dictionary, L: float) -> float:
	var pl = tuning.get("player")
	var innate: float = D6Js.nz(pl.get("innateHp"), 0.0) if pl is Dictionary else 0.0
	var armor: float = D6Js.nz(tuning.get("armorBase"), 1.0)
	return (innate + armor * L) / (innate + armor)

## Difficulté au DÉBUT de la section (checkpoint), face à un héros qui n'a que son PERMANENT :
## équipement trouvé jusqu'au Gardien précédent (niveau d'objet = étage − 1), aucune bénédiction.
##   toughness = PV ennemis ÷ dégâts de l'arme portée (temps pour tuer, relatif à l'étage 1)
##   lethality = dégâts ennemis ÷ PV du héros équipé (part des PV par coup, relative à l'étage 1)
static func section_start_difficulty(tuning: Dictionary, section: float) -> Dictionary:
	var first: float = section_bounds(tuning, section).first
	var s := floor_scaling(tuning, first)
	var gear := floor_scaling(tuning, maxf(1.0, first - 1.0))
	return {"floor": first, "toughness": s.hp / gear.level, "lethality": s.damage / gear.hpGrowth}

## Modèle de Gardien qui garde la section `section` (1..37) : rotation des modèles connus
## (tuning.guardians.rotation). Un même modèle revient plus loin, plus coriace (floorScaling).
static func guardian_for(tuning: Dictionary, section: float):
	var rot: Array = tuning.guardians.rotation.filter(func(k): return D6Js.truthy(tuning.boss.get(k)))
	if rot.is_empty():
		var keys: Array = tuning.boss.keys()
		return null if keys.is_empty() else keys[0]
	var i := fmod(maxf(1.0, section) - 1.0, float(rot.size()))
	if i != floorf(i):
		return null # section non entière : rot[1.5] est « undefined » en JavaScript
	return rot[int(i)]

## Étage du Gardien de la section, et checkpoint qu'il ouvre.
static func section_bounds(tuning: Dictionary, section: float) -> Dictionary:
	var length: float = tuning.floors.sectionLength
	var last := minf(tuning.floors.total, section * length)
	return {"first": (section - 1.0) * length + 1.0, "guardian": last, "checkpoint": checkpoint_after_boss(tuning, last)}
