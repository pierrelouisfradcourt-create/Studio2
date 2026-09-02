# test_audio_score.gd — core.audio (dernier CORE non honore) et le bareme de score.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Cues = preload("res://05_SYSTEMS/sound_cues/sound_cues.gd")
const Score = preload("res://05_SYSTEMS/score/score.gd")
const Purete = preload("res://06_RUNTIME/adapters/proof_harness/purete_visuelle.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func run(h) -> void:
	# ---------- BANQUE DE SONS ----------
	h.eq(Cues.BANQUE.size(), Cues.CUES.size(), "audio: un descripteur par moment declare")
	for c in Cues.CUES:
		var d: Dictionary = Cues.descripteur(String(c))
		h.ok(not d.is_empty(), "audio: '%s' a un descripteur" % str(c))
		h.gt(float(d["hz"]), 0.0, "audio: '%s' a une hauteur positive" % str(c))
		h.gt(int(d["ms"]), 0, "audio: '%s' a une duree positive" % str(c))
		h.ok(float(d["gain"]) > 0.0 and float(d["gain"]) <= 1.0, "audio: '%s' a un gain borne" % str(c))
	h.eq(Cues.descripteur("inexistant"), {}, "audio: un moment inconnu rend un descripteur vide")

	# DISCERNABILITE A L'OREILLE — meme regle que la discernabilite visuelle, autre sens.
	h.eq(Cues.cues_indiscernables(), 0,
		"audio: 0 paire de moments partageant hauteur ET onde")

	# ---------- CORRESPONDANCE EVENEMENT -> SON ----------
	# Tout evenement que la boucle emet REELLEMENT doit avoir un son, sinon le jeu est muet
	# la ou il se passe quelque chose. La liste est derivee d'une partie JOUEE, pas devinee.
	var s = Fx.etat(Fx.desc_blocs(), 3, 2)
	s.acteurs[0]["rayon"] = 2
	var vus := {}
	var r: Dictionary = Loop.step(s, [P.POSER, P.AUCUNE])
	s = r["state"]
	for e in r["events"]:
		vus[String(e["kind"])] = true
	for i in range(P.MECHE_TICKS + P.DUREE_FLAMME + 4):
		r = Loop.step(s, [P.AUCUNE, P.AUCUNE])
		s = r["state"]
		for e in r["events"]:
			vus[String(e["kind"])] = true
	h.gt(vus.size(), 3, "audio: la partie jouee a emis plusieurs sortes d'evenements")
	var muets: Array = []
	for k in vus.keys():
		# `deplacement` est volontairement muet : un son a chaque pas serait insupportable.
		if String(k) == "deplacement":
			continue
		if Cues.cue_pour_evenement(String(k)) == "":
			muets.append(String(k))
	h.eq(muets, [], "audio: aucun evenement significatif n'est muet")
	h.eq(Cues.cue_pour_evenement("evenement_inconnu"), "",
		"audio: un evenement inconnu est silencieux, jamais une erreur")

	# ---------- VOLUME DE SYNTHESE, calculable sans jouer un son ----------
	h.gt(Cues.echantillons(Cues.CUE_EXPLOSION, 22050), 0, "audio: l'explosion produit des echantillons")
	h.eq(Cues.echantillons(Cues.CUE_EXPLOSION, 0), 0, "audio: frequence nulle -> 0 echantillon")
	h.eq(Cues.echantillons("inexistant", 22050), 0, "audio: moment inconnu -> 0 echantillon")
	h.gt(Cues.echantillons(Cues.CUE_MORT, 22050), Cues.echantillons(Cues.CUE_POSE, 22050),
		"audio: une mort dure plus longtemps qu'une pose")

	# ---------- CONTROLE POSITIF : l'API plateforme est REFERENCEE, et seulement en runtime.
	# Sans ce controle, un projet SANS audio du tout passerait « 0 API audio dans la logique ».
	var f := FileAccess.open("res://06_RUNTIME/adapters/audio/audio.gd", FileAccess.READ)
	var code_audio: String = Purete.code_seul(f.get_as_text() if f != null else "")
	h.ok(code_audio.contains("AudioStreamGenerator"),
		"audio: l'adaptateur reference REELLEMENT l'API de synthese (controle positif)")
	var g := FileAccess.open("res://05_SYSTEMS/sound_cues/sound_cues.gd", FileAccess.READ)
	var code_cues: String = Purete.code_seul(g.get_as_text() if g != null else "")
	h.eq(code_cues.contains("AudioStream"), false,
		"audio: la LOGIQUE ne connait aucune API audio de plateforme")
	h.eq(code_cues.contains("AudioServer"), false, "audio: ni AudioServer dans la logique")

	# ---------- VOLUME : le reglage atteint REELLEMENT la synthese ----------
	# Ce volet existe parce qu'un reglage non consomme est le mode de panne courant du
	# studio : un chiffre change dans un dictionnaire, et rien ne l'entend. On mesure donc
	# l'AMPLITUDE que la synthese applique, pas la valeur du reglage.
	const AudioA = preload("res://06_RUNTIME/adapters/audio/audio.gd")
	const AppA = preload("res://05_SYSTEMS/app_state/app_state.gd")
	const CuesA = preload("res://05_SYSTEMS/sound_cues/sound_cues.gd")
	var au = AudioA.new()
	au.muet(true)   # headless : aucun peripherique, mais l'amplitude reste calculee
	AudioA.reinitialiser_journal()
	var un_cue: String = String(CuesA.CUES[0]) if CuesA.CUES.size() > 0 else ""
	h.ok(un_cue != "", "audio: le registre de cues est peuple (controle positif)")

	var plein: float = au.amplitude_effet(un_cue)
	h.gt(plein, 0.0, "audio: a volume 100%%, l'amplitude d'un effet est non nulle")
	au.volume_effets = 0.0
	h.eq(au.amplitude_effet(un_cue), 0.0, "audio: a volume 0, l'amplitude d'un effet tombe a 0")
	au.volume_effets = 0.5
	h.ok(abs(au.amplitude_effet(un_cue) - plein * 0.5) < 0.0001,
		"audio: a volume 50%%, l'amplitude est la MOITIE de l'amplitude pleine")

	var plein_m: float = au.amplitude_musique()
	h.gt(plein_m, 0.0, "audio: a volume 100%%, l'amplitude musicale est non nulle")
	au.volume_musique = 0.0
	h.eq(au.amplitude_musique(), 0.0, "audio: a volume 0, la musique est reellement coupee")
	au.volume_musique = 1.0
	au.volume_effets = 1.0

	# LA SYNTHESE LIT CETTE AMPLITUDE — prouve par le JOURNAL, ecrit par le vrai `jouer()`.
	# Sans ce volet, `amplitude_effet` pourrait etre juste et n'etre appelee par personne.
	AudioA.reinitialiser_journal()
	au.jouer(un_cue, 0)
	au.jouer_musique(0, 0)
	h.eq(AudioA.journal.size(), 1, "audio: le journal enregistre l'effet joue")
	h.ok(abs(float(AudioA.journal[0]["amplitude"]) - plein) < 0.0001,
		"audio: la synthese a REELLEMENT applique l'amplitude pleine")
	h.ok(abs(float(AudioA.journal_musique[0]["amplitude"]) - plein_m) < 0.0001,
		"audio: la synthese musicale a REELLEMENT applique son amplitude")
	au.volume_effets = 0.0
	au.volume_musique = 0.0
	AudioA.reinitialiser_journal()
	au.jouer(un_cue, 1)
	au.jouer_musique(1, 1)
	h.eq(float(AudioA.journal[0]["amplitude"]), 0.0,
		"audio: volume coupe -> la synthese applique une amplitude NULLE")
	h.eq(float(AudioA.journal_musique[0]["amplitude"]), 0.0,
		"audio: musique coupee -> amplitude NULLE dans la synthese")

	# CHAINE COMPLETE : app_state (pourcentage) -> runtime (facteur) -> synthese.
	var appv: Dictionary = AppA.initial(1)
	appv = AppA.appliquer(appv, AppA.OUVRIR_OPTIONS, P.EN_COURS)
	appv = AppA.appliquer(appv, AppA.CYCLE_VOL_EFFETS, P.EN_COURS)   # 100 -> 0
	au.volume_effets = float(appv["vol_effets"]) / 100.0
	AudioA.reinitialiser_journal()
	au.jouer(un_cue, 2)
	h.eq(float(AudioA.journal[0]["amplitude"]), 0.0,
		"audio: MENU -> OPTIONS -> reglage -> RUNTIME : la chaine complete est branchee")
	au.free()

	# ---------- BAREME ----------
	h.eq(Score.points_pour({"kind": "bloc_detruit", "cellule": Vector2i.ZERO}, 0, false),
		Score.POINTS_BLOC, "score: un bloc detruit rapporte")
	h.eq(Score.points_pour({"kind": "powerup_ramasse", "acteur": 0, "effet": true}, 0, false),
		Score.POINTS_POWERUP, "score: un power-up UTILE rapporte")
	h.eq(Score.points_pour({"kind": "powerup_ramasse", "acteur": 0, "effet": false}, 0, false), 0,
		"score: un power-up SANS effet ne rapporte rien (sinon on apprend a farmer le plafond)")
	h.eq(Score.points_pour({"kind": "powerup_ramasse", "acteur": 1, "effet": true}, 0, false), 0,
		"score: le power-up d'un autre ne rapporte rien")
	h.eq(Score.points_pour({"kind": "mort", "victime": 1, "tueur": 0}, 0, false),
		Score.POINTS_ELIMINATION, "score: une elimination rapporte")
	h.eq(Score.points_pour({"kind": "mort", "victime": 0, "tueur": 0}, 0, false), 0,
		"score: se tuer soi-meme ne rapporte rien")
	h.eq(Score.points_pour({"kind": "fin", "statut": P.GAGNE}, 0, true),
		Score.POINTS_VICTOIRE, "score: la victoire porte une prime")
	h.eq(Score.points_pour({"kind": "fin", "statut": P.PERDU}, 0, false), 0,
		"score: une defaite ne prime rien")
	h.gt(Score.POINTS_ELIMINATION, Score.POINTS_BLOC * 10,
		"score: eliminer vaut plus que casser dix blocs — le bareme recompense l'objectif")

	# ---------- LE SCORE VIT DANS L'ETAT et suit une partie reelle ----------
	var s2 = Fx.etat(Fx.desc_blocs(), 3, 2)
	s2.acteurs[0]["rayon"] = 2
	h.eq(int(s2.score), 0, "score: une partie neuve part de zero")
	var s3 = s2
	s3 = Loop.step(s3, [P.POSER, P.AUCUNE])["state"]
	for i in range(P.MECHE_TICKS + 4):
		s3 = Loop.step(s3, [P.AUCUNE, P.AUCUNE])["state"]
	h.gt(int(s3.score), 0, "score: casser des blocs fait REELLEMENT monter le score en partie")
	h.eq(int(s3.clone().score), int(s3.score), "score: il survit au clone")
	h.eq(int(Fx.etat(Fx.desc_blocs(), 3, 2).score), 0, "score: une relance repart de zero")
