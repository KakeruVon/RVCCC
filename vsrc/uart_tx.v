`timescale 1ns/1ps
module uart_tx #(
    parameter clk_freq = 25_000_000,
    parameter baud = 115200
) (
    input wire clk,
    input wire rst,
    input wire tx_valid,
    input wire [7:0] tx_data,
    output reg tx_busy,
    output reg tx
);

// ================================================================
// Clock cycles counter for baud rate generation
// For a 25MHz clock and 115200 baud rate, we need to count 217 clock cycles per bit,
// The actual boud rate is 25,000,000 / 217 = 115207.37, which is very close to 115200(0.0064% error).
// Parameter boundaries protected.
// ================================================================
localparam integer bit_time = (clk_freq + baud/2) / baud;
localparam integer cnt_width = (bit_time > 1) ? $clog2(bit_time) : 1;
reg [cnt_width-1:0] bit_cnt;
reg [3:0] bit_idx;

// ================================================================
// Frame register to hold the data to be transmitted
// Garantees that the data is stable during the transmission process.
// ================================================================
reg [7:0] frame;


// ================================================================
// FSM for UART transmission
// States:
// - STATE_IDLE: Waiting for tx_valid signal to start transmission
// - STATE_START: Sending start bit (0)
// - STATE_DATA: Sending data bits (LSB first)
// - STATE_STOP: Sending stop bit (1)
// ================================================================
reg [1:0] state;
localparam STATE_IDLE = 2'd0;
localparam STATE_START = 2'd1;
localparam STATE_DATA = 2'd2;
localparam STATE_STOP = 2'd3;

initial begin
    tx_busy = 1'b0;
    tx = 1'b1;
    state = STATE_IDLE;
    bit_cnt <= 16'd0;
    bit_idx <= 4'd0;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_busy <= 1'b0;
        tx <= 1'b1;
        state <= STATE_IDLE;
        bit_cnt <= 16'd0;
        bit_idx <= 4'd0;
    end else begin
        case (state)
            STATE_IDLE: begin
                if (tx_valid) begin
                    frame <= tx_data;
                    tx_busy <= 1'b1;
                    bit_idx <= 4'd0;
                    bit_cnt <= 16'd0;
                    state <= STATE_START;
                end
            end
            STATE_START: begin
                if (bit_cnt < bit_time - 1) begin
                    tx <= 1'b0; // Keep sending start bit
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    bit_cnt <= 16'd0;
                    state <= STATE_DATA;
                end
            end
            STATE_DATA: begin
                if (bit_cnt < bit_time - 1) begin
                    tx <= frame[bit_idx];
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    bit_cnt <= 16'd0;
                    if (bit_idx < 7) begin
                        bit_idx <= bit_idx + 1;
                    end else begin
                        bit_idx <= 4'd0;
                        state <= STATE_STOP;
                    end
                end
            end
            STATE_STOP: begin
                if (bit_cnt < bit_time - 1) begin
                    tx <= 1'b1; // Keep sending stop bit
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    tx_busy <= 1'b0;
                    bit_cnt <= 16'd0;
                    state <= STATE_IDLE;
                end
            end
            default: begin
                tx_busy <= 1'b0;
                tx <= 1'b1;
                state <= STATE_IDLE;
                bit_cnt <= 16'd0;
                bit_idx <= 4'd0;
            end
        endcase
    end
end
endmodule