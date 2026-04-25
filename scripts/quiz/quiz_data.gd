class_name QuizData
extends RefCounted

enum QuestionType {
	MATH,
	QA,
}

var id: int = 0
var question_type: QuestionType = QuestionType.MATH
var question: String = ""
var answer: String = ""
