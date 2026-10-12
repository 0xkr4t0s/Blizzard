import BMAPShim
import Testing

// PLAN T007: a throwing or garbage link must come back as a blz_status, never a crash.
// Every case goes through the C API: Swift → shim → CallbackTransport → this fake link → shim → Swift.

/// Scripted link. `status` is what the callback returns; `reply` is what it writes when that is BLZ_OK.
private final class FakeLink {
    var status: blz_status = BLZ_OK
    var reply: [UInt8] = []
    /// Reported in `*out_len` instead of `reply.count`, to simulate a link that lies about the length.
    var claimedLength: Int?
    var requests: [[UInt8]] = []
}

private struct InitResult {
    var status: blz_status
    var deviceError: UInt8
    var message: String
}

private func runInit(_ link: FakeLink, profile: blz_profile = BLZ_PROFILE_APP) throws -> InitResult {
    try withExtendedLifetime(link) {
        let ctx = Unmanaged.passUnretained(link).toOpaque()
        let session = blz_session_create(
            { ctx, pkt, pktLen, _, out, outCap, outLen in
                let link = Unmanaged<FakeLink>.fromOpaque(ctx!).takeUnretainedValue()
                link.requests.append(Array(UnsafeBufferPointer(start: pkt, count: pktLen)))
                guard link.status == BLZ_OK else { return link.status }
                let n = min(link.reply.count, outCap)
                if n > 0 {
                    link.reply.withUnsafeBufferPointer { out!.update(from: $0.baseAddress!, count: n) }
                }
                outLen!.pointee = link.claimedLength ?? link.reply.count
                return BLZ_OK
            }, ctx, profile)
        let s = try #require(session)
        defer { blz_session_destroy(s) }
        let status = blz_init(s)
        return InitResult(status: status, deviceError: blz_last_device_error(s), message: lastMessage(s))
    }
}

private func lastMessage(_ s: OpaquePointer) -> String {
    let length = blz_last_error_message(s, nil, 0)
    var buffer = [CChar](repeating: 0, count: length + 1)
    _ = blz_last_error_message(s, &buffer, buffer.count)
    return String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

private func link(status: blz_status = BLZ_OK, reply: [UInt8] = [], claimedLength: Int? = nil) -> FakeLink {
    let link = FakeLink()
    link.status = status
    link.reply = reply
    link.claimedLength = claimedLength
    return link
}

private let initReply: [UInt8] = [0x00, 0x01, 0x03, 0x05, 0x01, 0x02, 0x03, 0x04, 0x05]

// MARK: - Good replies

@Test func initSendsExactlyGet01() throws {
    let fake = link(reply: initReply)
    let result = try runInit(fake)
    #expect(result.status == BLZ_OK)
    #expect(result.message.isEmpty)
    #expect(fake.requests == [[0x00, 0x01, 0x01, 0x00]])
}

@Test func initSkipsAnUnsolicitedFrameBeforeTheReply() throws {
    let result = try runInit(link(reply: [0x02, 0x02, 0x03, 0x01, 0x50] + initReply))
    #expect(result.status == BLZ_OK)
}

@Test(arguments: [BLZ_PROFILE_APP, BLZ_PROFILE_PROBE, BLZ_PROFILE_REPLAY])
func initIsAllowedInEveryProfile(profile: blz_profile) throws {
    #expect(try runInit(link(reply: initReply), profile: profile).status == BLZ_OK)
}

// MARK: - Link failures

@Test(arguments: [BLZ_ERR_CONNECT, BLZ_ERR_BUSY, BLZ_ERR_TIMEOUT, BLZ_ERR_CLOSED])
func linkFailureStatusPassesThrough(status: blz_status) throws {
    let result = try runInit(link(status: status))
    #expect(result.status == status)
    #expect(!result.message.isEmpty)
}

@Test(arguments: [BLZ_ERR_DENIED, BLZ_ERR_DEVICE, blz_status(rawValue: 99)])
func unexpectedLinkStatusIsInternal(status: blz_status) throws {
    #expect(try runInit(link(status: status)).status == BLZ_ERR_INTERNAL)
}

@Test func linkClaimingMoreBytesThanTheBufferIsInternal() throws {
    let result = try runInit(link(reply: initReply, claimedLength: 64 * 1024 + 1))
    #expect(result.status == BLZ_ERR_INTERNAL)
}

// MARK: - Garbage replies

@Test(arguments: [
    [],
    [0xFF, 0xFF, 0xFF, 0xFF],
    [0x00, 0x01, 0x03, 0x05, 0x01],  // header promises 5 bytes, 1 arrives
    [0x00, 0x01],
] as [[UInt8]])
func unparseableReplyIsParseError(reply: [UInt8]) throws {
    let result = try runInit(link(reply: reply))
    #expect(result.status == BLZ_ERR_PARSE)
    #expect(!result.message.isEmpty)
}

@Test func replyWithTheWrongOperatorIsParseError() throws {
    #expect(try runInit(link(reply: [0x00, 0x01, 0x06, 0x00])).status == BLZ_ERR_PARSE)
}

@Test func replyFromAnotherAddressIsDesync() throws {
    #expect(try runInit(link(reply: [0x00, 0x05, 0x03, 0x01, 0x41])).status == BLZ_ERR_DESYNC)
}

@Test func errorReplyIsDeviceErrorWithItsCode() throws {
    let result = try runInit(link(reply: [0x00, 0x01, 0x04, 0x01, 0x05]))
    #expect(result.status == BLZ_ERR_DEVICE)
    #expect(result.deviceError == 5)
}

@Test func successClearsThePreviousError() throws {
    let fake = link(status: BLZ_ERR_TIMEOUT)
    try withExtendedLifetime(fake) {
        let ctx = Unmanaged.passUnretained(fake).toOpaque()
        // Built outside #require: the macro rewrites call arguments, which breaks the C function pointer conversion.
        let session = blz_session_create(
            { ctx, _, _, _, out, _, outLen in
                let link = Unmanaged<FakeLink>.fromOpaque(ctx!).takeUnretainedValue()
                guard link.status == BLZ_OK else { return link.status }
                link.reply.withUnsafeBufferPointer { out!.update(from: $0.baseAddress!, count: $0.count) }
                outLen!.pointee = link.reply.count
                return BLZ_OK
            }, ctx, BLZ_PROFILE_APP)
        let s = try #require(session)
        defer { blz_session_destroy(s) }
        #expect(blz_init(s) == BLZ_ERR_TIMEOUT)
        #expect(!lastMessage(s).isEmpty)
        fake.status = BLZ_OK
        fake.reply = initReply
        #expect(blz_init(s) == BLZ_OK)
        #expect(lastMessage(s).isEmpty)
        #expect(blz_last_device_error(s) == 0)
    }
}

// MARK: - Bad arguments

@Test func nullArgumentsAreRejected() {
    #expect(blz_init(nil) == BLZ_ERR_INVALID_ARG)
    let session = blz_session_create(nil, nil, BLZ_PROFILE_APP)
    #expect(session == nil)
    #expect(blz_last_device_error(nil) == 0)
    #expect(blz_last_error_message(nil, nil, 0) == 0)
    blz_session_destroy(nil)
}

@Test func unknownProfileIsRejected() {
    let session = blz_session_create({ _, _, _, _, _, _, _ in BLZ_OK }, nil, blz_profile(rawValue: 7))
    #expect(session == nil)
    blz_session_destroy(session)
}

@Test func errorMessageIsTruncatedAndTerminated() throws {
    let fake = link(status: BLZ_ERR_TIMEOUT)
    try withExtendedLifetime(fake) {
        let ctx = Unmanaged.passUnretained(fake).toOpaque()
        let session = blz_session_create(
            { ctx, _, _, _, _, _, _ in
                Unmanaged<FakeLink>.fromOpaque(ctx!).takeUnretainedValue().status
            }, ctx, BLZ_PROFILE_APP)
        let s = try #require(session)
        defer { blz_session_destroy(s) }
        #expect(blz_init(s) == BLZ_ERR_TIMEOUT)
        var small = [CChar](repeating: 0x7F, count: 4)
        let full = blz_last_error_message(s, &small, small.count)
        #expect(full > 3)
        #expect(small[3] == 0)
    }
}
