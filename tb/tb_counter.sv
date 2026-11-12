`timescale 1ns/1ps
`default_nettype none

module tb_counter;
    logic clk = 0;
    logic rst = 1;
    logic enable = 0;
    wire [7:0] count;
    integer checks = 0;

    counter dut (.clk(clk), .rst(rst), .enable(enable), .count(count));
    always #5 clk = ~clk;

    task automatic check(input logic [7:0] expected);
        begin
            @(posedge clk);
            #1; // Observe the result after nonblocking assignments settle.
            if (count !== expected)
                $fatal(1, "Expected %0d, received %0d", expected, count);
            checks = checks + 1;
            @(negedge clk);
        end
    endtask

    initial begin
        $dumpfile("build/smoke.vcd");
        $dumpvars(0, tb_counter);
        check(0);
        rst = 0;
        check(0);                    // Disabled counter holds its value.
        enable = 1;
        for (integer n = 1; n <= 255; n = n + 1)
            check(n[7:0]);
        check(0);                    // Wraparound from 255 to 0.
        check(1);
        enable = 0;
        repeat (3) check(1);         // Hold a nonzero value.
        rst = 1;
        check(0);                    // Reset while disabled.
        rst = 0;
        enable = 1;
        check(1);                    // Resume after reset.
        $display("PASS: %0d checks; reset, enable, hold and wraparound", checks);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Simulation timeout");
    end
endmodule

`default_nettype wire
