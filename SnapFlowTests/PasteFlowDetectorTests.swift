import XCTest

final class PasteFlowDetectorTests: XCTestCase {
	func testPasteFlowTypeDoesNotIncludeRichText() {
		let type = PasteFlowType.email("user@example.com")

		switch type {
		case .url,
				.email,
				.phone,
				.address,
				.ipAddress,
				.color,
				.dateTime,
				.timestamp,
				.json,
				.math,
				.tracking:
			break
		}
	}

	func testDetectsURL() {
		guard case let .url(url)? = PasteFlowDetector.detect("https://example.com/path") else {
			return XCTFail("应识别为 URL")
		}
		XCTAssertEqual(url.absoluteString, "https://example.com/path")
	}

	func testPlainWordIsNotURL() {
		if case .url = PasteFlowDetector.detect("example.com") {
			XCTFail("无协议前缀不应判为 URL")
		}
	}

	func testDetectsEmail() {
		guard case let .email(value)? = PasteFlowDetector.detect("user.name@example.co.uk") else {
			return XCTFail("应识别为邮箱")
		}
		XCTAssertEqual(value, "user.name@example.co.uk")
	}

	func testDetectsIPAddress() {
		guard case let .ipAddress(value)? = PasteFlowDetector.detect("8.8.8.8") else {
			return XCTFail("应识别为 IP")
		}
		XCTAssertEqual(value, "8.8.8.8")
	}

	func testRejectsOutOfRangeIP() {
		if case .ipAddress = PasteFlowDetector.detect("999.1.1.1") {
			XCTFail("超范围段不应判为 IP")
		}
	}

	func testDetectsHexColor() {
		guard case let .color(color)? = PasteFlowDetector.detect("#FF8800") else {
			return XCTFail("应识别为颜色")
		}
		XCTAssertEqual(color.red, 255)
		XCTAssertEqual(color.green, 136)
		XCTAssertEqual(color.blue, 0)
		XCTAssertEqual(color.hex, "#FF8800")
	}

	func testDetectsShortHexColor() {
		guard case let .color(color)? = PasteFlowDetector.detect("#0f0") else {
			return XCTFail("应识别 3 位十六进制颜色")
		}
		XCTAssertEqual(color.red, 0)
		XCTAssertEqual(color.green, 255)
		XCTAssertEqual(color.blue, 0)
	}

	func testDetectsRGBColor() {
		guard case let .color(color)? = PasteFlowDetector.detect("rgb(10, 20, 30)") else {
			return XCTFail("应识别 rgb() 颜色")
		}
		XCTAssertEqual(color.red, 10)
		XCTAssertEqual(color.green, 20)
		XCTAssertEqual(color.blue, 30)
	}

	func testDetectsMath() {
		guard case let .math(_, result)? = PasteFlowDetector.detect("12+3*4") else {
			return XCTFail("应识别为数学式")
		}
		XCTAssertEqual(result, 24, accuracy: 0.0001)
	}

	func testMathRespectsParentheses() {
		XCTAssertEqual(PasteFlowDetector.detectMath("(1+2)*3"), 9)
	}

	func testMathHandlesNegativeAndDivision() {
		XCTAssertEqual(PasteFlowDetector.detectMath("-6/2"), -3)
	}

	func testMathRejectsDivisionByZero() {
		XCTAssertNil(PasteFlowDetector.detectMath("1/0"))
	}

	func testPlainNumberIsNotMath() {
		if case .math = PasteFlowDetector.detect("12345") {
			XCTFail("纯数字不应判为数学式")
		}
	}

	func testDetectsPhone() {
		guard case let .phone(value)? = PasteFlowDetector.detect("+1 415-555-1234") else {
			return XCTFail("应识别为电话")
		}
		XCTAssertEqual(value, "+1 415-555-1234")
	}

	func testDetectsDate() {
		if case .dateTime? = PasteFlowDetector.detect("2026-07-13") {
			// ok
		} else {
			XCTFail("应识别为日期")
		}
	}

	func testDetectsAddress() {
		if case .address? = PasteFlowDetector.detect("北京市海淀区中关村大街1号") {
			// ok
		} else {
			XCTFail("应识别为地址")
		}
	}

	func testCodeIdentifiersAreNotAddresses() {
		XCTAssertNil(PasteFlowDetector.detect("keywordTypeDao"))
		XCTAssertNil(PasteFlowDetector.detect("findKeywordTypeByName"))
	}

	func testPlainSentenceReturnsNil() {
		XCTAssertNil(PasteFlowDetector.detect("这是一句普通的话"))
	}

	func testDetectsJSONObject() {
		guard case let .json(pretty)? = PasteFlowDetector.detect("{\"b\":1,\"a\":2}") else {
			return XCTFail("应识别为 JSON")
		}
		XCTAssertTrue(pretty.contains("\"a\""))
		XCTAssertTrue(pretty.contains("\n")) // 已格式化为多行
	}

	func testDetectsJSONArray() {
		if case .json? = PasteFlowDetector.detect("[1, 2, 3]") {
			// ok
		} else {
			XCTFail("应识别 JSON 数组")
		}
	}

	func testInvalidJSONReturnsNil() {
		if case .json? = PasteFlowDetector.detect("{not valid json}") {
			XCTFail("非法 JSON 不应判为 JSON")
		}
	}

	func testDetectsUnixTimestampSeconds() {
		guard case let .timestamp(_, formatted)? = PasteFlowDetector.detect("1700000000") else {
			return XCTFail("应识别 10 位秒级时间戳")
		}
		XCTAssertTrue(formatted.hasPrefix("2023-11-"))
	}

	func testDetectsUnixTimestampMilliseconds() {
		if case .timestamp? = PasteFlowDetector.detect("1700000000000") {
			// ok
		} else {
			XCTFail("应识别 13 位毫秒级时间戳")
		}
	}

	func testSmallNumberIsNotTimestamp() {
		if case .timestamp? = PasteFlowDetector.detect("12345") {
			XCTFail("过小的数字不应判为时间戳")
		}
	}
}
