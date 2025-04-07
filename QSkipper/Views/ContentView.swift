import SwiftUI

struct ContentView: View {
    @State private var isLoading = true
    @State private var showSignInScreen = false
    @StateObject private var authManager = AuthManager.shared
    
    var body: some View {
        ZStack {
            if isLoading {
                // Loading screen while checking authentication state
                loadingView
            } else if authManager.isLoggedIn {
                // Main app content when authenticated
                HomeView()
                    .onAppear {
                        print("🔐 ContentView - User authenticated, displaying HomeView")
                        print("🔐 User data: ID=\(authManager.getCurrentUserId() ?? "nil"), Name=\(authManager.getCurrentUserName() ?? "nil")")
                    }
            } else {
                // Login screen when not authenticated
                StartView()
                    .onAppear {
                        print("🔓 ContentView - User not authenticated, displaying StartView")
                    }
            }
        }
        .onAppear {
            print("📱 ContentView - onAppear triggered")
            
            // Check if we have valid user data
            let userId = authManager.getCurrentUserId()
            let userName = authManager.getCurrentUserName()
            let userEmail = authManager.getCurrentUserEmail()
            
            print("""
            📱 ContentView - User data check:
            - User ID: \(userId ?? "nil")
            - User Name: \(userName ?? "nil")
            - User Email: \(userEmail ?? "nil")
            - isLoggedIn: \(authManager.isLoggedIn)
            """)
            
            // If isLoggedIn is true but we're missing crucial user data, force logout
            if authManager.isLoggedIn && (userId == nil || userName == nil) {
                print("⚠️ ContentView - Logged in but missing user data, forcing logout")
                authManager.logout()
            }
            
            print("📱 Authentication state after check: isLoggedIn=\(authManager.isLoggedIn)")
            
            // Display splash screen for 2 seconds before showing main content
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("📱 ContentView - Splash screen timeout, updating UI")
                print("📱 Authentication state before update: isLoggedIn=\(authManager.isLoggedIn)")
                
                withAnimation {
                    isLoading = false
                }
            }
        }
        .onChange(of: authManager.isLoggedIn) { newValue in
            print("🔄 ContentView - Authentication state changed to: \(newValue)")
        }
    }
    
    // Loading/splash screen view
    private var loadingView: some View {
        ZStack {
            // Background color
            Color(hex: "#f8f8f8")
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // App logo - using UIImage to avoid ambiguous init
                if let logoImage = UIImage(named: "Logo") {
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                } else {
                    // Fallback if logo image is not found
                    Image(systemName: "fork.knife")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(AppColors.primaryGreen)
                        .frame(width: 120, height: 120)
                }
                
                // Use LottieWebAnimationView directly instead of AnimationView to avoid ambiguity
                LottieWebAnimationView(
                    webURL: "https://lottie.host/20b64309-9089-4464-a4c5-f9a1ab3dbba1/l5b3WsrLuK.lottie",
                    loopMode: .loop,
                    autoplay: true,
                    contentMode: .scaleAspectFit
                )
                .frame(width: 100, height: 100)
                
                Text("QSkipper")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.darkGray)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 