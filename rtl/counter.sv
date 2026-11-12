`timescale 1ns/1ps
`default_nettype none

// Small setup example: synchronous reset, enable, and 8-bit wraparound.
module counter (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    output logic [7:0] count
);
    always_ff @(posedge clk) begin
        if (rst)
            count <= 8'h00;
        else if (enable)
            count <= count + 8'd1;
    end
endmodule

`default_nettype wire
