extends Node2D
# Snake classique - version minimale (Godot 4, GDScript)
# À attacher à un Node2D racine. Aucun fichier image nécessaire : tout est dessiné par le code.

const COLONNES := 38          # largeur de la grille (en cases) -> 912 px
const LIGNES := 26            # hauteur de la grille (en cases) -> 624 px
const TAILLE_CASE := 24       # taille d'une case (en pixels)
const ORIGINE_GRILLE := Vector2(24, 72)  # centrée dans 960x720, avec barre HUD de 72 px en haut
const DELAI_DEPART := 0.15    # secondes entre deux déplacements au départ
const DELAI_MINIMAL := 0.06   # vitesse maximale (délai le plus court)

# Paramètres des bonus aléatoires
const DELAI_BONUS_MIN := 4.0      # secondes min avant l'apparition d'un bonus
const DELAI_BONUS_MAX := 9.0      # secondes max avant l'apparition d'un bonus
const DUREE_VIE_BONUS := 12.0     # secondes avant qu'un bonus non ramassé disparaisse
const MAX_BONUS_SIMULTANES := 2   # nombre max de bonus présents en même temps sur la grille
const VIES_DEPART := 1
const MAX_VIES := 3               # plafond de vies pour éviter le farm infini
const COOLDOWN_VIE := 50.0        # délai minimum (en secondes) entre deux apparitions de Vie
const DUREE_FANTOME := 6.0        # secondes de Mode Fantôme (traverse murs et corps)
const DUREE_COMBO_X2 := 10.0      # secondes de Combo x2 (points doublés)
const DUREE_RALENTI := 6.0        # secondes de Ralenti (Slow-Mo)
const INTERVALLE_RALENTI := 60.0  # un bonus Ralenti apparaît toutes les 60 secondes
const FACTEUR_RALENTI := 1.75     # multiplicateur de délai pendant le Ralenti
const PALIER_POINTS_CISEAUX := 15 # un bonus Ciseaux apparaît tous les 15 points
const REDUCTION_CISEAUX := 5      # nombre de segments coupés par les Ciseaux
const TAILLE_MIN_SERPENT := 3

# Paramètres du mode Difficile (serpents ennemis par paires toutes les 90 s)
const INTERVALLE_ENNEMIS := 90.0
const DUREE_ALERTE_ENNEMIS := 2.5
const DELAI_PAS_ENNEMI := 0.095
const LONGUEUR_SERPENT_ENNEMI := 9

enum TypeBonus { BOUCLIER, VIE, FANTOME, COMBO_X2, RALENTI, CISEAUX }
enum EtatJeu { MENU, JEU, PAUSE, GAME_OVER }
enum Difficulte { FACILE, DIFFICILE }

# Poids d'apparition par bonus aléatoire (Ciseaux chaque 15 pts, Ralenti chaque 1 min)
const POIDS_BONUS := {
	TypeBonus.BOUCLIER: 35,
	TypeBonus.FANTOME: 30,
	TypeBonus.COMBO_X2: 25,
	TypeBonus.VIE: 10,
}

# Palette de couleurs (noir et blanc de base, rouge pour la nourriture, couleurs par bonus)
const COULEUR_FOND := Color("#000000")
const COULEUR_BORDURE := Color("#ffffff")
const COULEUR_TETE := Color("#ffffff")
const COULEUR_CORPS := Color("#cccccc")
const COULEUR_CONSOMMABLE := Color("#e52521")
const COULEUR_BOUCLIER := Color("#38bdf8")
const COULEUR_VIE := Color("#22c55e")
const COULEUR_FANTOME := Color("#a855f7")
const COULEUR_COMBO_X2 := Color("#facc15")
const COULEUR_RALENTI := Color("#f472b6")
const COULEUR_CISEAUX := Color("#fb923c")
const COULEUR_ENNEMI_TETE := Color("#ff2a2a")
const COULEUR_ENNEMI_CORPS := Color("#991b1b")
const COULEUR_TEXTE := Color("#ffffff")
const COULEUR_TEXTE_INACTIF := Color("#444444")
const CHEMIN_SAUVEGARDE := "user://snake_save.cfg"

var serpent: Array[Vector2i] = []          # serpent[0] = la tête
var direction := Vector2i.RIGHT
var file_directions: Array[Vector2i] = []  # directions demandées, appliquées au prochain pas
var nourriture := Vector2i.ZERO
var bonus_actifs: Array[Dictionary] = []   # [{ "pos": Vector2i, "type": TypeBonus, "temps_restant": float }]
var cooldown_vie_restant := 0.0            # temps restant avant qu'un bonus Vie puisse réapparaître
var temps_prochain_ralenti := INTERVALLE_RALENTI
var prochain_palier_ciseaux := PALIER_POINTS_CISEAUX
var vies := VIES_DEPART
var a_bouclier := false
var temps_fantome := 0.0
var temps_combo_x2 := 0.0
var temps_ralenti := 0.0
var difficulte := Difficulte.FACILE
var serpents_ennemis: Array[Dictionary] = [] # [{ "segments": Array[Vector2i], "dir": Vector2i }]
var alertes_ennemis: Array[Dictionary] = []  # [{ "entree": Vector2i, "dir": Vector2i, "temps_restant": float }]
var temps_prochaine_vague := INTERVALLE_ENNEMIS
var timer_pas_ennemi := 0.0
var temps_immunite_collision := 0.0
var score := 0
var meilleur_score := 0
var meilleurs_scores := {
	Difficulte.FACILE: 0,
	Difficulte.DIFFICILE: 0,
}
var nouveau_record := false
var etat_jeu := EtatJeu.MENU
var minuteur: Timer
var minuteur_bonus: Timer

# Audio moderne synthétisé (AudioStreamWAV + pool de lecteurs) + musique d'ambiance
const FREQ_AUDIO := 44100
const CHEMIN_MUSIQUE := "res://musique_ambiance.mp3"
const VOLUME_MUSIQUE_JEU := -13.0
const VOLUME_MUSIQUE_ATTENUE := -20.0
var lecteur_musique: AudioStreamPlayer
var lecteurs_audio: Array[AudioStreamPlayer] = []
var son_demarrer: AudioStreamWAV
var son_manger: AudioStreamWAV
var son_manger_x2: AudioStreamWAV
var son_bouclier: AudioStreamWAV
var son_vie: AudioStreamWAV
var son_fantome: AudioStreamWAV
var son_combo: AudioStreamWAV
var son_ralenti: AudioStreamWAV
var son_ciseaux: AudioStreamWAV
var son_bouclier_brise: AudioStreamWAV
var son_degat: AudioStreamWAV
var son_perdu: AudioStreamWAV
var son_alerte: AudioStreamWAV

# Effets visuels / Jutosité (Game Feel) & Polices
var police_ui: Font
var police_titre: Font
var particules: Array[Dictionary] = []        # [{ "pos": Vector2, "vel": Vector2, "taille": float, "couleur": Color, "vie": float, "vie_max": float }]
var textes_flottants: Array[Dictionary] = []  # [{ "pos": Vector2, "texte": String, "couleur": Color, "vie": float, "vie_max": float }]
var intensite_secousse := 0.0
var couleur_flash := Color.TRANSPARENT
var alpha_flash := 0.0
var temps_pause_respawn := 0.0                # micro-pause avec clignotement après perte d'une vie


func _ready() -> void:
	RenderingServer.set_default_clear_color(COULEUR_FOND)
	police_ui = load("res://fonts/FiraMono-Bold.otf") if ResourceLoader.exists("res://fonts/FiraMono-Bold.otf") else ThemeDB.fallback_font
	police_titre = load("res://fonts/FiraSansCondensed-Heavy.otf") if ResourceLoader.exists("res://fonts/FiraSansCondensed-Heavy.otf") else police_ui
	_charger_meilleur_score()
	_initialiser_audio()
	minuteur = Timer.new()
	minuteur.timeout.connect(_avancer)
	add_child(minuteur)

	minuteur_bonus = Timer.new()
	minuteur_bonus.one_shot = true
	minuteur_bonus.timeout.connect(_apparaitre_bonus)
	add_child(minuteur_bonus)

	_reinitialiser_serpent()
	_placer_nourriture()
	etat_jeu = EtatJeu.MENU
	_maj_volume_musique()
	queue_redraw()


func _process(delta: float) -> void:
	var modifie := false

	# 1. Expiration / clignotement des bonus, cooldown des vies et durées des pouvoirs actifs
	if etat_jeu == EtatJeu.JEU:
		if cooldown_vie_restant > 0.0:
			cooldown_vie_restant = maxf(0.0, cooldown_vie_restant - delta)
		temps_prochain_ralenti -= delta
		if temps_prochain_ralenti <= 0.0:
			temps_prochain_ralenti += INTERVALLE_RALENTI
			var case_ralenti := _trouver_case_libre()
			if case_ralenti != Vector2i(-1, -1):
				bonus_actifs.append({
					"pos": case_ralenti,
					"type": TypeBonus.RALENTI,
					"temps_restant": DUREE_VIE_BONUS,
				})
				_creer_particules(_centre_case(case_ralenti), COULEUR_RALENTI, 8, 90.0)
				modifie = true
		if temps_pause_respawn <= 0.0:
			if temps_fantome > 0.0:
				temps_fantome = maxf(0.0, temps_fantome - delta)
				modifie = true
			if temps_combo_x2 > 0.0:
				temps_combo_x2 = maxf(0.0, temps_combo_x2 - delta)
				modifie = true
			if temps_ralenti > 0.0:
				temps_ralenti = maxf(0.0, temps_ralenti - delta)
				if temps_ralenti == 0.0:
					_maj_vitesse()
				modifie = true
			if temps_immunite_collision > 0.0:
				temps_immunite_collision = maxf(0.0, temps_immunite_collision - delta)
			if difficulte == Difficulte.DIFFICILE:
				if temps_prochaine_vague > 0.0:
					temps_prochaine_vague -= delta
					if temps_prochaine_vague <= 0.0:
						temps_prochaine_vague += INTERVALLE_ENNEMIS
						_preparer_vague_ennemis()
						modifie = true
				for j in range(alertes_ennemis.size() - 1, -1, -1):
					alertes_ennemis[j]["temps_restant"] -= delta
					if alertes_ennemis[j]["temps_restant"] <= 0.0:
						var alerte: Dictionary = alertes_ennemis[j]
						alertes_ennemis.remove_at(j)
						_faire_apparaitre_serpent_ennemi(alerte["entree"], alerte["dir"])
					modifie = true
				if not serpents_ennemis.is_empty():
					var pas_ennemi := DELAI_PAS_ENNEMI * (FACTEUR_RALENTI if temps_ralenti > 0.0 else 1.0)
					timer_pas_ennemi += delta
					while timer_pas_ennemi >= pas_ennemi:
						timer_pas_ennemi -= pas_ennemi
						_avancer_ennemis()
						modifie = true
						if etat_jeu != EtatJeu.JEU or temps_pause_respawn > 0.0:
							break
		for i in range(bonus_actifs.size() - 1, -1, -1):
			bonus_actifs[i]["temps_restant"] -= delta
			if bonus_actifs[i]["temps_restant"] <= 0.0:
				bonus_actifs.remove_at(i)
				modifie = true
			elif bonus_actifs[i]["temps_restant"] <= 3.0:
				modifie = true

	# 2. Micro-pause après respawn d'une vie
	if temps_pause_respawn > 0.0 and etat_jeu == EtatJeu.JEU:
		temps_pause_respawn = maxf(0.0, temps_pause_respawn - delta)
		modifie = true
		if temps_pause_respawn == 0.0 and etat_jeu == EtatJeu.JEU:
			minuteur.start()

	# 3. Particules
	for i in range(particules.size() - 1, -1, -1):
		var p: Dictionary = particules[i]
		p["vie"] -= delta
		if p["vie"] <= 0.0:
			particules.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta
			p["vel"] *= pow(0.08, delta)  # freinage fluide
		modifie = true

	# 4. Textes flottants
	for i in range(textes_flottants.size() - 1, -1, -1):
		var t: Dictionary = textes_flottants[i]
		t["vie"] -= delta
		if t["vie"] <= 0.0:
			textes_flottants.remove_at(i)
		else:
			t["pos"].y -= 48.0 * delta
		modifie = true

	# 5. Secousse d'écran (screen-shake)
	if intensite_secousse > 0.0:
		intensite_secousse = maxf(0.0, intensite_secousse - delta * 36.0)
		modifie = true

	# 6. Flash d'écran
	if alpha_flash > 0.0:
		alpha_flash = maxf(0.0, alpha_flash - delta * 2.2)
		modifie = true

	if modifie:
		queue_redraw()


func _centre_case(case_grille: Vector2i) -> Vector2:
	return ORIGINE_GRILLE + Vector2(case_grille) * TAILLE_CASE + Vector2(TAILLE_CASE * 0.5, TAILLE_CASE * 0.5)


func _creer_particules(pos: Vector2, couleur: Color, nombre := 12, vitesse := 170.0) -> void:
	for _i in nombre:
		var angle := randf() * TAU
		var v := randf_range(vitesse * 0.35, vitesse)
		var duree := randf_range(0.28, 0.55)
		particules.append({
			"pos": pos,
			"vel": Vector2.from_angle(angle) * v,
			"taille": randf_range(3.0, 6.5),
			"couleur": couleur,
			"vie": duree,
			"vie_max": duree,
		})


func _creer_texte_flottant(pos: Vector2, texte: String, couleur: Color) -> void:
	textes_flottants.append({
		"pos": pos + Vector2(0, -8),
		"texte": texte,
		"couleur": couleur,
		"vie": 0.85,
		"vie_max": 0.85,
	})


func _declencher_secousse(force: float) -> void:
	intensite_secousse = maxf(intensite_secousse, force)


func _declencher_flash(couleur: Color, alpha := 0.25) -> void:
	couleur_flash = couleur
	alpha_flash = alpha


func _reinitialiser_serpent() -> void:
	var cx := COLONNES / 2
	var cy := LIGNES / 2
	serpent = [Vector2i(cx, cy), Vector2i(cx - 1, cy), Vector2i(cx - 2, cy)]
	direction = Vector2i.RIGHT
	file_directions.clear()


func _nouvelle_partie() -> void:
	_reinitialiser_serpent()
	bonus_actifs.clear()
	serpents_ennemis.clear()
	alertes_ennemis.clear()
	particules.clear()
	textes_flottants.clear()
	intensite_secousse = 0.0
	alpha_flash = 0.0
	temps_pause_respawn = 0.0
	cooldown_vie_restant = 0.0
	temps_prochain_ralenti = INTERVALLE_RALENTI
	temps_prochaine_vague = INTERVALLE_ENNEMIS
	timer_pas_ennemi = 0.0
	temps_immunite_collision = 0.0
	prochain_palier_ciseaux = PALIER_POINTS_CISEAUX
	vies = VIES_DEPART
	a_bouclier = false
	temps_fantome = 0.0
	temps_combo_x2 = 0.0
	temps_ralenti = 0.0
	score = 0
	meilleur_score = int(meilleurs_scores[difficulte])
	nouveau_record = false
	etat_jeu = EtatJeu.JEU
	_maj_volume_musique()
	_placer_nourriture()
	_maj_vitesse()
	minuteur.start()
	_planifier_prochain_bonus()
	queue_redraw()


func _maj_vitesse() -> void:
	var delai := maxf(DELAI_MINIMAL, DELAI_DEPART - score * 0.003)
	if temps_ralenti > 0.0:
		delai *= FACTEUR_RALENTI
	minuteur.wait_time = delai


func _planifier_prochain_bonus() -> void:
	minuteur_bonus.start(randf_range(DELAI_BONUS_MIN, DELAI_BONUS_MAX))


func _choisir_type_bonus() -> TypeBonus:
	var vie_deja_presente := false
	for bonus in bonus_actifs:
		if bonus["type"] == TypeBonus.VIE:
			vie_deja_presente = true
			break

	var candidats: Array[TypeBonus] = []
	var poids_total := 0
	for type_bonus in POIDS_BONUS:
		if type_bonus == TypeBonus.VIE:
			if vies >= MAX_VIES or cooldown_vie_restant > 0.0 or vie_deja_presente:
				continue
		candidats.append(type_bonus)
		poids_total += POIDS_BONUS[type_bonus]

	var tirage := randi_range(1, poids_total)
	var cumul := 0
	for type_bonus in candidats:
		cumul += POIDS_BONUS[type_bonus]
		if tirage <= cumul:
			return type_bonus
	return TypeBonus.BOUCLIER


func _apparaitre_bonus() -> void:
	if etat_jeu != EtatJeu.JEU:
		return
	if bonus_actifs.size() < MAX_BONUS_SIMULTANES:
		var case_libre := _trouver_case_libre()
		if case_libre != Vector2i(-1, -1):
			var type_choisi := _choisir_type_bonus()
			bonus_actifs.append({
				"pos": case_libre,
				"type": type_choisi,
				"temps_restant": DUREE_VIE_BONUS,
			})
			if type_choisi == TypeBonus.VIE:
				cooldown_vie_restant = COOLDOWN_VIE
			queue_redraw()
	_planifier_prochain_bonus()


func _basculer_pause() -> void:
	if etat_jeu == EtatJeu.JEU:
		etat_jeu = EtatJeu.PAUSE
		minuteur.paused = true
		minuteur_bonus.paused = true
		_maj_volume_musique()
		_jouer_son(son_demarrer, 0.85)
		queue_redraw()
	elif etat_jeu == EtatJeu.PAUSE:
		etat_jeu = EtatJeu.JEU
		minuteur.paused = false
		minuteur_bonus.paused = false
		_maj_volume_musique()
		_jouer_son(son_demarrer, 1.05)
		queue_redraw()


func _unhandled_input(evenement: InputEvent) -> void:
	if not (evenement is InputEventKey and evenement.pressed and not evenement.echo):
		return

	if etat_jeu == EtatJeu.MENU:
		if evenement.physical_keycode in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
			difficulte = Difficulte.DIFFICILE if difficulte == Difficulte.FACILE else Difficulte.FACILE
			meilleur_score = int(meilleurs_scores[difficulte])
			_jouer_son(son_demarrer, 1.15 if difficulte == Difficulte.DIFFICILE else 0.9)
			queue_redraw()
			return
		if evenement.keycode == KEY_ENTER or evenement.keycode == KEY_SPACE:
			_jouer_son(son_demarrer)
			_nouvelle_partie()
		return

	if etat_jeu == EtatJeu.GAME_OVER:
		if evenement.keycode == KEY_ENTER or evenement.keycode == KEY_SPACE:
			_jouer_son(son_demarrer)
			_nouvelle_partie()
		return

	if evenement.keycode == KEY_P or evenement.keycode == KEY_ESCAPE:
		_basculer_pause()
		return

	if etat_jeu == EtatJeu.PAUSE:
		if evenement.keycode == KEY_ENTER:
			minuteur.paused = false
			minuteur_bonus.paused = false
			_jouer_son(son_demarrer)
			_nouvelle_partie()
		return

	# physical_keycode : la touche W/A/S/D d'un clavier QWERTY correspond à Z/Q/S/D sur AZERTY
	var nouvelle_direction := Vector2i.ZERO
	match evenement.physical_keycode:
		KEY_UP, KEY_W:
			nouvelle_direction = Vector2i.UP
		KEY_DOWN, KEY_S:
			nouvelle_direction = Vector2i.DOWN
		KEY_LEFT, KEY_A:
			nouvelle_direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D:
			nouvelle_direction = Vector2i.RIGHT
	if nouvelle_direction == Vector2i.ZERO:
		return

	# On compare avec la dernière direction demandée : pas de demi-tour possible,
	# et on garde au plus 2 ordres en attente.
	var derniere_direction: Vector2i = direction
	if not file_directions.is_empty():
		derniere_direction = file_directions.back()
	if nouvelle_direction != derniere_direction and nouvelle_direction != -derniere_direction and file_directions.size() < 2:
		file_directions.append(nouvelle_direction)


func _avancer() -> void:
	# 1. appliquer la prochaine direction demandée
	if not file_directions.is_empty():
		direction = file_directions.pop_front()

	# 2. calculer la nouvelle case de la tête
	var nouvelle_tete: Vector2i = serpent[0] + direction
	var mange := nouvelle_tete == nourriture

	# 3. tester les collisions AVANT de bouger
	#    (si on ne mange pas, la queue va se libérer : sa case n'est pas dangereuse)
	var corps: Array = serpent if mange else serpent.slice(0, serpent.size() - 1)
	var touche_mur := nouvelle_tete.x < 0 or nouvelle_tete.x >= COLONNES or nouvelle_tete.y < 0 or nouvelle_tete.y >= LIGNES
	var touche_corps := nouvelle_tete in corps
	var touche_ennemi := temps_immunite_collision <= 0.0 and _case_sur_ennemi(nouvelle_tete)

	if touche_mur or touche_corps or touche_ennemi:
		var pos_impact := _centre_case(serpent[0])
		if temps_fantome > 0.0:
			# Mode Fantôme : traverse librement son corps, les ennemis et passe de l'autre côté des murs
			if touche_mur:
				nouvelle_tete = Vector2i(posmod(nouvelle_tete.x, COLONNES), posmod(nouvelle_tete.y, LIGNES))
				mange = nouvelle_tete == nourriture
		elif a_bouclier:
			# Le bouclier absorbe la collision : on traverse le corps/ennemi ou on passe de l'autre côté du mur
			a_bouclier = false
			temps_immunite_collision = 0.45
			_creer_particules(pos_impact, COULEUR_BOUCLIER, 18, 220.0)
			_creer_particules(pos_impact, COULEUR_TETE, 8, 150.0)
			_creer_texte_flottant(pos_impact, "BOUCLIER BRISÉ !", COULEUR_BOUCLIER)
			_declencher_secousse(8.0)
			_declencher_flash(COULEUR_BOUCLIER, 0.22)
			_jouer_son(son_bouclier_brise)
			if touche_mur:
				nouvelle_tete = Vector2i(posmod(nouvelle_tete.x, COLONNES), posmod(nouvelle_tete.y, LIGNES))
				mange = nouvelle_tete == nourriture
		elif vies > 1:
			# On perd une vie et on réapparaît au centre avec une micro-pause lisible
			vies -= 1
			serpents_ennemis.clear()
			alertes_ennemis.clear()
			_creer_particules(pos_impact, COULEUR_CONSOMMABLE, 18, 220.0)
			_creer_particules(pos_impact, COULEUR_TETE, 10, 160.0)
			_declencher_secousse(11.0)
			_declencher_flash(COULEUR_CONSOMMABLE, 0.30)
			_jouer_son(son_degat)
			_reinitialiser_serpent()
			_creer_texte_flottant(_centre_case(serpent[0]), "-1 VIE !", COULEUR_CONSOMMABLE)
			minuteur.stop()
			temps_pause_respawn = 0.65
			queue_redraw()
			return
		else:
			vies = 0
			_creer_particules(pos_impact, COULEUR_CONSOMMABLE, 22, 240.0)
			_creer_particules(pos_impact, COULEUR_TETE, 14, 180.0)
			_declencher_secousse(13.0)
			_declencher_flash(COULEUR_CONSOMMABLE, 0.35)
			_finir_partie()
			return

	# 4. déplacer : on ajoute la tête, et on retire la queue sauf si on mange
	serpent.push_front(nouvelle_tete)
	if mange:
		var points := 2 if temps_combo_x2 > 0.0 else 1
		score += points
		_verifier_record()
		_maj_vitesse()
		var pos_mange := _centre_case(nouvelle_tete)
		var couleur_effet := COULEUR_COMBO_X2 if points == 2 else COULEUR_CONSOMMABLE
		var texte_points := "+2 (x2)" if points == 2 else "+1"
		_creer_particules(pos_mange, couleur_effet, 10, 150.0)
		_creer_texte_flottant(pos_mange, texte_points, COULEUR_COMBO_X2 if points == 2 else COULEUR_TEXTE)
		_declencher_secousse(2.5)
		_jouer_son(son_manger_x2 if points == 2 else son_manger, randf_range(0.96, 1.06))
		_placer_nourriture()
		_verifier_palier_ciseaux()
	else:
		serpent.pop_back()

	# 5. vérifier si on ramasse un bonus
	_verifier_ramassage_bonus(nouvelle_tete)

	queue_redraw()


func _verifier_palier_ciseaux() -> void:
	if score < prochain_palier_ciseaux:
		return
	while score >= prochain_palier_ciseaux:
		prochain_palier_ciseaux += PALIER_POINTS_CISEAUX
	var case_libre := _trouver_case_libre()
	if case_libre != Vector2i(-1, -1):
		bonus_actifs.append({
			"pos": case_libre,
			"type": TypeBonus.CISEAUX,
			"temps_restant": DUREE_VIE_BONUS,
		})
		_creer_particules(_centre_case(case_libre), COULEUR_CISEAUX, 8, 90.0)


func _verifier_ramassage_bonus(position_tete: Vector2i) -> void:
	for i in range(bonus_actifs.size() - 1, -1, -1):
		if bonus_actifs[i]["pos"] == position_tete:
			var type_bonus: TypeBonus = bonus_actifs[i]["type"]
			var pos_bonus := _centre_case(position_tete)
			bonus_actifs.remove_at(i)
			match type_bonus:
				TypeBonus.BOUCLIER:
					_creer_particules(pos_bonus, COULEUR_BOUCLIER, 14, 180.0)
					_declencher_secousse(3.5)
					_jouer_son(son_bouclier)
					if a_bouclier:
						score += 2                            # déjà un bouclier : petit bonus de points
						_verifier_record()
						_verifier_palier_ciseaux()
						_creer_texte_flottant(pos_bonus, "+2", COULEUR_BOUCLIER)
					else:
						a_bouclier = true
						_creer_texte_flottant(pos_bonus, "BOUCLIER !", COULEUR_BOUCLIER)
				TypeBonus.VIE:
					_creer_particules(pos_bonus, COULEUR_VIE, 14, 180.0)
					_declencher_secousse(3.5)
					_jouer_son(son_vie)
					if vies < MAX_VIES:
						vies += 1
						_creer_texte_flottant(pos_bonus, "+1 VIE !", COULEUR_VIE)
					else:
						score += 3
						_verifier_record()
						_verifier_palier_ciseaux()
						_creer_texte_flottant(pos_bonus, "+3", COULEUR_VIE)
				TypeBonus.FANTOME:
					temps_fantome = DUREE_FANTOME
					_creer_particules(pos_bonus, COULEUR_FANTOME, 16, 190.0)
					_creer_texte_flottant(pos_bonus, "FANTÔME !", COULEUR_FANTOME)
					_declencher_secousse(3.5)
					_declencher_flash(COULEUR_FANTOME, 0.16)
					_jouer_son(son_fantome)
				TypeBonus.COMBO_X2:
					temps_combo_x2 = DUREE_COMBO_X2
					_creer_particules(pos_bonus, COULEUR_COMBO_X2, 16, 190.0)
					_creer_texte_flottant(pos_bonus, "COMBO x2 !", COULEUR_COMBO_X2)
					_declencher_secousse(3.5)
					_declencher_flash(COULEUR_COMBO_X2, 0.16)
					_jouer_son(son_combo)
				TypeBonus.RALENTI:
					temps_ralenti = DUREE_RALENTI
					_maj_vitesse()
					_creer_particules(pos_bonus, COULEUR_RALENTI, 16, 190.0)
					_creer_texte_flottant(pos_bonus, "RALENTI !", COULEUR_RALENTI)
					_declencher_secousse(3.5)
					_declencher_flash(COULEUR_RALENTI, 0.16)
					_jouer_son(son_ralenti)
				TypeBonus.CISEAUX:
					var coupes := mini(REDUCTION_CISEAUX, maxi(0, serpent.size() - TAILLE_MIN_SERPENT))
					for _k in coupes:
						var queue_coupee: Vector2i = serpent.pop_back()
						_creer_particules(_centre_case(queue_coupee), COULEUR_CISEAUX, 6, 120.0)
					_creer_particules(pos_bonus, COULEUR_CISEAUX, 14, 180.0)
					_creer_texte_flottant(pos_bonus, "-%d QUEUE !" % coupes if coupes > 0 else "CISEAUX !", COULEUR_CISEAUX)
					_declencher_secousse(4.5)
					_declencher_flash(COULEUR_CISEAUX, 0.14)
					_jouer_son(son_ciseaux)


func _preparer_vague_ennemis() -> void:
	var horizontal := randi() % 2 == 0
	if horizontal:
		var y1 := randi_range(2, LIGNES - 3)
		var y2 := posmod(y1 + randi_range(5, 10), LIGNES - 4) + 2
		if y2 == y1:
			y2 = posmod(y1 + 6, LIGNES - 4) + 2
		alertes_ennemis.append({"entree": Vector2i(0, y1), "dir": Vector2i.RIGHT, "temps_restant": DUREE_ALERTE_ENNEMIS})
		alertes_ennemis.append({"entree": Vector2i(COLONNES - 1, y2), "dir": Vector2i.LEFT, "temps_restant": DUREE_ALERTE_ENNEMIS})
	else:
		var x1 := randi_range(2, COLONNES - 3)
		var x2 := posmod(x1 + randi_range(6, 12), COLONNES - 4) + 2
		if x2 == x1:
			x2 = posmod(x1 + 8, COLONNES - 4) + 2
		alertes_ennemis.append({"entree": Vector2i(x1, 0), "dir": Vector2i.DOWN, "temps_restant": DUREE_ALERTE_ENNEMIS})
		alertes_ennemis.append({"entree": Vector2i(x2, LIGNES - 1), "dir": Vector2i.UP, "temps_restant": DUREE_ALERTE_ENNEMIS})
	_jouer_son(son_alerte)


func _faire_apparaitre_serpent_ennemi(entree: Vector2i, dir: Vector2i) -> void:
	var segments: Array[Vector2i] = []
	for k in LONGUEUR_SERPENT_ENNEMI:
		segments.append(entree - dir * k)
	serpents_ennemis.append({
		"segments": segments,
		"dir": dir,
	})


func _est_dans_grille(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLONNES and c.y >= 0 and c.y < LIGNES


func _avancer_ennemis() -> void:
	for i in range(serpents_ennemis.size() - 1, -1, -1):
		var ennemi: Dictionary = serpents_ennemis[i]
		var segments: Array[Vector2i] = ennemi["segments"]
		var dir: Vector2i = ennemi["dir"]
		var nouvelle_tete := segments[0] + dir
		segments.push_front(nouvelle_tete)
		segments.pop_back()

		var encore_visible := false
		for seg in segments:
			if _est_dans_grille(seg):
				encore_visible = true
				break
		if not encore_visible:
			serpents_ennemis.remove_at(i)
			continue

		if temps_fantome <= 0.0 and temps_immunite_collision <= 0.0 and nouvelle_tete == serpent[0]:
			_gerer_collision_ennemi()
			if etat_jeu != EtatJeu.JEU or temps_pause_respawn > 0.0:
				return


func _case_sur_ennemi(case_pos: Vector2i) -> bool:
	for ennemi in serpents_ennemis:
		if case_pos in ennemi["segments"]:
			return true
	return false


func _gerer_collision_ennemi() -> void:
	var pos_impact := _centre_case(serpent[0])
	if a_bouclier:
		a_bouclier = false
		temps_immunite_collision = 0.45
		_creer_particules(pos_impact, COULEUR_BOUCLIER, 18, 220.0)
		_creer_particules(pos_impact, COULEUR_TETE, 8, 150.0)
		_creer_texte_flottant(pos_impact, "BOUCLIER BRISÉ !", COULEUR_BOUCLIER)
		_declencher_secousse(8.0)
		_declencher_flash(COULEUR_BOUCLIER, 0.22)
		_jouer_son(son_bouclier_brise)
	elif vies > 1:
		vies -= 1
		serpents_ennemis.clear()
		alertes_ennemis.clear()
		_creer_particules(pos_impact, COULEUR_CONSOMMABLE, 18, 220.0)
		_creer_particules(pos_impact, COULEUR_TETE, 10, 160.0)
		_declencher_secousse(11.0)
		_declencher_flash(COULEUR_CONSOMMABLE, 0.30)
		_jouer_son(son_degat)
		_reinitialiser_serpent()
		_creer_texte_flottant(_centre_case(serpent[0]), "-1 VIE !", COULEUR_CONSOMMABLE)
		minuteur.stop()
		temps_pause_respawn = 0.65
	else:
		vies = 0
		_creer_particules(pos_impact, COULEUR_CONSOMMABLE, 22, 240.0)
		_creer_particules(pos_impact, COULEUR_TETE, 14, 180.0)
		_declencher_secousse(13.0)
		_declencher_flash(COULEUR_CONSOMMABLE, 0.35)
		_finir_partie()


func _trouver_case_libre(eviter_nourriture := true) -> Vector2i:
	var occupees := {}
	for segment in serpent:
		occupees[segment] = true
	for ennemi in serpents_ennemis:
		for seg in ennemi["segments"]:
			occupees[seg] = true
	if eviter_nourriture:
		occupees[nourriture] = true
	for bonus in bonus_actifs:
		occupees[bonus["pos"]] = true

	var cases_libres: Array[Vector2i] = []
	for x in COLONNES:
		for y in LIGNES:
			var une_case := Vector2i(x, y)
			if not occupees.has(une_case):
				cases_libres.append(une_case)
	if cases_libres.is_empty():
		return Vector2i(-1, -1)
	return cases_libres.pick_random()


func _placer_nourriture() -> void:
	# On choisit parmi les cases libres : la nourriture n'apparaît jamais sur le serpent ou un bonus.
	var case_libre := _trouver_case_libre(false)
	if case_libre == Vector2i(-1, -1):
		_finir_partie()  # grille pleine : victoire
		return
	nourriture = case_libre


func _charger_meilleur_score() -> void:
	var config := ConfigFile.new()
	if config.load(CHEMIN_SAUVEGARDE) == OK:
		meilleurs_scores[Difficulte.FACILE] = int(config.get_value("scores", "facile", config.get_value("scores", "meilleur", 0)))
		meilleurs_scores[Difficulte.DIFFICILE] = int(config.get_value("scores", "difficile", 0))
	meilleur_score = int(meilleurs_scores[difficulte])


func _sauvegarder_meilleur_score() -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "facile", meilleurs_scores[Difficulte.FACILE])
	config.set_value("scores", "difficile", meilleurs_scores[Difficulte.DIFFICILE])
	config.save(CHEMIN_SAUVEGARDE)


func _verifier_record() -> void:
	if score > meilleur_score:
		meilleur_score = score
		meilleurs_scores[difficulte] = score
		nouveau_record = true


func _finir_partie() -> void:
	_verifier_record()
	if nouveau_record:
		_sauvegarder_meilleur_score()
	etat_jeu = EtatJeu.GAME_OVER
	minuteur.stop()
	minuteur_bonus.stop()
	_maj_volume_musique()
	_jouer_son(son_perdu)
	queue_redraw()


func _maj_volume_musique() -> void:
	if lecteur_musique == null:
		return
	lecteur_musique.volume_db = VOLUME_MUSIQUE_JEU if etat_jeu == EtatJeu.JEU else VOLUME_MUSIQUE_ATTENUE


func _initialiser_audio() -> void:
	lecteur_musique = AudioStreamPlayer.new()
	lecteur_musique.volume_db = VOLUME_MUSIQUE_ATTENUE
	add_child(lecteur_musique)
	if ResourceLoader.exists(CHEMIN_MUSIQUE):
		var musique := load(CHEMIN_MUSIQUE)
		if musique is AudioStreamMP3:
			musique.loop = true
		lecteur_musique.stream = musique
		lecteur_musique.finished.connect(func() -> void: lecteur_musique.play())
		lecteur_musique.play()

	for _i in 8:
		var lecteur := AudioStreamPlayer.new()
		lecteur.volume_db = -6.0
		add_child(lecteur)
		lecteurs_audio.append(lecteur)

	son_demarrer = _creer_son_notes([523.25, 659.25], 0.08, 0.35, 1.0)
	son_manger = _creer_son_notes([587.33, 880.0], 0.055, 0.38, 1.15)
	son_manger_x2 = _creer_son_notes([659.25, 987.77, 1318.51], 0.05, 0.40, 1.2)
	son_bouclier = _creer_son_notes([440.0, 554.37, 659.25, 880.0], 0.075, 0.35, 1.0)
	son_vie = _creer_son_notes([523.25, 659.25, 783.99, 1046.50], 0.08, 0.38, 1.0)
	son_fantome = _creer_son_whoosh(340.0, 760.0, 0.36, 0.35)
	son_combo = _creer_son_notes([587.33, 739.99, 880.0, 1174.66], 0.065, 0.38, 1.0)
	son_ralenti = _creer_son_notes([783.99, 587.33, 440.0], 0.095, 0.36, 0.94)
	son_ciseaux = _creer_son_notes([1046.50, 1318.51], 0.04, 0.38, 0.85)
	son_bouclier_brise = _creer_son_impact(320.0, 95.0, 0.24, 0.28, 0.45)
	son_degat = _creer_son_impact(180.0, 52.0, 0.32, 0.35, 0.50)
	son_perdu = _creer_son_notes([392.0, 349.23, 311.13, 261.63], 0.14, 0.40, 0.96)
	son_alerte = _creer_son_notes([880.0, 880.0], 0.14, 0.36, 1.0)


func _jouer_son(flux: AudioStreamWAV, pitch := 1.0) -> void:
	if flux == null:
		return
	for lecteur in lecteurs_audio:
		if not lecteur.playing:
			lecteur.stream = flux
			lecteur.pitch_scale = pitch
			lecteur.play()
			return
	lecteurs_audio[0].stream = flux
	lecteurs_audio[0].pitch_scale = pitch
	lecteurs_audio[0].play()


func _creer_wav_depuis_echantillons(echantillons: PackedFloat32Array) -> AudioStreamWAV:
	var donnees := PackedByteArray()
	donnees.resize(echantillons.size() * 2)
	for i in echantillons.size():
		var val := int(clampf(echantillons[i], -1.0, 1.0) * 32767.0)
		donnees.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = FREQ_AUDIO
	wav.stereo = false
	wav.data = donnees
	return wav


func _creer_son_notes(notes: Array, duree_note: float, volume: float, glissando := 1.0) -> AudioStreamWAV:
	var total := int(notes.size() * duree_note * FREQ_AUDIO) + int(0.12 * FREQ_AUDIO)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for n_idx in notes.size():
		var freq: float = notes[n_idx]
		var debut := int(n_idx * duree_note * FREQ_AUDIO)
		var duree := duree_note + 0.11
		var nb := int(duree * FREQ_AUDIO)
		var phase := 0.0
		for i in nb:
			if debut + i >= total:
				break
			var t := float(i) / FREQ_AUDIO
			var f_courante := lerpf(freq, freq * glissando, clampf(t / duree, 0.0, 1.0))
			phase += TAU * f_courante / FREQ_AUDIO
			var env := minf(t / 0.005, 1.0) * exp(-t * 14.0)
			# Synthé doux moderne (fondamentale + harmoniques légères, sans onde carrée agressive)
			var onde := sin(phase) + 0.25 * sin(phase * 2.0) + 0.08 * sin(phase * 3.0)
			buf[debut + i] += onde * env * volume * 0.65
	return _creer_wav_depuis_echantillons(buf)


func _creer_son_whoosh(freq_debut: float, freq_fin: float, duree: float, volume: float) -> AudioStreamWAV:
	var total := int(duree * FREQ_AUDIO)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var phase := 0.0
	var phase_lfo := 0.0
	var filtre_bruit := 0.0
	for i in total:
		var t := float(i) / FREQ_AUDIO
		var p := t / duree
		var freq := lerpf(freq_debut, freq_fin, p)
		phase += TAU * freq / FREQ_AUDIO
		phase_lfo += TAU * 18.0 / FREQ_AUDIO
		var env := sin(p * PI) * (1.0 - p * 0.25)
		filtre_bruit = lerpf(filtre_bruit, randf_range(-1.0, 1.0), 0.12)
		var onde := sin(phase + 0.6 * sin(phase_lfo)) * 0.7 + filtre_bruit * 0.35
		buf[i] = onde * env * volume
	return _creer_wav_depuis_echantillons(buf)


func _creer_son_impact(freq_debut: float, freq_fin: float, duree: float, bruit: float, volume: float) -> AudioStreamWAV:
	var total := int(duree * FREQ_AUDIO)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var phase := 0.0
	var filtre_bruit := 0.0
	for i in total:
		var t := float(i) / FREQ_AUDIO
		var p := t / duree
		var freq := lerpf(freq_debut, freq_fin, pow(p, 0.45))
		phase += TAU * freq / FREQ_AUDIO
		var env := minf(t / 0.003, 1.0) * exp(-t * 10.5)
		filtre_bruit = lerpf(filtre_bruit, randf_range(-1.0, 1.0), 0.25)
		var onde := sin(phase) * 0.8 + filtre_bruit * bruit * exp(-t * 18.0)
		buf[i] = onde * env * volume
	return _creer_wav_depuis_echantillons(buf)


func _dessiner_forme_bonus(type_bonus: TypeBonus, centre: Vector2, demi: float) -> void:
	match type_bonus:
		TypeBonus.BOUCLIER:
			# Losange bleu cyan avec contour blanc
			var losange := PackedVector2Array([
				centre + Vector2(0, -demi),
				centre + Vector2(demi, 0),
				centre + Vector2(0, demi),
				centre + Vector2(-demi, 0),
			])
			draw_colored_polygon(losange, COULEUR_BOUCLIER)
			var contour := PackedVector2Array([losange[0], losange[1], losange[2], losange[3], losange[0]])
			draw_polyline(contour, COULEUR_TETE, 1.5, true)
		TypeBonus.VIE:
			# Croix verte (+)
			var epaisseur := demi * 0.6
			var longueur := demi * 1.8
			draw_rect(Rect2(centre.x - epaisseur * 0.5, centre.y - longueur * 0.5, epaisseur, longueur), COULEUR_VIE)
			draw_rect(Rect2(centre.x - longueur * 0.5, centre.y - epaisseur * 0.5, longueur, epaisseur), COULEUR_VIE)
		TypeBonus.FANTOME:
			# Anneau violet (cercle creux) avec point central blanc
			draw_arc(centre, demi - 1.0, 0.0, TAU, 24, COULEUR_FANTOME, 3.0, true)
			draw_circle(centre, 2.5, COULEUR_TETE)
		TypeBonus.COMBO_X2:
			# Triangle doré pointé vers le haut
			var triangle := PackedVector2Array([
				centre + Vector2(0, -demi),
				centre + Vector2(demi, demi * 0.85),
				centre + Vector2(-demi, demi * 0.85),
			])
			draw_colored_polygon(triangle, COULEUR_COMBO_X2)
			var contour_tri := PackedVector2Array([triangle[0], triangle[1], triangle[2], triangle[0]])
			draw_polyline(contour_tri, COULEUR_TETE, 1.2, true)
		TypeBonus.RALENTI:
			# Sablier rose néon (deux triangles opposés)
			var sablier_haut := PackedVector2Array([
				centre + Vector2(-demi * 0.85, -demi),
				centre + Vector2(demi * 0.85, -demi),
				centre,
			])
			var sablier_bas := PackedVector2Array([
				centre,
				centre + Vector2(demi * 0.85, demi),
				centre + Vector2(-demi * 0.85, demi),
			])
			draw_colored_polygon(sablier_haut, COULEUR_RALENTI)
			draw_colored_polygon(sablier_bas, COULEUR_RALENTI)
			draw_polyline(PackedVector2Array([sablier_haut[0], sablier_haut[1], sablier_bas[2], sablier_bas[1], sablier_haut[0]]), COULEUR_TETE, 1.2, true)
		TypeBonus.CISEAUX:
			# Deux lames croisées en X orange néon
			var d := demi * 0.82
			draw_line(centre + Vector2(-d, -d), centre + Vector2(d, d), COULEUR_CISEAUX, 3.2, true)
			draw_line(centre + Vector2(d, -d), centre + Vector2(-d, d), COULEUR_CISEAUX, 3.2, true)
			draw_circle(centre, 2.2, COULEUR_TETE)


func _dessiner_bonus(bonus: Dictionary) -> void:
	var temps_restant: float = bonus["temps_restant"]
	# Clignotement dans les 3 dernières secondes avant disparition
	if temps_restant <= 3.0 and int(temps_restant * 6.0) % 2 == 0:
		return

	var origine := ORIGINE_GRILLE + Vector2(bonus["pos"]) * TAILLE_CASE
	var centre := origine + Vector2(TAILLE_CASE * 0.5, TAILLE_CASE * 0.5)
	var demi := TAILLE_CASE * 0.5 - 2.0
	_dessiner_forme_bonus(bonus["type"], centre, demi)


func _draw() -> void:
	var largeur_arene := COLONNES * TAILLE_CASE
	var hauteur_arene := LIGNES * TAILLE_CASE
	var rect_arene := Rect2(ORIGINE_GRILLE, Vector2(largeur_arene, hauteur_arene))
	var police := police_ui if police_ui != null else ThemeDB.fallback_font
	var titre_font := police_titre if police_titre != null else police

	# Appliquer la secousse d'écran à l'arène et aux effets
	var decalage_secousse := Vector2.ZERO
	if intensite_secousse > 0.0:
		decalage_secousse = Vector2(
			randf_range(-intensite_secousse, intensite_secousse),
			randf_range(-intensite_secousse, intensite_secousse)
		)
	draw_set_transform(decalage_secousse)

	# 1. Fond de l'arène (noir pur sans grille)
	draw_rect(rect_arene, COULEUR_FOND)

	# 2. Nourriture normale (carré rouge)
	draw_rect(Rect2(ORIGINE_GRILLE + Vector2(nourriture) * TAILLE_CASE + Vector2(2, 2), Vector2(TAILLE_CASE - 4, TAILLE_CASE - 4)), COULEUR_CONSOMMABLE)

	# 4. Bonus aléatoires
	for bonus in bonus_actifs:
		_dessiner_bonus(bonus)

	# 4b. Alertes d'arrivée des serpents ennemis (mode Difficile)
	for alerte in alertes_ennemis:
		var t_alerte: float = alerte["temps_restant"]
		var entree: Vector2i = alerte["entree"]
		var dir_ennemi: Vector2i = alerte["dir"]
		var centre_entree := _centre_case(entree)
		# Ligne de trajectoire discrète
		var fin_ligne := centre_entree + Vector2(dir_ennemi) * float(maxi(COLONNES, LIGNES) * TAILLE_CASE)
		fin_ligne.x = clampf(fin_ligne.x, ORIGINE_GRILLE.x, ORIGINE_GRILLE.x + largeur_arene)
		fin_ligne.y = clampf(fin_ligne.y, ORIGINE_GRILLE.y, ORIGINE_GRILLE.y + hauteur_arene)
		draw_line(centre_entree, fin_ligne, Color(COULEUR_ENNEMI_TETE.r, COULEUR_ENNEMI_TETE.g, COULEUR_ENNEMI_TETE.b, 0.22), 2.0)
		if int(t_alerte * 8.0) % 2 == 0:
			draw_rect(Rect2(ORIGINE_GRILLE + Vector2(entree) * TAILLE_CASE + Vector2(2, 2), Vector2(TAILLE_CASE - 4, TAILLE_CASE - 4)), COULEUR_ENNEMI_TETE, false, 2.0)
			draw_string(police, Vector2(centre_entree.x - 10.0, centre_entree.y + 6.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 18, COULEUR_ENNEMI_TETE)

	# 4c. Serpents ennemis (mode Difficile)
	for ennemi in serpents_ennemis:
		var segs: Array[Vector2i] = ennemi["segments"]
		for k in segs.size():
			if not _est_dans_grille(segs[k]):
				continue
			var couleur_e := COULEUR_ENNEMI_TETE if k == 0 else COULEUR_ENNEMI_CORPS
			var rect_e := Rect2(ORIGINE_GRILLE + Vector2(segs[k]) * TAILLE_CASE + Vector2(1, 1), Vector2(TAILLE_CASE - 2, TAILLE_CASE - 2))
			draw_rect(rect_e, couleur_e)
			if k == 0:
				draw_rect(rect_e, COULEUR_TETE, false, 1.5)

	# 5. Serpent (clignote pendant la micro-pause après respawn, translucide violet en Mode Fantôme)
	var afficher_serpent := temps_pause_respawn <= 0.0 or int(temps_pause_respawn * 14.0) % 2 == 0
	var en_fantome := temps_fantome > 0.0
	if afficher_serpent:
		for i in serpent.size():
			var couleur := COULEUR_TETE if i == 0 else COULEUR_CORPS
			if en_fantome:
				couleur = couleur.lerp(COULEUR_FANTOME, 0.45)
				couleur.a = 0.6
			var rect_segment := Rect2(ORIGINE_GRILLE + Vector2(serpent[i]) * TAILLE_CASE + Vector2(1, 1), Vector2(TAILLE_CASE - 2, TAILLE_CASE - 2))
			draw_rect(rect_segment, couleur)
			if en_fantome:
				draw_rect(rect_segment, COULEUR_FANTOME, false, 1.5)
			if i == 0 and a_bouclier:
				draw_rect(rect_segment, COULEUR_BOUCLIER, false, 2.5)

	# 6. Particules / éclats
	for p in particules:
		var ratio: float = clampf(p["vie"] / p["vie_max"], 0.0, 1.0)
		var c: Color = p["couleur"]
		c.a = ratio
		var t: float = p["taille"] * (0.4 + 0.6 * ratio)
		var pos: Vector2 = p["pos"]
		draw_rect(Rect2(pos.x - t * 0.5, pos.y - t * 0.5, t, t), c)

	# 7. Textes flottants
	for tf in textes_flottants:
		var ratio: float = clampf(tf["vie"] / tf["vie_max"], 0.0, 1.0)
		var c: Color = tf["couleur"]
		c.a = ratio
		var pos: Vector2 = tf["pos"]
		draw_string(police, Vector2(pos.x - 80.0, pos.y), tf["texte"], HORIZONTAL_ALIGNMENT_CENTER, 160.0, 16, c)

	# 8. Flash d'écran dans l'arène
	if alpha_flash > 0.0:
		var c_flash := couleur_flash
		c_flash.a = alpha_flash
		draw_rect(rect_arene, c_flash)

	# 9. Bordure blanche nette autour de l'arène
	draw_rect(rect_arene, COULEUR_BORDURE, false, 2.0)

	# Remise à zéro de la transformation pour que le HUD reste stable
	draw_set_transform(Vector2.ZERO)

	# 10. Barre HUD en haut (au-dessus de l'arène)
	var y_hud := 44.0
	var texte_score := "SCORE : %d  |  RECORD : %d" % [score, meilleur_score]
	if temps_combo_x2 > 0.0:
		texte_score += "  x2 (%.0fs)" % ceilf(temps_combo_x2)
	var couleur_score := COULEUR_COMBO_X2 if temps_combo_x2 > 0.0 else COULEUR_TEXTE
	draw_string(police, Vector2(ORIGINE_GRILLE.x, y_hud), texte_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, couleur_score)
	draw_string(police, Vector2(ORIGINE_GRILLE.x, y_hud), "VIES : %d/%d" % [vies, MAX_VIES], HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 22, COULEUR_VIE if vies > 1 else COULEUR_TEXTE)

	var statuts_droite: Array[String] = []
	var couleur_droite := COULEUR_TEXTE_INACTIF
	if difficulte == Difficulte.DIFFICILE:
		if not alertes_ennemis.is_empty() or not serpents_ennemis.is_empty():
			statuts_droite.append("ALERTE !")
			couleur_droite = COULEUR_ENNEMI_TETE
		else:
			statuts_droite.append("VAGUE %.0fs" % ceilf(temps_prochaine_vague))
			couleur_droite = COULEUR_TEXTE
	if temps_ralenti > 0.0:
		statuts_droite.append("RALENTI %.0fs" % ceilf(temps_ralenti))
		couleur_droite = COULEUR_RALENTI
	if temps_fantome > 0.0:
		statuts_droite.append("FANTÔME %.0fs" % ceilf(temps_fantome))
		couleur_droite = COULEUR_FANTOME
	if a_bouclier:
		statuts_droite.append("BOUCLIER")
		if temps_fantome <= 0.0 and temps_ralenti <= 0.0:
			couleur_droite = COULEUR_BOUCLIER
	var texte_droite := " | ".join(statuts_droite) if not statuts_droite.is_empty() else "POUVOIRS : --"
	draw_string(police, Vector2(ORIGINE_GRILLE.x, y_hud), texte_droite, HORIZONTAL_ALIGNMENT_RIGHT, largeur_arene, 20, couleur_droite)

	# 11. Écrans d'état (Menu Titre, Pause, Game Over)
	if etat_jeu == EtatJeu.MENU:
		draw_rect(rect_arene, Color(0, 0, 0, 0.86))
		var y_base := ORIGINE_GRILLE.y + 68.0
		draw_string(titre_font, Vector2(ORIGINE_GRILLE.x, y_base), "SNAKE",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 62, COULEUR_TETE)
		draw_string(police, Vector2(ORIGINE_GRILLE.x, y_base + 30), "ÉDITION NÉON",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 16, COULEUR_CONSOMMABLE)

		# Sélecteur de difficulté (FACILE / DIFFICILE)
		var y_diff := y_base + 66.0
		var label_facile := "[ FACILE ]" if difficulte == Difficulte.FACILE else "  FACILE  "
		var label_difficile := "[ DIFFICILE ]" if difficulte == Difficulte.DIFFICILE else "  DIFFICILE  "
		var centre_x := ORIGINE_GRILLE.x + largeur_arene * 0.5
		draw_string(police, Vector2(centre_x - 210.0, y_diff), label_facile,
			HORIZONTAL_ALIGNMENT_RIGHT, 190.0, 20, COULEUR_VIE if difficulte == Difficulte.FACILE else COULEUR_TEXTE_INACTIF)
		draw_string(police, Vector2(centre_x + 20.0, y_diff), label_difficile,
			HORIZONTAL_ALIGNMENT_LEFT, 210.0, 20, COULEUR_ENNEMI_TETE if difficulte == Difficulte.DIFFICILE else COULEUR_TEXTE_INACTIF)
		var desc_diff := "Classique sans ennemis" if difficulte == Difficulte.FACILE else "2 serpents ennemis traversent toutes les 90s"
		draw_string(police, Vector2(ORIGINE_GRILLE.x, y_diff + 24.0), desc_diff + "   (◀ ▶ pour changer)",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 14, COULEUR_TEXTE_INACTIF.lightened(0.45))

		if meilleur_score > 0:
			draw_string(police, Vector2(ORIGINE_GRILLE.x, y_diff + 50.0), "MEILLEUR SCORE : %d" % meilleur_score,
				HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 18, COULEUR_COMBO_X2)

		# Légende des consommables
		var x_legende := ORIGINE_GRILLE.x + largeur_arene * 0.5 - 185.0
		var y_leg := y_diff + 86.0
		var pas_y := 32.0
		var demi_icone := 10.0

		# Nourriture
		draw_rect(Rect2(x_legende - demi_icone, y_leg - demi_icone - 5.0, demi_icone * 2.0, demi_icone * 2.0), COULEUR_CONSOMMABLE)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Nourriture  —  +1 pt (grandit et accélère)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_TEXTE)

		# Bouclier
		y_leg += pas_y
		_dessiner_forme_bonus(TypeBonus.BOUCLIER, Vector2(x_legende, y_leg - 5.0), demi_icone)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Bouclier  —  Absorbe 1 collision", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_BOUCLIER)

		# Fantôme
		y_leg += pas_y
		_dessiner_forme_bonus(TypeBonus.FANTOME, Vector2(x_legende, y_leg - 5.0), demi_icone)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Fantôme  —  Traverse murs et corps (6s)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_FANTOME)

		# Combo x2
		y_leg += pas_y
		_dessiner_forme_bonus(TypeBonus.COMBO_X2, Vector2(x_legende, y_leg - 5.0), demi_icone)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Combo x2  —  Points doublés (10s)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_COMBO_X2)

		# Ralenti
		y_leg += pas_y
		_dessiner_forme_bonus(TypeBonus.RALENTI, Vector2(x_legende, y_leg - 5.0), demi_icone)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Ralenti  —  Ralentit 6s (toutes les 1 min)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_RALENTI)

		# Ciseaux
		y_leg += pas_y
		_dessiner_forme_bonus(TypeBonus.CISEAUX, Vector2(x_legende, y_leg - 5.0), demi_icone)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Ciseaux  —  Coupe 5 segments (tous les 15 pts)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_CISEAUX)

		# Vie
		y_leg += pas_y
		_dessiner_forme_bonus(TypeBonus.VIE, Vector2(x_legende, y_leg - 5.0), demi_icone)
		draw_string(police, Vector2(x_legende + 24.0, y_leg), "Vie +1  —  Respawn au centre (max 3)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_VIE)

		draw_string(police, Vector2(ORIGINE_GRILLE.x, ORIGINE_GRILLE.y + hauteur_arene - 84.0), "APPUIE SUR ENTRÉE OU ESPACE POUR JOUER",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 22, COULEUR_TETE)
		draw_string(police, Vector2(ORIGINE_GRILLE.x, ORIGINE_GRILLE.y + hauteur_arene - 52.0), "Flèches ou ZQSD pour diriger   •   P ou Échap pour Pause",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 15, COULEUR_TEXTE_INACTIF.lightened(0.4))

	elif etat_jeu == EtatJeu.PAUSE:
		draw_rect(rect_arene, Color(0, 0, 0, 0.72))
		var y_centre := ORIGINE_GRILLE.y + hauteur_arene * 0.5
		draw_string(titre_font, Vector2(ORIGINE_GRILLE.x, y_centre - 18), "PAUSE",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 46, COULEUR_TETE)
		draw_string(police, Vector2(ORIGINE_GRILLE.x, y_centre + 24), "P ou Échap pour reprendre   •   Entrée pour recommencer",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 18, COULEUR_TEXTE_INACTIF.lightened(0.4))

	elif etat_jeu == EtatJeu.GAME_OVER:
		draw_rect(rect_arene, Color(0, 0, 0, 0.75))
		var y_centre := ORIGINE_GRILLE.y + hauteur_arene * 0.5
		draw_string(titre_font, Vector2(ORIGINE_GRILLE.x, y_centre - 28), "PERDU",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 48, COULEUR_CONSOMMABLE)
		if nouveau_record:
			draw_string(police, Vector2(ORIGINE_GRILLE.x, y_centre + 8), "NOUVEAU RECORD : %d !" % meilleur_score,
				HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 22, COULEUR_COMBO_X2)
		else:
			draw_string(police, Vector2(ORIGINE_GRILLE.x, y_centre + 8), "Score : %d   |   Meilleur score : %d" % [score, meilleur_score],
				HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 20, COULEUR_TEXTE)
		draw_string(police, Vector2(ORIGINE_GRILLE.x, y_centre + 42), "Entrée ou Espace pour rejouer",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 18, COULEUR_TEXTE_INACTIF.lightened(0.4))
