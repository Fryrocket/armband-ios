import XCTest
@testable import ArmbandIOS

final class SubjectIDTests: XCTestCase {
    func testParseAcceptsClosedEnumOnly() {
        XCTAssertEqual(SubjectID.parse("SUBJ_A"), .subjA)
        XCTAssertEqual(SubjectID.parse("SUBJ_B"), .subjB)
        XCTAssertNil(SubjectID.parse(nil))
        XCTAssertNil(SubjectID.parse(""))
        XCTAssertNil(SubjectID.parse("SUBJ_C"))
        XCTAssertNil(SubjectID.parse("subj_a"))
        XCTAssertNil(SubjectID.parse("Fry"))
    }

    func testAllCasesAreThePilotPair() {
        XCTAssertEqual(SubjectID.allCases.map(\.rawValue), ["SUBJ_A", "SUBJ_B"])
    }

    func testDefaultsKeyIsSubjectId() {
        XCTAssertEqual(SubjectID.defaultsKey, "subject_id")
    }
}
