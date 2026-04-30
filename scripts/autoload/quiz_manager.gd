extends Node

var _question_loader := QuestionLoader.new()
var _all_questions: Array[QuizData] = []
var _wrong_records: Array[Dictionary] = []
var _recent_question_keys: Array[String] = []  # 内容去重：type:question:answer

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

func reload_questions() -> Dictionary:
	var report := _question_loader.load_all_questions_with_report()
	_all_questions = report["questions"]
	_recent_question_keys.clear()
	question_bank_changed.emit()
	return report

func get_question_bank_paths() -> Dictionary:
	return _question_loader.get_current_bank_paths()

func get_question_bank_display_paths() -> Dictionary:
	var paths := get_question_bank_paths()
	return {
		"math": ProjectSettings.globalize_path(paths.get("math", "")),
		"qa": ProjectSettings.globalize_path(paths.get("qa", "")),
		"folder": ProjectSettings.globalize_path("user://quiz_banks"),
	}

# 导入题库：校验 → 备份 → 替换 → 加载验证
func import_question_bank(source_path: String, question_type: QuizData.QuestionType) -> Dictionary:
	if source_path.is_empty():
		return { "success": false, "message": "未选择文件" }
	if not FileAccess.file_exists(source_path):
		return { "success": false, "message": "文件不存在：" + source_path }

	# 1. 校验源文件
	var validation := _question_loader.validate_csv(source_path)
	if not validation["valid"]:
		var err_count: int = validation["errors"].size()
		var first_err: String = validation["errors"][0]["reason"] if err_count > 0 else "未知错误"
		return {
			"success": false,
			"message": "文件格式错误（%d处问题），未导入。\n第1个错误: %s" % [err_count, first_err],
			"errors": validation["errors"],
		}

	if validation["would_load"] == 0:
		return { "success": false, "message": "文件中没有有效题目" }

	# 2. 确保目标目录存在
	var target_path := QuestionLoader.USER_MATH_CSV_PATH if question_type == QuizData.QuestionType.MATH else QuestionLoader.USER_QA_CSV_PATH
	var target_dir := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(target_dir)
		if mk_err != OK:
			return { "success": false, "message": "创建题库目录失败，错误码：%d" % mk_err }

	# 3. 备份原文件
	var backup_path := target_path + ".bak"
	var has_backup := false
	if FileAccess.file_exists(target_path):
		var dir := DirAccess.open(target_dir)
		if dir:
			# 删除旧备份
			if FileAccess.file_exists(backup_path):
				dir.remove(backup_path.get_file())
			var rename_err := dir.rename(target_path.get_file(), backup_path.get_file())
			if rename_err == OK:
				has_backup = true
			else:
				return { "success": false, "message": "备份原题库失败，错误码：%d" % rename_err }

	# 4. 复制新文件
	var copy_err := DirAccess.copy_absolute(source_path, target_path)
	if copy_err != OK:
		# 还原备份
		if has_backup:
			var dir := DirAccess.open(target_dir)
			if dir:
				dir.remove(target_path.get_file())
				dir.rename(backup_path.get_file(), target_path.get_file())
		return { "success": false, "message": "写入题库文件失败，错误码：%d" % copy_err }

	# 5. 重新加载并验证
	var report := reload_questions()
	if report["loaded"] == 0:
		# 加载失败，还原备份
		if has_backup:
			var dir := DirAccess.open(target_dir)
			if dir:
				dir.remove(target_path.get_file())
				dir.rename(backup_path.get_file(), target_path.get_file())
			reload_questions()
		return { "success": false, "message": "题库文件已写入但加载失败，已还原原题库" }

	# 6. 清理备份（成功后）
	if has_backup:
		var dir := DirAccess.open(target_dir)
		if dir:
			dir.remove(backup_path.get_file())

	var type_name := "数学" if question_type == QuizData.QuestionType.MATH else "问答"
	var msg := "%s题库导入成功！加载了 %d 道题" % [type_name, report["loaded"]]
	if report["skipped"] > 0:
		msg += "，跳过 %d 行有问题的数据" % report["skipped"]

	return {
		"success": true,
		"message": msg,
		"loaded": report["loaded"],
		"skipped": report["skipped"],
		"errors": report["errors"],
		"warnings": report.get("warnings", []),
	}

func get_random_question() -> QuizData:
	if _all_questions.is_empty():
		reload_questions()
	if _all_questions.is_empty():
		return null

	# 内容去重：按 type:question:answer 去重
	var available: Array[QuizData] = []
	for q in _all_questions:
		var key := _make_dedup_key(q)
		if key not in _recent_question_keys:
			available.append(q)

	# 所有题都出过了，重置历史
	if available.is_empty():
		_recent_question_keys.clear()
		available = _all_questions

	var picked := available[randi() % available.size()]
	_recent_question_keys.append(_make_dedup_key(picked))

	# 保留最近一半题库大小的历史
	var max_recent := maxi(1, _all_questions.size() / 2)
	if _recent_question_keys.size() > max_recent:
		_recent_question_keys = _recent_question_keys.slice(-max_recent)

	return picked

func _make_dedup_key(q: QuizData) -> String:
	return "%d:%s:%s" % [q.question_type, q.question, q.answer]

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
