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
signal question_bank_changed

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
	question_bank_changed.emit()

func get_question_bank_paths() -> Dictionary:
	return _question_loader.get_current_bank_paths()

func get_question_bank_display_paths() -> Dictionary:
	var paths := get_question_bank_paths()
	return {
		"math": ProjectSettings.globalize_path(paths.get("math", "")),
		"qa": ProjectSettings.globalize_path(paths.get("qa", "")),
		"folder": ProjectSettings.globalize_path("user://quiz_banks"),
	}

func import_question_bank(source_path: String, question_type: QuizData.QuestionType) -> String:
	if source_path.is_empty():
		return "未选择文件"
	if not FileAccess.file_exists(source_path):
		return "文件不存在：" + source_path

	var target_path := QuestionLoader.USER_MATH_CSV_PATH if question_type == QuizData.QuestionType.MATH else QuestionLoader.USER_QA_CSV_PATH
	var target_dir := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(target_dir)
		if mk_err != OK:
			return "创建题库目录失败，错误码：%d" % mk_err

	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return "无法读取文件：" + source_path
	var content := source_file.get_as_text()
	source_file.close()

	var target_file := FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		return "无法写入题库文件：" + target_path
	target_file.store_string(content)
	target_file.close()

	reload_questions()
	return ""

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
