# SPI / SFDP starter

This project reads a simulated flash chip's SFDP information and reports its
capacity. Start with the demo; the implementation can wait until you feel ready.

## Run it

Open a terminal in this project folder:

```sh
make demo-sfdp   # One successful discovery; also saves a waveform
make waves-sfdp  # Run that demo and open its waveform in Surfer
make test-sfdp   # Run the full SPI and discovery tests
```

The demo should print:

```text
DEMO: discovered 16777216 bytes (16 MiB); BFPT at 0x000040
```

Cursor also has **Terminal > Run Task > SFDP: run demo**, **SFDP: run tests**,
and **SFDP: view waveforms**. The existing counter and UART tasks still work.

## What happens, in five steps

1. The testbench pulses `start`.
2. The controller sends `5A`, address `000000`, then eight dummy clocks.
3. It reads and checks the eight-byte SFDP header.
4. It reads parameter headers until it finds a compatible Basic Flash Parameter
   Table (BFPT), then reads the first two DWORDs at that table's address.
5. It decodes capacity, raises `valid`, and pulses `done` for one system clock.

```text
Testbench
    | start
    v
sfdp_discovery       Reads and interprets the SFDP structure
    |
    v
spi_sfdp_reader      Sends command/address; receives bytes
    | CS#, SCLK, MOSI              ^ MISO
    +-----------------------------+
                  |
          Simulated flash
```

In the demo there are three SPI transactions, each returning eight bytes:
address `000000` (header), `000008` (parameter header), and `000040` (BFPT).
Each has 104 SCLK periods: 8 command + 24 address + 8 dummy + 64 data.

## Files to read later

| File | Purpose |
| --- | --- |
| `rtl/spi_sfdp_reader.sv` | SPI mode-0 transaction engine; start here for the wire protocol |
| `rtl/sfdp_discovery.sv` | Header checking, table lookup and capacity decoding |
| `tb/spi_sfdp_flash_model.sv` | Simulation-only flash responder |
| `tb/tb_spi_sfdp_reader.sv` | Byte, clock, address, input-latching and reset tests |
| `tb/tb_sfdp_discovery.sv` | Discovery demo and malformed-data tests |

## Scope

Implemented: single-bit SDR SPI mode 0, command `5A`, 24-bit SFDP byte addresses,
eight dummy clocks, MSB-first serial bytes, and little-endian SFDP DWORD decoding.
Discovery accepts SFDP major 1 with access protocol `FF`, skips unrecognised
parameter headers, and uses the first major-1 BFPT. New minor revisions are
accepted because this implementation reads only the original fields.

The parser checks the BFPT length (at least nine DWORDs), alignment, header
overlap and address range. It returns DWORD 1 as raw bits and decodes DWORD 2:

- Bit 31 clear: capacity in bytes = `(density + 1) / 8`.
- Bit 31 set: low 31 bits hold exponent N; capacity in bytes = `2^(N - 3)`.
  This implementation accepts N from 32 through 66, fitting its 64-bit output.

The simulated flash contains **synthetic test data**, including a 16 MiB example.
It is not a Winbond SFDP dump or a manufacturer-validated chip model. Only the
fields needed for these tests are populated meaningfully. Tests also deliberately
provide malformed and unusual layouts to check the parser's error handling.
No full flash storage array, program/erase behaviour, or vendor timing model is
implemented. The responder inserts a 2 ns output delay and releases MISO when
unselected; the array outside its small test memory uses a deterministic test
pattern to exercise all 24 address bits.

This is an SFDP discovery subset, not complete JESD216G or JESD251C conformance.
It does not yet read normal flash contents (`03`), read JEDEC ID (`9F`), program,
erase, switch quad/octal modes, or provide an APB/AXI CPU interface. It does not
parse all capability fields or select the newest of duplicate BFPT revisions.

## Interface and timing notes

Both RTL modules use a synchronous active-high reset. Pulse `start` for one
system clock while `busy` is low; starts while busy are ignored. Do not hold
`start` high, as it could launch another operation after completion. Reset aborts
an operation without asserting `done` and releases CS# on the next system edge.

`spi_sfdp_reader` latches its address and length on start and returns one-cycle
`data_valid` pulses. There is no backpressure: its consumer must accept every
byte. A zero length or a request crossing the 24-bit address boundary produces
`done` with `error`, without selecting the chip. `done` comes after the final
SCLK falling edge and CS hold interval, later than the last data-valid pulse.

In `sfdp_discovery`, `done` means the attempt finished. Use the results only when
`valid` is high. Results stay available until the next accepted start or reset.
On failure, some metadata may describe how far the attempt got; capacity stays
zero and `valid` stays low.

| `error_code` | Meaning |
| --- | --- |
| 0 | Success, when `done` and `valid` are asserted |
| 1 | SFDP signature mismatch |
| 2 | Unsupported SFDP major revision or access protocol |
| 3 | No major-1 BFPT found |
| 4 | Malformed header/table: reserved NPH, short length, bad alignment or range |
| 5 | Invalid or unsupported density encoding |
| 6 | SPI reader rejection or internal state error |

The discovery scan is bounded by the header count. NPH=`FE` means 255 headers;
NPH=`FF` is reserved and is rejected. A disconnected flash has no protocol-level
acknowledgement; its returned bits will normally cause a signature error.

SCLK frequency is `system clock / (2 * HALF_CYCLES)`. With the demo's 50 MHz
system clock and default divider of 4, SCLK is 6.25 MHz. MOSI changes on falling
edges and MISO is sampled on rising edges. MISO is a timed return path from the
generated SPI clock, not a UART-style asynchronous input.

These are intended as synthesizable RTL modules, but only simulation and Icarus
compilation have been checked. A board implementation still needs pin mapping,
voltage compatibility, power-up delay, input/output timing constraints and FPGA
toolchain timing verification. Set clock division to meet the selected chip's
Read-SFDP limit and timing; the divider parameter itself has no knowledge of the
system clock frequency. The SPI mode must already be single-bit SDR mode 0.

## Verification and waveform

`make test-sfdp` runs both testbenches at half-period dividers 1, 3 and 4. It checks
serial byte order, all address bytes, dummy and data clock counts, CS setup/hold,
one-cycle output pulses, length boundaries, starts while busy, and reset during
command/dummy/data phases. Discovery checks both density encodings, newer minor
versions, table scanning through 255 headers, malformed metadata and recovery.

`make lint-sfdp` compiles the RTL with simulation-only checks disabled; it is a
syntax/elaboration check, not synthesis. `make test-all` also runs the original
counter and UART tests.

`make waves-sfdp` now loads the main signals automatically using
`sfdp_waveforms.sucl`. To select them manually, open `build/sfdp_discovery.vcd`
in Surfer, expand `tb_sfdp_discovery`, and add:
`clk`, `start`, `busy`, `cs_n`, `sclk`, `mosi`, `miso`, `done`, `valid`,
`error_code`, `bfpt_address`, and `capacity_bytes`. Set address/data display to
hexadecimal and capacity to unsigned decimal. Zoom into one CS-low interval to
see a transaction; zoom out to see the three reads and the final result.

## Sources

The supplied JESD216G standard, sections 4.1–4.5, 6.2–6.3 and 6.4.5, defines the
transaction and fields used here. JESD251C octal/DDR features are outside this
first implementation. The commercial reference for later device-specific work
is the [Winbond W25Q128JV datasheet, revision M](https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/6750/256_W25Q128JVPIM.pdf),
especially section 8.2.28. An actual SFDP dump or manufacturer-provided values
will be needed before claiming a model matches a particular Winbond device.
