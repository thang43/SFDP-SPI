`timescale 1ns/1ps
`default_nettype none

// TESTBENCH ONLY. A small 5Ah responder, not a complete Winbond device model.
// Tests supply synthetic SFDP bytes. No vendor SFDP dump is embedded here.
module spi_sfdp_flash_model #(
    parameter integer MEMORY_BYTES = 4096,
    parameter integer OUTPUT_DELAY_NS = 2
) (
    input wire cs_n,
    input wire sclk,
    input wire mosi,
    output logic miso
);
    logic [7:0] mem [0:MEMORY_BYTES-1];
    logic [7:0] command = 0;
    logic [23:0] address = 0;
    integer rising_count = 0;

    // A pattern outside the small array lets tests exercise all 24 address bits.
    function automatic [7:0] byte_at(input logic [23:0] addr);
        if (addr < MEMORY_BYTES)
            byte_at = mem[addr];
        else
            byte_at = addr[7:0] ^ addr[15:8] ^ addr[23:16] ^ 8'ha5;
    endfunction

    initial begin
        miso = 1'bz;
        for (integer i = 0; i < MEMORY_BYTES; i = i + 1)
            mem[i] = 8'hff;
    end

    // Decode the wire transaction independently of the controller's state.
    always @(posedge sclk or posedge cs_n) begin
        if (cs_n) begin
            command = 0;
            address = 0;
            rising_count = 0;
        end else begin
            if (rising_count < 8) begin
                command = {command[6:0], mosi};
                if (rising_count == 7 && command !== 8'h5a)
                    $fatal(1, "Flash received %h, expected Read SFDP 5Ah", command);
            end else if (rising_count < 32) begin
                address = {address[22:0], mosi};
            end
            rising_count = rising_count + 1;
        end
    end

    // First return bit appears after the 40th falling edge (8+24+8 clocks).
    // Nonzero propagation delay catches sampling on the wrong SPI edge.
    logic [7:0] output_byte;
    always @(negedge sclk or posedge cs_n) begin
        if (cs_n) begin
            miso <= 1'bz;
        end else if (rising_count >= 40) begin
            output_byte = byte_at(address + 24'((rising_count - 40) / 8));
            miso <= #(OUTPUT_DELAY_NS) output_byte[7 - ((rising_count - 40) % 8)];
        end else begin
            miso <= 1'bz;
        end
    end
endmodule

`default_nettype wire
