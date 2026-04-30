class_name QuestionLoader
extends RefCounted

const DEFAULT_MATH_CSV_PATH := "res://data/quiz_math.txt"
const DEFAULT_QA_CSV_PATH := "res://data/quiz_qa.txt"
const USER_MATH_CSV_PATH := "user://quiz_banks/quiz_math.txt"
const USER_QA_CSV_PATH := "user://quiz_banks/quiz_qa.txt"

const MAX_FILE_SIZE_BYTES := 5 * 1024 * 1024  # 5MB
const MAX_QUESTION_COUNT := 10000

# 全局递增 id，确保跨题库唯一
var _next_id := 1

# ─── 公开接口 ───────────────────────────────────────────

func load_all_questions() -> Array[QuizData]:
	return load_all_questions_with_report()["questions"]

func load_all_questions_with_report() -> Dictionary:
	_next_id = 1
	var questions: Array[QuizData] = []
	var all_errors: Array[Dictionary] = []
	var total := 0
	var skipped := 0
	var warnings: Array[String] = []

	var math_result := _load_csv(get_math_csv_path(), QuizData.QuestionType.MATH)
	questions.append_array(math_result["questions"])
	all_errors.append_array(math_result["errors"])
	total += math_result["total"]
	skipped += math_result["skipped"]

	var qa_result := _load_csv(get_qa_csv_path(), QuizData.QuestionType.QA)
	questions.append_array(qa_result["questions"])
	all_errors.append_array(qa_result["errors"])
	total += qa_result["total"]
	skipped += qa_result["skipped"]

	if questions.size() > MAX_QUESTION_COUNT:
		warnings.append("题库较大(%d题)，加载可能较慢" % questions.size())

	if not all_errors.is_empty():
		print("QuizManager: 加载完成 %d/%d题，跳过%d行" % [questions.size(), total, skipped])
		for err in all_errors:
			print("  第%d行: %s" % [err["line"], err["reason"]])

	return {
		"questions": questions,
		"total": total,
		"loaded": questions.size(),
		"skipped": skipped,
		"errors": all_errors,
		"warnings": warnings,
	}

# 导入前校验，不修改任何文件
func validate_csv(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "valid": false, "total": 0, "would_load": 0, "errors": [{ "line": 0, "reason": "文件不存在: " + path }] }

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { "valid": false, "total": 0, "would_load": 0, "errors": [{ "line": 0, "reason": "无法读取文件: " + path }] }

	var content := file.get_as_text()
	file.close()

	# 去除 UTF-8 BOM
	if content.begins_with("\ufeff"):
		content = content.substr(1)

	# 文件大小检查
	var file_size := content.length()
	var warnings: Array[String] = []
	if file_size > MAX_FILE_SIZE_BYTES:
		warnings.append("文件较大(%.1fMB)，加载可能较慢" % (file_size / 1048576.0))

	var records := _split_csv_records(content)
	var errors: Array[Dictionary] = []
	var valid_count := 0
	var data_lines := 0

	for i in range(records.size()):
		var record: String = records[i]
		if record.is_empty():
			continue
		# 跳过表头
		var lower := record.to_lower()
		if i == 0 and (lower.begins_with("question") or lower.begins_with("\ufeffquestion")):
			continue
		data_lines += 1
		var fields := _parse_csv_line(record)
		if fields.size() < 2:
			errors.append({ "line": i + 1, "reason": "列数不足(需≥2列，实际%d列): %s" % [fields.size(), record.left(60)] })
		elif fields[0].strip_edges().is_empty():
			errors.append({ "line": i + 1, "reason": "题目为空" })
		else:
			valid_count += 1

	return {
		"valid": errors.is_empty(),
		"total": data_lines,
		"would_load": valid_count,
		"errors": errors,
		"warnings": warnings,
	}

func get_math_csv_path() -> String:
	if FileAccess.file_exists(USER_MATH_CSV_PATH):
		return USER_MATH_CSV_PATH
	return DEFAULT_MATH_CSV_PATH

func get_qa_csv_path() -> String:
	if FileAccess.file_exists(USER_QA_CSV_PATH):
		return USER_QA_CSV_PATH
	return DEFAULT_QA_CSV_PATH

func get_current_bank_paths() -> Dictionary:
	return {
		"math": get_math_csv_path(),
		"qa": get_qa_csv_path(),
		"math_default": DEFAULT_MATH_CSV_PATH,
		"qa_default": DEFAULT_QA_CSV_PATH,
		"math_user": USER_MATH_CSV_PATH,
		"qa_user": USER_QA_CSV_PATH,
	}

# ─── 内部实现 ───────────────────────────────────────────

func _load_csv(path: String, type: QuizData.QuestionType) -> Dictionary:
	var questions: Array[QuizData] = []
	var errors: Array[Dictionary] = []
	var skipped := 0
	var total := 0

	if not FileAccess.file_exists(path):
		print("QuizManager: CSV file not found: ", path)
		return { "questions": questions, "total": 0, "skipped": 0, "errors": errors }

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("QuizManager: Cannot open CSV file: " + path)
		return { "questions": questions, "total": 0, "skipped": 0, "errors": errors }

	var content := file.get_as_text()
	file.close()

	# 去除 UTF-8 BOM（Excel 导出的 CSV 常见）
	if content.begins_with("\ufeff"):
		content = content.substr(1)

	var records := _split_csv_records(content)
	for i in range(records.size()):
		var record: String = records[i]
		if record.is_empty():
			continue
		# 跳过表头（首行且以 question 开头，忽略 BOM 残留）
		var lower := record.to_lower()
		if i == 0 and (lower.begins_with("question") or lower.begins_with("\ufeffquestion")):
			continue

		total += 1
		var fields := _parse_csv_line(record)

		if fields.size() < 2:
			skipped += 1
			errors.append({ "line": i + 1, "reason": "列数不足: %s" % record.left(60) })
			continue

		var question_text := fields[0].strip_edges()
		if question_text.is_empty():
			skipped += 1
			errors.append({ "line": i + 1, "reason": "题目为空" })
			continue

		var q := QuizData.new()
		q.id = _next_id
		_next_id += 1
		q.question_type = type
		q.question = question_text
		q.answer = fields[1].strip_edges()

		if fields.size() > 2:
			print("QuizManager: 第%d行有%d列，额外列已忽略" % [i + 1, fields.size()])

		questions.append(q)

	return { "questions": questions, "total": total, "skipped": skipped, "errors": errors }


# 标准 CSV 解析：处理引号包裹、逗号、转义双引号
func _parse_csv_line(line: String) -> PackedStringArray:
	var fields: PackedStringArray = []
	var current := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if in_quotes:
			if c == '"':
				if i + 1 < line.length() and line[i + 1] == '"':
					current += '"'
					i += 1
				else:
					in_quotes = false
			else:
				current += c
		else:
			if c == '"':
				in_quotes = true
			elif c == ',':
				fields.append(current)
				current = ""
			else:
				current += c
		i += 1
	fields.append(current)
	return fields


# 将文件内容拆分为逻辑 CSV 记录（处理引号内的换行）
func _split_csv_records(content: String) -> PackedStringArray:
	var records: PackedStringArray = []
	var current := ""
	var in_quotes := false
	var i := 0
	while i < content.length():
		var c := content[i]
		if in_quotes:
			if c == '"':
				if i + 1 < content.length() and content[i + 1] == '"':
					current += '"'
					i += 1
				else:
					in_quotes = false
				current += c  # 保留引号供 _parse_csv_line 处理
			else:
				current += c
		else:
			if c == '"':
				in_quotes = true
				current += c
			elif c == '\n':
				var trimmed := current.strip_edges()
				if not trimmed.is_empty():
					records.append(trimmed)
				current = ""
			elif c == '\r':
				pass
			else:
				current += c
		i += 1
	var trimmed := current.strip_edges()
	if not trimmed.is_empty():
		records.append(trimmed)
	return records
