//
//  SplashView.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 27/03/25.
//

import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isActive = false
    @State private var shouldReset = false
    
    var body: some View {
        ZStack {
            Image("splash_background")
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaledToFill()
                .ignoresSafeArea()
            
            Image("Logo")
                .resizable()
                .frame(width: 140, height: 140)
                .padding(.bottom, 60)
        }
        .onAppear {
            print("SplashView appeared")
            // Check the current auth state to make sure it's correct
            let userId = authManager.getCurrentUserId()
            let userName = authManager.getCurrentUserName()
            print("🔍 SplashView - Current auth state: isLoggedIn=\(authManager.isLoggedIn), userId=\(userId ?? "nil"), userName=\(userName ?? "nil")")
            
            // Navigate to next screen after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("Timer completed, setting isActive to true")
                withAnimation {
                    isActive = true
                }
            }
        }
        .onChange(of: authManager.isLoggedIn) { newValue in
            print("🔄 SplashView - Auth state changed to: \(newValue)")
            
            // If user just logged out, reset to StartView
            if !newValue {
                print("🔄 SplashView - User logged out, resetting navigation")
                
                // Reset the navigation state
                isActive = false
                
                // Then trigger navigation after a brief delay to ensure state is updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔄 SplashView - Reactivating navigation after logout")
                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .background(
            NavigationLink(
                destination: destinationView,
                isActive: $isActive,
                label: { EmptyView() }
            )
        )
    }
    
    @ViewBuilder
    private var destinationView: some View {
        if authManager.isLoggedIn {
            let _ = print("🔄 SplashView - Navigating to HomeView (isLoggedIn=true)")
            HomeTabView()
        } else {
            let _ = print("🔄 SplashView - Navigating to StartView (isLoggedIn=false)")
            StartView()
        }
    }
}

// HomeTabView is a wrapper for HomeView that guarantees it conforms to View protocol
struct HomeTabView: View {
    var body: some View {
        HomeView()
    }
}

// Extension to simplify navigation
extension View {
    func navigation<Destination: View>(isActive: Binding<Bool>, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        overlay(
            NavigationLink(
                destination: isActive.wrappedValue ? destination() : nil,
                isActive: isActive,
                label: { EmptyView() }
            )
            .hidden()
        )
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
            .environmentObject(AuthManager.shared)
    }
} 
