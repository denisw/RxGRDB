import XCTest
import GRDB
import RxSwift
import RxGRDB

class DatabaseRegionObservationTests : XCTestCase { }


// MARK: - Changes

extension DatabaseRegionObservationTests {
    func testRxChanges() throws {
        try Test(testRxChanges)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testRxChanges(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        try writer.write { db in
            try db.create(table: "table1") { t in
                t.column("id", .integer).primaryKey()
                t.column("a", .integer)
                t.column("b", .integer)
            }
            try db.create(table: "table2") { t in
                t.column("id", .integer).primaryKey()
                t.column("a", .integer)
                t.column("b", .integer)
            }
        }
        
        let requests: [SQLRequest<Row>] = [
            SQLRequest(sql: "SELECT a FROM table1"),
            SQLRequest(sql: "SELECT table1.a, table2.b FROM table1, table2")]
        
        let recorder = EventRecorder<Void>(expectedEventCount: 5)
        
        // 1 (startImmediately parameter is true by default)
        DatabaseRegionObservation(tracking: requests).rx
            .changes(in: writer)
            .map { _ in }
            .subscribe(recorder)
            .disposed(by: disposeBag)
        
        try writer.writeWithoutTransaction { db in
            // 2 (modify both requests)
            try db.inTransaction {
                try db.execute(sql: "INSERT INTO table1 (id, a, b) VALUES (NULL, 0, 0)")
                try db.execute(sql: "INSERT INTO table2 (id, a, b) VALUES (NULL, 0, 0)")
                return .commit
            }
            
            // still 2 (modifying ignored columns)
            try db.execute(sql: "UPDATE table1 SET b = 1")
            try db.execute(sql: "UPDATE table2 SET a = 1")
            
            // 3 (modify both requests)
            try db.inTransaction {
                try db.execute(sql: "DELETE FROM table1")
                try db.execute(sql: "DELETE FROM table2")
                return .commit
            }
            
            // 4 (modify both request)
            try db.execute(sql: "INSERT INTO table1 (id, a, b) VALUES (NULL, 0, 0)")
            
            // 5 (modify one request)
            try db.execute(sql: "INSERT INTO table2 (id, a, b) VALUES (NULL, 0, 0)")
        }

        wait(for: recorder, timeout: 1)
    }
}

extension DatabaseRegionObservationTests {
    
    func testChangesInFullDatabase() throws {
        try Test(testChangesInFullDatabase)
            .run { try DatabaseQueue(path: $0) }
            .run { try DatabasePool(path: $0) }
    }
    
    func testChangesInFullDatabase(writer: DatabaseWriter, disposeBag: DisposeBag) throws {
        try writer.write { db in
            try db.create(table: "table1") { t in
                t.column("id", .integer).primaryKey()
                t.column("a", .text).notNull()
            }
            try db.create(table: "table2") { t in
                t.column("id", .integer).primaryKey()
            }
        }
        
        let recorder = EventRecorder<Void>(expectedEventCount: 4)
        
        // 1
        DatabaseRegionObservation(tracking: DatabaseRegion.fullDatabase).rx
            .changes(in: writer)
            .map { _ in }
            .subscribe(recorder)
            .disposed(by: disposeBag)
        
        try writer.writeWithoutTransaction { db in
            // 2
            try db.inTransaction {
                try db.execute(sql: "INSERT INTO table1 (a) VALUES ('foo')")
                try db.execute(sql: "INSERT INTO table1 (a) VALUES ('bar')")
                try db.execute(sql: "INSERT INTO table2 DEFAULT VALUES")
                return .commit
            }
            
            // 3
            try db.execute(sql: "INSERT INTO table2 DEFAULT VALUES")
            
            // 4
            try db.execute(sql: "DELETE FROM table1")
        }
        wait(for: recorder, timeout: 1)
    }
}
