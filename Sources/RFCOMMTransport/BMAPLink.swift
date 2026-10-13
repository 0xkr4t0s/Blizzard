/// A blocking byte link to a BMAP device (ARCHITECTURE §10).
///
/// Every call happens synchronously on `BMAPThread`. Implementations: `IOBluetoothLink` (PLAN T023),
/// and `ReplayLink` / `SimLink` in tests (PLAN T028).
public protocol BMAPLink: AnyObject {
    func open() throws
    func sendRecv(_ packet: [UInt8], drain: Bool) throws -> [UInt8]
    func close()
}
