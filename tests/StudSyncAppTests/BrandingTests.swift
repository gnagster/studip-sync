import AppKit
import Testing
@testable import StudSyncApp

struct BrandingTests {
    @Test func bundledLogoAndAppIconDecode() throws {
        for (name, extensionName) in [("ClassicFold", "png"), ("AppIcon", "icns")] {
            let url = try #require(appResourceBundle.url(forResource: name, withExtension: extensionName))
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width > 0 && image.size.height > 0)
        }
    }
}
