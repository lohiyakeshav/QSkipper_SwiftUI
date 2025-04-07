//
//  LoginView.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 27/03/25.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var otp = ""
    @Published var otpSent = false
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var showError = false
    @Published var navigateToLocation = false
    @Published var showPasswordFallback = false
    @Published var password = ""
    
    private let authManager = AuthManager.shared
    var currentNonce: String?
    
    @MainActor
    func sendOTP() async {
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            showError = true
            return
        }
        
        isLoading = true
        
        do {
            let receivedOTP = try await authManager.requestLoginOTP(email: email)
            
            // The server may return an empty OTP in production environments
            // when it sends the OTP via email instead of returning it directly
            self.otp = receivedOTP
            self.otpSent = true
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
            self.isLoading = false
        }
    }
    
    @MainActor
    func verifyOTP() async {
        guard !otp.isEmpty else {
            errorMessage = "Please enter the OTP sent to your email"
            showError = true
            return
        }
        
        isLoading = true
        
        do {
            let success = try await authManager.verifyLoginOTP(email: email, otp: otp)
            
            self.isLoading = false
            
            if success {
                // User is now logged in, navigate to location
                self.navigateToLocation = true
            } else {
                self.errorMessage = "Invalid OTP. Please try again."
                self.showError = true
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
            self.isLoading = false
        }
    }
    
    @MainActor
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        print("🍎🔄 LoginView - Apple Sign In Flow Started")
        isLoading = true

        switch result {
        case .success(let authorization):
            print("🍎✅ LoginView - Received successful authorization from Apple")
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let userID = appleIDCredential.user
                let email = appleIDCredential.email ?? ""
                let fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let identityToken = appleIDCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
                
                let realName = fullName.isEmpty ? "N/A" : fullName
                
                print("""
                🍎📋 LoginView - APPLE SIGN IN CREDENTIALS:
                ==========================================
                🆔 User ID: \(userID)
                📧 Email: \(email.isEmpty ? "Not provided" : email)
                👤 Full Name: \(realName)
                🔑 Identity Token Present: \(identityToken != nil ? "YES - \(identityToken!.count) chars" : "NO")
                ==========================================
                """)
                
                // Initialize success flag
                var authSuccess = false
                
                // First try to register with backend server if we have a token
                if let identityToken = identityToken {
                    print("🍎🌐 LoginView - Attempting server authentication with Apple identity token")
                    do {
                        let networkUtils = NetworkUtils()
                        // Use the actual name or fallback to user ID
                        let userName = fullName.isEmpty ? userID : fullName
                        
                        print("🍎🌐 LoginView - Calling registerWithApple with identity token and user: \(userName)")
                        
                        // CRITICAL: Save the user's real email if provided by Apple (first-time login only)
                        if !email.isEmpty {
                            print("🍎📧 LoginView - Received REAL EMAIL from Apple: \(email) - saving for future use")
                            UserDefaults.standard.set(email, forKey: "apple_real_email_\(userID)")
                        }
                        
                        // CRITICAL: Save the user's real name if provided by Apple (first-time login only)
                        if !fullName.isEmpty {
                            print("🍎👤 LoginView - Received REAL NAME from Apple: \(fullName) - saving for future use")
                            UserDefaults.standard.set(fullName, forKey: "apple_real_name_\(userID)")
                        }
                        
                        authSuccess = try await networkUtils.registerWithApple(
                            identityToken: identityToken,
                            user: userName
                        )
                        
                        print("🍎🌐 LoginView - Server authentication result: \(authSuccess ? "SUCCESS" : "FAILED")")
                    } catch {
                        print("🍎❌ LoginView - Server authentication ERROR: \(error.localizedDescription)")
                        authSuccess = false
                    }
                } else {
                    print("🍎⚠️ LoginView - No identity token available, skipping server authentication")
                }
                
                // Fall back to local authentication if server auth failed
                if !authSuccess {
                    print("🍎💾 LoginView - Using local authentication fallback")
                    
                    // Try to get the previously stored real email for this Apple ID
                    let storedRealEmail = UserDefaults.standard.string(forKey: "apple_real_email_\(userID)")
                    
                    // Create user with best available information - use persistent values
                    let userEmail: String
                    if !email.isEmpty {
                        // Use the email from this login if provided
                        userEmail = email
                        print("🍎📧 LoginView - Using email from current sign-in: \(userEmail)")
                    } else if let stored = storedRealEmail, !stored.isEmpty {
                        // Use previously stored email if available
                        userEmail = stored
                        print("🍎📧 LoginView - Using previously stored email: \(userEmail)")
                    } else {
                        // Fallback to generated email
                        userEmail = "apple_user_\(userID)@example.com"
                        print("🍎📧 LoginView - Using generated email: \(userEmail)")
                    }
                    
                    // Try to get the previously stored real name for this Apple ID
                    let storedRealName = UserDefaults.standard.string(forKey: "apple_real_name_\(userID)")
                    
                    // For name, check if the provided fullName looks like an Apple ID
                    let existingName = UserDefaultsManager.shared.getUserName()
                    print("🍎💾 LoginView - Existing saved name: \(existingName ?? "nil")")
                    
                    let userName: String
                    
                    if !fullName.isEmpty {
                        // Use the fullName from Apple if available
                        userName = fullName
                        print("🍎💾 LoginView - Using Apple-provided name: \(userName)")
                    } else if let stored = storedRealName, !stored.isEmpty {
                        // Use previously stored real name if available
                        userName = stored
                        print("🍎💾 LoginView - Using previously stored real name: \(userName)")
                    } else if let existing = existingName, !existing.isEmpty && !(existing.contains(".") && existing.contains("0") && existing.count > 20) {
                        // Use existing name if it's not an Apple ID
                        userName = existing
                        print("🍎💾 LoginView - Using existing name: \(userName)")
                    } else if userID.contains(".") && userID.contains("0") && userID.count > 20 {
                        // If userID is an Apple ID format, use generic name
                        userName = "Apple User"
                        print("🍎💾 LoginView - Using generic name as userID appears to be Apple ID format")
                    } else {
                        // Last resort - extract from email or use generic
                        userName = (email.components(separatedBy: "@").first ?? "Apple User")
                        print("🍎💾 LoginView - Using name derived from email: \(userName)")
                    }
                    
                    let user = User(
                        id: userID,
                        email: userEmail,
                        name: userName,
                        phone: nil,
                        token: identityToken ?? "apple_token_\(UUID().uuidString)"
                    )
                    
                    print("""
                    🍎💾 LoginView - SAVING LOCAL USER DATA:
                    ==========================================
                    🆔 ID: \(user.id)
                    📧 Email: \(user.email)
                    👤 Name: \(user.name ?? "nil")
                    🔑 Token Length: \(user.token?.count ?? 0) chars
                    ==========================================
                    """)
                    
                    UserDefaultsManager.shared.saveUser(user)
                    print("🍎💾 LoginView - User data saved to UserDefaults")
                    
                    authManager.isLoggedIn = true
                    print("🍎💾 LoginView - isLoggedIn set to TRUE")
                    
                    authSuccess = true
                }
                
                // Only navigate if we have successful authentication
                if authSuccess {
                    print("🍎✅ LoginView - Authentication successful, navigating to location screen")
                    // Navigate to location view
                    self.navigateToLocation = true
                } else {
                    print("🍎❌ LoginView - Authentication failed, showing error")
                    self.errorMessage = "Authentication failed. Please try again."
                    self.showError = true
                }
                
                self.isLoading = false
            } else {
                print("🍎❌ LoginView - Failed to get Apple credentials - no ASAuthorizationAppleIDCredential found")
                self.errorMessage = "Failed to get Apple credentials."
                self.showError = true
                self.isLoading = false
            }

        case .failure(let error):
            print("🍎❌ LoginView - Apple Sign In ERROR: \(error.localizedDescription)")
            // Handle specific Apple Sign In errors
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    self.errorMessage = "Sign in was canceled"
                default:
                    self.errorMessage = "Sign in failed. Please try again."
                    self.showPasswordFallback = true
                }
            }
            // Handle specific error codes for simulator/development
            else if error.localizedDescription.contains("AKAuthenticationError") || 
                   error.localizedDescription.contains("-7") {
                
                // Create test user for development purposes
                let testUserID = "apple_test_\(UUID().uuidString)"
                
                let user = User(
                    id: testUserID,
                    email: "apple_test@example.com",
                    name: "Apple Test User",
                    phone: nil,
                    token: "apple_test_token_\(UUID().uuidString)"
                )
                
                UserDefaultsManager.shared.saveUser(user)
                authManager.isLoggedIn = true
                
                // Navigate to location view
                self.navigateToLocation = true
                
                self.isLoading = false
                return
            } else {
                self.errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
                self.showPasswordFallback = true
            }
            
            self.showError = true
            self.isLoading = false
        }
    }
    
    @MainActor
    func handlePasswordFallback() async {
        guard !password.isEmpty else {
            errorMessage = "Please enter your password"
            showError = true
            return
        }
        
        isLoading = true
        
        do {
            // Try to authenticate with password
            let success = try await authManager.loginWithPassword(email: email, password: password)
            
            if success {
                print("🔐 Password authentication successful, setting navigateToLocation to true")
                
                // Use DispatchQueue.main to ensure UI update happens on main thread
                DispatchQueue.main.async {
                    print("🔐 CRITICAL: Dispatching password auth navigation to main thread")
                    self.navigateToLocation = true
                    
                    // Double-check navigation after delay as a fallback
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !self.navigateToLocation {
                            print("🔐 CRITICAL: Retrying navigation after delay")
                            self.navigateToLocation = true
                        }
                    }
                }
            } else {
                self.errorMessage = "Invalid password. Please try again."
                self.showError = true
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
        }
        
        self.isLoading = false
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    // Function to generate a random nonce for Apple Sign In
    func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }

    // SHA256 hash for the nonce
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @State private var animateContent = false
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Add splash background image
            Image("splash_background")
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaledToFill()
                .ignoresSafeArea()
                
            // White overlay with opacity for better readability
            Color.white.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    // Add a spacer at the top to push content to center
                    Spacer().frame(height: 20)
                    
                    // Title
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Login to your")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("account.")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                    
                    Text("Please sign in to your account")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .padding(.bottom, 10)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 15)
                    
                    // Email Input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Email Address")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black.opacity(0.8))
                        
                        TextField("Enter your email address", text: $viewModel.email)
                            .font(.system(size: 16))
                            .padding(.vertical, 16)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .focused($isFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isFieldFocused = false
                            }
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                    
                    // Get Started Button
                    Button(action: {
                        isFieldFocused = false
                        Task {
                            await viewModel.sendOTP()
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.primaryGreen)
                                .frame(height: 50)
                                .shadow(color: AppColors.primaryGreen.opacity(0.3), radius: 5, x: 0, y: 3)
                            
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Get Started")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                    .padding(.top, 10)
                    
                    // Password Fallback View
                    if viewModel.showPasswordFallback {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Password")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black.opacity(0.8))
                            
                            SecureField("Enter your password", text: $viewModel.password)
                                .font(.system(size: 16))
                                .padding(.vertical, 16)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .autocapitalization(.none)
                                .textContentType(.password)
                                .focused($isFieldFocused)
                            
                            Button(action: {
                                Task {
                                    await viewModel.handlePasswordFallback()
                                }
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AppColors.primaryGreen)
                                        .frame(height: 50)
                                        .shadow(color: AppColors.primaryGreen.opacity(0.3), radius: 5, x: 0, y: 3)
                                    
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Sign In with Password")
                                            .foregroundColor(.white)
                                            .font(.system(size: 18, weight: .semibold))
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                    }
                    
                    // Don't have an account section
                    HStack {
                        Spacer()
                        
                        Text("Don't have an account?")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                        
                        NavigationLink(destination: RegisterView()) {
                            Text("Register")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppColors.primaryGreen)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 20)
                    .opacity(animateContent ? 1 : 0)
                    
                    // Add a spacer at the bottom to push content to center
                    Spacer().frame(height: 50)
                }
                .padding(.horizontal, 25)
                .frame(minHeight: UIScreen.main.bounds.height - 120) // Reduced height to account for keyboard
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle()) // Make entire ScrollView tappable
            .onTapGesture {
                // Dismiss keyboard when tapping outside text fields
                isFieldFocused = false
            }
            
            // Adding Sign in with Apple at the bottom of screen (similar to RegisterView)
            VStack {
                Spacer()
                
                VStack(spacing: 15) {
                    /* Commented out Divider and OR text
                    Divider()
                    
                    Text("OR")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.vertical, 5)
                    */
                    
                    /* Commented out Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        // Configure the request
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        // Dismiss keyboard
                        isFieldFocused = false
                        
                        // Create an instance of our AppleSignInManager with success and failure handlers
                        let appleManager = AppleSignInManager(
                            onSuccess: {
                                // Handle successful authentication - navigate to location
                                DispatchQueue.main.async {
                                    print("🍎✅ LoginView - Authentication successful, navigating to location screen")
                                    viewModel.navigateToLocation = true
                                }
                            },
                            onFailure: { errorMessage in
                                // Handle authentication failure
                                DispatchQueue.main.async {
                                    print("🍎❌ LoginView - Authentication failed: \(errorMessage)")
                                    viewModel.errorMessage = errorMessage
                                    viewModel.showError = true
                                }
                            }
                        )
                        
                        // Start the Apple sign-in process
                        if case .success(let authorization) = result {
                            // Pass the authorization to our manager for handling
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                // Process credentials through the AppleSignInManager
                                appleManager.authorizationController(
                                    controller: ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()]),
                                    didCompleteWithAuthorization: authorization
                                )
                            } else {
                                // Handle invalid credentials
                                viewModel.errorMessage = "Invalid credentials received from Apple"
                                viewModel.showError = true
                            }
                        } else if case .failure(let error) = result {
                            // Handle sign-in failure
                            appleManager.authorizationController(
                                controller: ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()]),
                                didCompleteWithError: error
                            )
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    */
                }
                .padding(.bottom, 80) // Increased padding to ensure visibility
                .opacity(animateContent ? 1 : 0)
            }
        }
        .navigationBarBackButtonHidden(true)
        .errorAlert(
            error: viewModel.errorMessage,
            isPresented: $viewModel.showError
        )
        .background(
            // If OTP is sent, navigate to OTP verification screen
            NavigationLink(
                destination: OTPVerificationView(email: viewModel.email, otp: $viewModel.otp, verifyAction: {
                    Task {
                        await viewModel.verifyOTP()
                    }
                }, isRegistration: false),
                isActive: $viewModel.otpSent,
                label: { EmptyView() }
            )
        )
        .background(
            // If OTP verification is successful, navigate to LocationView
            NavigationLink(
                destination: LocationView().navigationBarBackButtonHidden(true),
                isActive: $viewModel.navigateToLocation,
                label: { EmptyView() }
            )
        )
        .onAppear {
            print("📱 LoginView appeared")
            print("📱 Checking Apple Sign In availability")
            
            // Test if Apple Sign In is available on this device
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            
            // We don't need to check credential state on initial load
            // This avoids the Error Domain=AKAuthenticationError Code=-7091 errors
            
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }
}

struct SocialLoginButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .padding()
                .foregroundColor(.black)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                )
        }
    }
}

#Preview {
    LoginView()
} 
