"""Oracle du moteur de mutation testing (méta-oracle).

On teste la GÉNÉRATION de mutants (pure, rapide) ; l'exécution réelle par mutant
est lente (elle lance node) et n'est pas dans la suite unitaire.
"""
from forge.mutation import Mutant, generate_mutants


def test_generates_a_mutant_per_operator_occurrence():
    text = "if (a >= b && c === d) return true;\n"
    muts = generate_mutants(text)
    names = {m.name for m in muts}
    assert "ge->gt" in names        # >= -> >
    assert "and->or" in names       # && -> ||
    assert "eq->neq" in names       # === -> !==
    assert "true->false" in names   # true -> false


def test_mutant_actually_changes_the_code():
    text = "return score >= best;\n"
    m = next(m for m in generate_mutants(text) if m.name == "ge->gt")
    assert ">=" not in m.mutant_text          # l'occurrence a bien muté
    assert "score > best" in m.mutant_text
    assert isinstance(m, Mutant)


def test_skips_comment_only_lines():
    text = "// on garde le >= ici, ne pas muter\nx = a >= b;\n"
    muts = [m for m in generate_mutants(text) if m.name == "ge->gt"]
    assert len(muts) == 1                      # seule la vraie ligne de code est mutée
    assert muts[0].line == 2


def test_no_mutation_no_mutants():
    assert generate_mutants("const x = plainText();\n") == []


def test_skip_marker_excludes_equivalent_mutants():
    """Une ligne marquée `mutation:skip` (mutant prouvé équivalent) n'est pas mutée."""
    text = "a >= b;\nc >= d; // mutation:skip équivalent\n"
    muts = [m for m in generate_mutants(text) if m.name == "ge->gt"]
    assert len(muts) == 1        # seule la ligne non marquée est mutée
    assert muts[0].line == 1


def test_each_occurrence_is_its_own_mutant():
    text = "a >= b; c >= d;\n"                  # deux occurrences => deux mutants
    assert len([m for m in generate_mutants(text) if m.name == "ge->gt"]) == 2


def test_gdscript_and_or_mutes():
    """GDScript utilise and/or, pas &&/||. Sans ces regles, le gate mutation
    est edente sur .gd (cf. plan etape 0, tache 4)."""
    from forge.mutation import generate_mutants
    names = {m.name for m in generate_mutants("if a and b:\n")}
    assert "and->or" in names
    names = {m.name for m in generate_mutants("if a or b:\n")}
    assert "or->and" in names


def test_gdscript_equality_mutes():
    from forge.mutation import generate_mutants
    names = {m.name for m in generate_mutants("if hp == 0:\n")}
    assert "eqeq->neq" in names
    names = {m.name for m in generate_mutants("if hp != 0:\n")}
    assert "neq->eqeq" in names


def test_js_strict_equality_not_fragmented():
    """GARDE ANTI-REGRESSION : `===` ne doit jamais produire un mutant `==`->`!=`
    qui casserait la syntaxe JS. Les regles JS existantes restent prioritaires."""
    from forge.mutation import generate_mutants
    mutants = generate_mutants("if (a === b) {}\n")
    names = {m.name for m in mutants}
    assert "eq->neq" in names
    assert "eqeq->neq" not in names
    for m in mutants:
        assert "=!=" not in m.mutant_text
        assert "!===" not in m.mutant_text


def test_and_or_only_as_whole_words():
    """`and`/`or` ne doivent pas muter a l interieur d un identifiant
    (`operand`, `random`, `for`, `word`) — sinon avalanche de faux mutants."""
    from forge.mutation import generate_mutants
    for src in ["var operand = 1\n", "var random_x = 2\n", "var sword = 3\n"]:
        names = {m.name for m in generate_mutants(src)}
        assert "and->or" not in names
        assert "or->and" not in names


def test_gdscript_hash_comment_skipped_with_hash_prefix():
    """Correctif de revue : un commentaire GDScript pur (`#`) n'est pas mute
    quand les prefixes de commentaire incluent `#`."""
    from forge.mutation import generate_mutants
    text = "# si a and b vaut true\n"
    muts = generate_mutants(text, comment_prefixes=("//", "*", "/*", "#"))
    assert muts == []


def test_gdscript_hash_comment_still_mutates_with_default_prefixes():
    """Le meme texte produit toujours ses mutants avec les prefixes par defaut :
    preuve que le defaut est inchange (aucune regression JS/Rust)."""
    from forge.mutation import generate_mutants
    text = "# si a and b vaut true\n"
    names = {m.name for m in generate_mutants(text)}
    assert "and->or" in names
    assert "true->false" in names


def test_js_private_field_not_treated_as_comment():
    """Garde anti-faux-positif : un champ prive JS commencant par `#` apres
    indentation reste mute avec les prefixes par defaut. `#` n'est PAS ajoute
    a la liste globale des marqueurs de commentaire — en JS moderne il
    introduit un champ prive de classe, pas un commentaire."""
    from forge.mutation import generate_mutants
    text = "class Foo {\n  #alive = true;\n}\n"
    names = {m.name for m in generate_mutants(text)}
    assert "true->false" in names


def test_gdscript_trailing_comment_line_still_mutates_code_part():
    """Seul le commentaire PUR est exclu : une ligne de code portant un
    commentaire en fin de ligne reste mutee."""
    from forge.mutation import generate_mutants
    text = "if a and b: # remarque\n"
    names = {m.name for m in generate_mutants(text, comment_prefixes=("//", "*", "/*", "#"))}
    assert "and->or" in names


def test_comment_prefixes_for_extension():
    """run_mutation_test derive les prefixes depuis l'extension du fichier
    source : `.gd` et `.py` ajoutent `#`, tout le reste garde le defaut."""
    from forge.mutation import comment_prefixes_for
    assert "#" in comment_prefixes_for("foo.gd")
    assert "#" in comment_prefixes_for("foo.py")
    assert "#" not in comment_prefixes_for("foo.js")
    assert "#" not in comment_prefixes_for("foo.ts")
    assert "#" not in comment_prefixes_for("foo.rs")
