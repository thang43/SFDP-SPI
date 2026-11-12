`timescale 1ns/1ps
`default_nettype none

module tb_spi_sfdp_reader;
    parameter integer HALF_CYCLES = 4;
    logic clk = 0;
    always #10 clk = !clk; // 50 MHz system clock.
    logic reset = 1, start = 0;
    logic [23:0] address = 0;
    logic [15:0] byte_count = 0;
    wire busy, done, error, data_valid, cs_n, sclk, mosi, miso;
    wire [7:0] data_out;
    integer checks = 0, received = 0, edges = 0;
    logic checking = 0;
    logic [23:0] expected_address;
    integer expected_bytes;
    logic previous_valid = 0, previous_done = 0;
    time last_edge, selected_at;

    spi_sfdp_reader #(.HALF_CYCLES(HALF_CYCLES)) dut (.*);
    spi_sfdp_flash_model flash (.cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso));

    task automatic check(input logic condition, input string message);
        checks = checks + 1;
        if (condition !== 1'b1) $fatal(1, "%s", message);
    endtask

    always @(negedge cs_n) begin
        selected_at = $time;
        edges = 0;
        last_edge = $time;
        if (!reset) check(sclk === 0, "SCLK must idle low at select");
    end

    always @(sclk) begin
        if (!reset && !cs_n) begin
            check($time - last_edge == HALF_CYCLES * 20, "Wrong SCLK half-period");
            last_edge = $time;
            if (sclk) edges = edges + 1;
        end
    end

    always @(posedge cs_n) begin
        if (!reset && checking)
            check($time - last_edge == HALF_CYCLES * 20, "Missing final CS hold time");
    end

    always @(posedge clk) begin
        #1;
        if (reset) begin
            previous_valid = 0;
            previous_done = 0;
        end else begin
            check(!(previous_valid && data_valid), "data_valid exceeds one cycle");
            check(!(previous_done && done), "done exceeds one cycle");
            if (data_valid && checking) begin
                check(received < expected_bytes, "Too many bytes");
                check(data_out === flash.byte_at(expected_address + 24'(received)),
                      $sformatf("Byte %0d mismatch: got %h", received, data_out));
                received = received + 1;
            end
            if (cs_n) check(sclk === 0, "SCLK must idle low");
            previous_valid = data_valid;
            previous_done = done;
        end
    end

    task automatic read_and_check(input logic [23:0] addr, input integer count);
        @(negedge clk);
        expected_address = addr;
        expected_bytes = count;
        received = 0;
        checking = 1;
        address = addr;
        byte_count = 16'(count);
        start = 1;
        @(negedge clk);
        start = 0;
        check(busy, "Request was not accepted");
        // Inputs must be latched; a second start while busy must be ignored.
        address = ~addr;
        byte_count = 0;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        for (integer cycles = 0; !done; cycles = cycles + 1) begin
            if (cycles > (40 + 8*count + 4)*2*HALF_CYCLES)
                $fatal(1, "Reader timed out");
            @(negedge clk);
        end
        check(!error && !busy && cs_n && !sclk, "Incorrect completion status");
        check(received == count, "Incorrect byte count");
        check(edges == 40 + 8*count, "Wrong command/address/dummy/data clock count");
        checking = 0;
        repeat (3) @(negedge clk);
    endtask

    task automatic reject_request(input logic [23:0] addr, input logic [15:0] count);
        @(negedge clk);
        address = addr; byte_count = count; start = 1;
        @(negedge clk); start = 0;
        check(done && error && !busy && cs_n && !data_valid, "Bad request not rejected");
        @(negedge clk);
        check(!done && !error, "Error/done must be pulses");
    endtask

    task automatic abort_read(input integer wait_cycles);
        @(negedge clk);
        start = 1; address = 0; byte_count = 32;
        @(negedge clk); start = 0;
        repeat (wait_cycles) @(negedge clk);
        reset = 1;
        @(negedge clk);
        check(cs_n && !sclk && !busy && !done && !data_valid, "Reset did not abort safely");
        reset = 0;
        repeat (3) @(negedge clk);
        read_and_check(24'h100, 4);
    endtask

    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("build/spi_sfdp_reader.vcd");
            $dumpvars(0, tb_spi_sfdp_reader);
        end
        repeat (3) @(negedge clk);
        for (integer i = 0; i < 4096; i = i + 1)
            flash.mem[i] = 8'((i * 37) ^ (i >> 8) ^ 8'ha6);
        reset = 0;
        read_and_check(0, 8);
        read_and_check(24'h31, 1);
        read_and_check(24'hfd, 19); // Cross a 256-byte boundary.
        read_and_check(24'h010203, 37); // Exercise every address byte.
        read_and_check(24'hfffffe, 2); // End exactly at the address-space boundary.
        read_and_check(24'h88, 257); // Byte count must not truncate at 8 bits.
        reject_request(0, 0);
        reject_request(24'hffffff, 2);
        abort_read(3 * HALF_CYCLES); // During command.
        abort_read(70 * HALF_CYCLES); // During dummy clocks.
        abort_read(100 * HALF_CYCLES); // During returned data.
        $display("PASS: SPI reader, HALF_CYCLES=%0d, %0d checks", HALF_CYCLES, checks);
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "Global reader watchdog");
    end
endmodule

`default_nettype wire
