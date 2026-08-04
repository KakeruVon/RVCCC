// ================================================================
// Mapped_IO - simple word-only memory-mapped peripheral block
//
// CNN registers:
//   0x80001000 CONTROL: bit0=start, bit1=clear error, bit2=soft reset
//   0x80001004 STATUS : bit0=busy, bit1=done, bit2=error
//   0x80001008 BASE   : input image byte base in the 4KB data RAM
//   0x8000100C RESULT : predicted class in bits [3:0]
// LED register:
//   0x80002000 LED    : bits [3:0] drive the board LEDs
// UART registers:
//   0x80003000 TXDATA : write bits [7:0] to start one transmission
//   0x80003004 STATUS : bit0=tx_busy_or_pending, bit1=rx_valid
//   0x80003008 RXDATA : most recently received byte in bits [7:0]
//
// Only naturally aligned lw/sw accesses are supported. The CNN image is
// 1024 bytes, so a valid base is aligned and no greater than 0xC00.
// A UART TX write while tx_busy or tx_valid is asserted is ignored; software
// should poll STATUS before writing the next byte.
// ================================================================
module Mapped_IO (
    input wire clk_cpu,
    input wire rst,
    input wire Mem_Write_EX_MEM,
    input wire Mem_Read_EX_MEM,
    input wire [31:0] Mem_Write_Data,
    input wire [31:0] Mem_Address,
    input wire [2:0] Mem_Funct3_EX_MEM,
    input wire cnn_busy,
    input wire cnn_done,
    input wire [3:0] cnn_result,
    input wire uart_tx_busy,
    input wire uart_rx_valid,
    input wire [7:0] uart_rx_data,
    output wire mmio_hit,
    output reg [31:0] MMIO_Read_Data,
    output reg cnn_start,
    output reg cnn_soft_reset,
    output reg [11:0] cnn_base_addr,
    output wire cnn_error,
    output reg [3:0] led_value,
    output reg uart_tx_valid,
    output reg [7:0] uart_tx_data
);
    localparam [31:0] CNN_MMIO_BASE = 32'h8000_1000;
    localparam [31:0] LED_MMIO_ADDR = 32'h8000_2000;
    localparam [31:0] UART_MMIO_BASE = 32'h8000_3000;
    localparam [31:0] CNN_MMIO_LAST = 32'h8000_1FFF;
    localparam [31:0] UART_MMIO_LAST = 32'h8000_300B;
    localparam [11:0] DEFAULT_CNN_BASE = 12'hC00;
    localparam [11:0] MAX_CNN_BASE = 12'hC00;

    wire cnn_window_hit;
    wire led_window_hit;
    wire uart_window_hit;
    wire word_read;
    wire word_write;
    wire base_value_valid;
    reg error_reg;
    reg uart_rx_valid_reg;
    reg [7:0] uart_rx_data_reg;

    assign cnn_window_hit = (Mem_Address >= CNN_MMIO_BASE) &&
                            (Mem_Address <= CNN_MMIO_LAST);
    assign led_window_hit = (Mem_Address == LED_MMIO_ADDR);
    assign uart_window_hit = (Mem_Address >= UART_MMIO_BASE) &&
                             (Mem_Address <= UART_MMIO_LAST);
    assign mmio_hit = (Mem_Read_EX_MEM || Mem_Write_EX_MEM) &&
                      (cnn_window_hit || led_window_hit || uart_window_hit);
    assign word_read = Mem_Read_EX_MEM && mmio_hit &&
                       (Mem_Funct3_EX_MEM == 3'b010) &&
                       (Mem_Address[1:0] == 2'b00);
    assign word_write = Mem_Write_EX_MEM && mmio_hit &&
                        (Mem_Funct3_EX_MEM == 3'b010) &&
                        (Mem_Address[1:0] == 2'b00);
    assign base_value_valid = (Mem_Write_Data[31:12] == 20'd0) &&
                              (Mem_Write_Data[1:0] == 2'b00) &&
                              (Mem_Write_Data[11:0] <= MAX_CNN_BASE);
    assign cnn_error = error_reg;

    always @(*) begin
        MMIO_Read_Data = 32'd0;
        if (word_read) begin
            case (Mem_Address)
                CNN_MMIO_BASE + 32'h0004:
                    MMIO_Read_Data = {29'd0, error_reg, cnn_done, cnn_busy};
                CNN_MMIO_BASE + 32'h0008:
                    MMIO_Read_Data = {20'd0, cnn_base_addr};
                CNN_MMIO_BASE + 32'h000C:
                    MMIO_Read_Data = {28'd0, cnn_result};
                LED_MMIO_ADDR:
                    MMIO_Read_Data = {28'd0, led_value};
                UART_MMIO_BASE + 32'h0004:
                    MMIO_Read_Data = {30'd0, uart_rx_valid_reg, (uart_tx_busy | uart_tx_valid)};
                UART_MMIO_BASE + 32'h0008:
                    MMIO_Read_Data = {24'd0, uart_rx_data_reg};
                default:
                    MMIO_Read_Data = 32'd0;
            endcase
        end
    end

    always @(posedge clk_cpu or posedge rst) begin
        if (rst) begin
            cnn_start <= 1'b0;
            cnn_soft_reset <= 1'b0;
            cnn_base_addr <= DEFAULT_CNN_BASE;
            led_value <= 4'd0;
            error_reg <= 1'b0;
            uart_tx_valid <= 1'b0;
            uart_tx_data <= 8'd0;
            uart_rx_valid_reg <= 1'b0;
            uart_rx_data_reg <= 8'd0;
        end else begin
            cnn_start <= 1'b0;
            cnn_soft_reset <= 1'b0;
            uart_tx_valid <= 1'b0;

            if (word_write) begin
                case (Mem_Address)
                    CNN_MMIO_BASE: begin
                        if (Mem_Write_Data[1])
                            error_reg <= 1'b0;
                        if (Mem_Write_Data[2]) begin
                            cnn_soft_reset <= 1'b1;
                            error_reg <= 1'b0;
                        end
                        if (Mem_Write_Data[0]) begin
                            if (!cnn_busy)
                                cnn_start <= 1'b1;
                            else
                                error_reg <= 1'b1;
                        end
                    end
                    CNN_MMIO_BASE + 32'h0008: begin
                        if (base_value_valid)
                            cnn_base_addr <= Mem_Write_Data[11:0];
                        else
                            error_reg <= 1'b1;
                    end
                    LED_MMIO_ADDR: begin
                        led_value <= Mem_Write_Data[3:0];
                    end
                    UART_MMIO_BASE: begin
                        if (!uart_tx_busy && !uart_tx_valid) begin
                            uart_tx_data <= Mem_Write_Data[7:0];
                            uart_tx_valid <= 1'b1;
                        end
                    end
                    default: begin
                        // Unsupported offsets are harmless no-ops.
                    end
                endcase
            end

            if (word_read && (Mem_Address == UART_MMIO_BASE + 32'h0008))
                uart_rx_valid_reg <= 1'b0;

            if (uart_rx_valid) begin
                uart_rx_data_reg <= uart_rx_data;
                uart_rx_valid_reg <= 1'b1;
            end
        end
    end
endmodule
