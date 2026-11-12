# RTL development setup

Prepared for your Apple Silicon Mac on 10 November 2026. This project includes counter and UART examples plus a simulated SPI/SFDP reader. For the flash project, start with [SFDP.md](SFDP.md) and run `make demo-sfdp`.

## Selected tools

| Tool | Purpose | Setup |
| --- | --- | --- |
| Cursor | Edit Verilog and SystemVerilog | Already installed; added mshr-h.veriloghdl 1.29.0 |
| Icarus Verilog 13.0 (`iverilog`, `vvp`) | Compile and run RTL simulations | Already installed; verified with this example |
| Surfer 0.7.0 | View simulation waveforms | Installed through Homebrew |
| Python 3.14.3 | Future test scripts and data generation | Already installed |
| Apple Clang 14.0.3 | Compile C/C++ programs | Already installed |
| Tcl 9.0.3 | Learn Tcl and run general Tcl scripts | Already installed; AMD tools supply their own Tcl environment |
| Git and Make | Track source changes and run repeatable builds | Already installed |

The workspace settings select Icarus for HDL error checking. No global editor settings were changed.

## Start here

Double-click `Open_Editor.command` to open the folder in Cursor, or use the steps below. `Open_Waveforms.command` runs the example and opens Surfer directly.

1. Open Cursor, choose **File > Open Folder**, and select this `RTL_Development_Starter` folder. Open the whole folder so its settings and tasks are loaded.
2. Open `rtl/counter.sv` to see the small circuit and `tb/tb_counter.sv` to see its testbench.
3. Press **Cmd+Shift+B** to compile and run the example. The terminal should report `PASS: 264 checks; reset, enable, hold and wraparound`.
4. Choose **Terminal > Run Task > RTL: view waveforms** to open Surfer. Expand the `tb_counter` scope and add `clk`, `rst`, `enable`, and `count` to the waveform display.

You can also run these commands from a terminal opened in this folder:

```sh
make test
make lint
make waves
```

`make test` creates `build/smoke.vcd`, which holds the signal changes. `make waves` runs the simulation and opens that file in Surfer. Close Surfer to finish the waveform task.

## Tools for later

Vivado and Vitis are the AMD development applications in your screenshot. Their supported platforms are Windows and Linux; macOS is absent from AMD's supported OS lists. For an AMD FPGA board, use a supported Windows/Linux computer or remote workstation with the appropriate AMD tools installed.

Yocto and Buildroot are Linux build systems. They become relevant when you build an embedded Linux image for a chosen board. PCIe, Ethernet, USB, DDR, RTL, FPGA, and Adaptive SoC describe technologies or design work rather than applications to install.

This setup is for learning and simulating RTL. Icarus implements a subset of SystemVerilog; advanced verification features may require a different simulator later. FPGA synthesis, placement, timing closure, and board programming need a toolchain for the selected device.

## UART receiver example

The complete receiver is in `rtl/uart_rx.sv`. Read [UART_RX.md](UART_RX.md) for the state machine, signal meanings and sampling timing. Run `make test-uart` to check it or `make waves-uart` to inspect the signals.

## SPI and SFDP example

The SPI reader and discovery engine read a simulated SFDP header, locate its Basic Flash Parameter Table and decode memory capacity. Run `make demo-sfdp` for a short example, `make test-sfdp` for the full tests, or `make waves-sfdp` to inspect the transaction in Surfer. See [SFDP.md](SFDP.md) for the interface and limitations. The flash test data is synthetic; this is not a complete manufacturer chip model or an octal xSPI controller.

References:

- [AMD installer and supported operating systems](https://www.amd.com/en/support/adaptive-socs-and-fpgas/installer-info-general.html)
- [Icarus Verilog documentation](https://steveicarus.github.io/iverilog/)
- [Surfer waveform viewer](https://surfer-project.org/)
- [Verilog/SystemVerilog editor extension](https://github.com/mshr-h/vscode-verilog-hdl-support)
