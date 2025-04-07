//
//  UserDefaultsManager.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 27/03/25.
//

import Foundation

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    
    private let userDefaults = UserDefaults.standard
    
    // Keys
    private let tokenKey = "user_token"
    private let userIdKey = "userID"
    private let userEmailKey = "user_email"
    private let userNameKey = "user_name"
    private let userPhoneKey = "user_phone"
    private let isLoggedInKey = "is_logged_in"
    
    private init() {}
    
    // MARK: - User Authentication
    
    func saveUserToken(_ token: String) {
        userDefaults.set(token, forKey: tokenKey)
    }
    
    func getUserToken() -> String? {
        return userDefaults.string(forKey: tokenKey)
    }
    
    func saveUserId(_ userId: String) {
        userDefaults.set(userId, forKey: userIdKey)
    }
    
    func getUserId() -> String? {
        return userDefaults.string(forKey: userIdKey)
    }
    
    func saveUserEmail(_ email: String) {
        userDefaults.set(email, forKey: userEmailKey)
    }
    
    func getUserEmail() -> String? {
        return userDefaults.string(forKey: userEmailKey)
    }
    
    func saveUserName(_ name: String) {
        print("📝 SAVING USERNAME: \(name) with key: \(userNameKey)")
        userDefaults.synchronize() // Make sure data is flushed before
        userDefaults.set(name, forKey: userNameKey)
        userDefaults.synchronize() // Force immediate write
        
        // Verify the save worked
        let savedName = userDefaults.string(forKey: userNameKey)
        print("📝 VERIFICATION - Saved username: \(savedName ?? "nil")")
    }
    
    func getUserName() -> String? {
        let name = userDefaults.string(forKey: userNameKey)
        print("📱 UserDefaultsManager.getUserName() called, key=\(userNameKey), value=\(name ?? "nil")")
        return name
    }
    
    func saveUserPhone(_ phone: String) {
        userDefaults.set(phone, forKey: userPhoneKey)
    }
    
    func getUserPhone() -> String? {
        return userDefaults.string(forKey: userPhoneKey)
    }
    
    func isUserLoggedIn() -> Bool {
        let isLoggedIn = UserDefaults.standard.bool(forKey: "user_logged_in")
        print("📝 UserDefaultsManager.isUserLoggedIn() = \(isLoggedIn)")
        return isLoggedIn
    }
    
    func setUserLoggedIn(_ value: Bool) {
        print("📝 UserDefaultsManager.setUserLoggedIn(\(value))")
        UserDefaults.standard.set(value, forKey: "user_logged_in")
        UserDefaults.standard.synchronize()
    }
    
    func saveUser(_ user: User) {
        print("📝 UserDefaultsManager - saveUser called with:")
        print("• ID: \(user.id)")
        print("• Email: \(user.email)")
        print("• Name: \(user.name ?? "nil")")
        print("• Token: \(user.token != nil ? "Present (\(user.token!.count) chars)" : "nil")")
        
        // Save individual user properties
        UserDefaults.standard.set(user.id, forKey: "user_id")
        UserDefaults.standard.set(user.email, forKey: "user_email")
        UserDefaults.standard.set(user.name, forKey: "user_name")
        UserDefaults.standard.set(user.phone, forKey: "user_phone")
        UserDefaults.standard.set(user.token, forKey: "user_token")
        
        // Set logged in status to true
        setUserLoggedIn(true)
        
        // Force synchronize to ensure data is saved immediately
        UserDefaults.standard.synchronize()
        
        // Verify data was saved correctly
        print("📝 UserDefaultsManager - Verification after save:")
        print("• Stored ID: \(UserDefaults.standard.string(forKey: "user_id") ?? "nil")")
        print("• Stored Email: \(UserDefaults.standard.string(forKey: "user_email") ?? "nil")")
        print("📱 UserDefaultsManager.getUserName() called, key=user_name, value=\(UserDefaults.standard.string(forKey: "user_name") ?? "nil")")
        print("• Stored Name: \(UserDefaults.standard.string(forKey: "user_name") ?? "nil")")
        print("• isLoggedIn: \(UserDefaults.standard.bool(forKey: "user_logged_in"))")
    }
    
    func savePartialUser(id: String, email: String, username: String) {
        saveUserId(id)
        saveUserEmail(email)
        saveUserName(username)
        // Don't set logged in here - only after OTP is verified
    }
    
    // Clear all user session data
    func clearUserData() {
        print("📝 UserDefaultsManager - clearUserData called")
        
        // Session data - always remove these
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_name")
        UserDefaults.standard.removeObject(forKey: "user_email")
        UserDefaults.standard.removeObject(forKey: "user_phone")
        UserDefaults.standard.removeObject(forKey: "user_token")
        UserDefaults.standard.removeObject(forKey: "user_logged_in")
        
        // Clean up any other temporary session-related data
        UserDefaults.standard.removeObject(forKey: "user_cart")
        UserDefaults.standard.removeObject(forKey: "selected_payment_method")
        
        // Note: We're NOT removing apple_real_email_* or apple_real_name_* keys
        // as those are tied to the Apple ID and needed for future sign-ins
        
        print("📝 UserDefaultsManager - Session data cleared successfully")
        
        // Force synchronize to make sure changes are saved immediately
        UserDefaults.standard.synchronize()
    }
} 