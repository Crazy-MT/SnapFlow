import Foundation

/// 检测到的剪贴板内容类型。纯数据，不依赖 AppKit，便于单元测试。
enum PasteFlowType: Equatable {
	case url(URL)
	case email(String)
	case phone(String)
	case address(String)
	case ipAddress(String)
	case color(PasteFlowColor)
	case dateTime(Date)
	case timestamp(date: Date, formatted: String)
	case json(pretty: String)
	case math(expression: String, result: Double)
	case tracking(String)
	case richHTML(String)
}

/// 具名结构承载颜色，避免元组的 Equatable 麻烦。
struct PasteFlowColor: Equatable {
	let red: Int
	let green: Int
	let blue: Int

	var hex: String {
		String(format: "#%02X%02X%02X", red, green, blue)
	}

	var rgbString: String {
		"rgb(\(red), \(green), \(blue))"
	}
}

enum PasteFlowDetector {
	/// 按「先具体后宽泛」的顺序判定，返回第一个命中的类型。
	static func detect(_ rawText: String) -> PasteFlowType? {
		let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return nil }

		if let url = detectURL(text) {
			return .url(url)
		}
		if let pretty = detectJSON(text) {
			return .json(pretty: pretty)
		}
		if detectEmail(text) {
			return .email(text)
		}
		if detectIPAddress(text) {
			return .ipAddress(text)
		}
		if let color = detectColor(text) {
			return .color(color)
		}
		// dateTime 排在 phone/math 之前：形如 "2026-07-13" 的日期只含数字与 '-'，
		// 会同时匹配 phone 正则和 math 字符集，需优先判定。
		if let date = detectDateTime(text) {
			return .dateTime(date)
		}
		// timestamp 排在 phone/tracking 之前：纯数字（10 位秒 / 13 位毫秒）会同时
		// 匹配 phone(7-15 位数字) 和 tracking(13-14 位数字)，需按合理年份范围优先判定。
		if let timestamp = detectTimestamp(text) {
			return .timestamp(date: timestamp.0, formatted: timestamp.1)
		}
		if let phone = detectPhone(text) {
			return .phone(phone)
		}
		if let result = detectMath(text) {
			return .math(expression: text, result: result)
		}
		if detectTracking(text) {
			return .tracking(text)
		}
		if detectAddress(text) {
			return .address(text)
		}

		return nil
	}

	// MARK: - URL

	private static func detectURL(_ text: String) -> URL? {
		guard !text.contains(" "), !text.contains("\n") else { return nil }
		let lowered = text.lowercased()
		guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return nil }
		guard let url = URL(string: text), url.host != nil else { return nil }
		return url
	}

	// MARK: - JSON

	/// 以 { 或 [ 开头，且能被 JSONSerialization 解析的字符串，返回美化后的文本。
	private static func detectJSON(_ text: String) -> String? {
		guard let first = text.first, first == "{" || first == "[" else { return nil }
		guard let data = text.data(using: .utf8) else { return nil }
		guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
		let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		guard let prettyData = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
		return String(data: prettyData, encoding: .utf8)
	}

	// MARK: - Timestamp

	/// 纯数字的 Unix 时间戳：10 位按秒、13 位按毫秒。
	/// 用合理年份范围（2001-2286）过滤，避免把普通数字/电话/单号误判为时间戳。
	private static func detectTimestamp(_ text: String) -> (Date, String)? {
		guard text.allSatisfy(\.isNumber) else { return nil }
		let seconds: TimeInterval
		switch text.count {
		case 10:
			guard let value = TimeInterval(text) else { return nil }
			seconds = value
		case 13:
			guard let value = TimeInterval(text) else { return nil }
			seconds = value / 1000
		default:
			return nil
		}

		// 1_000_000_000 ≈ 2001-09-09，9_999_999_999 ≈ 2286-11-20（秒）。
		guard seconds >= 1_000_000_000, seconds <= 9_999_999_999 else { return nil }

		let date = Date(timeIntervalSince1970: seconds)
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		return (date, formatter.string(from: date))
	}

	// MARK: - Email

	private static func detectEmail(_ text: String) -> Bool {
		matches(text, pattern: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$", caseInsensitive: true)
	}

	// MARK: - IP

	private static func detectIPAddress(_ text: String) -> Bool {
		let segments = text.split(separator: ".", omittingEmptySubsequences: false)
		guard segments.count == 4 else { return false }
		for segment in segments {
			guard let value = Int(segment), value >= 0, value <= 255 else { return false }
			// 拒绝前导零（如 "01"），避免把奇怪串误判为 IP。
			if segment.count > 1, segment.hasPrefix("0") { return false }
		}
		return true
	}

	// MARK: - Color

	private static func detectColor(_ text: String) -> PasteFlowColor? {
		if text.hasPrefix("#") {
			let hex = String(text.dropFirst())
			if hex.count == 6, let value = Int(hex, radix: 16) {
				return PasteFlowColor(
					red: (value >> 16) & 0xFF,
					green: (value >> 8) & 0xFF,
					blue: value & 0xFF
				)
			}
			if hex.count == 3 {
				let chars = Array(hex)
				func expand(_ c: Character) -> Int? {
					guard let v = Int(String(c), radix: 16) else { return nil }
					return v * 16 + v
				}
				if let r = expand(chars[0]), let g = expand(chars[1]), let b = expand(chars[2]) {
					return PasteFlowColor(red: r, green: g, blue: b)
				}
			}
			return nil
		}

		let lowered = text.lowercased().replacingOccurrences(of: " ", with: "")
		guard lowered.hasPrefix("rgb("), lowered.hasSuffix(")") else { return nil }
		let inner = lowered.dropFirst(4).dropLast()
		let parts = inner.split(separator: ",")
		guard parts.count == 3 else { return nil }
		var values: [Int] = []
		for part in parts {
			guard let value = Int(part), value >= 0, value <= 255 else { return nil }
			values.append(value)
		}
		return PasteFlowColor(red: values[0], green: values[1], blue: values[2])
	}

	// MARK: - Math

	/// 只接受由数字与 + - * / ( ) . 空格 组成、且至少含一个运算符的表达式。
	static func detectMath(_ text: String) -> Double? {
		let allowed = CharacterSet(charactersIn: "0123456789+-*/(). ")
		guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
		let operators = CharacterSet(charactersIn: "+*/") // 注意：单独的 '-' 可能是负号，另行判断
		let hasBinaryOperator = text.dropFirst().unicodeScalars.contains { operators.contains($0) || $0 == "-" }
		guard hasBinaryOperator else { return nil }
		guard text.contains(where: { $0.isNumber }) else { return nil }

		var parser = MathParser(text)
		guard let value = parser.parse() else { return nil }
		return value
	}

	// MARK: - Phone

	private static func detectPhone(_ text: String) -> String? {
		let phonePattern = "^\\+?[0-9][0-9\\s\\-()]{5,}$"
		guard matches(text, pattern: phonePattern, caseInsensitive: false) else { return nil }
		let digitCount = text.filter(\.isNumber).count
		guard digitCount >= 7, digitCount <= 15 else { return nil }
		return text
	}

	// MARK: - Tracking

	/// 覆盖有限的常见快递单号模式，并非穷尽。
	private static func detectTracking(_ text: String) -> Bool {
		let upper = text.uppercased()
		let patterns = [
			"^SF[0-9]{12,15}$",          // 顺丰
			"^YT[0-9]{10,15}$",          // 圆通
			"^1Z[0-9A-Z]{16}$",          // UPS
			"^[0-9]{12}$",               // FedEx 12 位
			"^[0-9]{13,14}$"             // 通用 13-14 位数字
		]
		return patterns.contains { matches(upper, pattern: $0, caseInsensitive: false) }
	}

	// MARK: - Date / Time

	private static func detectDateTime(_ text: String) -> Date? {
		let isoFormatter = ISO8601DateFormatter()
		if let date = isoFormatter.date(from: text) {
			return date
		}

		let formats = [
			"yyyy-MM-dd HH:mm:ss",
			"yyyy-MM-dd HH:mm",
			"yyyy-MM-dd",
			"yyyy/MM/dd HH:mm",
			"yyyy/MM/dd",
			"MM/dd/yyyy"
		]
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		for format in formats {
			formatter.dateFormat = format
			if let date = formatter.date(from: text) {
				return date
			}
		}
		return nil
	}

	// MARK: - Address（弱启发式，作为兜底）

	private static func detectAddress(_ text: String) -> Bool {
		guard text.count >= 6, text.count <= 120 else { return false }
		let keywords = ["路", "街", "号", "室", "区", "省", "市", "县", "巷",
						"Street", "St.", "Avenue", "Ave", "Road", "Rd", "Blvd", "Lane"]
		let lowered = text.lowercased()
		return keywords.contains { lowered.contains($0.lowercased()) }
	}

	// MARK: - Helpers

	private static func matches(_ text: String, pattern: String, caseInsensitive: Bool) -> Bool {
		let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
		guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
		let range = NSRange(text.startIndex..<text.endIndex, in: text)
		return regex.firstMatch(in: text, options: [], range: range) != nil
	}
}

/// 手写递归下降解析器：expr → term → factor，支持 + - * / 与括号、负号。
private struct MathParser {
	private let characters: [Character]
	private var index = 0

	init(_ text: String) {
		characters = Array(text.filter { !$0.isWhitespace })
	}

	mutating func parse() -> Double? {
		guard let value = parseExpression() else { return nil }
		guard index == characters.count else { return nil } // 必须消费全部输入
		return value
	}

	private mutating func parseExpression() -> Double? {
		guard var result = parseTerm() else { return nil }
		while let op = peek(), op == "+" || op == "-" {
			index += 1
			guard let rhs = parseTerm() else { return nil }
			result = op == "+" ? result + rhs : result - rhs
		}
		return result
	}

	private mutating func parseTerm() -> Double? {
		guard var result = parseFactor() else { return nil }
		while let op = peek(), op == "*" || op == "/" {
			index += 1
			guard let rhs = parseFactor() else { return nil }
			if op == "/" {
				guard rhs != 0 else { return nil }
				result /= rhs
			} else {
				result *= rhs
			}
		}
		return result
	}

	private mutating func parseFactor() -> Double? {
		guard let char = peek() else { return nil }

		if char == "+" {
			index += 1
			return parseFactor()
		}
		if char == "-" {
			index += 1
			guard let value = parseFactor() else { return nil }
			return -value
		}
		if char == "(" {
			index += 1
			guard let value = parseExpression() else { return nil }
			guard peek() == ")" else { return nil }
			index += 1
			return value
		}
		return parseNumber()
	}

	private mutating func parseNumber() -> Double? {
		var digits = ""
		while let char = peek(), char.isNumber || char == "." {
			digits.append(char)
			index += 1
		}
		guard !digits.isEmpty else { return nil }
		return Double(digits)
	}

	private func peek() -> Character? {
		index < characters.count ? characters[index] : nil
	}
}
