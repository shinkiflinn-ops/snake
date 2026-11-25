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
enum EtatJeu { PSEUDO, MENU, CLASSEMENT, JEU, PAUSE, GAME_OVER }
enum Difficulte { FACILE, DIFFICILE }

# Poids d'apparition par bonus aléatoire (Ciseaux chaque 15 pts, Ralenti chaque 1 min)
const POIDS_BONUS := {
	TypeBonus.BOUCLIER: 35,
	TypeBonus.FANTOME: 30,
	TypeBonus.COMBO_X2: 25,
	TypeBonus.VIE: 10,
}

# Palette de couleurs (tokens Hallmark : surfaces, bordures, texte, accents)
const COULEUR_FOND := Color("#050507")
const COULEUR_FOND_ARENE := Color("#000000")
const COULEUR_SURFACE_UI := Color("#0d0d12")
const COULEUR_SURFACE_SURVOL := Color("#16161f")
const COULEUR_BORDURE_SUBTILE := Color("#23232d")
const COULEUR_BORDURE := Color("#ffffff")
const COULEUR_TETE := Color("#ffffff")
const COULEUR_CORPS := Color("#b8b8c4")
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
const COULEUR_TEXTE_MUTED := Color("#8a8a99")
const COULEUR_TEXTE_INACTIF := Color("#444452")
const CHEMIN_SAUVEGARDE := "user://snake_save.cfg"
const CHEMIN_CLASSEMENT := "user://snake_classement.json"
const URL_FIREBASE_DB := ""  # Optionnel : URL Firebase Realtime DB pour synchro en ligne

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
var etat_jeu := EtatJeu.PSEUDO
var pseudo_joueur := ""
var saisie_pseudo := ""
var erreur_pseudo := ""
var classement_joueurs: Array[Dictionary] = []  # [{ "pseudo": String, "facile": int, "difficile": int }]
var filtre_classement := Difficulte.FACILE
var statut_sync_classement := ""
var http_classement: HTTPRequest
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
var temps_animation := 0.0                    # horloge visuelle pour micro-animations
var zones_cliquables: Dictionary = {}         # { action: Rect2 } pour les boutons d'interface
var survol_action := ""


func _ready() -> void:
	RenderingServer.set_default_clear_color(COULEUR_FOND)
	police_ui = load("res://fonts/FiraMono-Bold.otf") if ResourceLoader.exists("res://fonts/FiraMono-Bold.otf") else ThemeDB.fallback_font
	police_titre = load("res://fonts/FiraSansCondensed-Heavy.otf") if ResourceLoader.exists("res://fonts/FiraSansCondensed-Heavy.otf") else police_ui
	_charger_meilleur_score()
	_charger_classement_local()
	_initialiser_audio()

	http_classement = HTTPRequest.new()
	http_classement.request_completed.connect(_sur_reponse_classement)
	add_child(http_classement)
	if URL_FIREBASE_DB != "":
		_rafraichir_classement_en_ligne()

	minuteur = Timer.new()
	minuteur.timeout.connect(_avancer)
	add_child(minuteur)

	minuteur_bonus = Timer.new()
	minuteur_bonus.one_shot = true
	minuteur_bonus.timeout.connect(_apparaitre_bonus)
	add_child(minuteur_bonus)

	_reinitialiser_serpent()
	_placer_nourriture()
	etat_jeu = EtatJeu.PSEUDO if pseudo_joueur.is_empty() else EtatJeu.MENU
	_maj_volume_musique()
	queue_redraw()


func _process(delta: float) -> void:
	temps_animation += delta
	var modifie := etat_jeu == EtatJeu.JEU or etat_jeu == EtatJeu.MENU or etat_jeu == EtatJeu.PSEUDO

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


func _retourner_au_menu() -> void:
	minuteur.paused = false
	minuteur_bonus.paused = false
	minuteur.stop()
	minuteur_bonus.stop()
	serpents_ennemis.clear()
	alertes_ennemis.clear()
	bonus_actifs.clear()
	particules.clear()
	textes_flottants.clear()
	_reinitialiser_serpent()
	_placer_nourriture()
	meilleur_score = int(meilleurs_scores[difficulte])
	etat_jeu = EtatJeu.MENU
	survol_action = ""
	_maj_volume_musique()
	queue_redraw()


func _executer_action_ui(action: String) -> void:
	match action:
		"valider_pseudo":
			_valider_pseudo()
		"facile":
			if difficulte != Difficulte.FACILE:
				difficulte = Difficulte.FACILE
				meilleur_score = int(meilleurs_scores[difficulte])
				_jouer_son(son_demarrer, 0.9)
				queue_redraw()
		"difficile":
			if difficulte != Difficulte.DIFFICILE:
				difficulte = Difficulte.DIFFICILE
				meilleur_score = int(meilleurs_scores[difficulte])
				_jouer_son(son_demarrer, 1.15)
				queue_redraw()
		"classement":
			filtre_classement = difficulte
			etat_jeu = EtatJeu.CLASSEMENT
			survol_action = ""
			_actualiser_classement()
			_jouer_son(son_demarrer, 1.05)
			queue_redraw()
		"classement_facile":
			filtre_classement = Difficulte.FACILE
			_jouer_son(son_demarrer, 0.9)
			queue_redraw()
		"classement_difficile":
			filtre_classement = Difficulte.DIFFICILE
			_jouer_son(son_demarrer, 1.15)
			queue_redraw()
		"actualiser_classement":
			_actualiser_classement()
			_jouer_son(son_demarrer, 1.1)
			queue_redraw()
		"jouer", "rejouer":
			minuteur.paused = false
			minuteur_bonus.paused = false
			_jouer_son(son_demarrer)
			_nouvelle_partie()
		"reprendre":
			_basculer_pause()
		"menu":
			_jouer_son(son_demarrer, 0.85)
			_retourner_au_menu()


func _unhandled_input(evenement: InputEvent) -> void:
	if etat_jeu != EtatJeu.JEU:
		if evenement is InputEventMouseMotion:
			var nouveau_survol := ""
			for action in zones_cliquables:
				if zones_cliquables[action].has_point(evenement.position):
					nouveau_survol = action
					break
			if nouveau_survol != survol_action:
				survol_action = nouveau_survol
				queue_redraw()
			return
		if evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT:
			for action in zones_cliquables:
				if zones_cliquables[action].has_point(evenement.position):
					_executer_action_ui(action)
					return

	if not (evenement is InputEventKey and evenement.pressed and not evenement.echo):
		return

	if etat_jeu == EtatJeu.PSEUDO:
		if evenement.keycode == KEY_ENTER or evenement.keycode == KEY_KP_ENTER:
			_valider_pseudo()
			return
		if evenement.keycode == KEY_BACKSPACE:
			if not saisie_pseudo.is_empty():
				saisie_pseudo = saisie_pseudo.left(saisie_pseudo.length() - 1)
				erreur_pseudo = ""
				queue_redraw()
			return
		if evenement.unicode >= 32 and saisie_pseudo.length() < 14:
			var ch := String.chr(evenement.unicode)
			if ch.is_valid_identifier() or ch in ["-", "_"] or (ch >= "0" and ch <= "9"):
				saisie_pseudo += ch
				erreur_pseudo = ""
				queue_redraw()
		return

	if etat_jeu == EtatJeu.MENU:
		if evenement.physical_keycode in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
			_executer_action_ui("difficile" if difficulte == Difficulte.FACILE else "facile")
			return
		if evenement.physical_keycode == KEY_C:
			_executer_action_ui("classement")
			return
		if evenement.keycode == KEY_ENTER or evenement.keycode == KEY_SPACE:
			_executer_action_ui("jouer")
		return

	if etat_jeu == EtatJeu.CLASSEMENT:
		if evenement.physical_keycode in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
			_executer_action_ui("classement_difficile" if filtre_classement == Difficulte.FACILE else "classement_facile")
			return
		if evenement.physical_keycode == KEY_R:
			_executer_action_ui("actualiser_classement")
			return
		if evenement.keycode == KEY_ESCAPE or evenement.physical_keycode == KEY_M or evenement.keycode == KEY_ENTER:
			_executer_action_ui("menu")
		return

	if etat_jeu == EtatJeu.GAME_OVER:
		if evenement.keycode == KEY_ENTER or evenement.keycode == KEY_SPACE:
			_executer_action_ui("rejouer")
		elif evenement.physical_keycode == KEY_C:
			_executer_action_ui("classement")
		elif evenement.physical_keycode == KEY_M:
			_executer_action_ui("menu")
		return

	if evenement.keycode == KEY_P or evenement.keycode == KEY_ESCAPE:
		_basculer_pause()
		return

	if etat_jeu == EtatJeu.PAUSE:
		if evenement.keycode == KEY_ENTER:
			_executer_action_ui("rejouer")
		elif evenement.physical_keycode == KEY_M:
			_executer_action_ui("menu")
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
		pseudo_joueur = str(config.get_value("joueur", "pseudo", "")).strip_edges()
		meilleurs_scores[Difficulte.FACILE] = int(config.get_value("scores", "facile", config.get_value("scores", "meilleur", 0)))
		meilleurs_scores[Difficulte.DIFFICILE] = int(config.get_value("scores", "difficile", 0))
	meilleur_score = int(meilleurs_scores[difficulte])


func _sauvegarder_meilleur_score() -> void:
	var config := ConfigFile.new()
	config.set_value("joueur", "pseudo", pseudo_joueur)
	config.set_value("scores", "facile", meilleurs_scores[Difficulte.FACILE])
	config.set_value("scores", "difficile", meilleurs_scores[Difficulte.DIFFICILE])
	config.save(CHEMIN_SAUVEGARDE)


func _charger_classement_local() -> void:
	classement_joueurs.clear()
	if not FileAccess.file_exists(CHEMIN_CLASSEMENT):
		return
	var fichier := FileAccess.open(CHEMIN_CLASSEMENT, FileAccess.READ)
	if fichier == null:
		return
	var parse := JSON.parse_string(fichier.get_as_text())
	if parse is Array:
		for item in parse:
			if item is Dictionary and item.has("pseudo"):
				classement_joueurs.append({
					"pseudo": str(item["pseudo"]),
					"facile": int(item.get("facile", 0)),
					"difficile": int(item.get("difficile", 0)),
				})


func _sauvegarder_classement_local() -> void:
	var fichier := FileAccess.open(CHEMIN_CLASSEMENT, FileAccess.WRITE)
	if fichier != null:
		fichier.store_string(JSON.stringify(classement_joueurs))


func _pseudo_existe(nom: String) -> bool:
	var cible := nom.to_lower()
	for entry in classement_joueurs:
		if str(entry["pseudo"]).to_lower() == cible:
			return true
	return false


func _valider_pseudo() -> void:
	var candidat := saisie_pseudo.strip_edges()
	if candidat.length() < 3:
		erreur_pseudo = "3 caractères minimum."
		_jouer_son(son_degat, 1.2)
		queue_redraw()
		return
	if _pseudo_existe(candidat):
		erreur_pseudo = "Ce pseudo est déjà pris !"
		_jouer_son(son_degat, 1.2)
		queue_redraw()
		return

	pseudo_joueur = candidat
	erreur_pseudo = ""
	_sauvegarder_meilleur_score()
	_mettre_a_jour_score_classement()
	_jouer_son(son_vie)
	etat_jeu = EtatJeu.MENU
	queue_redraw()


func _mettre_a_jour_score_classement() -> void:
	if pseudo_joueur.is_empty():
		return
	var trouve := false
	for entry in classement_joueurs:
		if str(entry["pseudo"]).to_lower() == pseudo_joueur.to_lower():
			entry["facile"] = maxi(int(entry["facile"]), int(meilleurs_scores[Difficulte.FACILE]))
			entry["difficile"] = maxi(int(entry["difficile"]), int(meilleurs_scores[Difficulte.DIFFICILE]))
			trouve = true
			break
	if not trouve:
		classement_joueurs.append({
			"pseudo": pseudo_joueur,
			"facile": int(meilleurs_scores[Difficulte.FACILE]),
			"difficile": int(meilleurs_scores[Difficulte.DIFFICILE]),
		})
	_sauvegarder_classement_local()
	if URL_FIREBASE_DB != "" and http_classement != null:
		var url := "%s/joueurs/%s.json" % [URL_FIREBASE_DB.trim_suffix("/"), pseudo_joueur.to_lower().uri_encode()]
		var payload := JSON.stringify({
			"pseudo": pseudo_joueur,
			"facile": int(meilleurs_scores[Difficulte.FACILE]),
			"difficile": int(meilleurs_scores[Difficulte.DIFFICILE]),
		})
		http_classement.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, payload)


func _actualiser_classement() -> void:
	_charger_classement_local()
	_mettre_a_jour_score_classement()
	if URL_FIREBASE_DB != "":
		_rafraichir_classement_en_ligne()
	else:
		statut_sync_classement = "Classement local à jour (%d joueur%s)" % [classement_joueurs.size(), "s" if classement_joueurs.size() > 1 else ""]


func _rafraichir_classement_en_ligne() -> void:
	if URL_FIREBASE_DB == "" or http_classement == null:
		return
	statut_sync_classement = "Actualisation..."
	var url := "%s/joueurs.json" % URL_FIREBASE_DB.trim_suffix("/")
	http_classement.request(url)


func _sur_reponse_classement(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		statut_sync_classement = "Hors-ligne (classement local)"
		queue_redraw()
		return
	var data := JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary:
		classement_joueurs.clear()
		for k in data:
			var item = data[k]
			if item is Dictionary and item.has("pseudo"):
				classement_joueurs.append({
					"pseudo": str(item["pseudo"]),
					"facile": int(item.get("facile", 0)),
					"difficile": int(item.get("difficile", 0)),
				})
		_sauvegarder_classement_local()
		statut_sync_classement = "Synchronisé (%d joueurs)" % classement_joueurs.size()
		queue_redraw()


func _obtenir_classement_trie(mode: Difficulte) -> Array[Dictionary]:
	var cle := "difficile" if mode == Difficulte.DIFFICILE else "facile"
	var copie: Array[Dictionary] = classement_joueurs.duplicate(true)
	copie.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.get(cle, 0))
		var sb := int(b.get(cle, 0))
		if sa == sb:
			return str(a["pseudo"]).naturalnocasecmp_to(str(b["pseudo"])) < 0
		return sa > sb
	)
	return copie


func _verifier_record() -> void:
	if score > meilleur_score:
		meilleur_score = score
		meilleurs_scores[difficulte] = score
		nouveau_record = true


func _finir_partie() -> void:
	_verifier_record()
	if nouveau_record:
		_sauvegarder_meilleur_score()
	_mettre_a_jour_score_classement()
	if URL_FIREBASE_DB != "":
		_rafraichir_classement_en_ligne()
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


func _dessiner_yeux_serpent(rect_tete: Rect2, dir: Vector2i, couleur_oeil: Color) -> void:
	var centre := rect_tete.position + rect_tete.size * 0.5
	var avant := Vector2(dir) * 4.5
	var perp := Vector2(-dir.y, dir.x) * 4.2
	draw_circle(centre + avant + perp, 1.9, couleur_oeil)
	draw_circle(centre + avant - perp, 1.9, couleur_oeil)


func _dessiner_icone_vie(centre: Vector2, taille: float, actif: bool) -> void:
	var c := COULEUR_VIE if actif else COULEUR_BORDURE_SUBTILE
	var ep := taille * 0.34
	draw_rect(Rect2(centre.x - ep * 0.5, centre.y - taille * 0.5, ep, taille), c)
	draw_rect(Rect2(centre.x - taille * 0.5, centre.y - ep * 0.5, taille, ep), c)


func _dessiner_badge_hud(police: Font, pos_droite: Vector2, texte: String, couleur: Color) -> float:
	var taille_texte := police.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var largeur := taille_texte.x + 18.0
	var rect := Rect2(pos_droite.x - largeur, pos_droite.y - 13.0, largeur, 26.0)
	draw_rect(rect, Color(couleur.r, couleur.g, couleur.b, 0.14))
	draw_rect(rect, Color(couleur.r, couleur.g, couleur.b, 0.65), false, 1.2)
	draw_string(police, Vector2(rect.position.x + 9.0, rect.position.y + 18.0), texte, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, couleur)
	return largeur + 8.0


func _dessiner_bouton(police: Font, action: String, rect: Rect2, label: String, primaire: bool, accent := COULEUR_TETE) -> void:
	zones_cliquables[action] = rect
	var survole := survol_action == action
	var fond := COULEUR_SURFACE_UI
	var bord := COULEUR_BORDURE_SUBTILE
	var couleur_txt := COULEUR_TEXTE

	if primaire:
		fond = accent if not survole else accent.lightened(0.15)
		bord = fond
		couleur_txt = COULEUR_FOND_ARENE
	elif survole:
		fond = COULEUR_SURFACE_SURVOL
		bord = accent

	draw_rect(rect, fond)
	draw_rect(rect, bord, false, 1.5)
	draw_string(police, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 6.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, couleur_txt)


func _dessiner_serpent_s(origine: Vector2, hauteur: float, couleur_corps: Color, decalage_phase: float) -> void:
	# Dessine un "S" en forme de serpent sinueux (queue en bas, tête avec yeux et langue en haut)
	var largeur := hauteur * 0.56
	var epaisseur := hauteur * 0.17
	var pts := PackedVector2Array()
	var nb := 22
	for i in range(nb + 1):
		var t := float(i) / float(nb)
		# t = 0 (bas/queue) -> t = 1 (haut/tête)
		var y := lerpf(hauteur, 0.0, t)
		var x := largeur * 0.5 + sin(t * TAU * 0.95 - PI * 0.4) * (largeur * 0.42)
		var ondulation := sin(temps_animation * 3.2 + decalage_phase + t * 4.0) * 1.4
		pts.append(origine + Vector2(x + ondulation, y))

	# Corps du serpent (légèrement plus fin vers la queue)
	for i in range(pts.size() - 1):
		var ratio := float(i) / float(pts.size() - 1)
		var w := lerpf(epaisseur * 0.48, epaisseur, ratio)
		draw_line(pts[i], pts[i + 1], couleur_corps, w, true)
		draw_circle(pts[i + 1], w * 0.5, couleur_corps)

	# Tête en haut du S
	var tete: Vector2 = pts[pts.size() - 1]
	var r_tete := epaisseur * 0.62
	draw_circle(tete, r_tete, couleur_corps)
	# Yeux
	draw_circle(tete + Vector2(r_tete * 0.25, -r_tete * 0.28), maxf(1.5, r_tete * 0.24), COULEUR_FOND_ARENE)
	draw_circle(tete + Vector2(r_tete * 0.25, r_tete * 0.28), maxf(1.5, r_tete * 0.24), COULEUR_FOND_ARENE)
	# Petite langue fourchue rouge
	var base_langue := tete + Vector2(r_tete * 0.85, 0.0)
	var pointe := base_langue + Vector2(r_tete * 0.95, 0.0)
	draw_line(base_langue, pointe, COULEUR_CONSOMMABLE, 1.8, true)
	draw_line(pointe, pointe + Vector2(r_tete * 0.45, -r_tete * 0.32), COULEUR_CONSOMMABLE, 1.5, true)
	draw_line(pointe, pointe + Vector2(r_tete * 0.45, r_tete * 0.32), COULEUR_CONSOMMABLE, 1.5, true)


func _dessiner_logo_sssnake(titre_font: Font, pos_haut_gauche: Vector2, hauteur_s: float) -> void:
	var largeur_s := hauteur_s * 0.56
	var espacement_s := largeur_s + hauteur_s * 0.12
	_dessiner_serpent_s(pos_haut_gauche, hauteur_s, COULEUR_TETE, 0.0)
	_dessiner_serpent_s(pos_haut_gauche + Vector2(espacement_s, 0.0), hauteur_s, COULEUR_CORPS, 1.2)
	_dessiner_serpent_s(pos_haut_gauche + Vector2(espacement_s * 2.0, 0.0), hauteur_s, COULEUR_CONSOMMABLE, 2.4)
	var x_nake := pos_haut_gauche.x + espacement_s * 3.0 + hauteur_s * 0.06
	var taille_police := int(hauteur_s * 1.18)
	draw_string(titre_font, Vector2(x_nake, pos_haut_gauche.y + hauteur_s * 0.96), "nake",
		HORIZONTAL_ALIGNMENT_LEFT, -1, taille_police, COULEUR_TETE)


func _draw() -> void:
	zones_cliquables.clear()
	var largeur_arene := COLONNES * TAILLE_CASE
	var hauteur_arene := LIGNES * TAILLE_CASE
	var rect_arene := Rect2(ORIGINE_GRILLE, Vector2(largeur_arene, hauteur_arene))
	var police := police_ui if police_ui != null else ThemeDB.fallback_font
	var titre_font := police_titre if police_titre != null else police

	# Fond global + barre HUD structurée
	draw_rect(Rect2(0, 0, ORIGINE_GRILLE.x * 2.0 + largeur_arene, ORIGINE_GRILLE.y + hauteur_arene + 24.0), COULEUR_FOND)
	draw_rect(Rect2(0, 0, ORIGINE_GRILLE.x * 2.0 + largeur_arene, ORIGINE_GRILLE.y - 8.0), COULEUR_SURFACE_UI)
	draw_line(Vector2(0, ORIGINE_GRILLE.y - 8.0), Vector2(ORIGINE_GRILLE.x * 2.0 + largeur_arene, ORIGINE_GRILLE.y - 8.0), COULEUR_BORDURE_SUBTILE, 1.0)

	# Appliquer la secousse d'écran à l'arène et aux effets
	var decalage_secousse := Vector2.ZERO
	if intensite_secousse > 0.0:
		decalage_secousse = Vector2(
			randf_range(-intensite_secousse, intensite_secousse),
			randf_range(-intensite_secousse, intensite_secousse)
		)
	draw_set_transform(decalage_secousse)

	# 1. Fond de l'arène (noir pur sans grille)
	draw_rect(rect_arene, COULEUR_FOND_ARENE)

	# 2. Nourriture normale (carré rouge avec légère pulsation)
	var pulse := 0.5 + 0.5 * sin(temps_animation * 5.0)
	var pos_nourriture := ORIGINE_GRILLE + Vector2(nourriture) * TAILLE_CASE
	draw_rect(Rect2(pos_nourriture + Vector2(1, 1), Vector2(TAILLE_CASE - 2, TAILLE_CASE - 2)),
		Color(COULEUR_CONSOMMABLE.r, COULEUR_CONSOMMABLE.g, COULEUR_CONSOMMABLE.b, 0.14 + 0.12 * pulse))
	draw_rect(Rect2(pos_nourriture + Vector2(3, 3), Vector2(TAILLE_CASE - 6, TAILLE_CASE - 6)), COULEUR_CONSOMMABLE)

	# 4. Bonus aléatoires
	for bonus in bonus_actifs:
		_dessiner_bonus(bonus)

	# 4b. Alertes d'arrivée des serpents ennemis (mode Difficile)
	for alerte in alertes_ennemis:
		var t_alerte: float = alerte["temps_restant"]
		var entree: Vector2i = alerte["entree"]
		var dir_ennemi: Vector2i = alerte["dir"]
		var centre_entree := _centre_case(entree)
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
				_dessiner_yeux_serpent(rect_e, ennemi["dir"], COULEUR_TETE)

	# 5. Serpent (dégradé subtil + yeux sur la tête, translucide en Mode Fantôme)
	var afficher_serpent := temps_pause_respawn <= 0.0 or int(temps_pause_respawn * 14.0) % 2 == 0
	var en_fantome := temps_fantome > 0.0
	var total_segs := maxf(1.0, float(serpent.size() - 1))
	if afficher_serpent:
		for i in serpent.size():
			var t_seg := float(i) / total_segs
			var couleur := COULEUR_TETE if i == 0 else COULEUR_CORPS.lerp(Color("#7a7a88"), t_seg * 0.65)
			if en_fantome:
				couleur = couleur.lerp(COULEUR_FANTOME, 0.45)
				couleur.a = 0.65
			var marge := 1.0 if i == 0 else lerpf(1.2, 3.0, t_seg)
			var rect_segment := Rect2(ORIGINE_GRILLE + Vector2(serpent[i]) * TAILLE_CASE + Vector2(marge, marge), Vector2(TAILLE_CASE - marge * 2.0, TAILLE_CASE - marge * 2.0))
			draw_rect(rect_segment, couleur)
			if en_fantome:
				draw_rect(rect_segment, COULEUR_FANTOME, false, 1.5)
			if i == 0:
				_dessiner_yeux_serpent(rect_segment, direction, COULEUR_FOND_ARENE)
				if a_bouclier:
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

	# 9. Bordure nette autour de l'arène
	draw_rect(rect_arene, COULEUR_BORDURE_SUBTILE if etat_jeu in [EtatJeu.MENU, EtatJeu.PSEUDO, EtatJeu.CLASSEMENT] else COULEUR_BORDURE, false, 2.0)

	# Remise à zéro de la transformation pour que le HUD reste stable
	draw_set_transform(Vector2.ZERO)

	# 10. Barre HUD structurée en haut
	var y_hud := 40.0
	var x_gauche := ORIGINE_GRILLE.x
	draw_string(police, Vector2(x_gauche, y_hud), "%d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, COULEUR_COMBO_X2 if temps_combo_x2 > 0.0 else COULEUR_TEXTE)
	var largeur_score := police.get_string_size("%d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(police, Vector2(x_gauche + largeur_score + 14.0, y_hud - 2.0), "Record %d" % meilleur_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COULEUR_TEXTE_MUTED)
	if temps_combo_x2 > 0.0:
		var x_x2 := x_gauche + largeur_score + 14.0 + police.get_string_size("Record %d" % meilleur_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0
		draw_string(police, Vector2(x_x2, y_hud - 2.0), "x2 %.0fs" % ceilf(temps_combo_x2), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_COMBO_X2)

	# Vies en icônes visuelles (+) centrées
	var centre_hud_x := ORIGINE_GRILLE.x + largeur_arene * 0.5
	var espacement_vies := 26.0
	var x_depart_vies := centre_hud_x - espacement_vies
	for v_idx in MAX_VIES:
		_dessiner_icone_vie(Vector2(x_depart_vies + v_idx * espacement_vies, 32.0), 14.0, v_idx < vies)

	# Badges de statut à droite
	var curseur_droite := ORIGINE_GRILLE.x + largeur_arene
	if difficulte == Difficulte.DIFFICILE:
		if not alertes_ennemis.is_empty() or not serpents_ennemis.is_empty():
			curseur_droite -= _dessiner_badge_hud(police, Vector2(curseur_droite, 32.0), "Alerte", COULEUR_ENNEMI_TETE)
		else:
			curseur_droite -= _dessiner_badge_hud(police, Vector2(curseur_droite, 32.0), "Vague %.0fs" % ceilf(temps_prochaine_vague), COULEUR_TEXTE_MUTED)
	if a_bouclier:
		curseur_droite -= _dessiner_badge_hud(police, Vector2(curseur_droite, 32.0), "Bouclier", COULEUR_BOUCLIER)
	if temps_fantome > 0.0:
		curseur_droite -= _dessiner_badge_hud(police, Vector2(curseur_droite, 32.0), "Fantôme %.0fs" % ceilf(temps_fantome), COULEUR_FANTOME)
	if temps_ralenti > 0.0:
		curseur_droite -= _dessiner_badge_hud(police, Vector2(curseur_droite, 32.0), "Ralenti %.0fs" % ceilf(temps_ralenti), COULEUR_RALENTI)

	# 11. Écrans d'état (Pseudo, Menu Titre 2 colonnes, Classement, Pause, Game Over)
	if etat_jeu == EtatJeu.PSEUDO:
		draw_rect(rect_arene, Color(0.02, 0.02, 0.03, 0.95))
		var hauteur_logo := 82.0
		var largeur_logo_approx := hauteur_logo * 3.8
		var x_logo := ORIGINE_GRILLE.x + (largeur_arene - largeur_logo_approx) * 0.5
		var y_logo := ORIGINE_GRILLE.y + 150.0
		_dessiner_logo_sssnake(titre_font, Vector2(x_logo, y_logo), hauteur_logo)
		draw_string(police, Vector2(ORIGINE_GRILLE.x, y_logo + hauteur_logo + 44.0), "Édition Néon  ·  Arcade",
			HORIZONTAL_ALIGNMENT_CENTER, largeur_arene, 16, COULEUR_TEXTE_MUTED)

		# Zone de saisie du pseudo en bas de l'écran
		var w_box := 440.0
		var x_box := ORIGINE_GRILLE.x + (largeur_arene - w_box) * 0.5
		var y_box := ORIGINE_GRILLE.y + hauteur_arene - 205.0
		draw_string(police, Vector2(x_box, y_box - 14.0), "Choisis ton pseudo unique pour le classement",
			HORIZONTAL_ALIGNMENT_CENTER, w_box, 15, COULEUR_TEXTE)

		var rect_input := Rect2(x_box, y_box, w_box, 48.0)
		draw_rect(rect_input, COULEUR_SURFACE_UI)
		draw_rect(rect_input, COULEUR_CONSOMMABLE if not erreur_pseudo.is_empty() else COULEUR_BORDURE, false, 1.5)
		var curseur := "_" if int(temps_animation * 2.5) % 2 == 0 else ""
		var texte_affiche := saisie_pseudo + curseur if not saisie_pseudo.is_empty() else ("Ton pseudo..." + curseur)
		var couleur_saisie := COULEUR_TEXTE if not saisie_pseudo.is_empty() else COULEUR_TEXTE_INACTIF.lightened(0.3)
		draw_string(police, Vector2(x_box + 16.0, y_box + 31.0), texte_affiche, HORIZONTAL_ALIGNMENT_LEFT, w_box - 32.0, 20, couleur_saisie)

		if not erreur_pseudo.is_empty():
			draw_string(police, Vector2(x_box, y_box + 70.0), erreur_pseudo, HORIZONTAL_ALIGNMENT_CENTER, w_box, 14, COULEUR_CONSOMMABLE)

		_dessiner_bouton(police, "valider_pseudo", Rect2(x_box + 110.0, y_box + 86.0, 220.0, 46.0), "Entrer (Entrée)", true, COULEUR_TETE)

	elif etat_jeu == EtatJeu.MENU:
		draw_rect(rect_arene, Color(0.02, 0.02, 0.03, 0.92))

		var x_col_g := ORIGINE_GRILLE.x + 48.0
		var w_col_g := 360.0
		var y_top := ORIGINE_GRILLE.y + 62.0

		# Colonne gauche : Logo SSSnake, Joueur, Difficulté, Actions
		_dessiner_logo_sssnake(titre_font, Vector2(x_col_g, y_top), 56.0)
		draw_rect(Rect2(x_col_g, y_top + 74.0, 44.0, 4.0), COULEUR_CONSOMMABLE)
		draw_string(police, Vector2(x_col_g + 56.0, y_top + 82.0), "Joueur : %s" % pseudo_joueur, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_TEXTE_MUTED)

		# Segmented control cliquable pour la difficulté
		var y_seg := y_top + 116.0
		var w_seg := 320.0
		var h_seg := 42.0
		draw_rect(Rect2(x_col_g, y_seg, w_seg, h_seg), COULEUR_SURFACE_UI)
		draw_rect(Rect2(x_col_g, y_seg, w_seg, h_seg), COULEUR_BORDURE_SUBTILE, false, 1.5)
		_dessiner_bouton(police, "facile", Rect2(x_col_g + 4.0, y_seg + 4.0, w_seg * 0.5 - 6.0, h_seg - 8.0),
			"Facile", difficulte == Difficulte.FACILE, COULEUR_VIE)
		_dessiner_bouton(police, "difficile", Rect2(x_col_g + w_seg * 0.5 + 2.0, y_seg + 4.0, w_seg * 0.5 - 6.0, h_seg - 8.0),
			"Difficile", difficulte == Difficulte.DIFFICILE, COULEUR_ENNEMI_TETE)

		var desc_mode := "Mode classique sans ennemis." if difficulte == Difficulte.FACILE else "2 serpents ennemis traversent toutes les 90 s."
		draw_string(police, Vector2(x_col_g, y_seg + 68.0), desc_mode, HORIZONTAL_ALIGNMENT_LEFT, w_col_g, 14, COULEUR_TEXTE_MUTED)

		if meilleur_score > 0:
			draw_string(police, Vector2(x_col_g, y_seg + 102.0), "Meilleur score : %d" % meilleur_score,
				HORIZONTAL_ALIGNMENT_LEFT, w_col_g, 18, COULEUR_COMBO_X2)

		# Boutons Jouer + Classement
		var y_btn := y_top + 256.0
		_dessiner_bouton(police, "jouer", Rect2(x_col_g, y_btn, 180.0, 50.0), "Jouer", true, COULEUR_TETE)
		_dessiner_bouton(police, "classement", Rect2(x_col_g + 194.0, y_btn, 150.0, 50.0), "Rangs (C)", false, COULEUR_COMBO_X2)
		draw_string(police, Vector2(x_col_g, y_btn + 78.0), "Entrée ou Espace pour lancer", HORIZONTAL_ALIGNMENT_LEFT, w_col_g, 13, COULEUR_TEXTE_MUTED)
		draw_string(police, Vector2(x_col_g, ORIGINE_GRILLE.y + hauteur_arene - 40.0), "Flèches / ZQSD : diriger   ·   P / Échap : pause",
			HORIZONTAL_ALIGNMENT_LEFT, w_col_g + 80.0, 13, COULEUR_TEXTE_INACTIF.lightened(0.25))

		# Colonne droite : Panneau des consommables
		var x_panel := ORIGINE_GRILLE.x + 448.0
		var y_panel := ORIGINE_GRILLE.y + 62.0
		var w_panel := largeur_arene - 496.0
		var h_panel := hauteur_arene - 124.0
		draw_rect(Rect2(x_panel, y_panel, w_panel, h_panel), COULEUR_SURFACE_UI)
		draw_rect(Rect2(x_panel, y_panel, w_panel, h_panel), COULEUR_BORDURE_SUBTILE, false, 1.5)
		draw_string(police, Vector2(x_panel + 24.0, y_panel + 36.0), "Consommables & bonus", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COULEUR_TEXTE)
		draw_line(Vector2(x_panel + 24.0, y_panel + 52.0), Vector2(x_panel + w_panel - 24.0, y_panel + 52.0), COULEUR_BORDURE_SUBTILE, 1.0)

		var x_ico := x_panel + 38.0
		var x_txt := x_panel + 68.0
		var y_item := y_panel + 86.0
		var pas_item := 58.0
		var demi_ico := 9.0

		# Nourriture
		draw_rect(Rect2(x_ico - demi_ico, y_item - demi_ico, demi_ico * 2.0, demi_ico * 2.0), COULEUR_CONSOMMABLE)
		draw_string(police, Vector2(x_txt, y_item - 2.0), "Nourriture", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COULEUR_CONSOMMABLE)
		draw_string(police, Vector2(x_txt, y_item + 17.0), "+1 pt, grandit et accélère", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COULEUR_TEXTE_MUTED)

		var items_bonus := [
			[TypeBonus.BOUCLIER, "Bouclier", "Absorbe 1 collision", COULEUR_BOUCLIER],
			[TypeBonus.FANTOME, "Fantôme", "Traverse murs et corps pendant 6 s", COULEUR_FANTOME],
			[TypeBonus.COMBO_X2, "Combo x2", "Points doublés pendant 10 s", COULEUR_COMBO_X2],
			[TypeBonus.RALENTI, "Ralenti", "Ralentit le jeu 6 s (toutes les 1 min)", COULEUR_RALENTI],
			[TypeBonus.CISEAUX, "Ciseaux", "Coupe 5 segments (tous les 15 pts)", COULEUR_CISEAUX],
			[TypeBonus.VIE, "Vie +1", "Respawn au centre (max 3 vies)", COULEUR_VIE],
		]
		for item in items_bonus:
			y_item += pas_item
			_dessiner_forme_bonus(item[0], Vector2(x_ico, y_item), demi_ico)
			draw_string(police, Vector2(x_txt, y_item - 2.0), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, item[3])
			draw_string(police, Vector2(x_txt, y_item + 17.0), item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COULEUR_TEXTE_MUTED)

	elif etat_jeu == EtatJeu.CLASSEMENT:
		draw_rect(rect_arene, Color(0.02, 0.02, 0.03, 0.94))
		var w_modal := 640.0
		var h_modal := 520.0
		var rect_modal := Rect2(ORIGINE_GRILLE.x + (largeur_arene - w_modal) * 0.5, ORIGINE_GRILLE.y + (hauteur_arene - h_modal) * 0.5, w_modal, h_modal)
		draw_rect(rect_modal, COULEUR_SURFACE_UI)
		draw_rect(rect_modal, COULEUR_BORDURE_SUBTILE, false, 1.5)

		draw_string(titre_font, Vector2(rect_modal.position.x + 28.0, rect_modal.position.y + 52.0), "CLASSEMENT",
			HORIZONTAL_ALIGNMENT_LEFT, 320.0, 38, COULEUR_TETE)
		draw_string(police, Vector2(rect_modal.position.x + 28.0, rect_modal.position.y + 76.0), statut_sync_classement,
			HORIZONTAL_ALIGNMENT_LEFT, 360.0, 13, COULEUR_TEXTE_MUTED)

		# Onglets Facile / Difficile
		var x_tabs := rect_modal.position.x + w_modal - 260.0
		var y_tabs := rect_modal.position.y + 24.0
		_dessiner_bouton(police, "classement_facile", Rect2(x_tabs, y_tabs, 112.0, 36.0), "Facile", filtre_classement == Difficulte.FACILE, COULEUR_VIE)
		_dessiner_bouton(police, "classement_difficile", Rect2(x_tabs + 120.0, y_tabs, 112.0, 36.0), "Difficile", filtre_classement == Difficulte.DIFFICILE, COULEUR_ENNEMI_TETE)

		draw_line(Vector2(rect_modal.position.x + 28.0, rect_modal.position.y + 92.0), Vector2(rect_modal.position.x + w_modal - 28.0, rect_modal.position.y + 92.0), COULEUR_BORDURE_SUBTILE, 1.0)

		var liste := _obtenir_classement_trie(filtre_classement)
		var cle_mode := "difficile" if filtre_classement == Difficulte.DIFFICILE else "facile"
		var y_ligne := rect_modal.position.y + 124.0
		var max_affiches := mini(10, liste.size())
		if max_affiches == 0:
			draw_string(police, Vector2(rect_modal.position.x, y_ligne + 80.0), "Aucun score enregistré.",
				HORIZONTAL_ALIGNMENT_CENTER, w_modal, 16, COULEUR_TEXTE_MUTED)
		for idx in max_affiches:
			var entree: Dictionary = liste[idx]
			var est_moi := str(entree["pseudo"]).to_lower() == pseudo_joueur.to_lower()
			var couleur_rang := COULEUR_COMBO_X2 if idx == 0 else (Color("#d4d4d8") if idx == 1 else (Color("#fb923c") if idx == 2 else COULEUR_TEXTE_MUTED))
			if est_moi:
				draw_rect(Rect2(rect_modal.position.x + 24.0, y_ligne - 18.0, w_modal - 48.0, 28.0), Color(1, 1, 1, 0.06))
			draw_string(police, Vector2(rect_modal.position.x + 36.0, y_ligne), "#%d" % (idx + 1), HORIZONTAL_ALIGNMENT_LEFT, 56.0, 16, couleur_rang)
			draw_string(police, Vector2(rect_modal.position.x + 96.0, y_ligne), str(entree["pseudo"]) + (" (toi)" if est_moi else ""),
				HORIZONTAL_ALIGNMENT_LEFT, 360.0, 16, COULEUR_TETE if est_moi else COULEUR_CORPS)
			draw_string(police, Vector2(rect_modal.position.x + w_modal - 140.0, y_ligne), "%d" % int(entree.get(cle_mode, 0)),
				HORIZONTAL_ALIGNMENT_RIGHT, 104.0, 16, couleur_rang if idx < 3 else COULEUR_TEXTE)
			y_ligne += 32.0

		var y_bas := rect_modal.position.y + h_modal - 62.0
		_dessiner_bouton(police, "actualiser_classement", Rect2(rect_modal.position.x + 28.0, y_bas, 170.0, 38.0), "Actualiser (R)", false, COULEUR_BOUCLIER)
		_dessiner_bouton(police, "menu", Rect2(rect_modal.position.x + w_modal - 198.0, y_bas, 170.0, 38.0), "Retour (Échap)", true, COULEUR_TETE)

	elif etat_jeu == EtatJeu.PAUSE:
		draw_rect(rect_arene, Color(0.02, 0.02, 0.03, 0.78))
		var w_modal := 420.0
		var h_modal := 260.0
		var rect_modal := Rect2(ORIGINE_GRILLE.x + (largeur_arene - w_modal) * 0.5, ORIGINE_GRILLE.y + (hauteur_arene - h_modal) * 0.5, w_modal, h_modal)
		draw_rect(rect_modal, COULEUR_SURFACE_UI)
		draw_rect(rect_modal, COULEUR_BORDURE_SUBTILE, false, 1.5)

		draw_string(titre_font, Vector2(rect_modal.position.x, rect_modal.position.y + 62.0), "PAUSE",
			HORIZONTAL_ALIGNMENT_CENTER, w_modal, 44, COULEUR_TETE)
		draw_string(police, Vector2(rect_modal.position.x, rect_modal.position.y + 92.0), "Score : %d   ·   %s" % [score, "Difficile" if difficulte == Difficulte.DIFFICILE else "Facile"],
			HORIZONTAL_ALIGNMENT_CENTER, w_modal, 14, COULEUR_TEXTE_MUTED)

		var x_btn_m := rect_modal.position.x + 40.0
		var w_btn_m := w_modal - 80.0
		_dessiner_bouton(police, "reprendre", Rect2(x_btn_m, rect_modal.position.y + 122.0, w_btn_m, 42.0), "Reprendre (P)", true, COULEUR_TETE)
		_dessiner_bouton(police, "rejouer", Rect2(x_btn_m, rect_modal.position.y + 174.0, w_btn_m * 0.5 - 6.0, 38.0), "Recommencer", false, COULEUR_TETE)
		_dessiner_bouton(police, "menu", Rect2(x_btn_m + w_btn_m * 0.5 + 6.0, rect_modal.position.y + 174.0, w_btn_m * 0.5 - 6.0, 38.0), "Menu (M)", false, COULEUR_TEXTE_MUTED)

	elif etat_jeu == EtatJeu.GAME_OVER:
		draw_rect(rect_arene, Color(0.02, 0.02, 0.03, 0.82))
		var w_modal := 440.0
		var h_modal := 270.0
		var rect_modal := Rect2(ORIGINE_GRILLE.x + (largeur_arene - w_modal) * 0.5, ORIGINE_GRILLE.y + (hauteur_arene - h_modal) * 0.5, w_modal, h_modal)
		draw_rect(rect_modal, COULEUR_SURFACE_UI)
		draw_rect(rect_modal, COULEUR_BORDURE_SUBTILE, false, 1.5)

		draw_string(titre_font, Vector2(rect_modal.position.x, rect_modal.position.y + 64.0), "PERDU",
			HORIZONTAL_ALIGNMENT_CENTER, w_modal, 48, COULEUR_CONSOMMABLE)
		if nouveau_record:
			draw_string(police, Vector2(rect_modal.position.x, rect_modal.position.y + 104.0), "Nouveau record : %d" % meilleur_score,
				HORIZONTAL_ALIGNMENT_CENTER, w_modal, 20, COULEUR_COMBO_X2)
		else:
			draw_string(police, Vector2(rect_modal.position.x, rect_modal.position.y + 104.0), "Score : %d   ·   Record : %d" % [score, meilleur_score],
				HORIZONTAL_ALIGNMENT_CENTER, w_modal, 18, COULEUR_TEXTE)
		draw_string(police, Vector2(rect_modal.position.x, rect_modal.position.y + 132.0), "Mode %s" % ("Difficile" if difficulte == Difficulte.DIFFICILE else "Facile"),
			HORIZONTAL_ALIGNMENT_CENTER, w_modal, 13, COULEUR_TEXTE_MUTED)

		var x_btn_go := rect_modal.position.x + 40.0
		var w_btn_go := w_modal - 80.0
		_dessiner_bouton(police, "rejouer", Rect2(x_btn_go, rect_modal.position.y + 160.0, w_btn_go, 44.0), "Rejouer (Entrée)", true, COULEUR_TETE)
		_dessiner_bouton(police, "classement", Rect2(x_btn_go, rect_modal.position.y + 212.0, w_btn_go * 0.5 - 6.0, 36.0), "Rangs (C)", false, COULEUR_COMBO_X2)
		_dessiner_bouton(police, "menu", Rect2(x_btn_go + w_btn_go * 0.5 + 6.0, rect_modal.position.y + 212.0, w_btn_go * 0.5 - 6.0, 36.0), "Menu (M)", false, COULEUR_TEXTE_MUTED)
