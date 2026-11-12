`timescale 1ns/1ps
`default_nettype none

// Single-bit SPI mode 0: 5Ah, 24 address bits, 8 dummy clocks, N data bytes.
// All logic uses clk; sclk is an output, not an internal clock domain.
module spi_sfdp_reader #(
    parameter integer HALF_CYCLES = 4 // SCLK = clk / (2 * HALF_CYCLES)
) (
    input  wire        clk,
    input  wire        reset,       // Synchronous, active high; aborts a read.
    input  wire        start,       // Pulse for one clk while !busy.
    input  wire [23:0] address,
    input  wire [15:0] byte_count,  // 1..65535; no 24-bit address wrap allowed.
    output wire        busy,
    output logic       done,        // One clk pulse, including rejected requests.
    output logic       error,       // Valid with done; invalid length/address range.
    output logic [7:0]  data_out,
    output logic       data_valid,  // One clk pulse per byte; no backpressure.
    output logic       cs_n,
    output logic       sclk,
    output logic       mosi,
    input  wire        miso
);
    localparam integer DIV_WIDTH = (HALF_CYCLES > 1) ? $clog2(HALF_CYCLES) : 1;
    localparam logic [DIV_WIDTH-1:0] RELOAD = DIV_WIDTH'(HALF_CYCLES - 1);
    typedef enum logic [2:0] {IDLE, SEND, RECEIVE, LAST_FALL, HOLD_CS} state_t;
    state_t state;
    logic [DIV_WIDTH-1:0] divider;
    logic [39:0] tx_shift;
    logic [5:0] tx_left;
    logic [7:0] rx_shift;
    logic [2:0] rx_bit;
    logic [15:0] bytes_left;
    wire [24:0] end_address = {1'b0, address} + {9'b0, byte_count};

    assign busy = (state != IDLE);

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            divider <= '0;
            tx_shift <= '0;
            tx_left <= '0;
            rx_shift <= '0;
            rx_bit <= '0;
            bytes_left <= '0;
            data_out <= '0;
            data_valid <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            cs_n <= 1'b1;
            sclk <= 1'b0;
            mosi <= 1'b0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
            data_valid <= 1'b0;

            if (state == IDLE) begin
                if (start) begin
                    if (byte_count == 0 || end_address > 25'h1000000) begin
                        done <= 1'b1;
                        error <= 1'b1;
                    end else begin
                        tx_shift <= {8'h5a, address, 8'h00};
                        tx_left <= 6'd39;
                        bytes_left <= byte_count;
                        rx_bit <= '0;
                        rx_shift <= '0;
                        divider <= RELOAD;
                        cs_n <= 1'b0;
                        mosi <= 1'b0; // First (MSB) bit of 5Ah.
                        state <= SEND;
                    end
                end
            end else if (divider != 0) begin
                divider <= divider - 1'b1;
            end else begin
                divider <= RELOAD;
                case (state)
                    SEND: begin
                        sclk <= !sclk;
                        if (sclk) begin // Falling edge: prepare the next bit.
                            if (tx_left == 0) begin
                                mosi <= 1'b0;
                                state <= RECEIVE;
                            end else begin
                                tx_shift <= {tx_shift[38:0], 1'b0};
                                mosi <= tx_shift[38];
                                tx_left <= tx_left - 1'b1;
                            end
                        end
                    end
                    RECEIVE: begin
                        sclk <= !sclk;
                        if (!sclk) begin // Rising edge: sample flash output.
                            rx_shift <= {rx_shift[6:0], miso};
                            if (rx_bit == 3'd7) begin
                                data_out <= {rx_shift[6:0], miso};
                                data_valid <= 1'b1;
                                rx_bit <= '0;
                                bytes_left <= bytes_left - 1'b1;
                                if (bytes_left == 1)
                                    state <= LAST_FALL;
                            end else begin
                                rx_bit <= rx_bit + 1'b1;
                            end
                        end
                    end
                    LAST_FALL: begin
                        sclk <= 1'b0; // Complete the final full clock period.
                        state <= HOLD_CS;
                    end
                    HOLD_CS: begin
                        cs_n <= 1'b1; // Hold CS low for another half-period.
                        done <= 1'b1;
                        state <= IDLE;
                    end
                    default: begin
                        cs_n <= 1'b1;
                        sclk <= 1'b0;
                        done <= 1'b1;
                        error <= 1'b1;
                        state <= IDLE;
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (HALF_CYCLES < 1)
            $fatal(1, "spi_sfdp_reader requires HALF_CYCLES >= 1");
    end
`endif
endmodule

`default_nettype wire
