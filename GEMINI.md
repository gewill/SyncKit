# SyncKit Project Instructions

SyncKit is a library for synchronizing RealmSwift data with CloudKit. Following the 2.0.0 refactor, the project focuses exclusively on RealmSwift and modern Swift practices.

## Project Structure

- `SyncKit/Classes/Core`: The core synchronization engine. It handles CloudKit operations, zone management, and the general synchronization lifecycle.
- `SyncKit/Classes/RealmSwift`: The implementation of the `ModelAdapter` protocol for RealmSwift. It handles change tracking and data mapping for Realm objects.
- `Example/RealmSwift`: The example application and test suite for the project.

## Coding Standards

### General
- **Language**: Swift 5.9+
- **Naming**: Avoid the legacy `QS` prefix. Use `SK` for internal keys or notifications where namespacing is required. Public APIs should use clear, idiomatic Swift names.
- **Serialization**: Use the `Coder` class for all CloudKit record and metadata serialization. It uses `NSSecureCoding`.

### Module Specifics
- [Core](./SyncKit/Classes/Core/GEMINI.md): Base synchronization logic.
- [RealmSwift](./SyncKit/Classes/RealmSwift/GEMINI.md): Realm-specific adapter implementation.

## Architecture

### Synchronization Lifecycle
1. **Fetch**: Download changes from CloudKit.
2. **Merge**: Apply changes using Advanced Conflict Resolution (Vector Clocks, Semantic Merging, and Tombstone handling).
3. **Upload**: Identify local changes and upload them to CloudKit.
4. **Finalize**: Persist server tokens and update local metadata.

## Conflict Resolution

Detailed strategies are documented in [CONFLICT_RESOLUTION.md](./CONFLICT_RESOLUTION.md). Key features:
- **Version Tracking**: Monotonic versioning for robust LWW.
- **Delta Counters**: Lossless merging for numeric properties.
- **Semantic List Merging**: Set-based merging for collections.
- **Resurrection**: Handles delete-modify conflicts by prioritizing data preservation.

## Testing Strategy

- **Verification**: All bug fixes and features must be verified with automated tests.
- **Test Target**: Primary tests are located in `Example/RealmSwift/SyncKitRealmSwiftExample/SyncKitRealmSwiftExampleTests`.
- **CloudKit Mocks**: Use mock databases and operations where possible to avoid dependency on live CloudKit environments during unit testing.

## Workflows

- **Adding Features**: Ensure any new features are exposed via the `CloudKitSynchronizer` and implemented in the `RealmSwiftAdapter` if they involve local data store interactions.
- **Refactoring**: Prioritize surgical changes. If refactoring core logic, ensure no regressions in existing RealmSwift sync behavior.
