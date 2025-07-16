import XCTest

final class DashPayiOSUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func test_mainTabsExist() throws {
        // Test that main tabs are visible
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        
        // Check for Core tab
        let coreTab = tabBar.buttons["Core"]
        XCTAssertTrue(coreTab.exists)
        
        // Check for Platform tab
        let platformTab = tabBar.buttons["Platform"]
        XCTAssertTrue(platformTab.exists)
        
        // Check for Bridge tab
        let bridgeTab = tabBar.buttons["Bridge"]
        XCTAssertTrue(bridgeTab.exists)
    }
    
    func test_navigateBetweenTabs() throws {
        let tabBar = app.tabBars.firstMatch
        
        // Start on Core tab
        let coreTab = tabBar.buttons["Core"]
        coreTab.tap()
        
        // Navigate to Platform tab
        let platformTab = tabBar.buttons["Platform"]
        platformTab.tap()
        
        // Navigate to Bridge tab
        let bridgeTab = tabBar.buttons["Bridge"]
        bridgeTab.tap()
        
        // Should see the unified dashboard
        let dashboardTitle = app.staticTexts["Unified Dashboard"]
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: 5))
    }
    
    func test_createWalletFlow() throws {
        // This test would verify the wallet creation flow
        // but requires the app to be in the correct state
        
        let tabBar = app.tabBars.firstMatch
        let coreTab = tabBar.buttons["Core"]
        coreTab.tap()
        
        // Look for create wallet button or empty state
        let createWalletButton = app.buttons["Create Wallet"]
        if createWalletButton.exists {
            createWalletButton.tap()
            
            // Verify we're on the create wallet screen
            let createWalletTitle = app.navigationBars["Create Wallet"]
            XCTAssertTrue(createWalletTitle.waitForExistence(timeout: 5))
        }
    }
}