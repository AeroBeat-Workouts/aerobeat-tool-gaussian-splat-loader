extends RefCounted

var _lines: Array[String] = []
var _index: int = 0

func parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return parse_string(FileAccess.get_file_as_string(path))

func parse_string(text: String) -> Variant:
	_lines.assign(text.split("\n", false))
	_index = 0
	return _parse_node(0)

func _parse_node(indent: int) -> Variant:
	_skip_non_content()
	if _index >= _lines.size():
		return {}
	var line := _current_line()
	var actual_indent := _indent_of(line)
	if actual_indent < indent:
		return {}
	var stripped := _strip_comments(line.strip_edges())
	if stripped.begins_with("- "):
		return _parse_list(indent)
	return _parse_map(indent)

func _parse_map(indent: int) -> Dictionary:
	var result: Dictionary = {}
	while true:
		_skip_non_content()
		if _index >= _lines.size():
			break
		var line := _current_line()
		var actual_indent := _indent_of(line)
		if actual_indent < indent:
			break
		var stripped_line := _strip_comments(line.strip_edges())
		if stripped_line.begins_with("- "):
			break
		if actual_indent > indent:
			_index += 1
			continue
		var split := _split_key_value(stripped_line)
		if split.is_empty():
			_index += 1
			continue
		var key := String(split[0])
		var value_text := String(split[1])
		_index += 1
		if value_text == ">" or value_text == ">-" or value_text == "|" or value_text == "|-":
			result[key] = _parse_block_scalar(indent + 2, value_text.begins_with(">"))
		elif value_text.is_empty():
			var next_indent := _peek_next_indent()
			if next_indent > indent:
				result[key] = _parse_node(indent + 2)
			else:
				result[key] = ""
		else:
			result[key] = _parse_scalar(value_text)
	return result

func _parse_list(indent: int) -> Array:
	var result: Array = []
	while true:
		_skip_non_content()
		if _index >= _lines.size():
			break
		var line := _current_line()
		var actual_indent := _indent_of(line)
		if actual_indent < indent:
			break
		var stripped_line := _strip_comments(line.strip_edges())
		if not stripped_line.begins_with("- "):
			break
		if actual_indent > indent:
			_index += 1
			continue
		var item_text := stripped_line.substr(2)
		_index += 1
		if item_text.is_empty():
			result.append(_parse_node(indent + 2))
			continue
		var split := _split_key_value(item_text)
		if not split.is_empty():
			var item_map: Dictionary = {}
			var key := String(split[0])
			var value_text := String(split[1])
			if value_text == ">" or value_text == ">-" or value_text == "|" or value_text == "|-":
				item_map[key] = _parse_block_scalar(indent + 4, value_text.begins_with(">"))
			elif value_text.is_empty():
				var next_indent := _peek_next_indent()
				if next_indent > indent + 2:
					item_map[key] = _parse_node(indent + 4)
				else:
					item_map[key] = ""
			else:
				item_map[key] = _parse_scalar(value_text)
			item_map.merge(_parse_map(indent + 2))
			result.append(item_map)
		else:
			result.append(_parse_scalar(item_text))
	return result

func _parse_block_scalar(indent: int, folded: bool) -> String:
	var chunks: Array[String] = []
	while _index < _lines.size():
		var line := _current_line()
		if line.strip_edges().is_empty():
			chunks.append("")
			_index += 1
			continue
		var actual_indent := _indent_of(line)
		if actual_indent < indent:
			break
		chunks.append(line.substr(min(indent, line.length())))
		_index += 1
	if folded:
		return _fold_block_scalar(chunks)
	return "\n".join(chunks).strip_edges()

func _fold_block_scalar(chunks: Array[String]) -> String:
	var parts: Array[String] = []
	for chunk in chunks:
		var trimmed := chunk.strip_edges()
		if trimmed.is_empty():
			if not parts.is_empty() and parts[parts.size() - 1] != "\n":
				parts.append("\n")
		else:
			parts.append(trimmed)
	var result := ""
	for part in parts:
		if part == "\n":
			result += "\n"
		elif result.is_empty() or result.ends_with("\n"):
			result += part
		else:
			result += " %s" % part
	return result.strip_edges()

func _parse_scalar(value_text: String) -> Variant:
	var trimmed := value_text.strip_edges()
	if trimmed == "[]":
		return []
	if trimmed == "{}":
		return {}
	if trimmed == "true":
		return true
	if trimmed == "false":
		return false
	if trimmed == "null" or trimmed == "~":
		return null
	if (trimmed.begins_with('"') and trimmed.ends_with('"')) or (trimmed.begins_with("'") and trimmed.ends_with("'")):
		return trimmed.substr(1, trimmed.length() - 2)
	if trimmed.begins_with("[") and trimmed.ends_with("]"):
		return _parse_flow_array(trimmed)
	if trimmed.is_valid_int():
		return int(trimmed)
	if trimmed.is_valid_float():
		return float(trimmed)
	return trimmed

func _parse_flow_array(value: String) -> Array:
	var inner := value.substr(1, value.length() - 2).strip_edges()
	if inner.is_empty():
		return []
	var result: Array = []
	for part in inner.split(",", false):
		result.append(_parse_scalar(String(part).strip_edges()))
	return result

func _split_key_value(text: String) -> Array:
	var in_single := false
	var in_double := false
	for i in text.length():
		var char_text := text.substr(i, 1)
		if char_text == "'" and not in_double:
			in_single = not in_single
		elif char_text == '"' and not in_single:
			in_double = not in_double
		elif char_text == ":" and not in_single and not in_double:
			var key := text.substr(0, i).strip_edges()
			var value := text.substr(i + 1).strip_edges()
			return [key, value]
	return []

func _strip_comments(text: String) -> String:
	var in_single := false
	var in_double := false
	for i in text.length():
		var char_text := text.substr(i, 1)
		if char_text == "'" and not in_double:
			in_single = not in_single
		elif char_text == '"' and not in_single:
			in_double = not in_double
		elif char_text == "#" and not in_single and not in_double:
			if i == 0:
				return ""
			var previous := text.substr(i - 1, 1)
			if previous == " " or previous == "\t":
				return text.substr(0, i).strip_edges(false, true)
	return text

func _skip_non_content() -> void:
	while _index < _lines.size():
		var stripped := _strip_comments(_current_line().strip_edges())
		if not stripped.is_empty():
			return
		_index += 1

func _peek_next_indent() -> int:
	var scan_index := _index
	while scan_index < _lines.size():
		var stripped := _strip_comments(_lines[scan_index].strip_edges())
		if not stripped.is_empty():
			return _indent_of(_lines[scan_index])
		scan_index += 1
	return -1

func _current_line() -> String:
	return _lines[_index]

func _indent_of(line: String) -> int:
	var count := 0
	while count < line.length() and line.substr(count, 1) == " ":
		count += 1
	return count
