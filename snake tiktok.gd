extends Node2D

const COLONNES := 20          
const LIGNES := 20            
const TAILLE_CASE := 24      
const DELAI_DEPART := 0.15    
const DELAI_MINIMAL := 0.06 

var serpent : Array[Vector2i] = []
var direction := Vector2i.RIGHT
var file_directions : Array[Vector2i] = []
var nourriture := 0
var score = 0
var partie_finie := false
var minuteur : Timer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	minuteur = Timer.new()
	minuteur.timeout.connect(_avancer)
	add_child(minuteur)
	_nouvelle_partie()


func _nouvelle_partie() -> void:
	serpent = [Vector2i(10, 10), Vector2i(9, 10), Vector2i(8, 10)]
	direction = Vector2i.RIGHT
	file_directions.clear()
	score = 0
	partie_finie = false
	_placer_nourriture()
	minuteur.start(DELAI_DEPART)
	queue_redraw()


func _unhandled_input(evenement: InputEvent) -> void:
	if not (evenement is InputEventKey and evenement.pressed and not evenement.echo):
		return

	if partie_finie:
		if evenement.keycode == KEY_ENTER or evenement.keycode == KEY_SPACE:
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
	if touche_mur or nouvelle_tete in corps:
		_finir_partie()
		return

	# 4. déplacer : on ajoute la tête, et on retire la queue sauf si on mange
	serpent.push_front(nouvelle_tete)
	if mange:
		score += 1
		minuteur.wait_time = maxf(DELAI_MINIMAL, DELAI_DEPART - score * 0.003)
		_placer_nourriture()
	else:
		serpent.pop_back()

	queue_redraw()


func _placer_nourriture() -> void:
	# On choisit parmi les cases libres : la nourriture n'apparaît jamais sur le serpent.
	var cases_libres: Array[Vector2i] = []
	for x in COLONNES:
		for y in LIGNES:
			var une_case := Vector2i(x, y)
			if une_case not in serpent:
				cases_libres.append(une_case)
	if cases_libres.is_empty():
		_finir_partie()  # grille pleine : victoire
		return
	nourriture = cases_libres.pick_random()


func _finir_partie() -> void:
	partie_finie = true
	minuteur.stop()
	queue_redraw()


func _draw() -> void:
	# fond
	draw_rect(Rect2(0, 0, COLONNES * TAILLE_CASE, LIGNES * TAILLE_CASE), Color("#1a1a2e"))
	# nourriture
	draw_rect(Rect2(Vector2(nourriture) * TAILLE_CASE + Vector2(2, 2), Vector2(TAILLE_CASE - 4, TAILLE_CASE - 4)), Color("#e94560"))
	# serpent
	for i in serpent.size():
		var couleur := Color("#9bdeac") if i == 0 else Color("#4ecca3")
		draw_rect(Rect2(Vector2(serpent[i]) * TAILLE_CASE + Vector2(1, 1), Vector2(TAILLE_CASE - 2, TAILLE_CASE - 2)), couleur)
	# score et message de fin
	var police := ThemeDB.fallback_font
	draw_string(police, Vector2(8, 22), "Score : %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	if partie_finie:
		draw_string(police, Vector2(0, LIGNES * TAILLE_CASE / 2.0), "PERDU - Entrée pour rejouer",
			HORIZONTAL_ALIGNMENT_CENTER, COLONNES * TAILLE_CASE, 24)
