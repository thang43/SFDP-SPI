# UART receiver walkthrough

The complete receiver is `rtl/uart_rx.sv`; its independent transmitter stimulus and scoreboard are in `tb/tb_uart_rx.sv`.

This is an 8N1 UART receiver: one low start bit, eight data bits sent least significant bit first, and one high stop bit. It runs entirely on the system clock. At 50 MHz and 115200 baud, use `CLKS_PER_BIT=434`, the nearest integer to 50000000/115200.

## Signal meanings

| Signal | Meaning |
| --- | --- |
| `clk` | System clock, not a clock received over UART |
| `reset` | Active-high synchronous reset; hold high for at least one system clock edge |
| `rx` | Serial input; normally high when idle |
| `data_out[7:0]` | Most recently received valid byte; holds until the next valid byte or reset |
| `data_valid` | High for one system clock when a valid byte becomes available |
| `busy` | Receiver is checking a start bit, receiving data, checking a stop bit, or waiting for a bad low line to recover |
| `framing_error` | High for one system clock when the sampled stop bit is low |

There is no connection to the remote transmitter's `busy` signal. The receiver watches `rx` to find the start of each frame. A consumer clocked by the same `clk` can use `if (data_valid) saved_byte <= data_out;` to capture each byte. There is no receive queue or backpressure in this block.

## What the hardware does

1. **Synchronise the pin.** `rx_meta` and `rx_sync` are two flip-flops in series. They reduce the risk of metastability from an external signal entering the state machine. RTL simulation does not model analogue metastability.
2. **IDLE:** wait for the synchronised input to become low.
3. **START:** wait half a bit, then check that the input is still low. A brief low pulse is rejected if the input has returned high by this sample.
4. **DATA:** wait one full bit between samples. The first sample goes to `shift_reg[0]`, then the next to `[1]`, up to `[7]`.
5. **STOP:** wait one more bit and check for a high stop bit. If high, copy the completed byte to `data_out` and pulse `data_valid`.
6. **WAIT_HIGH:** after a low stop bit, pulse `framing_error` once and wait for the line to return high before looking for another frame.

The timing counter counts down. The `count == 0` condition acts like an internal sampling tick. Unlike a free-running transmitter tick, this timing is aligned again for every detected start bit.

Nominal sample positions relative to the detected start transition are:

| Sample | Bit periods after detection |
| --- | --- |
| Confirm start | 0.5 |
| Data bit 0 | 1.5 |
| Data bit 1 | 2.5 |
| Data bit 7 | 8.5 |
| Stop bit | 9.5 |

Input synchronisation and system-clock quantisation add a small delay to these positions. The stop bit is checked near its centre; `busy` returns low at that point, while the transmitter may still be completing the stop bit.

Despite its name, `shift_reg` here is a byte assembly register: `shift_reg[bit_index] <= rx_sync` writes each incoming bit directly into its position. This is an alternative to shifting the entire register on each sample.

## Run and inspect

From the project folder:

```sh
make test-uart
make waves-uart
```

Or use Cursor's **Terminal > Run Task** menu and select the UART task.

Tests run at a 50 MHz system clock with both 32 and 434 clocks per bit. Each run checks 16 valid bytes, including all-zero/all-one bytes and walking-one patterns, consecutive frames, fixed transmitter bit periods 2% shorter and longer than nominal, false starts, a low stop bit, prolonged low input, recovery, reset during reception, output stability, and one-clock status pulses. These are directed functional simulations, not exhaustive noise or baud-tolerance qualification.

The final waveform file `build/uart_rx.vcd` comes from the 434-clocks-per-bit run. In Surfer, add `rx`, `dut.rx_sync`, `dut.state`, `dut.count`, `dut.bit_index`, `data_out`, `data_valid`, `busy`, and `framing_error`. State encodings are IDLE=0, START=1, DATA=2, STOP=3, WAIT_HIGH=4.

The design uses one sample per bit, supports no parity, and expects at least eight system clocks per bit. FPGA deployment additionally requires pin assignments, correct IO voltage levels and timing/CDC constraints. This block is for logic-level UART, not direct connection to RS-232 voltage levels.
