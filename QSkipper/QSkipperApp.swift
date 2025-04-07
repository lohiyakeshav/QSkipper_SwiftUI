//
//  QSkipperApp.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 27/03/25.
//

import SwiftUI
import AuthenticationServices

@main
struct QSkipperApp: App {
    // Initialize shared state managers
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var orderManager = OrderManager.shared
    @StateObject private var favoriteManager = FavoriteManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var tabSelection = TabSelection()
    
    init() {
        print("🚀 QSkipperApp initializing")
        setupAppleSignIn()
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ZStack {
                    // Use SplashView as the initial view
                    // When it finishes, it will navigate to the appropriate view
                    // based on authentication state
                    SplashView()
                        .environmentObject(authManager)
                        .environmentObject(orderManager)
                        .environmentObject(favoriteManager)
                        .environmentObject(locationManager)
                        .environmentObject(tabSelection)
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .preferredColorScheme(.light)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 0)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 1)
            }
            .onAppear {
                print("🚀 QSkipperApp root view appeared")
            }
        }
    }
    
    // Setup Apple Sign In
    private func setupAppleSignIn() {
        print("🍎 Setting up Apple Sign In")
        
        // Initialize state providers
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        
        // Verify current Apple Sign In status on launch
        if let userId = UserDefaults.standard.string(forKey: "user_id"), 
           userId.hasPrefix("apple_") {
            print("🍎🔍 Found saved Apple Sign In user: \(userId)")
            
            // For Apple Sign In users, we consider them logged in if they have user data in UserDefaults
            // We don't attempt to check credential state on startup as this can fail
            if let userName = UserDefaults.standard.string(forKey: "user_name"),
               UserDefaults.standard.bool(forKey: "user_logged_in") {
                print("🍎✅ Verified Apple Sign In user is still logged in: \(userName)")
            } else {
                print("🍎⚠️ Apple user data found but not fully logged in")
            }
        }
        
        // Set up notification observer for credentials
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: OperationQueue.main
        ) { _ in
            print("🍎⚠️ Apple ID credentials revoked notification received")
            // Log out the user if their Apple ID credentials are revoked
            AuthManager.shared.logout()
        }
    }
}
