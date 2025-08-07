import XCTest
@testable import Whisk

final class IngredientImageServiceTests: XCTestCase {
    func testSluggingBasic() {
        let s = IngredientImageService.shared
        XCTAssertEqual(s.slug(from: "Tomatoes"), "tomato")
        XCTAssertEqual(s.slug(from: "Green Onions"), "green-onion")
        XCTAssertEqual(s.slug(from: "Fresh Tarragon"), "tarragon")
        XCTAssertEqual(s.slug(from: "Chopped Shallots"), "shallot")
    }

    func testAliases() {
        let s = IngredientImageService.shared
        XCTAssertEqual(s.slug(from: "Scallions"), "green-onion")
        XCTAssertEqual(s.slug(from: "Coriander"), "cilantro")
        XCTAssertEqual(s.slug(from: "Aubergine"), "eggplant")
    }
}


