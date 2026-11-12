`timescale 1ns/1ps
`default_nettype none

// Small discovery engine: SFDP header -> parameter headers -> BFPT DWORDs 1/2.
// Supports major revision 1, access protocol FFh and single-bit SPI mode 0.
// Chooses the first major-1 BFPT. It does not configure quad/octal flash modes.
module sfdp_discovery #(
    parameter integer HALF_CYCLES = 4
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,          // One clk pulse while !busy.
    output wire        busy,
    output logic       done,           // One clk pulse on success or error.
    output logic       valid,          // Results valid until next start/reset.
    output logic [3:0] error_code,     // See SFDP.md; zero on success.
    output logic [7:0] sfdp_major,
    output logic [7:0] sfdp_minor,
    output logic [7:0] parameter_count,
    output logic [23:0] bfpt_address,
    output logic [7:0] bfpt_dwords,
    output logic [31:0] bfpt_word1,     // Raw capability bits, not decoded yet.
    output logic [31:0] density_raw,
    output logic [63:0] capacity_bytes,
    output wire        cs_n,
    output wire        sclk,
    output wire        mosi,
    input  wire        miso
);
    typedef enum logic [3:0] {
        IDLE, ISSUE, READ_BYTES, CHECK_HEADER, CHECK_PARAMETER, CHECK_DENSITY, FINISH
    } state_t;
    state_t state, next_check;
    logic read_start;
    logic [23:0] read_address;
    wire read_done, read_error, read_valid;
    wire [7:0] read_data;
    logic [7:0] buffer_bytes [0:7];
    logic [2:0] byte_index;
    logic [7:0] header_index;
    wire [23:0] table_pointer = {buffer_bytes[6], buffer_bytes[5], buffer_bytes[4]};
    wire [24:0] table_end = {1'b0, table_pointer} + {15'b0, buffer_bytes[3], 2'b00};
    wire [23:0] headers_end = 24'd8 + {13'b0, parameter_count, 3'b000};
    wire [31:0] word1 = {buffer_bytes[3], buffer_bytes[2], buffer_bytes[1], buffer_bytes[0]};
    wire [31:0] density = {buffer_bytes[7], buffer_bytes[6], buffer_bytes[5], buffer_bytes[4]};

    assign busy = (state != IDLE);

    spi_sfdp_reader #(.HALF_CYCLES(HALF_CYCLES)) reader (
        .clk(clk), .reset(reset), .start(read_start), .address(read_address),
        .byte_count(16'd8), .busy(), .done(read_done), .error(read_error),
        .data_out(read_data), .data_valid(read_valid),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            next_check <= CHECK_HEADER;
            read_start <= 1'b0;
            read_address <= '0;
            byte_index <= '0;
            header_index <= '0;
            done <= 1'b0;
            valid <= 1'b0;
            error_code <= '0;
            sfdp_major <= '0;
            sfdp_minor <= '0;
            parameter_count <= '0;
            bfpt_address <= '0;
            bfpt_dwords <= '0;
            bfpt_word1 <= '0;
            density_raw <= '0;
            capacity_bytes <= '0;
            for (integer i = 0; i < 8; i = i + 1)
                buffer_bytes[i] <= '0;
        end else begin
            done <= 1'b0;
            read_start <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    valid <= 1'b0;
                    error_code <= '0;
                    sfdp_major <= '0;
                    sfdp_minor <= '0;
                    parameter_count <= '0;
                    bfpt_address <= '0;
                    bfpt_dwords <= '0;
                    bfpt_word1 <= '0;
                    density_raw <= '0;
                    capacity_bytes <= '0;
                    read_address <= '0;
                    header_index <= '0;
                    next_check <= CHECK_HEADER;
                    state <= ISSUE;
                end
                ISSUE: begin
                    byte_index <= '0;
                    read_start <= 1'b1;
                    state <= READ_BYTES;
                end
                READ_BYTES: begin
                    if (read_valid) begin
                        buffer_bytes[byte_index] <= read_data;
                        byte_index <= byte_index + 1'b1;
                    end
                    if (read_done) begin
                        if (read_error) begin
                            error_code <= 4'd6;
                            state <= FINISH;
                        end else begin
                            state <= next_check;
                        end
                    end
                end
                CHECK_HEADER: begin
                    sfdp_minor <= buffer_bytes[4];
                    sfdp_major <= buffer_bytes[5];
                    if (word1 != 32'h50444653) begin
                        error_code <= 4'd1;
                        state <= FINISH;
                    end else if (buffer_bytes[5] != 1 || buffer_bytes[7] != 8'hff) begin
                        error_code <= 4'd2;
                        state <= FINISH;
                    end else if (buffer_bytes[6] == 8'hff) begin
                        error_code <= 4'd4; // NPH=FFh is reserved, not 256 headers.
                        state <= FINISH;
                    end else begin
                        parameter_count <= buffer_bytes[6] + 1'b1;
                        read_address <= 24'd8;
                        next_check <= CHECK_PARAMETER;
                        state <= ISSUE;
                    end
                end
                CHECK_PARAMETER: begin
                    if ({buffer_bytes[7], buffer_bytes[0]} == 16'hff00 &&
                        buffer_bytes[2] == 1) begin
                        if (buffer_bytes[3] < 9 || table_pointer[1:0] != 0 ||
                            table_pointer < headers_end || table_end > 25'h1000000) begin
                            error_code <= 4'd4;
                            state <= FINISH;
                        end else begin
                            bfpt_address <= table_pointer;
                            bfpt_dwords <= buffer_bytes[3];
                            read_address <= table_pointer;
                            next_check <= CHECK_DENSITY;
                            state <= ISSUE;
                        end
                    end else if (header_index == parameter_count - 1'b1) begin
                        error_code <= 4'd3;
                        state <= FINISH;
                    end else begin
                        header_index <= header_index + 1'b1;
                        read_address <= read_address + 24'd8;
                        state <= ISSUE;
                    end
                end
                CHECK_DENSITY: begin
                    bfpt_word1 <= word1;
                    density_raw <= density;
                    if (!density[31]) begin
                        // Linear encoding: bit count minus 1. Require whole bytes.
                        if (density[2:0] != 3'b111)
                            error_code <= 4'd5;
                        else begin
                            capacity_bytes <= ({32'b0, density} + 64'd1) >> 3;
                            valid <= 1'b1;
                        end
                    end else if (density[30:0] >= 32 && density[30:0] <= 66) begin
                        // Exponent encoding: 2^N bits = 2^(N-3) bytes.
                        capacity_bytes <= 64'd1 << (density[30:0] - 31'd3);
                        valid <= 1'b1;
                    end else begin
                        error_code <= 4'd5;
                    end
                    state <= FINISH;
                end
                FINISH: begin
                    done <= 1'b1;
                    state <= IDLE;
                end
                default: begin
                    error_code <= 4'd6;
                    state <= FINISH;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
