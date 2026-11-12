`timescale 1ns/1ps
`default_nettype none

module tb_uart_rx;
    parameter integer CLKS_PER_BIT = 32;
    localparam real CLOCK_NS = 20.0; // 50 MHz, matching the RTL default example.
    localparam real BIT_NS = CLOCK_NS * CLKS_PER_BIT;
    logic clk = 0, reset = 1, rx = 1;
    wire [7:0] data_out;
    wire data_valid, busy, framing_error;
    logic [7:0] expected [0:63];
    integer sent = 0, received = 0, errors = 0;
    integer before_errors;
    logic previous_valid = 0, previous_error = 0;
    logic [7:0] previous_data = 0;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (.*);
    always #(CLOCK_NS / 2) clk = ~clk;

    // Independent transmitter stimulus: timed line changes, no DUT counter access.
    task automatic send_byte(
        input logic [7:0] value,
        input real bit_period,
        input logic good_stop
    );
        begin
            if (good_stop) begin
                expected[sent] = value;
                sent = sent + 1;
            end
            rx = 0;
            #(bit_period);
            for (integer b = 0; b < 8; b = b + 1) begin
                rx = value[b];
                #(bit_period);
            end
            rx = good_stop;
            #(bit_period);
        end
    endtask

    // Scoreboard checks content, ordering, pulse width and stable output data.
    always @(posedge clk) begin
        #1;
        if (reset) begin
            if (data_valid || framing_error || busy || data_out !== 8'h00)
                $fatal(1, "Reset did not clear receiver outputs");
            previous_valid = 0;
            previous_error = 0;
            previous_data = 0;
        end else begin
            if (data_valid && previous_valid)
                $fatal(1, "data_valid lasted more than one system clock");
            if (framing_error && previous_error)
                $fatal(1, "framing_error lasted more than one system clock");
            if (data_valid && framing_error)
                $fatal(1, "Invalid frame was reported as valid");
            if (data_valid) begin
                if (received >= sent)
                    $fatal(1, "Unexpected byte %02h", data_out);
                if (data_out !== expected[received])
                    $fatal(1, "Byte %0d: expected %02h, got %02h",
                           received, expected[received], data_out);
                received = received + 1;
            end else if (data_out !== previous_data)
                $fatal(1, "data_out changed without data_valid");
            if (framing_error)
                errors = errors + 1;
            previous_valid = data_valid;
            previous_error = framing_error;
            previous_data = data_out;
        end
    end

    initial begin
        $dumpfile("build/uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
        repeat (4) @(negedge clk);
        reset = 0;
        #(BIT_NS * 2 + 3); // Deliberately asynchronous to system clock edges.

        // Idle and a false start must produce no byte or error.
        rx = 0;
        #(BIT_NS / 4);
        rx = 1;
        #(BIT_NS * 2);
        if (received != 0 || errors != 0 || busy)
            $fatal(1, "False-start rejection failed");

        // Consecutive frames with exactly one stop bit and no extra idle time.
        send_byte(8'h00, BIT_NS, 1);
        send_byte(8'hFF, BIT_NS, 1);
        send_byte(8'hA5, BIT_NS, 1);
        send_byte(8'h96, BIT_NS, 1);
        for (integer b = 0; b < 8; b = b + 1)
            send_byte(8'b1 << b, BIT_NS, 1);
        #(BIT_NS);

        // Fixed baud mismatch in both directions.
        send_byte(8'h81, BIT_NS * 0.98, 1);
        send_byte(8'h3C, BIT_NS * 1.02, 1);
        rx = 1;
        #(BIT_NS * 2);
        if (received != sent || errors != 0)
            $fatal(1, "Valid traffic was lost or marked invalid");

        // Bad stop bit, prolonged low line, then recovery.
        before_errors = errors;
        send_byte(8'h55, BIT_NS, 0);
        #(BIT_NS * 12);
        if (errors != before_errors + 1 || !busy)
            $fatal(1, "Bad-stop/held-low handling failed");
        rx = 1;
        #(BIT_NS * 2);
        send_byte(8'h42, BIT_NS, 1);
        rx = 1;
        #(BIT_NS * 2);

        // Reset abandons a frame that is only partly received.
        rx = 0;
        #(BIT_NS * 3);
        @(negedge clk);
        reset = 1;
        rx = 1;
        repeat (4) @(negedge clk);
        reset = 0;
        #(BIT_NS * 2);
        send_byte(8'hC3, BIT_NS, 1);
        rx = 1;
        #(BIT_NS * 2);
        if (received != sent || errors != 1 || busy)
            $fatal(1, "Final receiver state or scoreboard mismatch");
        $display("PASS UART RX: CLKS_PER_BIT=%0d, %0d bytes; false start, back-to-back, +/-2%% baud, bad stop, held-low recovery, reset",
                 CLKS_PER_BIT, received);
        $finish;
    end

    initial begin
        #500000000;
        $fatal(1, "Simulation timeout");
    end
endmodule

`default_nettype wire
