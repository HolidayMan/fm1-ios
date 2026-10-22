import XCTest
@testable import FM1

final class PerformanceExportTests:XCTestCase {
    private final class JobBox:@unchecked Sendable {
        private let lock=NSLock()
        private var task:Task<URL,Error>?
        private var requested=false
        func set(_ value:Task<URL,Error>){lock.lock();task=value;let cancel=requested;lock.unlock();if cancel {value.cancel()}}
        func cancel(){lock.lock();requested=true;let current=task;lock.unlock();current?.cancel()}
        var didRequest:Bool {lock.lock();defer{lock.unlock()};return requested}
    }
    private func package()throws->Data {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        for folder in ["Native16Packages","Native13Packages","Firmwares"] {
            for file in (try? FileManager.default.contentsOfDirectory(at:documents.appendingPathComponent(folder),includingPropertiesForKeys:nil)) ?? [] where file.pathExtension == "fwsc" {
                let data=try Data(contentsOf:file)
                if data.withUnsafeBytes({instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,data.count)}) == 2 {return data}
            }
        }
        throw XCTSkip("Requires the pinned local SLOOP package; never downloads")
    }
    private func musicalSnapshot(package:Data)async throws->SloopWorkSnapshot {
        try await withCheckedThrowingContinuation {continuation in
            DispatchQueue(label:"fm1.export-test-fixture").async {
                do {
                    var error=[UInt8](repeating:0,count:512)
                    let optional=package.withUnsafeBytes{instrument_create($0.bindMemory(to:UInt8.self).baseAddress,package.count,&error,error.count)}
                    let machine=try XCTUnwrap(optional);defer{instrument_destroy(machine)}
                    var samples=[Float](repeating:0,count:1024)
                    func advance(_ frames:Int)throws {
                        var left=frames
                        while left>0 {let count=min(512,left);let rendered=samples.withUnsafeMutableBufferPointer{instrument_render(machine,$0.baseAddress,count)};XCTAssertEqual(rendered,count);left-=count}
                    }
                    func tap(_ key:UInt32)throws {instrument_key(machine,key,true);try advance(6615);instrument_key(machine,key,false);try advance(1024)}
                    try advance(22050)
                    for _ in 0..<3 {instrument_encoder(machine,1,1);try advance(2205)}
                    try tap(13)
                    for key:UInt32 in [14,16,18,20,21] {try tap(key);try advance(8820)}
                    try tap(13);try advance(132300);try tap(12)
                    continuation.resume(returning:try SloopWorkSnapshot.capture(machine:machine,master:716))
                } catch {continuation.resume(throwing:error)}
            }
        }
    }
    func testPreviousReleaseProjectRendersWithCurrentEngineWithoutChangingOriginal()async throws {
        let package=try package(),current=try await musicalSnapshot(package:package)
        let previous=SloopWorkSnapshot(version:current.version,packageSHA256:SloopVersionMigration.previousPackageSHA256,master:current.master,parts:current.parts)
        try previous.validate()
        let url=try await PerformanceExport.render(snapshot:previous,package:package,duration:1,tail:0.1)
        defer {try? FileManager.default.removeItem(at:url)}
        XCTAssertGreaterThan(try Data(contentsOf:url).count,44)
        XCTAssertEqual(previous.packageSHA256,SloopVersionMigration.previousPackageSHA256)
        XCTAssertEqual(try previous.bytes("object0"),try current.bytes("object0"))
    }
    func testRendersRecordedUnsavedLoopIntoPlayableWAV()async throws {
        let package=try package(),snapshot=try await musicalSnapshot(package:package)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(snapshot)
        let url=try await PerformanceExport.render(snapshot:snapshot,package:package,duration:1,tail:0.25)
        defer {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
        let bytes=try Data(contentsOf:url)
        XCTAssertEqual(bytes.count,44+55125*4)
        XCTAssertEqual(bytes.prefix(4),Data("RIFF".utf8));XCTAssertEqual(bytes[8..<12],Data("WAVE".utf8))
        let audio=bytes.dropFirst(44)
        XCTAssertTrue(audio.contains{$0 != 0},"The captured unsaved musical loop must be audible, not a valid silent WAV header")
        XCTAssertEqual(try encoder.encode(snapshot),before)
        let decoded=try SampleAudioImporter.load(url)
        XCTAssertEqual(decoded.duration,1.25,accuracy:0.005)
        XCTAssertGreaterThan(decoded.samples.map{abs($0)}.max() ?? 0,0.001)
    }
    func testWholeSongExportsAllEntriesOnceAndPreservesSource()async throws {
        let package=try package(),original=try await musicalSnapshot(package:package)
        func song(_ bars:UInt8)throws->SloopWorkSnapshot {
            let loop=try original.bytes("object0")
            var copy=original
            copy.parts.removeAll{["object2","object3","arrangement"].contains($0.name)}
            copy.parts += [.init("object2",loop),.init("object3",loop),
                .init("arrangement",Data([0,0,3,0,0,0,0,0,0,1,2,0,1,1,bars]))]
            return copy
        }
        let source=try song(2)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let before=try encoder.encode(source)
        let url=try await PerformanceExport.render(snapshot:source,package:package,duration:1,tail:0.25,mode:.song)
        defer{try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
        let decoded=try SampleAudioImporter.load(url)
        XCTAssertGreaterThan(decoded.duration,2,"Whole song must not use the one-second loop duration")
        XCTAssertGreaterThan(decoded.samples.map{abs($0)}.max() ?? 0,0.001)
        let short=try await PerformanceExport.render(snapshot:song(1),package:package,duration:1,tail:0.25,mode:.song)
        defer{try? FileManager.default.removeItem(at:short.deletingLastPathComponent())}
        let shortAudio=try SampleAudioImporter.load(short)
        XCTAssertEqual((decoded.duration-0.25)/(shortAudio.duration-0.25),1.5,accuracy:0.01,"A1+B2 must last three bars; A1+B1 two. Repeat must not loop forever.")
        XCTAssertEqual(try encoder.encode(source),before,"Export must not change the live song mode or repeat setting")
        let loop=try await PerformanceExport.render(snapshot:source,package:package,duration:1,tail:0.25,mode:.loop)
        defer{try? FileManager.default.removeItem(at:loop.deletingLastPathComponent())}
        XCTAssertEqual(try SampleAudioImporter.load(loop).duration,1.25,accuracy:0.001)
        var invalid=source
        var arrangement=try invalid.bytes("arrangement");arrangement[2]=1
        invalid.parts.removeAll{$0.name == "arrangement"};invalid.parts.append(.init("arrangement",arrangement))
        do {_=try await PerformanceExport.render(snapshot:invalid,package:package,duration:1,tail:0,mode:.song);XCTFail("Missing B must not export a silent or partial song")}
        catch {XCTAssertTrue(error.localizedDescription.contains("section"))}
    }
    func testCancelledRenderNeverReturnsACompletedFile()async throws {
        let package=try package(),snapshot=try await musicalSnapshot(package:package)
        let box=JobBox()
        let job=Task {try await PerformanceExport.render(snapshot:snapshot,package:package,duration:120,tail:10){fraction in if fraction>0 {box.cancel()}}}
        box.set(job)
        do {_=try await job.value;XCTFail("Cancellation must not return an apparently complete take")}
        catch is CancellationError {} catch {XCTFail("Expected cancellation, got \(error)")}
        XCTAssertTrue(box.didRequest,"Cancel only after actual rendered audio, exercising partial-file cleanup")
    }
}
