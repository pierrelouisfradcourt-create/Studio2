# run_tests.gd — POINT D'ENTREE MECANIQUE de l'oracle headless (category godot.project_tests).
# Lancer : godot --headless --path games/kitten_clicker --script res://tests/run_tests.gd
# exit 0 = tous verts, 1 = au moins un rouge.
#
# Chemin IMPOSE par godot_oracle.mjs (res://tests/run_tests.gd). Patron chess_tcg/bomberman :
# le SceneTree EST le harnais (ok/eq/gt), assertions STRICTES (jamais un >= tautologique).
# Garde anti-FAUX-VERT EXPECTED_ASSERTS : si un coeur ne compile pas, ses tests avortent en
# silence, le total n'est pas atteint et l'echec est FORCE. C'est aussi la cible du gate
# mutation : chaque mutant d'un systeme pur doit faire tomber au moins une assertion.
extends SceneTree

const Economy = preload("res://05_SYSTEMS/economy/economy.gd")
const Pricing = preload("res://05_SYSTEMS/pricing/pricing.gd")
const WorldContent = preload("res://05_SYSTEMS/world_content/world_content.gd")
const Collection = preload("res://05_SYSTEMS/collection/collection.gd")
const Upgrades = preload("res://05_SYSTEMS/upgrades/upgrades.gd")
const Prestige = preload("res://05_SYSTEMS/prestige/prestige.gd")
const Progression = preload("res://05_SYSTEMS/progression/progression.gd")
const Goals = preload("res://05_SYSTEMS/goals/goals.gd")
const Decision = preload("res://05_SYSTEMS/decision/decision.gd")

const EXPECTED_ASSERTS := 132

var _passed := 0
var _failed := 0
var _fails: Array = []

const KITS := [
	{"name": "A", "rarity": "common", "ronrons_per_sec": 1},
	{"name": "B", "rarity": "common", "ronrons_per_sec": 2},
	{"name": "C", "rarity": "rare", "ronrons_per_sec": 3},
]
const PLACES := [
	{"id": "refuge", "name": "R", "unlock_tier": 0},
	{"id": "lieu_2", "name": "J", "unlock_tier": 3},
]


func _initialize() -> void:
	test_economy_state()
	test_economy_click_and_spend()
	test_economy_production_tick()
	test_pricing()
	test_world_content()
	test_collection()
	test_upgrades()
	test_prestige()
	test_progression()
	test_goals()
	test_decision()
	var total := _passed + _failed
	if total != EXPECTED_ASSERTS:
		_failed += 1
		_fails.append("META: %d/%d assertions executees (coeur non charge ?)" % [total, EXPECTED_ASSERTS])
	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	for f in _fails:
		print("  FAIL: ", f)
	quit(0 if _failed == 0 else 1)


func ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_fails.append(name)

func eq(a, b, name: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		_fails.append("%s (attendu %s, obtenu %s)" % [name, str(b), str(a)])

func feq(a: float, b: float, name: String) -> void:
	if absf(a - b) < 0.0001:
		_passed += 1
	else:
		_failed += 1
		_fails.append("%s (attendu %f, obtenu %f)" % [name, b, a])


# --- economy -------------------------------------------------------------------
func test_economy_state() -> void:
	var s := Economy.initial_state()
	feq(float(s["ronrons"]), 0.0, "state ronrons 0")
	eq(int(s["upgrade_level"]), 0, "state upgrade_level 0")
	eq((s["adopted"] as Array).size(), 0, "state adopted vide")
	eq(int(s["prestige_count"]), 0, "state prestige_count 0")
	eq(int(s["prod_paused"]), 0, "state prod_paused 0")
	eq(Economy.base_click(), 10, "base_click 10")
	feq(Economy.PASSIVE_UNIT, 0.5, "PASSIVE_UNIT 0.5")

func test_economy_click_and_spend() -> void:
	var s := Economy.initial_state()
	Economy.add(s, 7.0)
	feq(float(s["ronrons"]), 7.0, "add 7")
	Economy.add(s, 0.0)
	feq(float(s["ronrons"]), 7.0, "add 0 no-op")
	Economy.add(s, -3.0)
	feq(float(s["ronrons"]), 7.0, "add negatif ignore")
	Economy.add(s, 3.0)
	feq(float(s["ronrons"]), 10.0, "add 3 -> 10")
	eq(Economy.total(s), 10, "total 10")
	# frontiere STRICTE : peut acheter avec EXACTEMENT le montant.
	ok(Economy.can_afford(s, 10), "afford exact 10")
	ok(not Economy.can_afford(s, 11), "not afford 11")
	ok(Economy.can_afford(s, 9), "afford 9")
	ok(Economy.spend(s, 10), "spend exact 10 ok")
	feq(float(s["ronrons"]), 0.0, "ronrons 0 apres spend")
	ok(not Economy.spend(s, 1), "spend insuffisant echoue")
	feq(float(s["ronrons"]), 0.0, "ronrons inchange apres echec")
	Economy.add(s, 5.7)
	eq(Economy.total(s), 5, "total plancher 5")

func test_economy_production_tick() -> void:
	var s := Economy.initial_state()
	# pause active : aucune production, la pause se consomme d'une trame.
	s["prod_paused"] = 2
	Economy.production_tick(s, 10.0, 3.0)
	feq(float(s["ronrons"]), 0.0, "pause: aucune production")
	eq(int(s["prod_paused"]), 1, "pause: 2 -> 1")
	Economy.production_tick(s, 10.0, 3.0)
	feq(float(s["ronrons"]), 0.0, "pause: encore aucune production")
	eq(int(s["prod_paused"]), 0, "pause: 1 -> 0")
	# hors pause : accrual = rate * mult * UNIT.
	Economy.production_tick(s, 4.0, 2.0)
	feq(float(s["ronrons"]), 4.0, "prod 4*2*0.5 = 4")
	Economy.production_tick(s, 0.0, 2.0)
	feq(float(s["ronrons"]), 4.0, "prod rate 0 -> rien")
	Economy.production_tick(s, 6.0, 1.0)
	feq(float(s["ronrons"]), 7.0, "prod 6*1*0.5 = 3 -> 7")


# --- pricing -------------------------------------------------------------------
func test_pricing() -> void:
	eq(Pricing.kitten_cost(0), 5, "kitten_cost 0 = 5")
	eq(Pricing.kitten_cost(1), 10, "kitten_cost 1 = 10")
	eq(Pricing.kitten_cost(2), 15, "kitten_cost 2 = 15")
	eq(Pricing.kitten_cost(3), 20, "kitten_cost 3 = 20")
	eq(Pricing.upgrade_cost(0), 8, "upgrade_cost 0 = 8")
	eq(Pricing.upgrade_cost(1), 12, "upgrade_cost 1 = 12")
	eq(Pricing.upgrade_cost(2), 16, "upgrade_cost 2 = 16")
	var pal := Pricing.paliers()
	eq(pal.size(), 3, "3 paliers")
	eq(pal[0], 5, "palier 0 = 5")
	eq(pal[1], 10, "palier 1 = 10")
	eq(pal[2], 15, "palier 2 = 15")
	ok(pal[0] < pal[1] and pal[1] < pal[2], "paliers strictement croissants")
	eq(Pricing.distinct_paliers(), 3, "3 paliers distincts (variance)")


# --- world_content -------------------------------------------------------------
func k6() -> Array:
	return [{"name": "a"}, {"name": "b"}, {"name": "c"}, {"name": "d"}, {"name": "e"}, {"name": "f"}]

func test_world_content() -> void:
	eq(WorldContent.MIN_KITTENS, 6, "MIN_KITTENS 6")
	eq(WorldContent.MIN_PLACES, 2, "MIN_PLACES 2")
	eq(WorldContent.MIN_OBJECTS, 3, "MIN_OBJECTS 3")
	eq(WorldContent.MIN_QUESTS, 3, "MIN_QUESTS 3")
	var ks := WorldContent.kittens()
	ok(ks.size() >= 6, "kittens >= 6 charges")
	eq(WorldContent.distinct_kitten_names(ks), ks.size(), "noms tous distincts")
	ok(WorldContent.valid(), "registres reels valides")
	# distinct_kitten_names : doublon, nom vide, deux distincts
	eq(WorldContent.distinct_kitten_names([{"name": "z"}, {"name": "z"}]), 1, "doublon de nom compte 1")
	eq(WorldContent.distinct_kitten_names([{"name": ""}]), 0, "nom vide compte 0")
	eq(WorldContent.distinct_kitten_names([{"name": "a"}, {"name": "b"}]), 2, "2 noms distincts")
	eq(WorldContent.distinct_kitten_names(["pasdict"]), 0, "entree non-dict ignoree")
	# has_refuge : tier 0 present / absent / liste vide
	ok(WorldContent.has_refuge([{"unlock_tier": 0}]), "refuge tier 0 present")
	ok(not WorldContent.has_refuge([{"unlock_tier": 1}]), "pas de refuge si tier 1")
	ok(not WorldContent.has_refuge([]), "liste vide : pas de refuge")
	# extract_array : Dict+Array vs Dict sans la cle
	eq(WorldContent.extract_array({"k": [1, 2]}, "k"), [1, 2], "extract Dict+Array")
	eq(WorldContent.extract_array({"autre": [1]}, "k"), [], "extract cle absente -> vide")
	eq(WorldContent.extract_array("pasdict", "k"), [], "extract non-dict -> vide")
	eq(WorldContent.extract_array({"k": "pasarray"}, "k"), [], "extract valeur non-Array -> vide")
	# registers_valid : frontiere exacte valide, puis CHAQUE condition falsifiee seule
	var P2 := [{"unlock_tier": 0}, {"unlock_tier": 1}]
	ok(WorldContent.registers_valid(k6(), P2, [1, 2, 3], [1, 2, 3]), "frontiere exacte -> valide")
	var k5 := k6(); k5.remove_at(0)
	ok(not WorldContent.registers_valid(k5, P2, [1, 2, 3], [1, 2, 3]), "5 chatons -> invalide")
	ok(not WorldContent.registers_valid(k6(), [{"unlock_tier": 0}], [1, 2, 3], [1, 2, 3]), "1 lieu -> invalide")
	ok(not WorldContent.registers_valid(k6(), [{"unlock_tier": 1}, {"unlock_tier": 2}], [1, 2, 3], [1, 2, 3]), "pas de refuge -> invalide")
	ok(not WorldContent.registers_valid(k6(), P2, [1, 2], [1, 2, 3]), "2 objets -> invalide")
	ok(not WorldContent.registers_valid(k6(), P2, [1, 2, 3], [1, 2]), "2 quetes -> invalide")


# --- collection ----------------------------------------------------------------
func test_collection() -> void:
	var s := Economy.initial_state()
	eq(Collection.count(s), 0, "count 0")
	feq(Collection.passive_rate(s, KITS), 0.0, "rate 0 sans chaton")
	ok(not Collection.is_adopted(s, 0), "0 pas adopte")
	ok(Collection.adopt(s, KITS), "adopt 1 ok")
	eq(Collection.count(s), 1, "count 1")
	eq(String((s["adopted"] as Array)[0]), "A", "1er chaton = A")
	feq(Collection.passive_rate(s, KITS), 1.0, "rate 1 (A)")
	ok(Collection.is_adopted(s, 0), "0 adopte")
	ok(Collection.adopt(s, KITS), "adopt 2 ok")
	feq(Collection.passive_rate(s, KITS), 3.0, "rate 3 (A+B)")
	ok(Collection.adopt(s, KITS), "adopt 3 ok")
	feq(Collection.passive_rate(s, KITS), 6.0, "rate 6 (A+B+C)")
	ok(not Collection.adopt(s, KITS), "adopt 4 echoue (epuise)")
	eq(Collection.count(s), 3, "count reste 3")
	# entree non-Dictionary : adopt refuse (jamais un true fabrique)
	var s2 := Economy.initial_state()
	ok(Collection.adopt(s2, [{"name": "X", "ronrons_per_sec": 1}, "pasdict"]), "adopt 1er (dict) ok")
	ok(not Collection.adopt(s2, [{"name": "X", "ronrons_per_sec": 1}, "pasdict"]), "adopt 2e (non-dict) refuse")
	# passive_rate : une entree non-Dict a l'index adopte est ignoree (and, jamais or)
	var s3 := Economy.initial_state()
	(s3["adopted"] as Array).append("A")
	(s3["adopted"] as Array).append("B")
	feq(Collection.passive_rate(s3, [{"ronrons_per_sec": 1}, "pasdict"]), 1.0, "rate ignore l'entree non-dict")


# --- upgrades ------------------------------------------------------------------
func test_upgrades() -> void:
	var s := Economy.initial_state()
	eq(Upgrades.level(s), 0, "level 0")
	eq(Upgrades.click_multiplier(s), 1, "mult 2^0 = 1")
	eq(Upgrades.buy(s), 1, "buy -> level 1")
	eq(Upgrades.click_multiplier(s), 2, "mult 2^1 = 2")
	eq(Upgrades.buy(s), 2, "buy -> level 2")
	eq(Upgrades.click_multiplier(s), 4, "mult 2^2 = 4")
	eq(Upgrades.buy(s), 3, "buy -> level 3")
	eq(Upgrades.click_multiplier(s), 8, "mult 2^3 = 8")


# --- prestige ------------------------------------------------------------------
func test_prestige() -> void:
	eq(Prestige.PRESTIGE_THRESHOLD, 1, "seuil 1")
	eq(Prestige.COOLDOWN_FRAMES, 45, "cooldown 45")
	var s := Economy.initial_state()
	eq(Prestige.bonus(s), 0, "bonus 0")
	eq(Prestige.production_multiplier(s), 1, "mult 1+0")
	ok(not Prestige.can_prestige(s), "0 ronron: pas de prestige")
	ok(not Prestige.prestige(s), "prestige echoue a 0")
	Economy.add(s, 1.0)
	ok(Prestige.can_prestige(s), "1 ronron (frontiere): prestige ok")
	Economy.add(s, 41.0)
	Collection.adopt(s, KITS)
	ok(Prestige.prestige(s), "prestige applique")
	feq(float(s["ronrons"]), 0.0, "ronrons remis a 0")
	eq(Prestige.bonus(s), 1, "bonus +1")
	eq(int(s["prod_paused"]), 45, "prod_paused = 45")
	eq(Collection.count(s), 1, "chatons conserves")
	eq(Prestige.production_multiplier(s), 2, "mult 1+1")
	Economy.add(s, 10.0)
	ok(Prestige.prestige(s), "2e prestige")
	eq(Prestige.bonus(s), 2, "bonus strictement croissant -> 2")
	eq(Prestige.production_multiplier(s), 3, "mult 1+2")


# --- progression ---------------------------------------------------------------
func test_progression() -> void:
	var s := Economy.initial_state()
	eq(Progression.tier(s), 0, "tier 0")
	ok(not Progression.lieu2_unlocked(s, PLACES), "lieu_2 verrouille a 0")
	eq(Progression.available_places(s, PLACES), 1, "1 lieu dispo (refuge)")
	Collection.adopt(s, KITS)
	Collection.adopt(s, KITS)
	eq(Progression.tier(s), 2, "tier 2")
	ok(not Progression.lieu2_unlocked(s, PLACES), "lieu_2 verrouille a 2")
	Collection.adopt(s, KITS)
	eq(Progression.tier(s), 3, "tier 3")
	ok(Progression.lieu2_unlocked(s, PLACES), "lieu_2 debloque a 3 (frontiere)")
	eq(Progression.available_places(s, PLACES), 2, "2 lieux dispo")
	ok(not Progression.lieu2_unlocked(s, [{"id": "refuge", "unlock_tier": 0}]), "pas de lieu_2 absent")


# --- goals ---------------------------------------------------------------------
func test_goals() -> void:
	var s := Economy.initial_state()
	var o0 := Goals.objective(s, PLACES, 0)
	ok(o0.strip_edges() != "", "objectif boot non vide")
	ok(o0.find("[ronrons 0]") != -1, "objectif porte le progres vivant")
	# frontiere 0 chaton : phrase de premier guidage (kittens <= 0)
	ok(o0.find("Caresse la pelote") != -1, "0 chaton -> guidage premier clic")
	Collection.adopt(s, KITS)
	var o1 := Goals.objective(s, PLACES, 12)
	ok(o1 != o0, "objectif change apres adoption")
	ok(o1.find("[ronrons 12]") != -1, "objectif porte le nouveau progres")
	ok(o1.find("agrandir le refuge") != -1, "1 chaton -> phrase refuge")
	var o1b := Goals.objective(s, PLACES, 13)
	ok(o1b != o1, "objectif distinct quand le progres monte (new_distinct)")
	# frontiere GARDEN_TIER-1 (2 chatons) : phrase 'ouvrir le jardin'
	Collection.adopt(s, KITS)
	ok(Goals.objective(s, PLACES, 20).find("ouvrir le jardin") != -1, "2 chatons -> phrase ouvrir le jardin")
	# lieu_2 debloque (3 chatons, tier 3) : phrase 'jardin est ouvert'
	Collection.adopt(s, KITS)
	ok(Goals.objective(s, PLACES, 30).find("jardin est ouvert") != -1, "3 chatons -> jardin ouvert")

# --- decision ------------------------------------------------------------------
func test_decision() -> void:
	var s := Economy.initial_state()
	eq(Decision.cost(s, "acheter_chaton"), 5, "cout chaton 0 = 5")
	eq(Decision.cost(s, "acheter_amelioration"), 8, "cout amelioration 0 = 8")
	eq(Decision.cost(s, "inconnu"), 0, "cout option inconnue = 0")
	eq(Decision.effect_text(s, KITS, "acheter_chaton"), "+1 ronron/s (production passive)", "effet chaton exact (rate KITS[0]=1)")
	ok(Decision.effect_text(s, KITS, "acheter_amelioration").find("clic") != -1, "effet amelioration")
	eq(Decision.effect_text(s, KITS, "inconnu"), "", "effet option inconnue vide")
	# tous les chatons adoptes : plus de prochain -> taux 0 (frontiere idx == taille)
	var sfull := Economy.initial_state()
	Collection.adopt(sfull, KITS); Collection.adopt(sfull, KITS); Collection.adopt(sfull, KITS)
	eq(Decision.effect_text(sfull, KITS, "acheter_chaton"), "+0 ronron/s (production passive)", "aucun prochain chaton -> +0")
	Collection.adopt(s, KITS)
	Upgrades.buy(s)
	# apres prefixe (1 chaton, 1 amelioration) : idle favorise ADOPTER, actif favorise AMELIORER.
	var idle_kit := Decision.projected_gain(s, KITS, "acheter_chaton", 0, 300)
	var idle_upg := Decision.projected_gain(s, KITS, "acheter_amelioration", 0, 300)
	ok(idle_kit > idle_upg, "idle: adopter domine")
	var act_kit := Decision.projected_gain(s, KITS, "acheter_chaton", 100, 300)
	var act_upg := Decision.projected_gain(s, KITS, "acheter_amelioration", 100, 300)
	ok(act_upg > act_kit, "actif: ameliorer domine")
