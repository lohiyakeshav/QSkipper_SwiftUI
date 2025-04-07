//
//  CartViewController.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 30/03/25.
//

import Foundation
import SwiftUI
import StoreKit

// Add SKPaymentTransactionObserver as a fallback
class CartViewController: NSObject, ObservableObject, SKPaymentTransactionObserver {
    // MARK: - Published Properties
    @Published var restaurant: Restaurant?
    @Published var selectedTipAmount: Double = 0
    @Published var isSchedulingOrder = false
    @Published var scheduledDate = Date()
    @Published var showSchedulePicker = false
    @Published var showPaymentView = false
    @Published var showOrderSuccess = false
    @Published var orderId: String?
    @Published var isProcessing = false
    @Published var currentOrderRequest: PlaceOrderRequest?
    
    // Transaction observers for older StoreKit 1
    private var productID = "com.qskipper.premium"
    
    // MARK: - Dependencies
    private var orderManager: OrderManager
    
    // MARK: - Initialization
    init(orderManager: OrderManager = OrderManager.shared) {
        self.orderManager = orderManager
        
        // Call super.init before using self
        super.init()
        
        // Now we can use self
        SKPaymentQueue.default().add(self)
        self.loadRestaurantDetails()
        
        // Observe cart changes to update restaurant details
        NotificationCenter.default.addObserver(self, selector: #selector(cartDidChange), name: NSNotification.Name("CartDidChange"), object: nil)
    }
    
    deinit {
        // Remove observer when controller is deallocated
        SKPaymentQueue.default().remove(self)
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
    
    // MARK: - Transaction Observer Methods (StoreKit 1)
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                // Handle successful purchase
                print("✅ StoreKit 1: Transaction successful for \(transaction.payment.productIdentifier)")
                
                // Complete the transaction
                SKPaymentQueue.default().finishTransaction(transaction)
                
                // Process the order if we have a request
                if let orderRequest = self.currentOrderRequest {
                    Task {
                        do {
                            try await submitOrderToAPI(orderRequest: orderRequest)
                        } catch {
                            print("❌ StoreKit 1: Failed to submit order after transaction: \(error.localizedDescription)")
                        }
                    }
                }
                
            case .failed:
                if let error = transaction.error {
                    print("❌ StoreKit 1: Transaction failed with error: \(error.localizedDescription)")
                } else {
                    print("❌ StoreKit 1: Transaction failed without error information")
                }
                SKPaymentQueue.default().finishTransaction(transaction)
                
                Task { @MainActor in
                    self.isProcessing = false
                }
                
            case .restored:
                print("ℹ️ StoreKit 1: Transaction restored")
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .deferred:
                print("⏳ StoreKit 1: Transaction deferred")
                
            case .purchasing:
                print("🔄 StoreKit 1: Transaction in progress")
                
            @unknown default:
                print("❓ StoreKit 1: Unknown transaction state")
            }
        }
    }
    
    // MARK: - StoreKit 1 Payment Method (Fallback)
    func makeLegacyPurchase() {
        print("🔄 CartViewController: Attempting StoreKit 1 purchase as fallback")
        
        guard SKPaymentQueue.canMakePayments() else {
            print("❌ StoreKit 1: User cannot make payments")
            return
        }
        
        let paymentRequest = SKMutablePayment()
        paymentRequest.productIdentifier = productID
        SKPaymentQueue.default().add(paymentRequest)
    }
    
    // Process order payment
    func placeOrder() {
        print("🔄 CartViewController: placeOrder() called - Starting transaction process")
        Task { @MainActor in
            print("🔄 CartViewController: Starting place order process inside Task...")
            self.isProcessing = true
            
            // Validate user
            guard let userId = UserDefaultsManager.shared.getUserId(),
                  let firstItem = orderManager.currentCart.first else {
                print("❌ CartViewController: Missing user or cart data.")
                self.isProcessing = false
                return
            }
            
            print("✅ CartViewController: User validation successful - UserId: \(userId)")
            print("📦 CartViewController: First cart item: \(firstItem.product.name)")

            let restaurantId = firstItem.product.restaurantId
            print("🏪 CartViewController: Restaurant ID: \(restaurantId)")

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
            
            print("📝 CartViewController: Order request created with \(orderRequest.items.count) items, total amount: \(orderRequest.totalAmount)")
            self.currentOrderRequest = orderRequest

            // First try StoreKit 2
            print("🔍 CartViewController: Attempting to retrieve StoreKit2 product 'com.qskipper.premium'")
            let product = StoreKitManager.shared.getProduct(byID: "com.qskipper.premium")
            
            if let orderProduct = product {
                print("✅ CartViewController: Found StoreKit product: \(orderProduct.id), displayName: \(orderProduct.displayName), price: \(orderProduct.displayPrice)")
                
                do {
                    print("🧪 StoreKit2: Attempting to purchase in sandbox...")
                    let result = try await orderProduct.purchase()
                    print("✅ StoreKit2: Purchase method returned with result: \(result)")

                    switch result {
                    case .success(let verification):
                        print("🔐 StoreKit2: Success path entered, verification result received")
                        switch verification {
                        case .unverified(_, let error):
                            print("⚠️ Transaction unverified: \(error.localizedDescription)")
                            self.isProcessing = false
                            return

                        case .verified(let transaction):
                            print("✅ StoreKit2 transaction verified!")
                            print("   - Transaction ID: \(transaction.id)")
                            print("   - Product ID: \(transaction.productID)")
                            
                            await transaction.finish()
                            print("✅ Transaction finished")
                            
                            print("🌐 Submitting order to API...")
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
                    print("❌ StoreKit2 purchase failed with error: \(error)")
                    print("   - Error localized description: \(error.localizedDescription)")
                    print("   - Error domain: \((error as NSError).domain)")
                    print("   - Error code: \((error as NSError).code)")
                    if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
                        print("   - Underlying error: \(underlyingError)")
                    }
                    
                    // If StoreKit 2 fails, try StoreKit 1 as fallback
                    print("🔄 Falling back to StoreKit 1 approach...")
                    makeLegacyPurchase()
                }
            } else {
                print("❌ CartViewController: StoreKit2 product NOT FOUND for ID: com.qskipper.premium")
                print("🧩 CartViewController: Available products: \(StoreKitManager.shared.availableProducts.map { $0.id })")
                print("🔄 Falling back to StoreKit 1 approach...")
                makeLegacyPurchase()
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