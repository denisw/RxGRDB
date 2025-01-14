import XCTest
import GRDB
import RxSwift
@testable import RxGRDB // @testable to get PrimaryKeyDiff initializer

// The tested request
private struct CustomFetchRequest<T>: FetchRequest, ReactiveCompatible {
    typealias RowDecoder = T
    
    private let _prepare: (Database, _ singleResult: Bool) throws -> (SelectStatement, RowAdapter?)
    private let _fetchCount: (Database) throws -> Int
    private let _databaseRegion: (Database) throws -> DatabaseRegion
    
    init<Request: FetchRequest>(_ request: Request) where Request.RowDecoder == T {
        _prepare = request.prepare
        _fetchCount = request.fetchCount
        _databaseRegion = request.databaseRegion
    }
    
    func prepare(_ db: Database, forSingleResult singleResult: Bool) throws -> (SelectStatement, RowAdapter?) {
        return try _prepare(db, singleResult)
    }
    
    func fetchCount(_ db: Database) throws -> Int {
        return try _fetchCount(db)
    }
    
    func databaseRegion(_ db: Database) throws -> DatabaseRegion {
        return try _databaseRegion(db)
    }
}

class FetchRequestTests : XCTestCase { }

extension FetchRequestTests {
    func setUpDatabase(in writer: DatabaseWriter) throws {
        try writer.write { db in
            try db.create(table: "player") { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text)
                t.column("email", .text)
            }
            var player = Player(id: nil, name: "Arthur", email: "arthur@example.com")
            try player.insert(db)
            player = Player(id: nil, name: "Barbara", email: nil)
            try player.insert(db)
        }
    }
    
    func modifyDatabase(in writer: DatabaseWriter) throws {
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "UPDATE player SET name = name WHERE id = 1")
            try db.execute(sql: "UPDATE player SET name = ? WHERE name = ?", arguments: ["Barbie", "Barbara"])
            _ = try Player.deleteAll(db)
            try db.inTransaction {
                var player = Player(id: nil, name: "Craig", email: nil)
                try player.insert(db)
                player = Player(id: nil, name: "David", email: "david@example.com")
                try player.insert(db)
                player = Player(id: nil, name: "Elena", email: "elena@example.com")
                try player.insert(db)
                return .commit
            }
        }
    }
}

// MARK: - RowConvertible

extension FetchRequestTests {
    func testRxFetchAllRecords() throws {
        try Test(testRxFetchAllRecords)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchAllRecords(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.order(Column("name"))
        let expectedNames = [
            ["Arthur", "Barbara"],
            ["Arthur", "Barbie"],
            [],
            ["Craig", "David", "Elena"],
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<[Player]>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchAll(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, names) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!.map { $0.name }, names)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchAllRecordsIdentifiedByIds() throws {
        try Test(testRxFetchAllRecordsIdentifiedByIds)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchAllRecordsIdentifiedByIds(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.filter(keys: [2, 3]).order(Column("name"))
        let expectedNames = [
            ["Barbara"],
            ["Barbie"],
            [],
            ["David", "Elena"],
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<[Player]>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchAll(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, names) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!.map { $0.name }, names)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchOneRecord() throws {
        try Test(testRxFetchOneRecord)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchOneRecord(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.order(Column("name"))
        let expectedNames = [
            "Arthur",
            nil,
            "Craig",
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<Player?>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchOne(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, name) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!?.name, name)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchOneRecordIdentifiedById() throws {
        try Test(testRxFetchOneRecordIdentifiedById)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchOneRecordIdentifiedById(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.filter(key: 2)
        let expectedNames = [
            "Barbara",
            "Barbie",
            nil,
            "David"
        ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<Player?>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchOne(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, name) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!?.name, name)
        }
    }
}

// MARK: - Row

extension FetchRequestTests {
    func testRxFetchAllRows() throws {
        try Test(testRxFetchAllRows)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchAllRows(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = SQLRequest<Row>(sql: "SELECT * FROM player ORDER BY name")
        let expectedNames = [
            ["Arthur", "Barbara"],
            ["Arthur", "Barbie"],
            [],
            ["Craig", "David", "Elena"],
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<[Row]>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchAll(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, names) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!.map { $0["name"] as String }, names)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchAllRowsIdentifiedByIds() throws {
        try Test(testRxFetchAllRowsIdentifiedByIds)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchAllRowsIdentifiedByIds(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.filter(keys: [2, 3]).order(Column("name")).asRequest(of: Row.self)
        let expectedNames = [
            ["Barbara"],
            ["Barbie"],
            [],
            ["David", "Elena"],
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<[Row]>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchAll(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, names) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!.map { $0["name"] as String }, names)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchOneRow() throws {
        try Test(testRxFetchOneRow)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchOneRow(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = SQLRequest<Row>(sql: "SELECT * FROM player ORDER BY name")
        let expectedNames = [
            "Arthur",
            nil,
            "Craig",
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<Row?>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchOne(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, name) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!?["name"] as String?, name)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchOneRowIdentifiedById() throws {
        try Test(testRxFetchOneRowIdentifiedById)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchOneRowIdentifiedById(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.filter(key: 2).asRequest(of: Row.self)
        let expectedNames = [
            "Barbara",
            "Barbie",
            nil,
            "David"
        ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<Row?>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchOne(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, name) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!?["name"] as String?, name)
        }
    }
}

// MARK: - DatabaseValue

extension FetchRequestTests {
    func testRxFetchAllDatabaseValues() throws {
        try Test(testRxFetchAllDatabaseValues)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchAllDatabaseValues(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = SQLRequest<String>(sql: "SELECT name FROM player ORDER BY name")
        let expectedNames = [
            ["Arthur", "Barbara"],
            ["Arthur", "Barbie"],
            [],
            ["Craig", "David", "Elena"],
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<[String]>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchAll(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, names) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!, names)
        }
    }
}

extension FetchRequestTests {
    func testRxFetchOneDatabaseValue() throws {
        try Test(testRxFetchOneDatabaseValue)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchOneDatabaseValue(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = SQLRequest<String>(sql: "SELECT name FROM player ORDER BY name")
        let expectedNames = [
            "Arthur",
            nil,
            "Craig",
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<String?>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchOne(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, name) in zip(recorder.recordedEvents, expectedNames) {
            XCTAssertEqual(event.element!, name)
        }
    }
}

// MARK: - Optional DatabaseValue

extension FetchRequestTests {
    func testRxFetchAllOptionalDatabaseValues() throws {
        try Test(testRxFetchAllOptionalDatabaseValues)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxFetchAllOptionalDatabaseValues(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = SQLRequest<String?>(sql: "SELECT email FROM player ORDER BY name")
        let expectedNames = [
            ["arthur@example.com", nil],
            [],
            [nil, "david@example.com", "elena@example.com"],
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<[String?]>(expectedEventCount: expectedNames.count)
        CustomFetchRequest(request).rx.fetchAll(in: writer)
            .subscribe { event in
                // events are expected on the main thread by default
                assertMainQueue()
                recorder.on(event)
            }
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, names) in zip(recorder.recordedEvents, expectedNames) {
            let fetchedNames = event.element!
            XCTAssertEqual(fetchedNames.count, names.count)
            for (fetchedName, name) in zip(fetchedNames, names) {
                XCTAssertEqual(fetchedName, name)
            }
        }
    }
}

extension FetchRequestTests {
    func testPrimaryKeyDiffScanner() throws {
        try Test(testPrimaryKeyDiffScanner)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testPrimaryKeyDiffScanner(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        let request = Player.orderByPrimaryKey()
        let expectedDiffs = [
            PrimaryKeyDiff(
                inserted: [
                    Player(id: 1, name: "Arthur", email: "arthur@example.com"),
                    Player(id: 2, name: "Barbara", email: nil),
                    ],
                updated: [],
                deleted: []),
            PrimaryKeyDiff(
                inserted: [],
                updated: [Player(id: 2, name: "Barbie", email: nil)],
                deleted: []),
            PrimaryKeyDiff(
                inserted: [],
                updated: [],
                deleted: [
                    Player(id: 1, name: "Arthur", email: "arthur@example.com"),
                    Player(id: 2, name: "Barbie", email: nil)]),
            PrimaryKeyDiff(
                inserted: [
                    Player(id: 1, name: "Craig", email: nil),
                    Player(id: 2, name: "David", email: "david@example.com"),
                    Player(id: 3, name: "Elena", email: "elena@example.com"),
                    ],
                updated: [],
                deleted: []),
            ]
        
        try setUpDatabase(in: writer)
        let recorder = EventRecorder<PrimaryKeyDiff<Player>>(expectedEventCount: expectedDiffs.count)
        
        let diffScanner = try writer.read { db in
            try PrimaryKeyDiffScanner(
                database: db,
                request: request,
                initialRecords: [])
        }
        CustomFetchRequest(request.asRequest(of: Row.self))
            .rx
            .fetchAll(in: writer)
            .scan(diffScanner) { (diffScanner, rows) in diffScanner.diffed(from: rows) }
            .map { $0.diff }
            .subscribe(recorder)
            .disposed(by: disposeBag)
        try modifyDatabase(in: writer)
        wait(for: recorder, timeout: 1)
        
        for (event, expectedDiff) in zip(recorder.recordedEvents, expectedDiffs) {
            let diff = event.element!
            XCTAssertEqual(diff.inserted, expectedDiff.inserted)
            XCTAssertEqual(diff.updated, expectedDiff.updated)
            XCTAssertEqual(diff.deleted, expectedDiff.deleted)
        }
    }
}

// MARK: - Support

private struct Player : FetchableRecord, MutablePersistableRecord, Codable, Equatable {
    var id: Int64?
    var name: String
    var email: String?
    
    mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}
