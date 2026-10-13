// blizzard-probe: developer CLI for read-only GET sweeps and capture replay (PLAN T014).
// Only --version exists so far; it proves the Swift → C shim link works.
import BlizzardCore
import Foundation

let usage = """
    usage: blizzard-probe --version

    --read, --sweep, --diff and --replay arrive with PLAN T014.
    """

switch Array(CommandLine.arguments.dropFirst()) {
case ["--version"]:
    print("blizzard-probe (BMAP shim ABI \(ShimInfo.abiVersion))")
case []:
    print(usage)
default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)  // EX_USAGE
}
