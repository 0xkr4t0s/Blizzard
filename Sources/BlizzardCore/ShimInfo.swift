import BMAPShim

/// Facts about the linked BMAP shim.
public enum ShimInfo {
    /// The `BLZ_ABI_VERSION` the shim library was built with.
    public static var abiVersion: UInt32 { blz_abi_version() }
}
