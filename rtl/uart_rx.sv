`timescale 1ns/1ps
`default_nettype none

// 8N1 receiver: idle high, one start bit, 8 data bits LSB first, one stop bit.
// clk is the SYSTEM clock. This module generates its own sampling timing.
// Default: 50 MHz / 115200 baud, rounded to 434 system clocks per bit.
module uart_rx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       reset,         // Synchronous, active high
    input  wire       rx,            // Asynchronous serial input
    output logic [7:0] data_out,
    output logic      data_valid,    // One clk pulse when a good byte is ready
    output wire       busy,
    output logic      framing_error  // One clk pulse for a low stop bit
);
    localparam integer COUNT_WIDTH = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam logic [COUNT_WIDTH-1:0] BIT_RELOAD = COUNT_WIDTH'(CLKS_PER_BIT - 1);
    localparam logic [COUNT_WIDTH-1:0] HALF_RELOAD = COUNT_WIDTH'(HALF_BIT - 1);

    typedef enum logic [2:0] {IDLE, START, DATA, STOP, WAIT_HIGH} state_t;
    state_t state;
    logic [COUNT_WIDTH-1:0] count;
    logic [2:0] bit_index;
    logic [7:0] shift_reg;
    (* ASYNC_REG = "TRUE" *) logic rx_meta, rx_sync;

    assign busy = (state != IDLE);

    // Two flip-flops reduce the risk of metastability entering the receiver.
    always_ff @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            count         <= '0;
            bit_index     <= '0;
            shift_reg     <= '0;
            data_out      <= '0;
            data_valid    <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            data_valid    <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                IDLE: begin
                    if (!rx_sync) begin
                        count <= HALF_RELOAD;
                        state <= START;
                    end
                end
                START: begin
                    if (count != 0)
                        count <= count - 1'b1;
                    else if (!rx_sync) begin
                        count     <= BIT_RELOAD;
                        bit_index <= '0;
                        state     <= DATA;
                    end else
                        state <= IDLE; // Short low pulse was a false start.
                end
                DATA: begin
                    if (count != 0)
                        count <= count - 1'b1;
                    else begin
                        shift_reg[bit_index] <= rx_sync;
                        count <= BIT_RELOAD;
                        if (bit_index == 3'd7)
                            state <= STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                end
                STOP: begin
                    if (count != 0)
                        count <= count - 1'b1;
                    else if (rx_sync) begin
                        data_out   <= shift_reg;
                        data_valid <= 1'b1;
                        state      <= IDLE;
                    end else begin
                        framing_error <= 1'b1;
                        state <= WAIT_HIGH;
                    end
                end
                WAIT_HIGH: begin
                    // A held-low input must not produce repeated invalid bytes.
                    if (rx_sync)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (CLKS_PER_BIT < 8)
            $fatal(1, "uart_rx requires CLKS_PER_BIT >= 8");
    end
`endif
endmodule

`default_nettype wire
