class_name QuestionLoader
extends RefCounted

const DEFAULT_MATH_CSV_PATH := "res://data/quiz_math.txt"
const DEFAULT_QA_CSV_PATH := "res://data/quiz_qa.txt"
const USER_MATH_CSV_PATH := "user://quiz_banks/quiz_math.txt"
const USER_QA_CSV_PATH := "user://quiz_banks/quiz_qa.txt"

func load_all_questions() -> Array[QuizData]:
	var questions: Array[QuizData] = []
	questions.append_array(_load_csv(get_math_csv_path(), QuizData.QuestionType.MATH))
	questions.append_array(_load_csv(get_qa_csv_path(), QuizData.QuestionType.QA))
	return questions

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

func _load_csv(path: String, type: QuizData.QuestionType) -> Array[QuizData]:
	var questions: Array[QuizData] = []
	if not FileAccess.file_exists(path):
		print("QuizManager: CSV file not found: ", path)
		return questions

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("QuizManager: Cannot open CSV file: " + path)
		return questions

	var line_index := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "":
			continue
		if line_index == 0:
			line_index += 1
			continue

		var parts := line.split(",")
		if parts.size() < 2:
			continue

		var q := QuizData.new()
		q.id = line_index
		q.question_type = type
		q.question = parts[0].strip_edges()
		if parts.size() >= 2:
			q.answer = parts[1].strip_edges()
		questions.append(q)
		line_index += 1

	file.close()
	return questions
