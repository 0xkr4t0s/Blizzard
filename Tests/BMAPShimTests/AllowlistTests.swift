import BMAPShim
import Testing

// PLAN T006: the allowlist must match the "Blizzard policy" column of docs/PROTOCOL.md (ADR-0004).
// Every absolute deny-list rule is tested in every profile. The tables here repeat the policy on purpose:
// a change to allowlist.cpp that is not also made here fails a test.

struct Packet: Sendable, CustomTestStringConvertible {
    let name: String
    let bytes: [UInt8]

    init(_ name: String, _ bytes: [UInt8]) {
        self.name = name
        self.bytes = bytes
    }

    var testDescription: String { name }
}

private let allProfiles = [BLZ_PROFILE_APP, BLZ_PROFILE_PROBE, BLZ_PROFILE_REPLAY]

private let mac: [UInt8] = [0, 0, 0, 0, 0, 0]

private func allowed(_ profile: blz_profile, _ packet: Packet) -> Bool {
    blz_packet_allowed(profile, packet.bytes, packet.bytes.count)
}

// MARK: - Absolute deny-list (every profile)

private let absoluteDenyList: [Packet] = [
    // Operators: SET needs cloud auth; STATUS, ERROR, RESULT and PROCESSING are responses; 8-15 are undefined.
    Packet("SET [0.5]", [0x00, 0x05, 0x00, 0x00]),
    Packet("SET [31.3]", [0x1F, 0x03, 0x00, 0x02, 0x01, 0x00]),
    Packet("STATUS [0.5]", [0x00, 0x05, 0x03, 0x00]),
    Packet("ERROR [0.5]", [0x00, 0x05, 0x04, 0x00]),
    Packet("RESULT [0.5]", [0x00, 0x05, 0x06, 0x00]),
    Packet("PROCESSING [0.5]", [0x00, 0x05, 0x07, 0x00]),
    Packet("op 8 [0.5]", [0x00, 0x05, 0x08, 0x00]),
    Packet("op 15 [0.5]", [0x00, 0x05, 0x0F, 0x00]),
    // Blocks denied for every operator, GET included.
    Packet("GET [3.1] FirmwareUpdate", [0x03, 0x01, 0x01, 0x00]),
    Packet("GET [8.1] Debug", [0x08, 0x01, 0x01, 0x00]),
    Packet("GET [18.1] Authentication", [0x12, 0x01, 0x01, 0x00]),
    Packet("GET [20.1] Cloud", [0x14, 0x01, 0x01, 0x00]),
    Packet("START [3.2] FirmwareUpdate", [0x03, 0x02, 0x05, 0x00]),
    // Functions PROTOCOL.md marks DENY.
    Packet("GET [1.6] ANR", [0x01, 0x06, 0x01, 0x00]),
    Packet("START [4.1] connect", [0x04, 0x01, 0x05, 0x06] + mac),
    Packet("START [4.2] disconnect", [0x04, 0x02, 0x05, 0x06] + mac),
    Packet("START [4.3] remove device", [0x04, 0x03, 0x05, 0x06] + mac),
    Packet("START [4.7] clear device list", [0x04, 0x07, 0x05, 0x00]),
    Packet("START [4.8] pairing mode", [0x04, 0x08, 0x05, 0x01, 0x01]),
    Packet("START [4.12] routing", [0x04, 0x0C, 0x05, 0x07, 0x82] + mac),
    Packet("START [5.3] media keys", [0x05, 0x03, 0x05, 0x01, 0x01]),
    Packet("START [7.4] power off", [0x07, 0x04, 0x05, 0x01, 0x00]),
    Packet("GET [7.4] power off", [0x07, 0x04, 0x01, 0x00]),
    Packet("START [7.5] factory default", [0x07, 0x05, 0x05, 0x00]),
    Packet("START [7.6] ship mode", [0x07, 0x06, 0x05, 0x00]),
    Packet("START [7.7] ANR-only", [0x07, 0x07, 0x05, 0x00]),
    Packet("START [7.11] reset", [0x07, 0x0B, 0x05, 0x00]),
    Packet("START [31.9] mode reset", [0x1F, 0x09, 0x05, 0x00]),
    Packet("SETGET [1.5] CNC", [0x01, 0x05, 0x02, 0x02, 0x05, 0x01]),
    // Malformed headers.
    Packet("empty", []),
    Packet("3 bytes", [0x00, 0x01, 0x01]),
    Packet("length byte too long", [0x00, 0x01, 0x01, 0x01]),
    Packet("length byte too short", [0x00, 0x01, 0x01, 0x00, 0x00]),
    Packet("non-zero device ID", [0x00, 0x01, 0x41, 0x00]),
    Packet("non-zero port", [0x00, 0x01, 0x11, 0x00]),
]

@Test(arguments: allProfiles, absoluteDenyList)
func absoluteDenyListAppliesInEveryProfile(profile: blz_profile, packet: Packet) {
    #expect(!allowed(profile, packet))
}

// MARK: - APP

private let appAllowed: [Packet] = [
    Packet("GET [0.1] init", [0x00, 0x01, 0x01, 0x00]),
    Packet("GET [0.3] product ID", [0x00, 0x03, 0x01, 0x00]),
    Packet("GET [0.5] firmware", [0x00, 0x05, 0x01, 0x00]),
    Packet("GET [1.2] name", [0x01, 0x02, 0x01, 0x00]),
    Packet("GET [2.2] battery", [0x02, 0x02, 0x01, 0x00]),
    Packet("GET [31.3] current mode", [0x1F, 0x03, 0x01, 0x00]),
    Packet("GET [31.6] mode 0", [0x1F, 0x06, 0x01, 0x01, 0x00]),
    Packet("GET [31.6] mode 9", [0x1F, 0x06, 0x01, 0x01, 0x09]),
    Packet("START [31.3] mode 0, no prompt", [0x1F, 0x03, 0x05, 0x02, 0x00, 0x00]),
    Packet("START [31.3] mode 9, prompt", [0x1F, 0x03, 0x05, 0x02, 0x09, 0x01]),
    Packet("SETGET [1.11] off", [0x01, 0x0B, 0x02, 0x02, 0x01, 0x00]),
    Packet("SETGET [1.11] low", [0x01, 0x0B, 0x02, 0x02, 0x01, 0x03]),
]

private let appDenied: [Packet] = [
    Packet("GET [0.6] MAC (PROBE only)", [0x00, 0x06, 0x01, 0x00]),
    Packet("GET [0.7] serial (PROBE only)", [0x00, 0x07, 0x01, 0x00]),
    Packet("GET [0.15] marketing name (PROBE only)", [0x00, 0x0F, 0x01, 0x00]),
    Packet("GET [1.3] voice prompts (PROBE only)", [0x01, 0x03, 0x01, 0x00]),
    Packet("GET [1.11] self-voice (until a sweep confirms)", [0x01, 0x0B, 0x01, 0x00]),
    Packet("GET [0.2] unknown", [0x00, 0x02, 0x01, 0x00]),
    Packet("GET [7.1] unknown block", [0x07, 0x01, 0x01, 0x00]),
    Packet("GET [0.5] with a payload", [0x00, 0x05, 0x01, 0x01, 0x00]),
    Packet("GET [31.6] no index", [0x1F, 0x06, 0x01, 0x00]),
    Packet("GET [31.6] mode 10", [0x1F, 0x06, 0x01, 0x01, 0x0A]),
    Packet("GET [31.6] two bytes", [0x1F, 0x06, 0x01, 0x02, 0x01, 0x00]),
    Packet("START [31.3] mode 10", [0x1F, 0x03, 0x05, 0x02, 0x0A, 0x00]),
    Packet("START [31.3] prompt 2", [0x1F, 0x03, 0x05, 0x02, 0x00, 0x02]),
    Packet("START [31.3] one byte", [0x1F, 0x03, 0x05, 0x01, 0x00]),
    Packet("START [31.3] three bytes", [0x1F, 0x03, 0x05, 0x03, 0x00, 0x00, 0x00]),
    Packet("SETGET [31.3]", [0x1F, 0x03, 0x02, 0x02, 0x00, 0x00]),
    Packet("SETGET [1.11] level 4", [0x01, 0x0B, 0x02, 0x02, 0x01, 0x04]),
    Packet("SETGET [1.11] persist 0", [0x01, 0x0B, 0x02, 0x02, 0x00, 0x01]),
    Packet("SETGET [1.11] one byte", [0x01, 0x0B, 0x02, 0x01, 0x01]),
    Packet("START [1.11]", [0x01, 0x0B, 0x05, 0x02, 0x01, 0x01]),
    Packet("SETGET [1.2] name (write GATED)", [0x01, 0x02, 0x02, 0x01, 0x41]),
    Packet("SETGET [1.7] EQ (write GATED)", [0x01, 0x07, 0x02, 0x02, 0x00, 0x00]),
    Packet("SETGET [31.6] mode config (write GATED)", [0x1F, 0x06, 0x02, 0x01, 0x04]),
    Packet("SETGET [5.5] volume", [0x05, 0x05, 0x02, 0x01, 0x05]),
]

@Test(arguments: appAllowed)
func appAllowsPolicyGetsAndWrites(packet: Packet) {
    #expect(allowed(BLZ_PROFILE_APP, packet))
}

@Test(arguments: appDenied)
func appDeniesEverythingElse(packet: Packet) {
    #expect(!allowed(BLZ_PROFILE_APP, packet))
}

// MARK: - PROBE

private let probeFunctions: [(UInt8, UInt8)] = [
    (0, 1), (0, 3), (0, 5), (0, 6), (0, 7), (0, 15),
    (1, 2), (1, 3), (1, 4), (1, 5), (1, 7), (1, 9), (1, 10), (1, 11), (1, 16), (1, 24), (1, 27), (1, 29),
    (2, 2), (2, 5), (2, 9),
    (4, 4), (4, 5),
    (5, 1), (5, 5),
    (31, 2), (31, 3), (31, 4), (31, 8), (31, 10), (31, 11),
]

private let probeAllowed: [Packet] =
    probeFunctions.map { Packet("GET [\($0.0).\($0.1)]", [$0.0, $0.1, 0x01, 0x00]) }
    + (0...9).map { Packet("GET [31.6] mode \($0)", [0x1F, 0x06, 0x01, 0x01, UInt8($0)]) }

private let probeDenied: [Packet] = [
    Packet("START [31.3] mode 0", [0x1F, 0x03, 0x05, 0x02, 0x00, 0x00]),
    Packet("SETGET [1.11] low", [0x01, 0x0B, 0x02, 0x02, 0x01, 0x03]),
    Packet("SETGET [5.5] volume", [0x05, 0x05, 0x02, 0x01, 0x05]),
    Packet("GET [0.2] unknown", [0x00, 0x02, 0x01, 0x00]),
    Packet("GET [1.1] unknown", [0x01, 0x01, 0x01, 0x00]),
    Packet("GET [7.1] block 7", [0x07, 0x01, 0x01, 0x00]),
    Packet("GET [31.6] mode 10", [0x1F, 0x06, 0x01, 0x01, 0x0A]),
    Packet("GET [31.6] no index", [0x1F, 0x06, 0x01, 0x00]),
    Packet("GET [0.5] with a payload", [0x00, 0x05, 0x01, 0x01, 0x00]),
    Packet("GET [4.5] with a payload", [0x04, 0x05, 0x01, 0x06] + mac),
]

@Test(arguments: probeAllowed)
func probeAllowsGetOnKnownFunctions(packet: Packet) {
    #expect(allowed(BLZ_PROFILE_PROBE, packet))
}

@Test(arguments: probeDenied)
func probeDeniesWritesAndUnknownFunctions(packet: Packet) {
    #expect(!allowed(BLZ_PROFILE_PROBE, packet))
}

// MARK: - REPLAY

private let replayAllowed: [Packet] = [
    Packet("GET [7.1] block 7", [0x07, 0x01, 0x01, 0x00]),
    Packet("SETGET [1.7] EQ", [0x01, 0x07, 0x02, 0x02, 0x00, 0x00]),
    Packet("SETGET [31.6] mode config", [0x1F, 0x06, 0x02, 0x01, 0x04]),
    Packet("START [31.3] mode 10", [0x1F, 0x03, 0x05, 0x02, 0x0A, 0x00]),
    Packet("GET [0.6] MAC", [0x00, 0x06, 0x01, 0x00]),
]

@Test(arguments: replayAllowed)
func replayAllowsWhatTheAbsoluteDenyListDoesNotBlock(packet: Packet) {
    #expect(allowed(BLZ_PROFILE_REPLAY, packet))
}

// MARK: - Bad arguments

@Test func nullPacketIsDenied() {
    for profile in allProfiles {
        #expect(!blz_packet_allowed(profile, nil, 4))
    }
}

@Test func unknownProfileIsDenied() {
    let get01: [UInt8] = [0x00, 0x01, 0x01, 0x00]
    #expect(!blz_packet_allowed(blz_profile(rawValue: 3), get01, get01.count))
    #expect(!blz_packet_allowed(BLZ_PROFILE_MAX_ENUM, get01, get01.count))
}
