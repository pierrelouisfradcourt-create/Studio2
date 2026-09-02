# v2_schema_map_convention.test.gd — ligne schema.map_convention, capacites F94/F95.
# La CONVENTION vit dans la logique, les INSTANCES vivent dans la donnee : map_schema
# connait la legende fermee et les champs obligatoires, et AUCUNE carte.
extends RefCounted

const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")


func run(h) -> void:
	# LEGENDE FERMEE : chaque symbole declare a exactement un type.
	h.eq(Schema.LEGENDE.size(), 8, "schema.convention: huit symboles declares")
	h.eq(Schema.type_du_symbole("#"), Schema.Type.MUR, "schema.convention: diese = mur")
	h.eq(Schema.type_du_symbole(" "), Schema.Type.MUR, "schema.convention: vide = mur")
	h.eq(Schema.type_du_symbole("."), Schema.Type.COULOIR, "schema.convention: point = couloir")
	h.eq(Schema.type_du_symbole("o"), Schema.Type.COULOIR, "schema.convention: super = couloir")
	h.eq(Schema.type_du_symbole("_"), Schema.Type.COULOIR, "schema.convention: couloir nu")
	h.eq(Schema.type_du_symbole("H"), Schema.Type.MAISON, "schema.convention: maison")
	h.eq(Schema.type_du_symbole("-"), Schema.Type.MAISON, "schema.convention: porte de maison")
	h.eq(Schema.type_du_symbole("T"), Schema.Type.TUNNEL, "schema.convention: tunnel")
	h.eq(Schema.symbole_connu("Z"), false, "schema.convention: un symbole hors legende est inconnu")
	h.eq(Schema.type_du_symbole("Z"), Schema.Type.MUR,
		"schema.convention: un symbole inconnu ne devient jamais praticable")

	# COLLECTIBLES : seuls deux symboles en portent.
	h.eq(Schema.porte_pastille("."), true, "schema.convention: le point porte une pastille")
	h.eq(Schema.porte_super("o"), true, "schema.convention: le o porte une super-pastille")
	h.eq(Schema.porte_pastille("_"), false, "schema.convention: le couloir nu n'en porte pas")
	h.eq(Schema.porte_super("T"), false, "schema.convention: le tunnel n'en porte pas")

	# CHAMPS OBLIGATOIRES : la liste est declaree, le manque est NOMME.
	h.eq(Schema.CHAMPS_OBLIGATOIRES.size(), 8, "schema.convention: huit champs obligatoires")
	h.eq(Schema.champs_manquants({}).size(), 8, "schema.convention: un descripteur vide manque de tout")
	h.eq(Schema.champs_manquants({"id": "x"})[0], "nom",
		"schema.convention: le manque est nomme dans l'ordre declare")

	# La convention ne connait AUCUNE instance : elle construit depuis un plan RECU.
	var plan: Array = ["##", "._"]
	h.eq(Schema.largeur(plan), 2, "schema.convention: largeur derivee du plan recu")
	h.eq(Schema.hauteur(plan), 2, "schema.convention: hauteur derivee du plan recu")
	h.eq(Schema.table_des_types(plan).size(), 4, "schema.convention: table construite depuis le plan recu")
	h.eq(Schema.plan_rectangulaire(["##", "#"]), false, "schema.convention: un plan irregulier est refuse")
	h.eq(Schema.plan_rectangulaire([]), false, "schema.convention: un plan vide est refuse")

	# LECTURE DE COUPLES : une valeur malformee ne leve pas, elle retombe.
	h.eq(Schema.vecteur([3, 4]), Vector2i(3, 4), "schema.convention: couple lu")
	h.eq(Schema.vecteur([3]), Vector2i(0, 0), "schema.convention: couple malforme refuse")
	h.eq(Schema.vecteurs([[1, 2], [3, 4]]).size(), 2, "schema.convention: liste de couples lue")
	# --- GATE MUTATION : le plan de LARGEUR NULLE, et le couple malforme -------------
	# Un plan dont la premiere ligne est vide a une largeur de 0 : rectangulaire au sens
	# naif (toutes les lignes ont la meme longueur), mais inutilisable. La garde doit le
	# refuser, et c'est le cas de bord EXACT qui la distingue d'une garde a « < 0 ».
	h.eq(Schema.plan_rectangulaire([""]), false, "schema.convention: un plan de largeur nulle est refuse")
	h.eq(Schema.plan_rectangulaire(["", ""]), false, "schema.convention: meme a plusieurs lignes vides")
	h.eq(Schema.largeur([""]), 0, "schema.convention: sa largeur derivee vaut bien 0")
	h.eq(Schema.plan_rectangulaire(["#"]), true, "schema.convention: une largeur de 1 est acceptee")

	# Un couple TROP LONG est aussi malforme qu'un couple trop court : les deux membres
	# de la garde comptent.
	h.eq(Schema.vecteur([1, 2, 3]), Vector2i(0, 0), "schema.convention: un couple de trois est refuse")
	h.eq(Schema.vecteur([]), Vector2i(0, 0), "schema.convention: un couple vide est refuse")
	h.eq(Schema.vecteur([7, 9]), Vector2i(7, 9), "schema.convention: un couple exact est lu")
	h.eq(Schema.vecteurs([[1, 2], [3, 4, 5]])[1], Vector2i(0, 0),
		"schema.convention: dans une liste, seul le couple malforme retombe")
