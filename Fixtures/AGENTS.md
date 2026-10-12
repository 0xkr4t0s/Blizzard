# Fixtures/: captured BMAP frames (test data and evidence)

This directory adds to the root AGENTS.md. Fixtures are produced by `/verify-bmap-feature` and `blizzard-probe`, and are
consumed by `ReplayLink` and the shim parser tests.

## Layout

```
Fixtures/lonestarr/<firmware>/                 e.g. Fixtures/lonestarr/1.6.7/
  <b>.<f>-<slug>.hex                           request line, then response line(s); hex bytes, space-separated
  <b>.<f>-<slug>.json                          {"addr":"2.2","op":"GET","request":"02 02 01 00",
                                                "response":"02 02 03 04 64 ff ff 00","expected":{...},
                                                "firmware":"1.6.7+g6ebabd2","captured":"2026-10-20",
                                                "method":"probe|packetlogger|hci-snoop|replay","source":"..."}
  sweeps/<date>-<slug>.json                    full read-only GET sweep output
```

The bytes in the example above are the battery reply reported by airvzxf; they illustrate the format and are not a Blizzard capture.

## Rules

- **Scrub before committing:**
  - [0.6] MAC, [0.7] serial, [4.4]/[4.5] paired-device MACs and [5.1] source MACs become `aa aa aa aa aa aa` (same length);
  - personal device names become `"Blizzard Test"`.
  - Keep lengths identical so parsers are exercised honestly. Note `"scrubbed": true` in the JSON.
- **Never commit raw PacketLogger (`.pklg`) or btsnoop logs.** They hold every nearby device's traffic. Extract only the BMAP frames
  you need.
- **Record the firmware** for every file. A fixture without firmware is not evidence.
- **Fixtures are immutable once committed.** If a later capture disagrees, add a new file and update `docs/PROTOCOL.md`. Do not
  overwrite the old one.
- **Never hand-craft a "captured" fixture.** Synthetic edge cases (truncated, oversize, concatenated) go in the test code
  itself, clearly labelled as synthetic.
- **Fuzzing corpus.** The M4 fuzzer seeds from these files. Keep them small.
