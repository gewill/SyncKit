# SyncKit Core Module Instructions

The Core module contains the synchronization engine and CloudKit abstractions.

## Key Components

- **`CloudKitSynchronizer`**: The main entry point. Orchestrates the fetch and upload operations.
- **`CloudKitDatabaseAdapter`**: A facade for `CKDatabase` to facilitate testing.
- **`ModelAdapter` Protocol**: The interface that must be implemented by any storage-specific adapter (currently `RealmSwiftAdapter`).
- **`CloudKitSynchronizerOperation`**: Base class for all sync-related operations (Fetch, Upload, etc.).

## Guidelines

- **Storage Agnostic**: The Core module should not depend on RealmSwift. All interactions with the local data store must go through the `ModelAdapter` protocol.
- **Operations**: New synchronization steps should be implemented as subclasses of `CloudKitSynchronizerOperation`.
- **Error Handling**: Use `CKError` codes to decide on retry logic or user intervention. Map common sync errors to `CloudKitSynchronizer.SyncError`.
