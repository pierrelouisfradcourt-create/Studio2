extends RefCounted
## Profils d'ESSAI pour le banc et le test de la Ville. Un banc a le droit de fabriquer son
## profil ; la Ville, non. Tout est fabriqué par les règles (D6Profile, D6Loot), sur une partie
## jetable, et écrit dans le dossier d'essai (`D666_DONNEES`), jamais dans le vrai profil.

const Profil = preload("res://jeu/profil.gd")

const GRAINE := 666.0
const AMES_LARGES := 100000.0
const NIVEAU_RICHE := 8.0 # niveau de classe du joueur avancé : sept points de compétence à dépenser
const AMELIORATIONS := ["vitalite", "vitalite", "ferocite", "fortune", "arsenal"]
const PORTES := [
	{"slot": "arme", "rarity": "rare", "floor": 52.0, "weaponType": "lame"},
	{"slot": "armure", "rarity": "magique", "floor": 48.0},
	{"slot": "talisman", "rarity": "legendaire", "floor": 54.0},
]
const COFFRE := [
	{"slot": "arme", "rarity": "legendaire", "floor": 55.0, "weaponType": "lame"},
	{"slot": "arme", "rarity": "magique", "floor": 40.0, "weaponType": "dagues"},
	{"slot": "arme", "rarity": "rare", "floor": 50.0, "weaponType": "hache"},
	{"slot": "arme", "rarity": "commun", "floor": 30.0, "weaponType": "arc"},
	{"slot": "armure", "rarity": "legendaire", "floor": 53.0},
	{"slot": "armure", "rarity": "rare", "floor": 51.0},
	{"slot": "armure", "rarity": "commun", "floor": 20.0},
	{"slot": "talisman", "rarity": "rare", "floor": 49.0},
	{"slot": "talisman", "rarity": "magique", "floor": 44.0},
	{"slot": "talisman", "rarity": "commun", "floor": 12.0},
	{"slot": "arme", "rarity": "rare", "floor": 37.0, "weaponType": "arbalete"},
	{"slot": "armure", "rarity": "magique", "floor": 36.0},
]

## Vide le dossier d'essai courant : la Ville s'ouvrira sur un joueur qui n'a jamais joué.
static func effacer() -> void:
	for fichier in [Profil.FICHIER, Profil.FICHIER_REGLAGES]:
		for suffixe in ["", ".bak", ".tmp"]:
			var chemin: String = ProjectSettings.globalize_path(Profil.chemin(fichier) + suffixe)
			if FileAccess.file_exists(chemin):
				DirAccess.remove_absolute(chemin)

## Profil avancé : toutes les classes, des Âmes, des niveaux de classe (donc des points de
## compétence à dépenser), quatre checkpoints, trois Gardiens rencontrés,
## un équipement porté et un coffre garni de toutes les raretés (dont des armes d'autres classes).
static func riche(tuning: Dictionary, ames: float = 345.0) -> Dictionary:
	var p: Dictionary = D6Profile.new_profile(tuning)
	p.souls = AMES_LARGES
	for id in tuning.classes:
		D6Profile.unlock(p, tuning, "classes", id)
	for id in AMELIORATIONS:
		D6Profile.buy_upgrade(p, tuning, id)
	var longueur: float = tuning.floors.sectionLength
	p.checkpoints = [1.0, longueur + 1.0, 2.0 * longueur + 1.0, 3.0 * longueur + 1.0]
	p.bestFloor = 3.0 * longueur + 7.0
	p.guardians = {}
	for modele in tuning.guardians.rotation.slice(0, 3):
		p.guardians[modele] = 1.0
	p.stats = {"runs": 23.0, "deaths": 19.0, "kills": 1840.0, "guardianKills": 3.0}
	var jetable: Dictionary = D6Game.create_game({"seed": GRAINE, "startFloor": 1.0, "meta": p, "sandbox": true})
	for voeu in PORTES:
		var objet: Dictionary = D6Loot.generate_item(jetable, voeu)
		D6Profile.ensure_uid(p, objet)
		p.equipment[voeu.slot] = objet
	for voeu in COFFRE:
		D6Profile.stash_loot(p, D6Loot.generate_item(jetable, voeu))
	p.souls = ames
	p.gold = 312.0
	p.tree[p.loadout.classId].level = NIVEAU_RICHE
	return p

## Profil du BOUT DU CHEMIN (test de parcours : l'écran de victoire) : un joueur qui a battu tous
## les Gardiens sauf le dernier. Tout est acheté, chaque début de section est un checkpoint
## jusqu'à la dernière, et il porte des objets légendaires du niveau de l'étage qui la précède.
static func au_bout_du_chemin(tuning: Dictionary, classe: String, ames: float = 345.0) -> Dictionary:
	var p: Dictionary = D6Profile.new_profile(tuning)
	p.souls = AMES_LARGES
	for id in tuning.classes:
		D6Profile.unlock(p, tuning, "classes", id)
	for id in tuning.town.upgrades:
		while D6Js.truthy(D6Profile.buy_upgrade(p, tuning, id).get("ok")):
			pass
	D6Profile.select_class(p, tuning, classe)
	var sections: float = ceilf(tuning.floors.total / tuning.floors.sectionLength)
	p.checkpoints = []
	p.guardians = {}
	for s in range(1, int(sections)):
		p.checkpoints.append(D6Floors.section_bounds(tuning, float(s)).first)
		var modele = D6Floors.guardian_for(tuning, float(s))
		p.guardians[modele] = D6Js.nz(p.guardians.get(modele), 0.0) + 1.0
	var derniere: float = D6Floors.section_bounds(tuning, sections).first
	p.checkpoints.append(derniere)
	p.bestFloor = derniere
	p.stats = {"runs": 240.0, "deaths": 203.0, "kills": 31800.0, "guardianKills": sections - 1.0}
	var jetable: Dictionary = D6Game.create_game({"seed": GRAINE, "startFloor": 1.0, "meta": p, "sandbox": true})
	for slot in p.equipment:
		var voeu := {"slot": slot, "rarity": "legendaire", "floor": derniere - 1.0}
		if slot == "arme":
			voeu.weaponType = tuning.classes[classe].weapons[0]
		var objet: Dictionary = D6Loot.generate_item(jetable, voeu)
		D6Profile.ensure_uid(p, objet)
		p.equipment[slot] = objet
	p.souls = ames
	return p

static func ecrire(profil: Dictionary) -> void:
	Profil.enregistrer(profil)
