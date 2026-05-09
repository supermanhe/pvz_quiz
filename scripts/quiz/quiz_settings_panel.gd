extends PanelContainer

const WINDOWS_ONLY_HINT := "仅 PC Windows 端支持本地题库设置"

@onready var header_row: HBoxContainer = $ContentVBox/HeaderRow
@onready var title_button: Button = $ContentVBox/HeaderRow/TitleButton
@onready var collapse_button: Button = $ContentVBox/HeaderRow/CollapseButton
@onready var settings_body: VBoxContainer = $ContentVBox/SettingsBody
@onready var enabled_check: CheckBox = $ContentVBox/SettingsBody/EnabledCheck
@onready var frequency_spin: SpinBox = $ContentVBox/SettingsBody/FrequencyContainer/FrequencySpin
@onready var speed_spin: SpinBox = $ContentVBox/SettingsBody/SpeedContainer/SpeedSpin
@onready var penalty_spin: SpinBox = $ContentVBox/SettingsBody/PenaltyContainer/PenaltySpin
@onready var opacity_slider: HSlider = $ContentVBox/SettingsBody/OpacityContainer/OpacitySlider
@onready var opacity_value: Label = $ContentVBox/SettingsBody/OpacityContainer/OpacityValue
@onready var blur_slider: HSlider = $ContentVBox/SettingsBody/BlurContainer/BlurSlider
@onready var blur_value: Label = $ContentVBox/SettingsBody/BlurContainer/BlurValue
@onready var bank_settings_button: Button = $ContentVBox/SettingsBody/BankSettingsButton
@onready var wrong_records_button: Button = $ContentVBox/SettingsBody/WrongRecordsButton
@onready var bank_dialog: AcceptDialog = $BankDialog
@onready var path_label_math: Label = $BankDialog/Content/MathPathValue
@onready var path_label_qa: Label = $BankDialog/Content/QAPathValue
@onready var status_label: Label = $BankDialog/Content/StatusLabel
@onready var open_folder_button: Button = $BankDialog/Content/Actions/OpenFolderButton
@onready var reload_button: Button = $BankDialog/Content/Actions/ReloadButton
@onready var import_math_button: Button = $BankDialog/Content/ImportButtons/ImportMathButton
@onready var import_qa_button: Button = $BankDialog/Content/ImportButtons/ImportQAButton
@onready var export_math_button: Button = $BankDialog/Content/ExportButtons/ExportMathButton
@onready var export_qa_button: Button = $BankDialog/Content/ExportButtons/ExportQAButton
@onready var file_dialog: FileDialog = $FileDialog
@onready var save_dialog: FileDialog = $SaveDialog
@onready var error_dialog: AcceptDialog = $ErrorDialog
@onready var error_summary: Label = $ErrorDialog/ErrorContent/ErrorSummary
@onready var error_list: VBoxContainer = $ErrorDialog/ErrorContent/ErrorScroll/ErrorList
@onready var wrong_records_dialog: AcceptDialog = $WrongRecordsDialog
@onready var records_count_label: Label = $WrongRecordsDialog/Content/HeaderRow/CountLabel
@onready var export_wrong_button: Button = $WrongRecordsDialog/Content/HeaderRow/ExportWrongButton
@onready var clear_wrong_button: Button = $WrongRecordsDialog/Content/HeaderRow/ClearWrongButton
@onready var records_list: VBoxContainer = $WrongRecordsDialog/Content/RecordsScroll/RecordsList
@onready var wrong_save_dialog: FileDialog = $WrongSaveDialog

var _pending_import_type: QuizData.QuestionType = QuizData.QuestionType.MATH
var _pending_export_type: QuizData.QuestionType = QuizData.QuestionType.MATH
var _is_collapsed := false
var _expanded_panel_style: StyleBoxFlat

const PANEL_X_OFFSET := 36.0

const EXPANDED_LEFT := -330.0 + PANEL_X_OFFSET
const EXPANDED_TOP := 108.0
const EXPANDED_RIGHT := -12.0 + PANEL_X_OFFSET
const EXPANDED_BOTTOM := 498.0

const COLLAPSED_LEFT := -84.0 + PANEL_X_OFFSET
const COLLAPSED_TOP := 108.0
const COLLAPSED_RIGHT := -12.0 + PANEL_X_OFFSET
const COLLAPSED_BOTTOM := 148.0

func _ready() -> void:
	_setup_ui()
	_load_values()
	_refresh_question_bank_info()
	EventBus.subscribe("main_game_progress_update", _on_game_progress_update)

func _on_game_progress_update(progress) -> void:
	if progress is Array and progress.size() > 0:
		progress = progress[0]
	if progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		_apply_collapsed_state(true)

func _setup_ui() -> void:
	_expanded_panel_style = get("theme_override_styles/panel") as StyleBoxFlat
	enabled_check.text = "启用答题模式"
	enabled_check.toggled.connect(_on_setting_changed)

	frequency_spin.min_value = 1
	frequency_spin.max_value = 99
	frequency_spin.value = 3
	frequency_spin.value_changed.connect(_on_setting_changed)

	speed_spin.min_value = 0.1
	speed_spin.max_value = 0.5
	speed_spin.step = 0.05
	speed_spin.value = 0.25
	speed_spin.value_changed.connect(_on_setting_changed)

	penalty_spin.min_value = 0
	penalty_spin.max_value = 999
	penalty_spin.value = 50
	penalty_spin.value_changed.connect(_on_setting_changed)

	# 遮罩透明度滑块
	opacity_slider.min_value = 0.1
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.05
	opacity_slider.value = 0.5
	opacity_slider.value_changed.connect(_on_opacity_changed)

	# 模糊强度滑块
	blur_slider.min_value = 0.0
	blur_slider.max_value = 10.0
	blur_slider.step = 0.5
	blur_slider.value = 3.0
	blur_slider.value_changed.connect(_on_blur_changed)

	title_button.text = "答题学习设置"
	title_button.flat = true
	title_button.pressed.connect(_on_title_button_pressed)
	collapse_button.pressed.connect(_on_collapse_button_pressed)

	bank_settings_button.text = "题库设置"
	bank_settings_button.pressed.connect(_on_bank_settings_button_pressed)

	wrong_records_button.text = "错题本"
	wrong_records_button.pressed.connect(_on_wrong_records_button_pressed)

	bank_dialog.title = "题库设置"
	bank_dialog.dialog_hide_on_ok = true
	bank_dialog.ok_button_text = "关闭"

	open_folder_button.pressed.connect(_on_open_folder_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	import_math_button.pressed.connect(_on_import_math_button_pressed)
	import_qa_button.pressed.connect(_on_import_qa_button_pressed)
	export_math_button.pressed.connect(_on_export_math_button_pressed)
	export_qa_button.pressed.connect(_on_export_qa_button_pressed)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.txt ; 文本题库", "*.csv ; CSV 题库", "*.xlsx ; Excel 题库"])
	file_dialog.file_selected.connect(_on_file_selected)

	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.xlsx ; Excel 文件"])
	save_dialog.file_selected.connect(_on_save_file_selected)

	# 错误弹窗
	error_dialog.title = "导入错误"
	error_dialog.dialog_hide_on_ok = true
	error_dialog.ok_button_text = "确定"

	# 错题本弹窗
	wrong_records_dialog.title = "错题本"
	wrong_records_dialog.dialog_hide_on_ok = true
	wrong_records_dialog.ok_button_text = "关闭"
	export_wrong_button.pressed.connect(_on_export_wrong_pressed)
	clear_wrong_button.pressed.connect(_on_clear_wrong_pressed)

	# 错题本导出对话框
	wrong_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	wrong_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	wrong_save_dialog.filters = PackedStringArray(["*.xlsx ; Excel 文件"])
	wrong_save_dialog.file_selected.connect(_on_wrong_save_file_selected)

func _load_values() -> void:
	enabled_check.button_pressed = QuizManager.is_enabled
	frequency_spin.value = QuizManager.trigger_frequency
	speed_spin.value = QuizManager.quiz_speed
	penalty_spin.value = QuizManager.wrong_penalty
	opacity_slider.value = QuizManager.overlay_opacity
	blur_slider.value = QuizManager.overlay_blur
	opacity_value.text = "%d%%" % int(QuizManager.overlay_opacity * 100)
	blur_value.text = "%.1f" % QuizManager.overlay_blur
	_apply_collapsed_state(false)

func _on_setting_changed(_value = null) -> void:
	QuizManager.is_enabled = enabled_check.button_pressed
	QuizManager.trigger_frequency = int(frequency_spin.value)
	QuizManager.quiz_speed = speed_spin.value
	QuizManager.wrong_penalty = int(penalty_spin.value)
	QuizManager.save_settings()

func _on_opacity_changed(value: float) -> void:
	QuizManager.overlay_opacity = value
	opacity_value.text = "%d%%" % int(value * 100)
	QuizManager.save_settings()

func _on_blur_changed(value: float) -> void:
	QuizManager.overlay_blur = value
	blur_value.text = "%.1f" % value
	QuizManager.save_settings()

func _refresh_question_bank_info(message: String = "") -> void:
	var paths := QuizManager.get_question_bank_display_paths()
	path_label_math.text = str(paths.get("math", ""))
	path_label_qa.text = str(paths.get("qa", ""))
	status_label.text = message if not message.is_empty() else WINDOWS_ONLY_HINT

func _apply_collapsed_state(collapsed: bool) -> void:
	_is_collapsed = collapsed
	settings_body.visible = not collapsed
	collapse_button.visible = not collapsed
	title_button.text = "设置" if collapsed else "答题学习设置"
	title_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if collapsed else Control.SIZE_EXPAND_FILL
	title_button.custom_minimum_size = Vector2(72, 36) if collapsed else Vector2.ZERO

	if collapsed:
		set("theme_override_styles/panel", null)
		offset_left = COLLAPSED_LEFT
		offset_top = COLLAPSED_TOP
		offset_right = COLLAPSED_RIGHT
		offset_bottom = COLLAPSED_BOTTOM
	else:
		if _expanded_panel_style == null:
			_expanded_panel_style = StyleBoxFlat.new()
			_expanded_panel_style.bg_color = Color(0, 0, 0, 0.6)
			_expanded_panel_style.border_width_left = 2
			_expanded_panel_style.border_width_top = 2
			_expanded_panel_style.border_width_right = 2
			_expanded_panel_style.border_width_bottom = 2
			_expanded_panel_style.border_color = Color(1, 1, 1, 0.2)
			_expanded_panel_style.corner_radius_top_left = 12
			_expanded_panel_style.corner_radius_top_right = 12
			_expanded_panel_style.corner_radius_bottom_right = 12
			_expanded_panel_style.corner_radius_bottom_left = 12
			_expanded_panel_style.content_margin_left = 12.0
			_expanded_panel_style.content_margin_top = 12.0
			_expanded_panel_style.content_margin_right = 12.0
			_expanded_panel_style.content_margin_bottom = 12.0
		set("theme_override_styles/panel", _expanded_panel_style)
		offset_left = EXPANDED_LEFT
		offset_top = EXPANDED_TOP
		offset_right = EXPANDED_RIGHT
		offset_bottom = EXPANDED_BOTTOM

func _on_title_button_pressed() -> void:
	_apply_collapsed_state(not _is_collapsed)

func _on_collapse_button_pressed() -> void:
	_apply_collapsed_state(not _is_collapsed)

func _on_bank_settings_button_pressed() -> void:
	_refresh_question_bank_info()
	bank_dialog.popup_centered_ratio(0.5)

func _on_open_folder_button_pressed() -> void:
	var folder_path := str(QuizManager.get_question_bank_display_paths().get("folder", ""))
	if folder_path.is_empty():
		_refresh_question_bank_info("题库目录不可用")
		return

	if not DirAccess.dir_exists_absolute(folder_path):
		var mk_err := DirAccess.make_dir_recursive_absolute(folder_path)
		if mk_err != OK:
			_refresh_question_bank_info("创建题库目录失败，错误码：%d" % mk_err)
			return

	var folder_url := "file:///" + folder_path.replace("\\", "/")
	OS.shell_open(folder_url)
	_refresh_question_bank_info("已尝试打开题库目录")

func _on_reload_button_pressed() -> void:
	var report := QuizManager.reload_questions()
	var msg := "题库已重新加载（%d题）" % report["loaded"]
	if report["skipped"] > 0:
		msg += "\n⚠ 跳过 %d 行有问题的数据" % report["skipped"]
	_refresh_question_bank_info(msg)

func _on_import_math_button_pressed() -> void:
	_pending_import_type = QuizData.QuestionType.MATH
	file_dialog.title = "选择数学题库文件"
	file_dialog.popup_centered_ratio(0.7)

func _on_import_qa_button_pressed() -> void:
	_pending_import_type = QuizData.QuestionType.QA
	file_dialog.title = "选择问答题库文件"
	file_dialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	var result := QuizManager.import_question_bank(path, _pending_import_type)
	if not result["success"]:
		# 显示详细错误弹窗
		_show_import_error_dialog(path, result)
	else:
		_refresh_question_bank_info(result["message"])

func _show_import_error_dialog(file_path: String, result: Dictionary) -> void:
	var file_name := file_path.get_file()
	var errors: Array = result.get("errors", [])
	var err_count := errors.size()

	error_summary.text = "❌ 文件 [%s] 导入失败\n共发现 %d 处问题" % [file_name, err_count]

	# 清空旧的错误列表
	for child in error_list.get_children():
		child.queue_free()

	# 显示每个错误
	var max_errors := mini(err_count, 20)  # 最多显示20条
	for i in range(max_errors):
		var err: Dictionary = errors[i]
		var line_num: int = err.get("line", 0)
		var reason: String = err.get("reason", "未知错误")
		var err_label := Label.new()
		if line_num > 0:
			err_label.text = "📍 第 %d 行：%s" % [line_num, reason]
		else:
			err_label.text = "📍 %s" % reason
		err_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		err_label.add_theme_color_override("font_color", Color(1, 0.8, 0.8))
		error_list.add_child(err_label)

	if err_count > 20:
		var more_label := Label.new()
		more_label.text = "... 还有 %d 条错误未显示" % (err_count - 20)
		more_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		error_list.add_child(more_label)

	error_dialog.popup_centered(Vector2i(700, 400))

func _on_export_math_button_pressed() -> void:
	_pending_export_type = QuizData.QuestionType.MATH
	save_dialog.title = "导出数学题库"
	save_dialog.current_file = "数学题库.xlsx"
	save_dialog.popup_centered_ratio(0.7)

func _on_export_qa_button_pressed() -> void:
	_pending_export_type = QuizData.QuestionType.QA
	save_dialog.title = "导出问答题库"
	save_dialog.current_file = "问答题库.xlsx"
	save_dialog.popup_centered_ratio(0.7)

func _on_save_file_selected(path: String) -> void:
	var result := QuizManager.export_question_bank(_pending_export_type, path)
	_refresh_question_bank_info(result["message"])

# ─── 错题本 ───────────────────────────────────────────

func _on_wrong_records_button_pressed() -> void:
	_refresh_wrong_records_list()
	wrong_records_dialog.popup_centered(Vector2i(860, 500))

func _refresh_wrong_records_list() -> void:
	var records := QuizManager.get_wrong_records()
	records_count_label.text = "共 %d 条错题" % records.size()

	# 清空旧列表
	for child in records_list.get_children():
		child.queue_free()

	if records.is_empty():
		var empty_label := Label.new()
		empty_label.text = "🎉 暂无错题记录"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		records_list.add_child(empty_label)
		return

	# 按做错次数排序（多的在前）
	var sorted_records := records.duplicate()
	sorted_records.sort_custom(func(a, b): return a.get("count", 0) > b.get("count", 0))

	for record in sorted_records:
		var type_name := "数学" if record.get("type", 0) == 0 else "问答"
		var question: String = record.get("question", "")
		var answer: String = record.get("answer", "")
		var user_answer: String = record.get("user_answer", "")
		var count: int = record.get("count", 0)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		# 题目信息
		var info_label := RichTextLabel.new()
		info_label.bbcode_enabled = true
		info_label.fit_content = true
		info_label.custom_minimum_size = Vector2(500, 0)
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var info_text := "[b][%s][/b] %s\n" % [type_name, question]
		info_text += "✅ 正确答案：[color=#4CAF50]%s[/color]\n" % answer
		if not user_answer.is_empty():
			info_text += "❌ 你的答案：[color=#FF5252]%s[/color]" % user_answer
		info_label.text = info_text
		hbox.add_child(info_label)

		# 做错次数
		var count_label := Label.new()
		count_label.text = "×%d" % count
		count_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.custom_minimum_size = Vector2(50, 0)
		hbox.add_child(count_label)

		records_list.add_child(hbox)

		# 分隔线
		var separator := HSeparator.new()
		records_list.add_child(separator)

func _on_export_wrong_pressed() -> void:
	wrong_save_dialog.current_file = "错题本.xlsx"
	wrong_save_dialog.popup_centered_ratio(0.7)

func _on_wrong_save_file_selected(path: String) -> void:
	var result := QuizManager.export_wrong_records(path)
	records_count_label.text = result["message"]

func _on_clear_wrong_pressed() -> void:
	QuizManager.clear_wrong_records()
	_refresh_wrong_records_list()
