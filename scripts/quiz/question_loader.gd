class_name QuestionLoader
extends RefCounted

const MATH_CSV_PATH := "res://data/quiz_math.csv"
const QA_CSV_PATH := "res://data/quiz_qa.csv"

func load_all_questions() -> Array[QuizData]:
	var questions: Array[QuizData] = []
	questions.append_array(_load_csv(MATH_CSV_PATH, QuizData.QuestionType.MATH))
	questions.append_array(_load_csv(QA_CSV_PATH, QuizData.QuestionType.QA))
	return questions

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
