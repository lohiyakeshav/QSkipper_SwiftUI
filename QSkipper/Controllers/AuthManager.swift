//
//  AuthManager.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 27/03/25.
//

import Foundation

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    private let networkManager = SimpleNetworkManager.shared
    private let userDefaultsManager = UserDefaultsManager.shared
    
    @Published var isLoggedIn: Bool = false {
        didSet {
            // Force notification of state change
            if isLoggedIn != oldValue {
                print("🔒 AuthManager - isLoggedIn changed from \(oldValue) to \(isLoggedIn)")
                objectWillChange.send()
            }
        }
    }
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    private init() {
        // Initialize with user's login status
        isLoggedIn = userDefaultsManager.isUserLoggedIn()
        print("🔒 AuthManager - Initialized with isLoggedIn = \(isLoggedIn)")
    }
    
  

    
    // Request OTP for login
    @MainActor
    func requestLoginOTP(email: String) async throws -> String {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            let loginRequest = LoginRequest(email: email)
            let jsonData = try JSONEncoder().encode(loginRequest)
            
            print("Sending login request to \(APIEndpoints.login) with data: \(String(data: jsonData, encoding: .utf8) ?? "")")
            
            let response: OTPResponse = try await networkManager.makeRequest(
                url: APIEndpoints.login,
                method: "POST",
                body: jsonData
            )
            
            print("Login response received: \(response)")
            
            // Check status
            if !response.status {
                self.error = response.message
                throw SimpleNetworkError.serverError(400, nil)
            }
            
            // Store username and ID if available
            if let username = response.username, let id = response.id {
                print("Storing user information - ID: \(id), Email: \(email), Username: \(username)")
                userDefaultsManager.savePartialUser(id: id, email: email, username: username)
            } else if let id = response.id {
                // If username is not provided but ID is available
                print("Storing user information - ID: \(id), Email: \(email)")
                userDefaultsManager.savePartialUser(id: id, email: email, username: "User")
            }
            
            // For development, we'll return the OTP received directly
            if let otp = response.otp {
                return otp
            } else {
                return "" // Return empty string instead of hardcoded OTP
            }
        } catch {
            print("Login error: \(error)")
            if let networkError = error as? SimpleNetworkError {
                self.error = networkError.message
            } else {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    // Verify login OTP
    @MainActor
    func verifyLoginOTP(email: String, otp: String) async throws -> Bool {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            let verificationRequest = OTPVerificationRequest(email: email, otp: otp)
            let jsonData = try JSONEncoder().encode(verificationRequest)
            
            let response: AuthResponse = try await networkManager.makeRequest(
                url: APIEndpoints.verifyLogin,
                method: "POST",
                body: jsonData
            )
            
            // Check if response is successful using the computed property
            if !response.isSuccess {
                self.error = response.message ?? "Verification failed"
                return false
            }
            
            // Get username from various sources with priority
            let username: String
            if let responseUsername = response.username, !responseUsername.isEmpty {
                username = responseUsername
            } else if let user = response.user, let userName = user.name, !userName.isEmpty {
                username = userName
            } else {
                // Use the name we saved during login OTP request
                username = userDefaultsManager.getUserName() ?? "User"
            }
            
            // Check if response has user data or just an ID
            if let user = response.user {
                // Create a new user with our determined username
                let updatedUser = User(
                    id: user.id,
                    email: user.email,
                    name: username,  // Use our determined username
                    phone: user.phone,
                    token: user.token ?? response.token
                )
                
                // Save user data
                userDefaultsManager.saveUser(updatedUser)
                
                // Update login status
                self.isLoggedIn = true
                
                return true
            } else if let id = response.id {
                // If we only got an ID, create minimal user data
                let user = User(
                    id: id,
                    email: email,
                    name: username,  // Use our determined username
                    phone: nil,
                    token: response.token
                )
                userDefaultsManager.saveUser(user)
                
                // Update login status
                self.isLoggedIn = true
                
                return true
            } else {
                self.error = response.message ?? "No user data or ID received"
                return false
            }
        } catch {
            if let networkError = error as? SimpleNetworkError {
                self.error = networkError.message
            } else {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    // Register a new user
    @MainActor
    func registerUser(email: String, name: String, phone: String) async throws -> String {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            let registerRequest = RegisterRequest(email: email, name: name, phone: phone)
            let jsonData = try JSONEncoder().encode(registerRequest)
            
            print("Sending register request to \(APIEndpoints.register) with data: \(String(data: jsonData, encoding: .utf8) ?? "")")
            
            let response: OTPResponse = try await networkManager.makeRequest(
                url: APIEndpoints.register,
                method: "POST",
                body: jsonData
            )
            
            print("Register response received: \(response)")
            
            // For development, we'll return the OTP received directly
            if let otp = response.otp {
                return otp
            } else {
                return "" // Return empty string instead of hardcoded OTP
            }
        } catch {
            print("Register error: \(error)")
            self.error = error.localizedDescription
            throw error
        }
    }
    
    // Verify register OTP
    @MainActor
    func verifyRegisterOTP(email: String, otp: String) async throws -> Bool {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            let verificationRequest = OTPVerificationRequest(email: email, otp: otp)
            let jsonData = try JSONEncoder().encode(verificationRequest)
            
            print("Sending verify register request to \(APIEndpoints.verifyRegister) with data: \(String(data: jsonData, encoding: .utf8) ?? "")")
            
            let response: AuthResponse = try await networkManager.makeRequest(
                url: APIEndpoints.verifyRegister,
                method: "POST",
                body: jsonData
            )
            
            print("Verify register response received: \(response)")
            
            // Check if response is successful using the computed property
            if !response.isSuccess {
                self.error = response.message ?? "Verification failed"
                return false
            }
            
            // Check if response has user data or just an ID
            if let user = response.user {
                // Save user data
                userDefaultsManager.saveUser(user)
                
                // Update login status
                self.isLoggedIn = true
                
                return true
            } else if let id = response.id {
                // Get username from the response or use provided username from registration
                let username = response.username ?? userDefaultsManager.getUserName() ?? "User"
                
                // If we only got an ID, create minimal user data
                let user = User(id: id, email: email, name: username, phone: nil, token: response.token)
                userDefaultsManager.saveUser(user)
                
                // Update login status
                self.isLoggedIn = true
                
                return true
            } else {
                self.error = response.message ?? "No user data or ID received"
                return false
            }
        } catch {
            print("Verify register error: \(error)")
            self.error = error.localizedDescription
            throw error
        }
    }
    
    // Logout user
    @MainActor
    func logout() {
        print("🔒 AuthManager - logout() called")
        
        // Debug current user state before logout
        let userId = userDefaultsManager.getUserId()
        let userName = userDefaultsManager.getUserName()
        let userEmail = userDefaultsManager.getUserEmail()
        
        print("""
        🔒 AuthManager - User state before logout:
        - User ID: \(userId ?? "nil")
        - User Name: \(userName ?? "nil")
        - User Email: \(userEmail ?? "nil")
        - isLoggedIn: \(isLoggedIn)
        """)
        
        // Preserve Apple-specific data for future logins
        // Apple email/name are stored with special keys that include the Apple ID
        if let userId = userId, userId.hasPrefix("apple_") {
            print("🍎 AuthManager - Preserving Apple login data for future sign-ins")
            
            // Note: We're already storing apple_real_email and apple_real_name 
            // with the real Apple ID as part of the key, so they won't be deleted
            // by the clearUserData call below
        }
        
        // Clear all user session data in UserDefaults
        userDefaultsManager.clearUserData()
        
        // Force update login state AFTER clearing data
        self.isLoggedIn = false
        
        // Verify logout was successful
        print("""
        🔒 AuthManager - User state after logout:
        - User ID: \(userDefaultsManager.getUserId() ?? "nil")
        - User Name: \(userDefaultsManager.getUserName() ?? "nil")
        - User Email: \(userDefaultsManager.getUserEmail() ?? "nil")
        - isLoggedIn: \(isLoggedIn)
        """)
        
        // Force publish the state change
        objectWillChange.send()
        
        print("🔒 AuthManager - logout complete")
    }
    
    // Check if user is logged in
    func checkLoginStatus() -> Bool {
        return userDefaultsManager.isUserLoggedIn()
    }
    
    // Get current user ID
    func getCurrentUserId() -> String? {
        return userDefaultsManager.getUserId()
    }
    
    // Get current user email
    func getCurrentUserEmail() -> String? {
        return userDefaultsManager.getUserEmail()
    }
    
    // Get current user name
    func getCurrentUserName() -> String? {
        let name = userDefaultsManager.getUserName()
        print("🔍 AuthManager.getCurrentUserName() called, returning: \(name ?? "nil")")
        return name
    }
    
    // Resend OTP (works for both login and registration)
    @MainActor
    func resendOTP(email: String, isRegistration: Bool = false) async throws -> String {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            if isRegistration {
                // Get existing user data if available
                let name = userDefaultsManager.getUserName() ?? ""
                let phone = userDefaultsManager.getUserPhone() ?? ""
                
                // Use the register endpoint to resend OTP
                return try await registerUser(email: email, name: name, phone: phone)
            } else {
                // Use the login endpoint to resend OTP
                return try await requestLoginOTP(email: email)
            }
        } catch {
            print("Resend OTP error: \(error)")
            if let networkError = error as? SimpleNetworkError {
                self.error = networkError.message
            } else {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - Apple Sign In Methods
    
    @MainActor
    func signInWithApple(userID: String, email: String?, fullName: String?, identityToken: String?) async throws -> Bool {
        print("🍎🔄 AuthManager - signInWithApple method called")
        isLoading = true
        error = nil

        defer { 
            isLoading = false
            print("🍎🔄 AuthManager - signInWithApple finished, isLoading set to false")
        }

        do {
            // 🌟 Pretty print the Apple Sign-In response
            print("""
            🍎📋 AuthManager - APPLE SIGN IN DATA:
            ==========================================
            🆔 User ID: \(userID)
            📧 Email: \(email ?? "nil")
            👤 Full Name: \(fullName ?? "nil")
            🔑 Identity Token: \(identityToken != nil ? "Present (\(identityToken!.count) chars)" : "nil")
            ==========================================
            """)

            // IMPORTANT: Save real user information when provided (first-time sign-in only)
            if let email = email, !email.isEmpty {
                print("🍎📧 AuthManager - Saving real email from Apple: \(email)")
                UserDefaults.standard.set(email, forKey: "apple_real_email_\(userID)")
            }
            
            if let realName = fullName, !realName.isEmpty {
                print("🍎👤 AuthManager - Saving real name from Apple: \(realName)")
                UserDefaults.standard.set(realName, forKey: "apple_real_name_\(userID)")
            }
            
            // Try to get previously stored real data if not provided in this login
            let storedRealEmail = UserDefaults.standard.string(forKey: "apple_real_email_\(userID)")
            let storedRealName = UserDefaults.standard.string(forKey: "apple_real_name_\(userID)")
            
            // Get the best available email
            let userEmail: String
            if let email = email, !email.isEmpty {
                userEmail = email
                print("🍎📧 AuthManager - Using Apple-provided email: \(userEmail)")
            } else if let stored = storedRealEmail, !stored.isEmpty {
                userEmail = stored
                print("🍎📧 AuthManager - Using previously stored email: \(userEmail)")
            } else {
                userEmail = "apple_user@example.com"
                print("🍎📧 AuthManager - Using generated email: \(userEmail)")
            }
            
            // Get the best available name
            let userName: String
            if let providedName = fullName, !providedName.isEmpty {
                userName = providedName
                print("🍎👤 AuthManager - Using Apple-provided name: \(userName)")
            } else if let stored = storedRealName, !stored.isEmpty {
                userName = stored
                print("🍎👤 AuthManager - Using previously stored real name: \(userName)")
            } else if userID.contains(".") && userID.contains("0") && userID.count > 20 {
                userName = "Apple User" // Use generic name for Apple ID format
                print("🍎👤 AuthManager - Using generic name as userID appears to be Apple ID format")
            } else {
                userName = userID
                print("🍎👤 AuthManager - Using userID as name: \(userName)")
            }
            
            // Send Apple credentials to the server for validation/registration
            guard let identityToken = identityToken else {
                throw NSError(domain: "Apple Sign In", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing identity token"])
            }
            
            print("🍎🔄 Sending Apple credentials to server for verification...")
            
            // Create the request with Apple identity token and user ID
            let appleSignInRequest = [
                "identityToken": identityToken,
                "user": userID
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: appleSignInRequest)
            
            // Log the request for debugging
            print("""
            🍎📡 APPLE API CALL INITIATED:
            --------------------------
            URL: \(APIEndpoints.appleSignIn)
            METHOD: POST
            IDENTITY TOKEN LENGTH: \(identityToken.count) characters
            USER: \(userID)
            --------------------------
            """)
            
            var serverUserID: String = ""
            var serverUsername: String = userName // Use our best available name as fallback
            var serverResponse: [String: Any]? = nil
            
            do {
                // Try to contact the server first
                let response: [String: Any] = try await networkManager.makeRequest(
                    url: APIEndpoints.appleSignIn,
                    method: "POST",
                    body: jsonData
                )
                
                print("🍎✅ Server response for Apple sign-in: \(response)")
                
                // Extract user ID and username from server response
                if let id = response["id"] as? String {
                    serverUserID = id
                    print("🍎🆔 Using server-provided ID: \(serverUserID)")
                }
                
                if let usernameFromServer = response["username"] as? String, !usernameFromServer.isEmpty {
                    serverUsername = usernameFromServer
                    print("🍎👤 Using server-provided username: \(serverUsername)")
                } else {
                    print("🍎👤 Server did not provide a username, using our best available name: \(serverUsername)")
                }
                
                serverResponse = response
            } catch {
                print("🍎⚠️ Server error: \(error.localizedDescription)")
                print("🍎⚠️ Falling back to local authentication...")
                
                // Generate a local ID with Apple prefix for tracking
                serverUserID = "apple_\(userID)"
                self.error = "Server error: \(error.localizedDescription). Using local authentication."
            }

            // Create user with server-provided ID and username or fallback to local
            let user = User(
                id: serverUserID.isEmpty ? "apple_\(userID)" : serverUserID,
                email: userEmail,
                name: serverUsername,
                phone: nil,
                token: identityToken
            )

            print("""
            🍎💾 AuthManager - SAVING USER DATA TO USERDEFAULTS:
            ==========================================
            🆔 ID: \(user.id)
            📧 Email: \(user.email)
            👤 Name: \(user.name ?? "nil")
            🔑 Token Length: \(user.token?.count ?? 0) chars
            ==========================================
            """)
            
            userDefaultsManager.saveUser(user)
            
            print("🍎🔐 AuthManager - Setting isLoggedIn to TRUE")
            self.isLoggedIn = true
            
            print("🍎✅ AuthManager - User successfully authenticated with Apple")
            return true
        } catch {
            print("🍎❌ AuthManager - Apple Sign In ERROR: \(error)")
            print("🍎❌ Detailed error information: \(error.localizedDescription)")
            self.error = error.localizedDescription
            throw error
        }
    }

    
    @MainActor
    func registerWithApple(userID: String, email: String?, fullName: String?, identityToken: String?) async throws -> Bool {
        print("🍎🔄 AuthManager - registerWithApple method called")
        isLoading = true
        error = nil
        
        defer { 
            isLoading = false 
            print("🍎🔄 AuthManager - registerWithApple finished, isLoading set to false")
        }
        
        do {
            print("""
            🍎📋 AuthManager - APPLE REGISTER DATA:
            ==========================================
            🆔 User ID: \(userID)
            📧 Email: \(email ?? "nil")
            👤 Full Name: \(fullName ?? "nil")
            🔑 Identity Token: \(identityToken != nil ? "Present (\(identityToken!.count) chars)" : "nil")
            ==========================================
            """)
            
            // IMPORTANT: Save real user information when provided (first-time registration only)
            if let email = email, !email.isEmpty {
                print("🍎📧 AuthManager - Saving real email from Apple: \(email)")
                UserDefaults.standard.set(email, forKey: "apple_real_email_\(userID)")
            }
            
            if let realName = fullName, !realName.isEmpty {
                print("🍎👤 AuthManager - Saving real name from Apple: \(realName)")
                UserDefaults.standard.set(realName, forKey: "apple_real_name_\(userID)")
            }
            
            // Try to get previously stored real data if not provided in this registration
            let storedEmail = UserDefaults.standard.string(forKey: "apple_real_email_\(userID)")
            let storedName = UserDefaults.standard.string(forKey: "apple_real_name_\(userID)")
            
            // Format the name properly
            let name: String
            if let fullName = fullName, !fullName.isEmpty {
                name = fullName
                print("🍎👤 AuthManager - Using Apple-provided name: \(name)")
            } else if let stored = storedName, !stored.isEmpty {
                name = stored
                print("🍎👤 AuthManager - Using previously stored name: \(name)")
            } else if userID.contains(".") && userID.contains("0") && userID.count > 20 {
                // If userID is an Apple ID format, use a generic name
                name = "Apple User"
                print("🍎👤 AuthManager - Using generic 'Apple User' name as userID appears to be Apple ID format")
            } else if let email = email, !email.isEmpty {
                name = email.components(separatedBy: "@").first ?? "Apple User"
                print("🍎👤 AuthManager - Using name derived from email: \(name)")
            } else {
                name = "Apple User"
                print("🍎👤 AuthManager - Using default 'Apple User' name as no better option available")
            }
            
            // Get the best available email
            let userEmail: String
            if let email = email, !email.isEmpty {
                userEmail = email
                print("🍎📧 AuthManager - Using Apple-provided email: \(userEmail)")
            } else if let stored = storedEmail, !stored.isEmpty {
                userEmail = stored
                print("🍎📧 AuthManager - Using previously stored email: \(userEmail)")
            } else {
                userEmail = "apple_user@example.com"
                print("🍎📧 AuthManager - Using generated email: \(userEmail)")
            }
            
            let user = User(
                id: userID,
                email: userEmail,
                name: name,
                phone: nil,
                token: identityToken ?? "simulated_token_\(UUID().uuidString)"
            )

            print("""
            🍎💾 AuthManager - SAVING USER DATA TO USERDEFAULTS:
            ==========================================
            🆔 ID: \(user.id)
            📧 Email: \(user.email)
            👤 Name: \(user.name ?? "nil")
            🔑 Token Length: \(user.token?.count ?? 0) chars
            ==========================================
            """)
            
            userDefaultsManager.saveUser(user)
            
            print("🍎🔐 AuthManager - Setting isLoggedIn to TRUE")
            self.isLoggedIn = true
            
            print("🍎✅ AuthManager - User successfully registered with Apple")
            return true
        } catch {
            print("🍎❌ AuthManager - Apple Registration ERROR: \(error)")
            print("🍎❌ Detailed error information: \(error.localizedDescription)")
            self.error = error.localizedDescription
            throw error
        }
    }
    
    @MainActor
    func loginWithPassword(email: String, password: String) async throws -> Bool {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            // Create login request with email and password
            let loginRequest = ["email": email, "password": password]
            let jsonData = try JSONSerialization.data(withJSONObject: loginRequest)
            
            print("🔐 Attempting password login for email: \(email)")
            
            let response: AuthResponse = try await networkManager.makeRequest(
                url: APIEndpoints.login,
                method: "POST",
                body: jsonData
            )
            
            print("🔐 Password login response received: \(response)")
            
            // Check if response is successful
            if !response.isSuccess {
                self.error = response.message ?? "Login failed"
                return false
            }
            
            // Get username from various sources with priority
            let username: String
            if let responseUsername = response.username, !responseUsername.isEmpty {
                username = responseUsername
            } else if let user = response.user, let userName = user.name, !userName.isEmpty {
                username = userName
            } else {
                username = "User"
            }
            
            // Check if response has user data or just an ID
            if let user = response.user {
                // Create a new user with our determined username
                let updatedUser = User(
                    id: user.id,
                    email: user.email,
                    name: username,
                    phone: user.phone,
                    token: user.token ?? response.token
                )
                
                // Save user data
                userDefaultsManager.saveUser(updatedUser)
                
                // Update login status
                self.isLoggedIn = true
                
                return true
            } else if let id = response.id {
                // If we only got an ID, create minimal user data
                let user = User(
                    id: id,
                    email: email,
                    name: username,
                    phone: nil,
                    token: response.token
                )
                userDefaultsManager.saveUser(user)
                
                // Update login status
                self.isLoggedIn = true
                
                return true
            } else {
                self.error = response.message ?? "No user data or ID received"
                return false
            }
        } catch {
            print("🔐 Password login error: \(error)")
            if let networkError = error as? SimpleNetworkError {
                self.error = networkError.message
            } else {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
}
