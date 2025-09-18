//
//  MrSaveMySpaceTests.swift
//  MrSaveMySpaceTests
//
//  Created by Tian Zhang on 9/13/25.
//

import XCTest

final class MrSaveMySpaceTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}

@testable import MrSaveMySpace

final class DuplicateDetectorTests: XCTestCase {
    func testWhenHashesMatchAndDatesWithinWindow_groupsDuplicates() {
        let baseTime: TimeInterval = 1_000
        let original = Fingerprint(localIdentifier: "0",
                                   creationTime: baseTime,
                                   width: 100,
                                   height: 100,
                                   dHash64: 1)
        let closeDuplicate = Fingerprint(localIdentifier: "1",
                                         creationTime: baseTime + 60,
                                         width: 100,
                                         height: 100,
                                         dHash64: 1)
        let detector = DuplicateDetector(creationWindow: 120)

        let groups = detector.groupExactDuplicates([original, closeDuplicate])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.duplicates.count, 1)
        XCTAssertEqual(groups.first?.duplicates.first?.localIdentifier, "1")
    }

    func testWhenDatesOutsideWindow_doesNotGroup() {
        let baseTime: TimeInterval = 1_000
        let original = Fingerprint(localIdentifier: "0",
                                   creationTime: baseTime,
                                   width: 100,
                                   height: 100,
                                   dHash64: 1)
        let farDuplicate = Fingerprint(localIdentifier: "1",
                                       creationTime: baseTime + 10_000,
                                       width: 100,
                                       height: 100,
                                       dHash64: 1)
        let detector = DuplicateDetector(creationWindow: 120)

        let groups = detector.groupExactDuplicates([original, farDuplicate])

        XCTAssertTrue(groups.isEmpty)
    }
}
