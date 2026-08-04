module cnn_core (
    input clk_cnn,
    input rst,
    input cnn_start,
    input cnn_soft_reset,
    input [11:0] cnn_base_addr,
    output wire cnn_mem_read_en,
    output wire cnn_mem_write_en,
    output wire [11:0] cnn_mem_addr,
    output wire [7:0] cnn_mem_write_data,
    input wire [7:0] cnn_mem_read_data,
    output wire cnn_busy,
    output wire cnn_done,
    output reg [3:0] cnn_result
);

    parameter SHIFT1 = 14;
    parameter SHIFT2 = 14;
    parameter SHIFT_FC = 14;

    localparam S_IDLE        = 5'd0;
    localparam S_C1_SETUP    = 5'd1;
    localparam S_C1_WAIT     = 5'd2;
    localparam S_C1_ACCUM    = 5'd3;
    localparam S_C1_STORE    = 5'd4;
    localparam S_C2_SETUP    = 5'd5;
    localparam S_C2_WAIT     = 5'd6;
    localparam S_C2_ACCUM    = 5'd7;
    localparam S_C2_STORE    = 5'd8;
    localparam S_FC_SETUP    = 5'd9;
    localparam S_FC_WAIT     = 5'd10;
    localparam S_FC_ACCUM    = 5'd11;
    localparam S_ARGMAX_INIT = 5'd12;
    localparam S_ARGMAX_SCAN = 5'd13;
    localparam S_DONE        = 5'd14;

    reg [4:0] state;
    
    assign cnn_busy = (state != S_IDLE) && (state != S_DONE);
    assign cnn_done = (state == S_DONE);

    // ================================================================
    // CNN weights, biases, and intermediate results.
    // The input image lives in the last 1KB of shared Data_Memory.
    // ================================================================
    (* rom_style = "block" *) reg signed [15:0] kernel1_rom [0:8];
    // Vivado synth can reject $readmemh when an initialized memory is
    // only read with a literal index like rom[0]. Keep the single-entry
    // memories as [0:0], but read them through constant address wires.
    (* rom_style = "block" *) reg signed [31:0] kernel1_bias_rom [0:0];
    (* rom_style = "block" *) reg signed [15:0] kernel2_rom [0:8];
    (* rom_style = "block" *) reg signed [31:0] kernel2_bias_rom [0:0];
    (* rom_style = "block" *) reg signed [15:0] fc_weights_rom [0:359];
    (* rom_style = "block" *) reg signed [31:0] fc_biases_rom [0:9];
    (* ram_style = "block" *) reg signed [31:0] pool1_mem [0:224];
    (* ram_style = "block" *) reg signed [31:0] pool2_mem [0:35];

    reg [9:0] image_addr;
    reg [3:0] kernel1_addr;
    reg [3:0] kernel2_addr;
    wire kernel1_bias_addr;
    wire kernel2_bias_addr;
    reg [7:0] pool1_addr;
    reg [5:0] pool2_addr;
    reg [8:0] fc_weight_addr;
    reg [3:0] fc_bias_addr;

    reg signed [15:0] kernel1_dout;
    reg signed [31:0] kernel1_bias_dout;
    reg signed [15:0] kernel2_dout;
    reg signed [31:0] kernel2_bias_dout;
    reg signed [31:0] pool1_dout;
    reg signed [31:0] pool2_dout;
    reg signed [15:0] fc_weight_dout;
    reg signed [31:0] fc_bias_dout;

    assign cnn_mem_read_en = (state == S_C1_WAIT);
    assign cnn_mem_write_en = 1'b0;
    assign cnn_mem_write_data = 8'd0;
    assign cnn_mem_addr = cnn_base_addr + image_addr;
    assign kernel1_bias_addr = 1'b0;
    assign kernel2_bias_addr = 1'b0;

    reg [4:0] c1_row;
    reg [4:0] c1_col;
    reg [3:0] c1_mac_idx;
    reg signed [31:0] c1_line [0:59];
    reg signed [31:0] c1_out;

    reg [4:0] c2_row;
    reg [4:0] c2_col;
    reg [3:0] c2_mac_idx;
    reg signed [31:0] c2_line [0:25];
    reg signed [31:0] c2_out;

    reg [2:0] fc_row;
    reg [3:0] fc_out_idx;
    reg [2:0] fc_j;
    reg [3:0] arg_idx;
    reg [3:0] best_idx;
    reg signed [63:0] best_score;
    reg signed [63:0] class_score [0:9];
    reg signed [63:0] mac_acc;

    integer i;

    wire signed [31:0] mac_operand_a;
    wire signed [31:0] mac_operand_b;
    wire signed [63:0] mac_product;
    wire signed [63:0] mac_acc_next;
    wire signed [63:0] fc_row_score;

    // ================================================================
    // Common MAC operation for conv and fc layers
    // Use the same MAC to reduce DSP usage, 
    // given that the process is now sequential.
    // ================================================================
    assign mac_operand_a = (state == S_C1_ACCUM) ? $signed({24'd0, cnn_mem_read_data}) :
                           (state == S_C2_ACCUM) ? $signed(pool1_dout) :
                                                   $signed(pool2_dout);
    assign mac_operand_b = (state == S_C1_ACCUM) ? $signed({{16{kernel1_dout[15]}}, kernel1_dout}) :
                           (state == S_C2_ACCUM) ? $signed({{16{kernel2_dout[15]}}, kernel2_dout}) :
                                                   $signed({{16{fc_weight_dout[15]}}, fc_weight_dout});
    assign mac_product = mac_operand_a * mac_operand_b;
    assign mac_acc_next = mac_acc + mac_product;
    assign fc_row_score = (fc_row == 3'd5) ? ((mac_acc_next + $signed(fc_bias_dout)) >>> SHIFT_FC) :
                                                (mac_acc_next >>> SHIFT_FC);

    function [31:0] max_value;  // Used for Max Pooling
        input [31:0] a, b, c, d;
        begin
            max_value = (a > b) ? ((a > c) ? ((a > d) ? a : d) : ((c > d) ? c : d)) :
                                  ((b > c) ? ((b > d) ? b : d) : ((c > d) ? c : d));
        end
    endfunction

    function [9:0] conv1_image_index;
        input [4:0] row;
        input [4:0] col;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: conv1_image_index = row * 32 + col;
                4'd1: conv1_image_index = row * 32 + col + 1;
                4'd2: conv1_image_index = row * 32 + col + 2;
                4'd3: conv1_image_index = (row + 1) * 32 + col;
                4'd4: conv1_image_index = (row + 1) * 32 + col + 1;
                4'd5: conv1_image_index = (row + 1) * 32 + col + 2;
                4'd6: conv1_image_index = (row + 2) * 32 + col;
                4'd7: conv1_image_index = (row + 2) * 32 + col + 1;
                default: conv1_image_index = (row + 2) * 32 + col + 2;
            endcase
        end
    endfunction

    function [7:0] conv2_pool1_index;
        input [4:0] row;
        input [4:0] col;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: conv2_pool1_index = row * 15 + col;
                4'd1: conv2_pool1_index = row * 15 + col + 1;
                4'd2: conv2_pool1_index = row * 15 + col + 2;
                4'd3: conv2_pool1_index = (row + 1) * 15 + col;
                4'd4: conv2_pool1_index = (row + 1) * 15 + col + 1;
                4'd5: conv2_pool1_index = (row + 1) * 15 + col + 2;
                4'd6: conv2_pool1_index = (row + 2) * 15 + col;
                4'd7: conv2_pool1_index = (row + 2) * 15 + col + 1;
                default: conv2_pool1_index = (row + 2) * 15 + col + 2;
            endcase
        end
    endfunction

    function [8:0] fc_weight_index;
        input [2:0] row;
        input [2:0] col;
        input [3:0] out_idx;
        begin
            fc_weight_index = 10 * ((row * 6) + col) + out_idx;
        end
    endfunction

    initial begin
        $readmemh("kernel1.mem", kernel1_rom);
        $readmemh("kernel1_bias.mem", kernel1_bias_rom);
        $readmemh("kernel2.mem", kernel2_rom);
        $readmemh("kernel2_bias.mem", kernel2_bias_rom);
        $readmemh("weights.mem", fc_weights_rom);
        $readmemh("biases.mem", fc_biases_rom);
    end

    // ================================================================
    // Synchronous read and write
    // block RAM features limited read ports, so we need to divide 
    // the read operations across multiple clock cycles, otherwise 
    // vivado will use too many LUTs to implement the memory.
    // ================================================================
    always @(posedge clk_cnn) begin
        kernel1_dout <= kernel1_rom[kernel1_addr];
        kernel1_bias_dout <= kernel1_bias_rom[kernel1_bias_addr];
        kernel2_dout <= kernel2_rom[kernel2_addr];
        kernel2_bias_dout <= kernel2_bias_rom[kernel2_bias_addr];
        pool1_dout <= pool1_mem[pool1_addr];
        pool2_dout <= pool2_mem[pool2_addr];
        fc_weight_dout <= fc_weights_rom[fc_weight_addr];
        fc_bias_dout <= fc_biases_rom[fc_bias_addr];

        if (state == S_C1_STORE && c1_row[0] && c1_col[0]) begin
            pool1_mem[(c1_row >> 1) * 15 + (c1_col >> 1)] <= max_value(
                c1_line[c1_col - 1],
                c1_line[c1_col],
                c1_line[30 + c1_col - 1],
                c1_out
            );
        end

        if (state == S_C2_STORE && c2_row[0] && c2_col[0] && c2_row < 12 && c2_col < 12) begin
            pool2_mem[(c2_row >> 1) * 6 + (c2_col >> 1)] <= max_value(
                c2_line[c2_col - 1],
                c2_line[c2_col],
                c2_line[13 + c2_col - 1],
                c2_out
            );
        end
    end

    // ================================================================
    // FSM for sequential CNN inference with one shared MAC.
    // Flow:
    //   IDLE waits for cnn_start.
    //   C1_SETUP/WAIT/ACCUM/STORE scans the 30x30 conv1 outputs;
    //   every 2x2 group is max-pooled and written to pool1_mem.
    //   C2_SETUP/WAIT/ACCUM/STORE scans the 13x13 conv2 outputs;
    //   valid 2x2 groups are max-pooled and written to pool2_mem.
    //   FC_SETUP/WAIT/ACCUM reuses the MAC for each class score row.
    //   ARGMAX_INIT/SCAN selects the largest class_score value.
    //   DONE holds cnn_result until reset or the next run.
    // Each WAIT state gives the synchronous ROM/RAM read one clock cycle
    // before the ACCUM state consumes the registered data.
    // ================================================================
    always @(posedge clk_cnn or posedge rst) begin
        if (rst || cnn_soft_reset) begin
            state <= S_IDLE;
            cnn_result <= 0;
            image_addr <= 0;
            kernel1_addr <= 0;
            kernel2_addr <= 0;
            pool1_addr <= 0;
            pool2_addr <= 0;
            fc_weight_addr <= 0;
            fc_bias_addr <= 0;
            c1_row <= 0;
            c1_col <= 0;
            c1_mac_idx <= 0;
            c1_out <= 0;
            c2_row <= 0;
            c2_col <= 0;
            c2_mac_idx <= 0;
            c2_out <= 0;
            fc_row <= 0;
            fc_out_idx <= 0;
            fc_j <= 0;
            arg_idx <= 0;
            best_idx <= 0;
            best_score <= 0;
            mac_acc <= 0;
            for (i = 0; i < 60; i = i + 1)
                c1_line[i] <= 0;
            for (i = 0; i < 26; i = i + 1)
                c2_line[i] <= 0;
            for (i = 0; i < 10; i = i + 1)
                class_score[i] <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (cnn_start) begin
                        cnn_result <= 0;
                        c1_row <= 0;
                        c1_col <= 0;
                        c1_mac_idx <= 0;
                        state <= S_C1_SETUP;
                    end
                end

                S_C1_SETUP: begin
                    mac_acc <= $signed(kernel1_bias_dout);
                    c1_mac_idx <= 0;
                    image_addr <= conv1_image_index(c1_row, c1_col, 0);
                    kernel1_addr <= 0;
                    state <= S_C1_WAIT;
                end

                S_C1_WAIT: begin
                    state <= S_C1_ACCUM;
                end

                S_C1_ACCUM: begin
                    if (c1_mac_idx == 8) begin
                        c1_out <= (mac_acc_next >= 0) ? (mac_acc_next >>> SHIFT1) : 0;
                        state <= S_C1_STORE;
                    end else begin
                        mac_acc <= mac_acc_next;
                        c1_mac_idx <= c1_mac_idx + 1;
                        image_addr <= conv1_image_index(c1_row, c1_col, c1_mac_idx + 1);
                        kernel1_addr <= c1_mac_idx + 1;
                        state <= S_C1_WAIT;
                    end
                end

                S_C1_STORE: begin
                    c1_line[(c1_row[0] ? 30 : 0) + c1_col] <= c1_out;
                    if (c1_row == 29 && c1_col == 29) begin
                        c2_row <= 0;
                        c2_col <= 0;
                        c2_mac_idx <= 0;
                        state <= S_C2_SETUP;
                    end else begin
                        if (c1_col == 29) begin
                            c1_col <= 0;
                            c1_row <= c1_row + 1;
                        end else begin
                            c1_col <= c1_col + 1;
                        end
                        state <= S_C1_SETUP;
                    end
                end

                S_C2_SETUP: begin
                    mac_acc <= $signed(kernel2_bias_dout);
                    c2_mac_idx <= 0;
                    pool1_addr <= conv2_pool1_index(c2_row, c2_col, 0);
                    kernel2_addr <= 0;
                    state <= S_C2_WAIT;
                end

                S_C2_WAIT: begin
                    state <= S_C2_ACCUM;
                end

                S_C2_ACCUM: begin
                    if (c2_mac_idx == 8) begin
                        c2_out <= (mac_acc_next >= 0) ? (mac_acc_next >>> SHIFT2) : 0;
                        state <= S_C2_STORE;
                    end else begin
                        mac_acc <= mac_acc_next;
                        c2_mac_idx <= c2_mac_idx + 1;
                        pool1_addr <= conv2_pool1_index(c2_row, c2_col, c2_mac_idx + 1);
                        kernel2_addr <= c2_mac_idx + 1;
                        state <= S_C2_WAIT;
                    end
                end

                S_C2_STORE: begin
                    c2_line[(c2_row[0] ? 13 : 0) + c2_col] <= c2_out;
                    if (c2_row == 12 && c2_col == 12) begin
                        fc_row <= 0;
                        fc_out_idx <= 0;
                        fc_j <= 0;
                        for (i = 0; i < 10; i = i + 1)
                            class_score[i] <= 0;
                        state <= S_FC_SETUP;
                    end else begin
                        if (c2_col == 12) begin
                            c2_col <= 0;
                            c2_row <= c2_row + 1;
                        end else begin
                            c2_col <= c2_col + 1;
                        end
                        state <= S_C2_SETUP;
                    end
                end

                S_FC_SETUP: begin
                    mac_acc <= 0;
                    fc_j <= 0;
                    pool2_addr <= (fc_row * 6);
                    fc_weight_addr <= fc_weight_index(fc_row, 0, fc_out_idx);
                    fc_bias_addr <= fc_out_idx;
                    state <= S_FC_WAIT;
                end

                S_FC_WAIT: begin
                    state <= S_FC_ACCUM;
                end

                S_FC_ACCUM: begin
                    if (fc_j == 5) begin
                        class_score[fc_out_idx] <= class_score[fc_out_idx] + fc_row_score;
                        if (fc_out_idx == 9) begin
                            fc_out_idx <= 0;
                            if (fc_row == 5) begin
                                state <= S_ARGMAX_INIT;
                            end else begin
                                fc_row <= fc_row + 1;
                                state <= S_FC_SETUP;
                            end
                        end else begin
                            fc_out_idx <= fc_out_idx + 1;
                            state <= S_FC_SETUP;
                        end
                    end else begin
                        mac_acc <= mac_acc_next;
                        fc_j <= fc_j + 1;
                        pool2_addr <= (fc_row * 6) + fc_j + 1;
                        fc_weight_addr <= fc_weight_index(fc_row, fc_j + 1, fc_out_idx);
                        state <= S_FC_WAIT;
                    end
                end

                S_ARGMAX_INIT: begin
                    best_idx <= 0;
                    best_score <= class_score[0];
                    arg_idx <= 1;
                    state <= S_ARGMAX_SCAN;
                end

                S_ARGMAX_SCAN: begin
                    if (class_score[arg_idx] > best_score) begin
                        best_score <= class_score[arg_idx];
                        best_idx <= arg_idx;
                        if (arg_idx == 9)
                            cnn_result <= arg_idx;
                    end else if (arg_idx == 9) begin
                        cnn_result <= best_idx;
                    end

                    if (arg_idx == 9) begin
                        state <= S_DONE;
                    end else begin
                        arg_idx <= arg_idx + 1;
                    end
                end

                S_DONE: begin
                    if (cnn_start) begin
                        cnn_result <= 0;
                        c1_row <= 0;
                        c1_col <= 0;
                        c1_mac_idx <= 0;
                        state <= S_C1_SETUP;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
