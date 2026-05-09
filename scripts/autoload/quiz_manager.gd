extends Node

var _question_loader := QuestionLoader.new()
var _all_questions: Array[QuizData] = []
var _wrong_records: Array[Dictionary] = []

var is_enabled := true
var trigger_frequency := 3
var quiz_speed := 0.25
var wrong_penalty := 50
var overlay_opacity := 0.5
var overlay_blur := 3.0

var plant_count := 0
var is_quiz_active := false
var _original_time_scale := 1.0

signal quiz_triggered(question: QuizData)
signal quiz_completed(was_correct: bool, question: QuizData)
signal question_bank_changed
signal settings_changed

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
		get_tree().root.add_child(_quiz_ui)
		print("QuizManager: QuizUI加载成功")
	else:
		push_error("QuizManager: 无法加载quiz_ui.tscn")

func reload_questions() -> Dictionary:
	var report := _question_loader.load_all_questions_with_report()
	_all_questions = report["questions"]
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

func import_question_bank(source_path: String, question_type: QuizData.QuestionType) -> Dictionary:
	if source_path.is_empty():
		return { "success": false, "message": "未选择文件" }
	if not FileAccess.file_exists(source_path):
		return { "success": false, "message": "文件不存在：" + source_path }

	var is_xlsx := source_path.to_lower().ends_with(".xlsx")

	# 1. 校验源文件
	var validation := _question_loader.validate_file(source_path)
	if not validation["valid"]:
		return {
			"success": false,
			"message": "文件格式错误（%d处问题），未导入" % validation["errors"].size(),
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

	# 3. 源文件 == 目标文件：直接重载
	if not is_xlsx:
		var source_abs := ProjectSettings.globalize_path(source_path) if source_path.begins_with("user://") or source_path.begins_with("res://") else source_path
		var target_abs := ProjectSettings.globalize_path(target_path) if target_path.begins_with("user://") or target_path.begins_with("res://") else target_path
		if source_abs == target_abs:
			var report := reload_questions()
			var type_name := "数学" if question_type == QuizData.QuestionType.MATH else "问答"
			return {
				"success": true,
				"message": "%s题库重新加载（%d题）" % [type_name, report["loaded"]],
				"loaded": report["loaded"],
				"skipped": report["skipped"],
				"errors": report["errors"],
			}

	# 4. 备份原文件
	var backup_path := target_path + ".bak"
	var has_backup := false
	if FileAccess.file_exists(target_path):
		var dir := DirAccess.open(target_dir)
		if dir:
			if FileAccess.file_exists(backup_path):
				dir.remove(backup_path.get_file())
			var rename_err := dir.rename(target_path.get_file(), backup_path.get_file())
			if rename_err == OK:
				has_backup = true
			else:
				return { "success": false, "message": "备份原题库失败，错误码：%d" % rename_err }

	# 5. 写入目标文件
	if is_xlsx:
		var load_result := _question_loader.load_xlsx(source_path, question_type)
		if load_result["questions"].is_empty():
			if has_backup:
				var dir := DirAccess.open(target_dir)
				if dir:
					dir.rename(backup_path.get_file(), target_path.get_file())
			return { "success": false, "message": "xlsx文件中没有有效题目" }
		var csv_content := "question,answer\n"
		for q: QuizData in load_result["questions"]:
			var question_escaped := q.question
			var answer_escaped := q.answer
			if question_escaped.contains(",") or question_escaped.contains("\"") or question_escaped.contains("\n"):
				question_escaped = "\"" + question_escaped.replace("\"", "\"\"") + "\""
			if answer_escaped.contains(",") or answer_escaped.contains("\"") or answer_escaped.contains("\n"):
				answer_escaped = "\"" + answer_escaped.replace("\"", "\"\"") + "\""
			csv_content += "%s,%s\n" % [question_escaped, answer_escaped]
		var file := FileAccess.open(target_path, FileAccess.WRITE)
		if file == null:
			if has_backup:
				var dir := DirAccess.open(target_dir)
				if dir:
					dir.rename(backup_path.get_file(), target_path.get_file())
			return { "success": false, "message": "写入题库文件失败" }
		file.store_string(csv_content)
		file.close()
	else:
		var copy_err := DirAccess.copy_absolute(source_path, target_path)
		if copy_err != OK:
			if has_backup:
				var dir := DirAccess.open(target_dir)
				if dir:
					dir.remove(target_path.get_file())
					dir.rename(backup_path.get_file(), target_path.get_file())
			return { "success": false, "message": "写入题库文件失败，错误码：%d" % copy_err }

	# 6. 重新加载并验证
	var report := reload_questions()
	if report["loaded"] == 0:
		if has_backup:
			var dir := DirAccess.open(target_dir)
			if dir:
				dir.remove(target_path.get_file())
				dir.rename(backup_path.get_file(), target_path.get_file())
			reload_questions()
		return { "success": false, "message": "题库文件已写入但加载失败，已还原原题库" }

	# 7. 清理备份
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
	}

# 导出题库为 xlsx
func export_question_bank(question_type: QuizData.QuestionType, target_path: String) -> Dictionary:
	if target_path.is_empty():
		return { "success": false, "message": "未选择保存位置" }

	var type_name := "数学" if question_type == QuizData.QuestionType.MATH else "问答"

	# 收集指定类型的题目
	var questions: Array[QuizData] = []
	for q in _all_questions:
		if q.question_type == question_type:
			questions.append(q)

	if questions.is_empty():
		return { "success": false, "message": "当前没有%s题可导出" % type_name }

	var headers: Array[String] = ["question", "answer"]
	var rows: Array[Array] = []
	for q in questions:
		rows.append([q.question, q.answer])

	var xlsx := XlsxHandler.new()
	var result := xlsx.write_xlsx(target_path, headers, rows)
	if not result["success"]:
		return { "success": false, "message": "导出失败: " + result["error"] }

	return {
		"success": true,
		"message": "%s题库导出成功！共 %d 道题\n%s" % [type_name, questions.size(), target_path],
		"count": questions.size(),
	}

# 导出错题本为 xlsx
func export_wrong_records(target_path: String) -> Dictionary:
	if target_path.is_empty():
		return { "success": false, "message": "未选择保存位置" }

	if _wrong_records.is_empty():
		return { "success": false, "message": "错题本为空，没有可导出的内容" }

	var headers: Array[String] = ["question", "answer", "user_answer", "wrong_count"]
	var rows: Array[Array] = []
	for record in _wrong_records:
		rows.append([
			record.get("question", ""),
			record.get("answer", ""),
			record.get("user_answer", ""),
			str(record.get("count", 1)),
		])

	var xlsx := XlsxHandler.new()
	var result := xlsx.write_xlsx(target_path, headers, rows)
	if not result["success"]:
		return { "success": false, "message": "导出失败: " + result["error"] }

	return {
		"success": true,
		"message": "错题本导出成功！共 %d 条错题\n%s" % [_wrong_records.size(), target_path],
		"count": _wrong_records.size(),
	}

# 获取错题本数据
func get_wrong_records() -> Array[Dictionary]:
	return _wrong_records

# 清空错题本
func clear_wrong_records() -> void:
	_wrong_records.clear()
	_save_wrong_records()

func get_random_question() -> QuizData:
	if _all_questions.is_empty():
		reload_questions()
	if _all_questions.is_empty():
		return null
	return _all_questions[randi() % _all_questions.size()]

func start_quiz() -> void:
	if not is_enabled:
		return
	if is_quiz_active:
		return
	var question := get_random_question()
	if question == null:
		push_error("QuizManager: 没有题目可用")
		return
	is_quiz_active = true
	_original_time_scale = Engine.time_scale
	Engine.time_scale = quiz_speed
	_ensure_quiz_ui()
	if is_instance_valid(_quiz_ui) and _quiz_ui.has_method("show_quiz"):
		_quiz_ui.show_quiz(question)
	else:
		push_error("QuizManager: QuizUI无效，无法弹出")
		is_quiz_active = false
		Engine.time_scale = _original_time_scale
		return
	quiz_triggered.emit(question)

func end_quiz(was_correct: bool, question: QuizData, user_answer: String = "") -> void:
	is_quiz_active = false
	Engine.time_scale = _original_time_scale
	if not was_correct:
		EventBus.push_event("add_sun_value", [-wrong_penalty])
		_record_wrong_answer(question, user_answer)
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

func _record_wrong_answer(question: QuizData, user_answer: String = "") -> void:
	var timestamp := Time.get_datetime_string_from_system()
	for record in _wrong_records:
		if record["question"] == question.question and record["type"] == question.question_type:
			record["count"] += 1
			record["last_time"] = timestamp
			record["user_answer"] = user_answer if not user_answer.is_empty() else record.get("user_answer", "")
			_save_wrong_records()
			return
	_wrong_records.append({
		"type": question.question_type,
		"question": question.question,
		"answer": question.answer,
		"user_answer": user_answer,
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
	is_enabled = data.get("enabled", true)
	trigger_frequency = data.get("trigger_frequency", 3)
	quiz_speed = data.get("quiz_speed", 0.25)
	wrong_penalty = data.get("wrong_penalty", 50)
	overlay_opacity = data.get("overlay_opacity", 0.5)
	overlay_blur = data.get("overlay_blur", 3.0)

func save_settings() -> void:
	var path := "user://quiz_settings.json"
	Global.save_json({
		"enabled": is_enabled,
		"trigger_frequency": trigger_frequency,
		"quiz_speed": quiz_speed,
		"wrong_penalty": wrong_penalty,
		"overlay_opacity": overlay_opacity,
		"overlay_blur": overlay_blur,
	}, path)
	settings_changed.emit()
