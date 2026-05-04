//
//  CloudKitDatabase.swift
//  SyncKit
//
//  Created by Manuel Entrena on 09/06/2019.
//  Copyright © 2019 Manuel Entrena. All rights reserved.
//

import Foundation
import CloudKit

/*
 CloudKitDatabaseAdapter is a façade of the CKDatabase api, used by CloudKitSynchronizer instead of using CKDatabase directly,
 because this allows us to test the synchronizer.
 */

@objc public protocol CloudKitDatabaseAdapter {
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449116-add
    func add(_ operation: CKDatabaseOperation)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449114-save
    func save(zone: CKRecordZone, completionHandler: @escaping (CKRecordZone?, Error?) -> Void)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449104-fetch
    func fetch(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping (CKRecordZone?, Error?) -> Void)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449126-fetch
    func fetch(withRecordID recordID: CKRecord.ID, completionHandler: @escaping (CKRecord?, Error?) -> Void)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449118-delete
    func delete(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping (CKRecordZone.ID?, Error?) -> Void)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1640398-databasescope
    var databaseScope: CKDatabase.Scope { get }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449110-fetchallsubscriptions
    @available(iOS 10.0, macOS 10.12, watchOS 6.0, *)
    func fetchAllSubscriptions(completionHandler: @escaping ([CKSubscription]?, Error?) -> Void)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449102-save
    @available(iOS 10.0, macOS 10.12, watchOS 6.0, *)
    func save(subscription: CKSubscription, completionHandler: @escaping (CKSubscription?, Error?) -> Void)
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/3003590-delete
    @available(iOS 10.0, macOS 10.12, watchOS 6.0, *)
    func delete(withSubscriptionID subscriptionID: CKSubscription.ID, completionHandler: @escaping (String?, Error?) -> Void)

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(saveZone:completionHandler:) func save(zone: CKRecordZone) async throws -> CKRecordZone
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(fetchRecordZoneWithID:completionHandler:) func fetch(withRecordZoneID zoneID: CKRecordZone.ID) async throws -> CKRecordZone
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(fetchRecordWithID:completionHandler:) func fetch(withRecordID recordID: CKRecord.ID) async throws -> CKRecord
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(deleteRecordZoneWithID:completionHandler:) func delete(withRecordZoneID zoneID: CKRecordZone.ID) async throws -> CKRecordZone.ID
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(fetchAllSubscriptionsWithCompletion:) func fetchAllSubscriptions() async throws -> [CKSubscription]
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(saveSubscription:completionHandler:) func save(subscription: CKSubscription) async throws -> CKSubscription
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(deleteSubscriptionWithID:completionHandler:) func delete(withSubscriptionID subscriptionID: CKSubscription.ID) async throws -> String
}

@objc public class DefaultCloudKitDatabaseAdapter: NSObject, CloudKitDatabaseAdapter {
    
    
    /// The `CKDatabase` used by this adapter
    public let database: CKDatabase
    
    /// Initialize a `DefaultCloudKitDatabaseAdapter` with a given `CKDatabase`. All calls to the adapter methods will be forwarded to the database instance.
    /// - Parameter database:
    public init(database: CKDatabase) {
        self.database = database
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449116-add
    public func add(_ operation: CKDatabaseOperation) {
        database.add(operation)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449114-save
    public func save(zone: CKRecordZone, completionHandler: @escaping (CKRecordZone?, Error?) -> Void) {
        database.save(zone, completionHandler: completionHandler)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449104-fetch
    public func fetch(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping (CKRecordZone?, Error?) -> Void) {
        database.fetch(withRecordZoneID: zoneID, completionHandler: completionHandler)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449126-fetch
    public func fetch(withRecordID recordID: CKRecord.ID, completionHandler: @escaping (CKRecord?, Error?) -> Void) {
        database.fetch(withRecordID: recordID, completionHandler: completionHandler)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449118-delete
    public func delete(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping (CKRecordZone.ID?, Error?) -> Void) {
        database.delete(withRecordZoneID: zoneID, completionHandler: completionHandler)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1640398-databasescope
    public var databaseScope: CKDatabase.Scope {
        return database.databaseScope
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449110-fetchallsubscriptions
    @available(iOS 10.0, macOS 10.12, watchOS 6.0, *)
    public func fetchAllSubscriptions(completionHandler: @escaping ([CKSubscription]?, Error?) -> Void) {
        database.fetchAllSubscriptions(completionHandler: completionHandler)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/1449102-save
    @available(iOS 10.0, macOS 10.12, watchOS 6.0, *)
    public func save(subscription: CKSubscription, completionHandler: @escaping (CKSubscription?, Error?) -> Void) {
        database.save(subscription, completionHandler: completionHandler)
    }
    
    /// See https://developer.apple.com/documentation/cloudkit/ckdatabase/3003590-delete
    @available(iOS 10.0, macOS 10.12, watchOS 6.0, *)
    public func delete(withSubscriptionID subscriptionID: CKSubscription.ID, completionHandler: @escaping (String?, Error?) -> Void) {
        database.delete(withSubscriptionID: subscriptionID, completionHandler: completionHandler)
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(saveZone:completionHandler:) public func save(zone: CKRecordZone) async throws -> CKRecordZone {
        try await database.save(zone)
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(fetchRecordZoneWithID:completionHandler:) public func fetch(withRecordZoneID zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        try await database.recordZone(for: zoneID)
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(fetchRecordWithID:completionHandler:) public func fetch(withRecordID recordID: CKRecord.ID) async throws -> CKRecord {
        try await database.record(for: recordID)
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(deleteRecordZoneWithID:completionHandler:) public func delete(withRecordZoneID zoneID: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        try await database.deleteRecordZone(withID: zoneID)
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(fetchAllSubscriptionsWithCompletion:) public func fetchAllSubscriptions() async throws -> [CKSubscription] {
        try await database.allSubscriptions()
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(saveSubscription:completionHandler:) public func save(subscription: CKSubscription) async throws -> CKSubscription {
        try await database.save(subscription)
    }

    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
    @objc(deleteSubscriptionWithID:completionHandler:) public func delete(withSubscriptionID subscriptionID: CKSubscription.ID) async throws -> String {
        try await database.deleteSubscription(withID: subscriptionID)
    }
}
