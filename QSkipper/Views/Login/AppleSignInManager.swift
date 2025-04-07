import SwiftUI
import AuthenticationServices

// Class for handling Apple Sign In logic
class AppleSignInManager: NSObject, ASAuthorizationControllerDelegate {
    var onSignInSuccess: () -> Void
    var onSignInFailure: (String) -> Void
    
    init(onSuccess: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        self.onSignInSuccess = onSuccess
        self.onSignInFailure = onFailure
        super.init()
    }
    
    // Start the Apple sign-in flow
    func startAppleSignIn() {
        print("🍎🔄 AppleSignInManager - startAppleSignIn called")
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authController = ASAuthorizationController(authorizationRequests: [request])
        authController.delegate = self
        authController.performRequests()
    }
    
    // Handle the result of Apple sign-in
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("🍎✅ AppleSignInManager - didCompleteWithAuthorization called")
        
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // Extract user details
            let userID = appleIDCredential.user
            let name = appleIDCredential.fullName?.givenName
            let email = appleIDCredential.email
            let identityToken = appleIDCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            
            print("""
            🍎📋 AppleSignInManager - APPLE SIGN IN CREDENTIALS:
            ==========================================
            🆔 User ID: \(userID)
            📧 Email: \(email ?? "Not provided")
            👤 Full Name: \(name ?? "N/A")
            🔑 Identity Token Present: \(identityToken != nil ? "YES - \(identityToken!.count) chars" : "NO")
            ==========================================
            """)
            
            // First run diagnostics on the backend connection
            Task {
                do {
                    print("🔍 AppleSignInManager - Running backend diagnostics before attempting sign-in...")
                    let diagnostics = await NetworkUtils.shared.diagnoseBakcendStatus()
                    
                    if !diagnostics.reachable {
                        print("🔍 AppleSignInManager - Server diagnostics indicate backend is unreachable")
                        print("🔍 Diagnostic result: \(diagnostics.message)")
                    }
                    
                    // Process Apple sign-in with AuthManager
                    print("🍎🌐 AppleSignInManager - Attempting server authentication with Apple identity token")
                    let authSuccess = try await AuthManager.shared.signInWithApple(
                        userID: userID,
                        email: email,
                        fullName: name,
                        identityToken: identityToken
                    )
                    
                    await MainActor.run {
                        if authSuccess {
                            print("🍎✅ AppleSignInManager - Authentication successful, calling onSignInSuccess")
                            self.onSignInSuccess()
                        } else {
                            print("🍎❌ AppleSignInManager - Authentication failed (returned false)")
                            self.onSignInFailure("Authentication failed")
                        }
                    }
                } catch {
                    print("🍎❌ AppleSignInManager - Authentication error: \(error.localizedDescription)")
                    
                    // Check if we're using local authentication due to server error
                    // If the error message contains "Using local authentication", we should 
                    // still proceed with the login as this is our offline fallback
                    let errorMsg = error.localizedDescription
                    
                    await MainActor.run {
                        if errorMsg.contains("Using local authentication") {
                            print("🍎✅ AppleSignInManager - Using local authentication fallback, continuing login")
                            self.onSignInSuccess()
                        } else {
                            self.onSignInFailure(errorMsg)
                        }
                    }
                }
            }
        } else {
            print("🍎❌ AppleSignInManager - Invalid credentials received")
            self.onSignInFailure("Invalid credentials received from Apple")
        }
    }
    
    // Handle authorization errors
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("🍎❌ AppleSignInManager - didCompleteWithError called: \(error.localizedDescription)")
        
        // Format a user-friendly error message
        var errorMessage = "Apple Sign In failed"
        
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                errorMessage = "You cancelled the sign in"
            case .failed:
                errorMessage = "Authorization failed, please try again"
            case .invalidResponse:
                errorMessage = "Invalid response from Apple"
            case .notHandled:
                errorMessage = "Sign in request wasn't handled"
            case .unknown:
                errorMessage = "Unknown error occurred"
            @unknown default:
                errorMessage = "Unexpected error occurred"
            }
        } else {
            // For simulator/development handle AKAuthenticationError
            if error.localizedDescription.contains("AKAuthenticationError") || 
               error.localizedDescription.contains("-7") {
                
                print("🍎🧪 AppleSignInManager - Development environment detected, proceeding with test user")
                
                // For development/simulator, create a test user and proceed
                Task {
                    do {
                        // Create test credentials for simulator
                        let testUserID = "apple_test_\(UUID().uuidString)"
                        let authSuccess = try await AuthManager.shared.signInWithApple(
                            userID: testUserID,
                            email: "apple_test@example.com",
                            fullName: "Apple Test User",
                            identityToken: "test_simulator_token_\(UUID().uuidString)"
                        )
                        
                        await MainActor.run {
                            if authSuccess {
                                print("🍎✅ AppleSignInManager - Test user authentication successful")
                                self.onSignInSuccess()
                                return
                            } else {
                                self.onSignInFailure("Test user authentication failed")
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.onSignInFailure("Test user setup failed: \(error.localizedDescription)")
                        }
                    }
                }
                return
            }
            
            errorMessage = "Error: \(error.localizedDescription)"
        }
        
        self.onSignInFailure(errorMessage)
    }
} 