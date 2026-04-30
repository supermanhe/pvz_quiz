class_name XlsxHandler
extends RefCounted

# ─── 读取 xlsx ──────────────────────────────────────────

func read_xlsx(path: String) -> Dictionary:
	var result := { "success": false, "headers": [], "rows": [], "error": "" }

	var zip := ZIPReader.new()
	var err := zip.open(path)
	if err != OK:
		result["error"] = "无法打开xlsx文件（错误码：%d）" % err
		return result

	if not zip.file_exists("xl/worksheets/sheet1.xml"):
		zip.close()
		result["error"] = "xlsx文件格式异常：找不到工作表"
		return result

	var shared_strings := _read_shared_strings(zip)
	var raw_rows := _read_sheet(zip, shared_strings)
	zip.close()

	if raw_rows.is_empty():
		result["success"] = true
		return result

	# 第一行作为 headers，其余作为 rows
	result["headers"] = raw_rows[0]
	for i in range(1, raw_rows.size()):
		result["rows"].append(raw_rows[i])
	result["success"] = true
	return result


func _read_shared_strings(zip: ZIPReader) -> Array[String]:
	var strings: Array[String] = []
	if not zip.file_exists("xl/sharedStrings.xml"):
		return strings

	var xml_bytes := zip.read_file("xl/sharedStrings.xml")
	var parser := XMLParser.new()
	parser.open_buffer(xml_bytes)

	var current_string := ""
	var in_t := false
	var in_r := false  # <r> 富文本 run

	while parser.read() == OK:
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var name := parser.get_node_name()
			if name == "t":
				in_t = true
				current_string = ""
			elif name == "r":
				in_r = true
		elif node_type == XMLParser.NODE_TEXT:
			if in_t:
				current_string += parser.get_node_data()
		elif node_type == XMLParser.NODE_ELEMENT_END:
			var name := parser.get_node_name()
			if name == "t":
				in_t = false
				strings.append(current_string)
			elif name == "r":
				in_r = false
			elif name == "si":
				# 如果 <si> 里没有 <t>（罕见），补一个空串
				if strings.size() < _si_count:
					strings.append("")

	return strings

var _si_count := 0

func _read_sheet(zip: ZIPReader, shared_strings: Array[String]) -> Array[Array]:
	var rows: Array[Array] = []

	var xml_bytes := zip.read_file("xl/worksheets/sheet1.xml")
	var parser := XMLParser.new()
	parser.open_buffer(xml_bytes)

	# 先数 sharedStrings 的 <si> 数量
	if zip.file_exists("xl/sharedStrings.xml"):
		var ss_bytes := zip.read_file("xl/sharedStrings.xml")
		var ss_parser := XMLParser.new()
		ss_parser.open_buffer(ss_bytes)
		_si_count = 0
		while ss_parser.read() == OK:
			if ss_parser.get_node_type() == XMLParser.NODE_ELEMENT and ss_parser.get_node_name() == "si":
				_si_count += 1
	else:
		_si_count = 0

	# 用 dict 临时存每行数据（处理稀疏列）
	var row_dict: Dictionary = {}  # col_index -> value
	var current_row_index := -1
	var cell_type := ""
	var cell_ref := ""
	var in_value := false
	var current_value := ""

	while parser.read() == OK:
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var name := parser.get_node_name()
			if name == "row":
				row_dict = {}
				current_row_index = -1
				for i in range(parser.get_attribute_count()):
					if parser.get_attribute_name(i) == "r":
						current_row_index = parser.get_attribute_value(i).to_int() - 1
			elif name == "c":
				cell_type = ""
				cell_ref = ""
				for i in range(parser.get_attribute_count()):
					var attr_name := parser.get_attribute_name(i)
					if attr_name == "t":
						cell_type = parser.get_attribute_value(i)
					elif attr_name == "r":
						cell_ref = parser.get_attribute_value(i)
			elif name == "v" or name == "is":
				in_value = true
				current_value = ""
			elif name == "t":
				# inline string <is><t>...</t></is>
				in_value = true
				current_value = ""
		elif node_type == XMLParser.NODE_TEXT:
			if in_value:
				current_value += parser.get_node_data()
		elif node_type == XMLParser.NODE_ELEMENT_END:
			var name := parser.get_node_name()
			if name == "v" or name == "t":
				in_value = false
				# 解析值
				var final_value := current_value
				if cell_type == "s":
					# shared string 引用
					var idx := current_value.to_int()
					if idx >= 0 and idx < shared_strings.size():
						final_value = shared_strings[idx]
				# 存入 row_dict
				if not cell_ref.is_empty():
					var indices := _cell_ref_to_indices(cell_ref)
					row_dict[indices.x] = final_value  # 用 col 作 key
			elif name == "row":
				# 组装一行
				if current_row_index >= 0 and not row_dict.is_empty():
					var row_array: Array[String] = []
					var max_col := -1
					for col_idx in row_dict.keys():
						if col_idx > max_col:
							max_col = col_idx
					for c in range(max_col + 1):
						row_array.append(row_dict.get(c, ""))
					rows.append(row_array)

	return rows


func _cell_ref_to_indices(ref: String) -> Vector2i:
	var col := 0
	var row_str := ""
	for c in ref:
		var code := c.unicode_at(0)
		if code >= 65 and code <= 90:  # A-Z
			col = col * 26 + (code - 64)
		elif code >= 97 and code <= 122:  # a-z
			col = col * 26 + (code - 96)
		else:
			row_str += c
	col -= 1
	var row := row_str.to_int() - 1
	return Vector2i(col, row)


# ─── 写入 xlsx ──────────────────────────────────────────

func write_xlsx(path: String, headers: Array[String], rows: Array[Array]) -> Dictionary:
	var result := { "success": false, "error": "" }

	# 收集所有唯一字符串，建立索引
	var all_strings: Array[String] = []
	var string_index: Dictionary = {}
	for h in headers:
		if h not in string_index:
			string_index[h] = all_strings.size()
			all_strings.append(h)
	for row in rows:
		for cell in row:
			var s := str(cell)
			if s not in string_index:
				string_index[s] = all_strings.size()
				all_strings.append(s)

	var zip := ZIPPacker.new()
	var err := zip.open(path)
	if err != OK:
		result["error"] = "无法创建xlsx文件（错误码：%d）" % err
		return result

	# 写入各个 XML 部件
	_write_zip_entry(zip, "[Content_Types].xml", _xml_content_types().to_utf8_buffer())
	_write_zip_entry(zip, "_rels/.rels", _xml_rels().to_utf8_buffer())
	_write_zip_entry(zip, "xl/workbook.xml", _xml_workbook().to_utf8_buffer())
	_write_zip_entry(zip, "xl/_rels/workbook.xml.rels", _xml_workbook_rels().to_utf8_buffer())
	_write_zip_entry(zip, "xl/styles.xml", _xml_styles().to_utf8_buffer())
	_write_zip_entry(zip, "xl/sharedStrings.xml", _xml_shared_strings(all_strings).to_utf8_buffer())
	_write_zip_entry(zip, "xl/worksheets/sheet1.xml", _xml_sheet(headers, rows, string_index).to_utf8_buffer())

	zip.close()
	result["success"] = true
	return result


func _write_zip_entry(zip: ZIPPacker, entry_path: String, data: PackedByteArray) -> void:
	zip.start_file(entry_path)
	zip.write_file(data)
	zip.close_file()


func _col_letter(col: int) -> String:
	var c := col + 1
	var result := ""
	while c > 0:
		c -= 1
		result = char(65 + c % 26) + result
		c = c / 26
	return result


func _xml_escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")


func _xml_content_types() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + \
		'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\n' + \
		'  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\n' + \
		'  <Default Extension="xml" ContentType="application/xml"/>\n' + \
		'  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\n' + \
		'  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\n' + \
		'  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\n' + \
		'  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\n' + \
		'</Types>'


func _xml_rels() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + \
		'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n' + \
		'  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\n' + \
		'</Relationships>'


func _xml_workbook() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + \
		'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\n' + \
		'  <sheets>\n' + \
		'    <sheet name="Sheet1" sheetId="1" r:id="rId1"/>\n' + \
		'  </sheets>\n' + \
		'</workbook>'


func _xml_workbook_rels() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + \
		'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n' + \
		'  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\n' + \
		'  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>\n' + \
		'  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\n' + \
		'</Relationships>'


func _xml_styles() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + \
		'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n' + \
		'  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>\n' + \
		'  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>\n' + \
		'  <borders count="1"><border/></borders>\n' + \
		'  <cellStyleXfs count="1"><xf/></cellStyleXfs>\n' + \
		'  <cellXfs count="1"><xf/></cellXfs>\n' + \
		'</styleSheet>'


func _xml_shared_strings(strings: Array[String]) -> String:
	var xml := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
	xml += '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="%d" uniqueCount="%d">\n' % [strings.size(), strings.size()]
	for s in strings:
		xml += '  <si><t>%s</t></si>\n' % _xml_escape(s)
	xml += '</sst>'
	return xml


func _xml_sheet(headers: Array[String], rows: Array[Array], string_index: Dictionary) -> String:
	var xml := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
	xml += '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n'
	xml += '  <sheetData>\n'

	# 表头行
	xml += '    <row r="1">\n'
	for col in range(headers.size()):
		var ref := _col_letter(col) + "1"
		var idx: int = string_index[headers[col]]
		xml += '      <c r="%s" t="s"><v>%d</v></c>\n' % [ref, idx]
	xml += '    </row>\n'

	# 数据行
	for row_idx in range(rows.size()):
		var row_num := row_idx + 2
		xml += '    <row r="%d">\n' % row_num
		var row: Array = rows[row_idx]
		for col in range(row.size()):
			var ref := _col_letter(col) + str(row_num)
			var cell_value := str(row[col])
			var idx: int = string_index[cell_value]
			xml += '      <c r="%s" t="s"><v>%d</v></c>\n' % [ref, idx]
		xml += '    </row>\n'

	xml += '  </sheetData>\n'
	xml += '</worksheet>'
	return xml
