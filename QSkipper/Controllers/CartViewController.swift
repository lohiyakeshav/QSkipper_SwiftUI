//
//  CartViewController.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 30/03/25.
//

import Foundation
import SwiftUI
import StoreKit

// Controller for handling cart view logic
class CartViewController: ObservableObject {
    private let orderManager: OrderManager
    @Published var isProcessing = false
    
    @Published var showOrderSuccess = false
    @Published var showPaymentConfirmation = false
    @Published var isSchedulingOrder = false
    @Published var scheduledDate = Date().addingTimeInterval(3600) // Default to 1 hour from now
    @Published var showSchedulePicker = false
    @Published var selectedTipAmount: Int = 18
    @Published var showPaymentView = false
    @Published var currentOrderRequest: PlaceOrderRequest?
    @Published var orderId: String? = nil
    let tipOptions = [12, 18, 25]
    
    @Published var restaurant: Restaurant?
    
    init(orderManager: OrderManager = OrderManager.shared) {
        self.orderManager = orderManager
        self.loadRestaurantDetails()
        
        // Observe cart changes to update restaurant details
        NotificationCenter.default.addObserver(self, selector: #selector(cartDidChange), name: NSNotification.Name("CartDidChange"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func cartDidChange() {
        loadRestaurantDetails()
    }
    
    // Load restaurant details for current cart items
    func loadRestaurantDetails() {
        if !orderManager.currentCart.isEmpty, let firstProduct = orderManager.currentCart.first {
            let restaurantId = firstProduct.product.restaurantId
            
            // Get restaurant from RestaurantManager
            self.restaurant = RestaurantManager.shared.getRestaurant(by: restaurantId)
            
            // If no restaurant found from manager, try to fetch it or create a default
            if self.restaurant == nil {
                print("Restaurant not found in RestaurantManager for ID: \(restaurantId), attempting to fetch")
                
                // Try to fetch restaurant data if RestaurantManager doesn't have it yet
                if RestaurantManager.shared.restaurants.isEmpty {
                    Task {
                        try? await RestaurantManager.shared.fetchAllRestaurants()
                        
                        // Try one more time after fetching
                        await MainActor.run {
                            self.restaurant = RestaurantManager.shared.getRestaurant(by: restaurantId)
                            
                            // If still not found, create a default
                            if self.restaurant == nil {
                                print("Still could not find restaurant, creating default")
                                self.restaurant = Restaurant(
                                    id: restaurantId,
                                    name: "Restaurant",
                                    estimatedTime: "30-40",
                                    cuisine: nil,
                                    photoId: nil,
                                    rating: 4.0,
                                    location: "Campus Area"
                                )
                            } else {
                                print("Found restaurant after fetching: \(String(describing: self.restaurant?.name))")
                            }
                        }
                    }
                } else {
                    // Create a default restaurant
                    print("Creating default restaurant for ID: \(restaurantId)")
                    self.restaurant = Restaurant(
                        id: restaurantId,
                        name: "Restaurant",
                        estimatedTime: "30-40",
                        cuisine: nil,
                        photoId: nil,
                        rating: 4.0,
                        location: "Campus Area"
                    )
                }
            } else {
                print("Restaurant found: \(String(describing: self.restaurant?.name))")
            }
        } else {
            print("Cart is empty or no products found")
        }
    }
    
    // Process order payment
    func placeOrder() {
        Task { @MainActor in
            print("🔄 CartViewController: Starting place order process...")
            self.isProcessing = true
            
            // Validate user
            guard let userId = UserDefaultsManager.shared.getUserId(),
                  let firstItem = orderManager.currentCart.first else {
                print("❌ Missing user or cart data.")
                self.isProcessing = false
                return
            }

            let restaurantId = firstItem.product.restaurantId

            let orderRequest = PlaceOrderRequest(
                userId: userId,
                restaurantId: restaurantId,
                items: orderManager.currentCart.map {
                    OrderItem(
                        productId: $0.productId,
                        quantity: $0.quantity,
                        price: $0.product.price,
                        productName: $0.product.name
                    )
                },
                totalAmount: getTotalAmount(),
                orderType: orderManager.selectedOrderType,
                scheduledTime: isSchedulingOrder ? scheduledDate : nil,
                specialInstructions: nil
            )
            
            self.currentOrderRequest = orderRequest

            // 🔐 Sandbox: Use StoreKit2 to simulate payment
            guard let orderProduct = StoreKitManager.shared.getProduct(byID: "com.qskipper.premium") else {
                print("❌ StoreKit product not found.")
                self.isProcessing = false
                self.showPaymentView = true
                return
            }

            do {
                print("🧪 StoreKit: Attempting to purchase in sandbox...")
                let result = try await orderProduct.purchase()

                switch result {
                case .success(let verification):
                    switch verification {
                    case .unverified(_, let error):
                        print("⚠️ Transaction unverified: \(error.localizedDescription)")
                        self.isProcessing = false
                        return

                    case .verified(let transaction):
                        print("✅ StoreKit transaction verified!")
                        print("   - Transaction ID: \(transaction.id)")
                        print("   - Product ID: \(transaction.productID)")
                        
                        await transaction.finish()
                        
                        try await submitOrderToAPI(orderRequest: orderRequest)
                    }

                case .userCancelled:
                    print("🚫 Payment cancelled by user.")
                    self.isProcessing = false
                    return

                case .pending:
                    print("⏳ Payment is pending...")
                    self.isProcessing = false
                    return

                @unknown default:
                    print("❓ Unknown result during purchase.")
                    self.isProcessing = false
                    return
                }
            } catch {
                print("❌ StoreKit purchase failed: \(error.localizedDescription)")
                self.isProcessing = false
            }
        }
    }
    
    // Submit order to the appropriate API endpoint
    private func submitOrderToAPI(orderRequest: PlaceOrderRequest) async throws {
        let networkManager = SimpleNetworkManager.shared
        
        // Format the price as a string
        let priceString = String(format: "%.0f", getTotalAmount())
        
        // Determine which API endpoint to use based on scheduling
        let apiEndpoint = isSchedulingOrder ? 
            APIEndpoints.scheduleOrderPlaced : 
            APIEndpoints.orderPlaced
        
        print("📤 CartViewController: Submitting order to \(isSchedulingOrder ? "schedule-order-placed" : "order-placed") API")
        
        // Create the correct payload structure based on order type
        var jsonDict: [String: Any] = [
            "restaurantId": orderRequest.restaurantId,
            "userId": orderRequest.userId,
            "items": orderRequest.items.map { item in
                [
                    "productId": item.productId,
                    "name": item.productName ?? "Unknown",
                    "quantity": item.quantity,
                    "price": Int(item.price)
                ]
            },
            "price": priceString,
            "takeAway": true
        ]
        
        // Add scheduleDate only for scheduled orders
        if isSchedulingOrder {
            let dateFormatter = ISO8601DateFormatter()
            let scheduleDateString = dateFormatter.string(from: scheduledDate)
            jsonDict["scheduleDate"] = scheduleDateString
        }
        
        // Convert dictionary to JSON data
        let requestData = try JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted)
        
        // Print the request for debugging
        if let jsonString = String(data: requestData, encoding: .utf8) {
            print("📄 CartViewController: Request payload:")
            print(jsonString)
        }
        
        do {
            // Use OrderAPIService to submit the order
            let orderId: String
            if isSchedulingOrder {
                orderId = try await OrderAPIService.shared.placeScheduledOrder(jsonDict: jsonDict)
            } else {
                orderId = try await OrderAPIService.shared.placeOrder(jsonDict: jsonDict)
            }
            
            print("✅ CartViewController: Order API call successful!")
            print("   - Order ID: \(orderId)")
            
            // Show success message
            await MainActor.run {
                self.orderId = orderId
                showOrderSuccess = true
                isProcessing = false
                
                // Clear the cart
                orderManager.clearCart()
            }
            
            // If we reach here, the order was successful
            return
        } catch {
            print("❌ CartViewController: Order API Error: \(error.localizedDescription)")
            
            // If the API returns a 200 status code with an order ID but we failed to parse it,
            // we should still treat it as a success
            if let responseData = (error as NSError).userInfo["responseData"] as? Data,
               let responseString = String(data: responseData, encoding: .utf8) {
                
                let cleanedText = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
                                               .replacingOccurrences(of: "\"", with: "")
                
                // If it looks like a MongoDB ObjectId (24 hex characters), treat as success
                if cleanedText.count == 24 && cleanedText.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil {
                    print("✅ CartViewController: Found valid order ID in error response: \(cleanedText)")
                    
                    await MainActor.run {
                        self.orderId = cleanedText
                        showOrderSuccess = true
                        isProcessing = false
                        
                        // Clear the cart
                        orderManager.clearCart()
                    }
                    
                    return
                }
            }
            
            // Re-throw the error if we couldn't recover
            throw error
        }
    }
    
    // Calculate convenience fee (4% of cart total)
    func getConvenienceFee() -> Double {
        return orderManager.getCartTotal() * 0.04
    }
    
    // Calculate total amount to pay with all fees
    func getTotalAmount() -> Double {
        return orderManager.getCartTotal() * (1 + 0.04)
    }
} 