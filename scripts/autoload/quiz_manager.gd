extends Node

var _question_loader := QuestionLoader.new()
var _all_questions: Array[QuizData] = []
var _wrong_records: Array[Dictionary] = []

var is_enabled := true
var trigger_frequency := 3
var quiz_speed := 0.25
var wrong_penalty := 50

var plant_count := 0
var is_quiz_active := false
var _original_time_scale := 1.0

signal quiz_triggered(question: QuizData)
signal quiz_completed(was_correct: bool, question: QuizData)

var _quiz_ui: CanvasLayer

func _ready() -> void:
	EventBus.subscribe("quiz_plant_placed", _on_plant_placed)
	EventBus.subscribe("main_game_progress_update", _on_game_progress_update)
	_load_settings()
	_load_wrong_records()
	_ensure_quiz_ui()

func _ensure_quiz_ui() -> void:
	if _quiz_ui != null and is_instance_valid(_quiz_ui):
		return
	var scene := load("res://scenes/quiz/quiz_ui.tscn")
	if scene:
		_quiz_ui = scene.instantiate()
		get_tree().root.add_child.call_deferred(_quiz_ui)
		print("QuizManager: QuizUI加载成功")
	else:
		push_error("QuizManager: 无法加载quiz_ui.tscn")

func reload_questions() -> void:
	_all_questions = _question_loader.load_all_questions()

func get_random_question() -> QuizData:
	if _all_questions.is_empty():
		reload_questions()
	if _all_questions.is_empty():
		return null
	return _all_questions[randi() % _all_questions.size()]

func start_quiz() -> void:
	if is_quiz_active:
		return
	var question := get_random_question()
	if question == null:
		push_error("QuizManager: 没有题目可用")
		return
	is_quiz_active = true
	_original_time_scale = Engine.time_scale
	Engine.time_scale = quiz_speed
	print("QuizManager: 准备弹出答题, quiz_ui有效:", is_instance_valid(_quiz_ui))
	_ensure_quiz_ui()
	if is_instance_valid(_quiz_ui) and _quiz_ui.has_method("show_quiz"):
		_quiz_ui.show_quiz(question)
	else:
		push_error("QuizManager: QuizUI无效，无法弹出")
	quiz_triggered.emit(question)

func end_quiz(was_correct: bool, question: QuizData) -> void:
	is_quiz_active = false
	Engine.time_scale = _original_time_scale
	if not was_correct:
		EventBus.push_event("add_sun_value", [-wrong_penalty])
		_record_wrong_answer(question)
	quiz_completed.emit(was_correct, question)

func _on_plant_placed() -> void:
	if not is_enabled or is_quiz_active:
		return
	if not is_instance_valid(Global.main_game):
		return
	if Global.main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	plant_count += 1
	print("QuizManager: 种植计数 ", plant_count, "/", trigger_frequency, " 启用:", is_enabled)
	if plant_count >= trigger_frequency:
		plant_count = 0
		start_quiz()

func _on_game_progress_update(progress: int) -> void:
	if progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		plant_count = 0
		reload_questions()

func _record_wrong_answer(question: QuizData) -> void:
	var timestamp := Time.get_datetime_string_from_system()
	for record in _wrong_records:
		if record["question"] == question.question and record["type"] == question.question_type:
			record["count"] += 1
			record["last_time"] = timestamp
			_save_wrong_records()
			return
	_wrong_records.append({
		"type": question.question_type,
		"question": question.question,
		"answer": question.answer,
		"count": 1,
		"last_time": timestamp,
	})
	_save_wrong_records()

func _load_wrong_records() -> void:
	var path := "user://quiz_wrong_records.json"
	var data = Global.load_json(path)
	if data is Dictionary and data.has("records"):
		_wrong_records = data["records"]
	elif data is Array:
		_wrong_records = data
	else:
		_wrong_records = []

func _save_wrong_records() -> void:
	var path := "user://quiz_wrong_records.json"
	Global.save_json({"records": _wrong_records}, path)

func _load_settings() -> void:
	var path := "user://quiz_settings.json"
	var data = Global.load_json(path)
	if data.is_empty():
		return
	is_enabled = data.get("enabled", false)
	trigger_frequency = data.get("trigger_frequency", 3)
	quiz_speed = data.get("quiz_speed", 0.25)
	wrong_penalty = data.get("wrong_penalty", 50)

func save_settings() -> void:
	var path := "user://quiz_settings.json"
	Global.save_json({
		"enabled": is_enabled,
		"trigger_frequency": trigger_frequency,
		"quiz_speed": quiz_speed,
		"wrong_penalty": wrong_penalty,
	}, path)
