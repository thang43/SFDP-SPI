`timescale 1ns/1ps
`default_nettype none

module tb_sfdp_discovery;
    parameter integer HALF_CYCLES = 4;
    logic clk = 0;
    always #10 clk = !clk;
    logic reset = 1, start = 0;
    wire busy, done, valid, cs_n, sclk, mosi, miso;
    wire [3:0] error_code;
    wire [7:0] sfdp_major, sfdp_minor, parameter_count, bfpt_dwords;
    wire [23:0] bfpt_address;
    wire [31:0] bfpt_word1, density_raw;
    wire [63:0] capacity_bytes;
    integer checks = 0, scenarios = 0;
    logic previous_done = 0;

    sfdp_discovery #(.HALF_CYCLES(HALF_CYCLES)) dut (.*);
    spi_sfdp_flash_model flash (.cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso));

    task automatic check(input logic condition, input string message);
        checks = checks + 1;
        if (condition !== 1'b1) $fatal(1, "%s", message);
    endtask

    task automatic put_word(input integer addr, input logic [31:0] value);
        for (integer b = 0; b < 4; b = b + 1)
            flash.mem[addr+b] = value[b*8 +: 8];
    endtask

    task automatic parameter_header(
        input integer index, input logic [15:0] id, input logic [7:0] major,
        input logic [7:0] length, input logic [23:0] pointer
    );
        integer base;
        base = 8 + index*8;
        flash.mem[base] = id[7:0];
        flash.mem[base+1] = 0;
        flash.mem[base+2] = major;
        flash.mem[base+3] = length;
        flash.mem[base+4] = pointer[7:0];
        flash.mem[base+5] = pointer[15:8];
        flash.mem[base+6] = pointer[23:16];
        flash.mem[base+7] = id[15:8];
    endtask

    task automatic fixture;
        // Synthetic 16 MiB example, NOT an exact commercial chip's SFDP image.
        for (integer i = 0; i < 4096; i = i + 1)
            flash.mem[i] = 8'hff;
        put_word(0, 32'h50444653);
        flash.mem[4] = 8'h06;
        flash.mem[5] = 1;
        flash.mem[6] = 0;
        flash.mem[7] = 8'hff;
        parameter_header(0, 16'hff00, 1, 9, 24'h40);
        for (integer w = 0; w < 9; w = w + 1)
            put_word('h40 + w*4, 0);
        put_word('h40, 32'hff802001);
        put_word('h44, 32'h07ffffff); // 134217728 bits = 16777216 bytes.
        put_word('h5c, 32'h0000200c); // Example erase descriptor, not parsed.
    endtask

    task automatic discover(
        input string label_text, input logic [3:0] expected_error,
        input logic [63:0] expected_capacity
    );
        scenarios = scenarios + 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        check(busy && !valid && error_code == 0 && capacity_bytes == 0,
              "Start must invalidate previous results");
        // A start pulse while busy must not interrupt discovery.
        repeat (5) @(negedge clk);
        start = 1;
        @(negedge clk); start = 0;
        for (integer cycles = 0; !done; cycles = cycles + 1) begin
            if (cycles > 300000 * HALF_CYCLES)
                $fatal(1, "Discovery timed out: %s", label_text);
            @(negedge clk);
        end
        check(!busy && cs_n && !sclk, "Completion must release the SPI bus");
        check(error_code === expected_error,
              $sformatf("%s: error %0d expected %0d", label_text, error_code, expected_error));
        check(valid === (expected_error == 0), "Incorrect valid result");
        check(capacity_bytes === expected_capacity,
              $sformatf("%s: capacity %0d expected %0d", label_text, capacity_bytes, expected_capacity));
        repeat (3) @(negedge clk);
        check(!done && valid === (expected_error == 0) && capacity_bytes === expected_capacity,
              "Result must stay available after done pulse");
        $display("  OK: %s", label_text);
    endtask

    always @(posedge clk) begin
        #1;
        if (reset) previous_done = 0;
        else begin
            if (done && previous_done) $fatal(1, "done exceeds one clock");
            if (done && valid && error_code != 0) $fatal(1, "Valid result has error");
            previous_done = done;
        end
    end

    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("build/sfdp_discovery.vcd");
            $dumpvars(0, tb_sfdp_discovery);
        end
        repeat (3) @(negedge clk);
        reset = 0;
        fixture();
        discover("16 MiB linear density", 0, 64'd16777216);
        check(sfdp_major == 1 && sfdp_minor == 6 && parameter_count == 1,
              "Header fields decoded incorrectly");
        check(bfpt_address == 24'h40 && bfpt_dwords == 9 &&
              bfpt_word1 == 32'hff802001 && density_raw == 32'h07ffffff,
              "BFPT fields decoded incorrectly");
        if ($test$plusargs("demo")) begin
            $display("DEMO: discovered %0d bytes (16 MiB); BFPT at 0x%06h",
                     capacity_bytes, bfpt_address);
            $finish;
        end

        fixture(); flash.mem[4] = 8'hfe;
        discover("Accept newer minor revision", 0, 64'd16777216);

        fixture(); put_word('h44, 32'h7fffffff);
        discover("Largest linear density", 0, 64'd268435456);
        fixture(); put_word('h44, 32'h80000020);
        discover("Exponent density: 4 Gibit", 0, 64'd536870912);
        fixture(); put_word('h44, 32'h80000021);
        discover("Exponent density: 8 Gibit", 0, 64'd1073741824);
        fixture(); put_word('h44, 32'h80000042);
        discover("Largest supported 64-bit byte capacity", 0, 64'h8000000000000000);

        fixture(); flash.mem[6] = 2;
        parameter_header(0, 16'hff81, 1, 1, 24'h100);
        parameter_header(1, 16'hff00, 2, 9, 24'h140);
        parameter_header(2, 16'hff00, 1, 9, 24'h40);
        discover("Skip unrelated and unsupported-major tables", 0, 64'd16777216);
        check(parameter_count == 3, "NPH must decode as count minus one");

        fixture(); flash.mem[0] = 0;
        discover("Reject bad signature", 1, 0);
        fixture(); flash.mem[5] = 2;
        discover("Reject unsupported SFDP major", 2, 0);
        fixture(); flash.mem[7] = 8'hfa;
        discover("Reject unsupported access protocol", 2, 0);
        fixture(); flash.mem[6] = 8'hff;
        discover("Reject reserved NPH FFh", 4, 0);
        fixture(); parameter_header(0, 16'hff81, 1, 9, 24'h40);
        discover("Report missing compatible BFPT", 3, 0);
        fixture(); parameter_header(0, 16'hff00, 1, 1, 24'h40);
        discover("Reject short BFPT", 4, 0);
        fixture(); parameter_header(0, 16'hff00, 1, 9, 24'h41);
        discover("Reject unaligned pointer", 4, 0);
        fixture(); parameter_header(0, 16'hff00, 1, 9, 24'h08);
        discover("Reject table/header overlap", 4, 0);
        fixture(); parameter_header(0, 16'hff00, 1, 9, 24'hfffff0);
        discover("Reject table beyond address space", 4, 0);
        fixture(); put_word('h44, 32'h07fffffe);
        discover("Reject density not divisible into bytes", 5, 0);
        fixture(); put_word('h44, 32'h8000001f);
        discover("Reject reserved small exponent", 5, 0);
        fixture(); put_word('h44, 32'h80000043);
        discover("Reject capacity beyond output width", 5, 0);

        // Exercise the full supported NPH range, including counter boundaries.
        fixture(); flash.mem[6] = 8'hfe;
        for (integer i = 0; i < 254; i = i + 1)
            parameter_header(i, 16'hff81, 1, 1, 24'h900);
        parameter_header(254, 16'hff00, 1, 9, 24'h900);
        put_word('h900, 32'hff802001);
        put_word('h904, 32'h07ffffff);
        discover("Find BFPT after 254 skipped headers", 0, 64'd16777216);
        check(parameter_count == 255 && bfpt_address == 24'h900, "Header scan overflow");

        fixture();
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        repeat (100 * HALF_CYCLES) @(negedge clk);
        reset = 1;
        @(negedge clk);
        check(!busy && !valid && !done && cs_n && !sclk && capacity_bytes == 0,
              "Reset must abort discovery and clear results");
        reset = 0;
        repeat (3) @(negedge clk);
        discover("Recovery after reset during SPI read", 0, 64'd16777216);

        $display("PASS: SFDP discovery, HALF_CYCLES=%0d, %0d scenarios, %0d checks",
                 HALF_CYCLES, scenarios, checks);
        $finish;
    end

    initial begin
        #1000000000;
        $fatal(1, "Global discovery watchdog");
    end
endmodule

`default_nettype wire
