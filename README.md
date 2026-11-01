# AXI4-Lite verification: UVM, protocol simulation, and bounded formal

Verification of a 256x32 AXI4-Lite memory slave with independent AW/W acceptance, byte strobes, and OKAY/DECERR responses. Evidence is separated by execution method: the free protocol test is not presented as a UVM run, and a policy-model proof is not presented as proof of the real RTL.

## Implemented verification layers

| Layer | Implementation | Evidence |
|---|---|---|
| Real-DUT protocol regression | Icarus + independent Python byte-memory oracle | 1,075 write/read pairs passed |
| Checker mutation | Ignored byte enables and incorrect response status | Both mutants detected by CI |
| Real-DUT bounded safety | Yosys SAT, actual slave with four-word memory | 24-step bounded check passed; arbitrary legal master timing |
| UVM | agent, driver, monitor, scoreboard, constrained sequences, covergroups, RAL | Sanity, regression and RAL PASS; zero UVM errors/fatals |
| Historical formal model | Separate response-policy model in `axi4lite_resp_fv.sv` | Its historical proof applies only to that model |

## Reproduce the protocol test for free

Install Python 3 and Icarus Verilog. From the repository root:

```bash
python3 scripts/gen_vectors.py
iverilog -g2012 -s tb_protocol -o build/protocol rtl/axi4lite_slave.sv tb/tb_protocol.sv
vvp build/protocol
```

The deterministic oracle seeds all 256 words, exercises all 16 WSTRB masks, simultaneous/AW-first/W-first channels, response backpressure, out-of-range accesses, alias protection, and complete valid-memory readback. The test also cancels a partial write with reset and checks that no orphan response appears. A watchdog and case-inequality data checks turn failures into nonzero process status. The Python model stores individual bytes; it does not copy the DUT's pending-channel implementation.

## Measured UVM results

On Verilator 5.052 + UVM 2020.3.1, seed 20261022, the full regression observed 344 writes, 108 reads, zero data/response mismatches, and zero UVM_ERROR/UVM_FATAL. The declared covergroup reports 100.00%; sanity reports 72.22% and RAL 38.89%. These percentages cover the defined bins only. The [regression summary](docs/REGRESSION_SUMMARY.md) links the actual run and its limits.

## UVM architecture and tests

The sequencer/driver drives `axi4lite_if`; the passive monitor publishes completed transactions to a scoreboard and functional-coverage subscriber. The scoreboard models byte updates and predicts response codes. The RAL adapter maps a 256-word `uvm_mem` onto bus transactions.

- `axi4lite_sanity_test`: ten write/read pairs.
- `axi4lite_regression_test`: initialize all memory, directed corners, 48 write/read pairs covering every mask in three AW/W timing profiles, 16 additional write/read pairs, 40 random transactions, and directed/random DECERR traffic.
- `axi4lite_ral_test`: eight RAL write/read pairs with operation-status and data checks.

Randomized AW/W launch delays and B/R response stalls range from zero to six cycles. The default driver serializes complete transactions; the monitor is not claimed to support arbitrary multiple outstanding/interleaved streams. Initialization is required because AXI does not guarantee unwritten memory contains zero. UVM mid-transaction reset recovery is not implemented; reset cancellation is tested in the independent protocol flow.

The interface assertions check known payloads, VALID/payload persistence, legal response codes for this DUT, and bounded completion. Write completion starts after both AW and W are accepted and does not require BREADY. Response bounds are this environment's contract, not an AXI protocol latency requirement.

The open-source workflow builds pinned Verilator 5.052 and upstream UVM 2020.3.1, enables assertions and coverage, and requires zero UVM_ERROR/UVM_FATAL plus scoreboard PASS. Four-state X/Z behavior is not validated by a two-state simulator. Do not infer coverage closure from a green compile or protocol-only result.

## Actual-DUT formal scope

The harness instantiates `axi4lite_slave`, reducing MEM_WORDS to four to keep checks inexpensive. Inputs are symbolic; master VALID/payload persistence is assumed across stalls, initial reset is required, and READY may stall indefinitely. Checks cover legal responses, response transaction credits, and B/R persistence while stalled.

This is bounded safety through 24 steps, not an unbounded proof, AXI certification, memory-data equivalence proof, or liveness proof under arbitrary backpressure. See [formal instructions](formal/README.md).

## Bugs corrected during the upgrade

- Replaced a bare write-response SVA sequence with a request-triggered implication and explicit finite bound.
- Added B response stability; retained R payload stability checks.
- Corrected UVM sequence declaration order and RAL memory construction.
- Primed memory before random reads rather than assuming reset initializes the DUT array.
- Added real channel skew/backpressure and a checker mutation gate.

Full evidence and limitations are in [regression summary](docs/REGRESSION_SUMMARY.md) and Actions logs. No paid simulator, FPGA board, or subscription is required for the protocol and formal flows.


**Enable the bug** by compiling with `+define+INJECT_WSTRB_BUG` (Questa:
`vlog -sv +define+INJECT_WSTRB_BUG ...`; EDA Playground: add it to the compile args).

**What the bug is:** the write path ignores `WSTRB` and writes the full 32-bit word
on every write. A partial-strobe write (e.g. `WSTRB=0x1`) should update only byte 0
and leave the other three bytes intact.

**How the TB catches it:** the directed sequence writes `0xFFFFFFFF` to `0x20`, then
writes `0x000000AA` with `WSTRB=0x1`. The reference-model scoreboard (which honors
strobes) predicts `0xFFFFFFAA`. The buggy DUT stores `0x000000AA`, so the read-back
fails:

```
UVM_ERROR ... [SCB] READ MISMATCH addr=0x00000020 expected=0xFFFFFFAA got=0x000000AA
UVM_INFO  ... [SCB] RESULT: FAIL
```

**Debug walk-through (say this in an interview):** mismatch on a partial-strobe write
→ compare expected vs actual byte-by-byte → only the strobed byte is correct, the
others are wrong → points straight at WSTRB handling in the write path → confirmed by
re-running without the define (PASS). This is the loop: *reproduce → localize from the
scoreboard diff → form a hypothesis → confirm.*

Run **without** the define = clean PASS. Run **with** it = the scoreboard catches the
bug on the exact transaction. That contrast is the artifact to screenshot.

**Second injectable bug — protocol error (assertion catch):** compile with
`+define+INJECT_BRESP_ERR` and the slave returns **SLVERR** on a normal read/write.
The bound concurrent assertions `A_BRESP_OKAY` / `A_RRESP_OKAY` fire immediately:
```
"[SVA] BRESP not OKAY"
```
This shows the **assertion layer** (not just the scoreboard) catching an illegal
protocol response — two independent checking mechanisms, two classes of bug caught.

## Coverage closure

The `axi4lite_regression_test` is built to **close 100% of the defined functional
coverage**: directed corners + 16 write/read pairs + 40 constrained-random transactions
hit every bin in `cg_axi` — operation (read/write), address range (low/mid/high),
byte-strobe (full/single/other), and the operation × address-range cross.

Read the closure number from the report:
```
UVM_INFO ... [COV] Functional coverage = 100.00%
```
If a bin is unhit, that's the signal to write a targeted directed test for it — the
core coverage-driven-verification loop. Capture the coverage report (Questa: `coverage
report -detail`) as proof.

## What this demonstrates (for interviews)
- Full UVM component hierarchy and phasing.
- Constrained-random stimulus with `constraint` blocks and `randomize() with`.
- Reference-model scoreboard (self-checking, not just log-watching).
- Functional coverage with `covergroup`/`coverpoint`/`cross` and coverage reporting.
- Assertion-based verification (concurrent SVA) for protocol legality.
- Reusable agent and a layered sequence library.

## Extensions — status

**Implemented (in this repo):**
- ✅ **DECERR error-path** — out-of-range → DECERR, `axi4lite_error_seq`,
  scoreboard response-prediction, resp/oob coverage, legal-response SVA.
- ✅ **UVM RAL** — `uvm_reg_block` + `uvm_mem` + `uvm_reg_adapter` in
  `tb/axi4lite_ral.sv` (run `+UVM_TESTNAME=axi4lite_ral_test`).
- ✅ **11 concurrent SVA assertions** bound to the interface.
- ✅ **Formal proof** — 5 response/handshake safety properties proven with
  SymbiYosys + Z3 (k-induction); see `formal/`.

**Planned (not yet implemented):**
- **Random back-pressure** — wait-states on AWREADY/WREADY/ARREADY + outstanding/
  interleaved transactions.
- **Gate-level / FPGA** smoke of the DUT.

## Notes / honesty
- Tested against UVM 1.2 semantics. First compile on a new tool version may need
  trivial tweaks (e.g., `+define`s); the methodology and structure are the point.
- Two injectable bugs are included (`INJECT_WSTRB_BUG` = data, `INJECT_BRESP_ERR` =
  protocol) to demonstrate the scoreboard and the SVA layer each catching defects.
```
## Cadence flow

### Formal (JasperGold)

Two harnesses check the same real-DUT properties on `axi4lite_slave` with `MEM_WORDS=4`. Run all commands from the repository root.

| Harness | Script | Style |
|---|---|---|
| `formal/axi4lite_dut_fv.sv` | `formal/axi4lite_dut_fv.tcl` | Immediate assertions and `(* anyseq *)` inputs, shared with the Yosys flow |
| `formal/axi4lite_dut_fv_sva.sv` | `formal/axi4lite_dut_fv_sva.tcl` | Concurrent SVA (`assert property`, `assume property`, `cover property`), labeled properties, free inputs as ports |

```
jg -no_gui formal/axi4lite_dut_fv.tcl        # shared harness, batch
jg -no_gui formal/axi4lite_dut_fv_sva.tcl    # SVA harness, batch
jg -gui    formal/axi4lite_dut_fv_sva.tcl    # GUI: Property Table, traces, Explain
```

`formal/axi4lite_dut_fv_sva.tcl`:

```
clear -all
analyze -sv12 rtl/axi4lite_slave.sv formal/axi4lite_dut_fv_sva.sv
elaborate -top axi4lite_dut_fv_sva
clock aclk
reset -expression {!aresetn}
prove -all
report -summary
```

Reset is applied by `reset -expression {!aresetn}` in both scripts. The SVA harness has no first-cycle reset assumption and no `past_valid` register.

What is checked, in both harnesses:

- Assumptions: master VALID and payload (address, data, strobe) persist until READY; READY may stall indefinitely.
- Assertions (10): B and R responses only for accepted requests (AW, W and AR credits), response codes limited to OKAY and DECERR, and B/R VALID and payload stable while the master stalls READY.

Measured result on `formal/axi4lite_dut_fv.sv` (JasperGold 2026.06):

| Item | Result |
|---|---|
| Assertions | 10 / 10 proven |
| Counterexamples / undetermined | 0 / 0 |
| Covers | 17 covered, 1 unreachable |
| Assumptions | 8 (7 master persistence + first-cycle reset) |

The unreachable cover is the first-cycle branch `if(!past_valid) assume(!aresetn)`. Jasper's `reset -expression {!aresetn}` already applies reset before analysis, so that branch is never entered. It is redundant, not a sign of an over-constrained harness. The SVA harness has no such branch.

Scope: safety properties (legal response codes, response credits, B/R persistence under stall) on a four-word memory. This is not a liveness, memory-data-equivalence, or full-size (256-word) proof. The Yosys flow still uses `formal/axi4lite_dut_fv.sv`.

Not committed: `jgproject/` (Jasper session output, listed in `.gitignore`).

### UVM on Xcelium - not yet run

The UVM environment has been run on Verilator (see above). It has not yet been run on Xcelium, so no Cadence UVM results are claimed here.
