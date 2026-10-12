import BMAPShim
import Testing

@Test func abiVersionMatchesHeader() {
    #expect(blz_abi_version() == BLZ_ABI_VERSION)
    #expect(blz_abi_version() == 1)
}
