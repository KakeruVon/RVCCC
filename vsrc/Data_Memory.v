// ================================================================
// Data_Memory - 4KB shared CPU/CNN data RAM
//
// The CPU port remains split into four 8-bit true dual-port RAMs so
// Vivado can infer block RAM. CPU funct3 selects byte/halfword/word
// loads and per-lane stores; the CNN port retains byte addressing.
// ================================================================
module Data_Memory #(
    parameter DATA_B0_FILE = "data_b0.mem",
    parameter DATA_B1_FILE = "data_b1.mem",
    parameter DATA_B2_FILE = "data_b2.mem",
    parameter DATA_B3_FILE = "data_b3.mem",
    parameter CNN_B0_FILE  = "cnn_b0.mem",
    parameter CNN_B1_FILE  = "cnn_b1.mem",
    parameter CNN_B2_FILE  = "cnn_b2.mem",
    parameter CNN_B3_FILE  = "cnn_b3.mem"
) (
    input wire clk_cpu,
    input wire Mem_Write_EX_MEM,
    input wire Mem_Read_EX_MEM,
    input wire [31:0] Mem_Write_Data,
    input wire [31:0] Mem_Address,
    input wire [2:0] Mem_Funct3_EX_MEM,
    input wire cnn_mem_read_en,
    input wire cnn_mem_write_en,
    input wire [11:0] cnn_mem_addr,
    input wire [7:0] cnn_mem_write_data,
    output wire [7:0] cnn_mem_read_data,
    output wire [31:0] Mem_Read_Data
);
    wire [9:0] cpu_word_addr;
    wire [9:0] cnn_word_addr;
    wire [1:0] cnn_byte_sel;
    wire cpu_access;
    wire cnn_access;
    wire cpu_cnn_addr_conflict;
    wire cnn_port_en;
    wire [3:0] cnn_byte_we;
    reg [3:0] cpu_byte_we;
    reg [7:0] cpu_din0, cpu_din1, cpu_din2, cpu_din3;
    wire [7:0] cpu_dout0, cpu_dout1, cpu_dout2, cpu_dout3;
    wire [7:0] cnn_dout0, cnn_dout1, cnn_dout2, cnn_dout3;
    wire [7:0] load_byte;
    wire [15:0] load_half;
    reg [31:0] cpu_load_data;

    assign cpu_word_addr = Mem_Address[11:2];
    assign cnn_word_addr = cnn_mem_addr[11:2];
    assign cnn_byte_sel = cnn_mem_addr[1:0];
    assign cpu_access = Mem_Write_EX_MEM | Mem_Read_EX_MEM;
    assign cnn_access = cnn_mem_write_en | cnn_mem_read_en;
    assign cpu_cnn_addr_conflict = cpu_access && cnn_access && (cpu_word_addr == cnn_word_addr);
    assign cnn_port_en = cnn_access && !cpu_cnn_addr_conflict;
    assign cnn_byte_we = {4{cnn_port_en && cnn_mem_write_en}} &
                         {cnn_byte_sel == 2'd3, cnn_byte_sel == 2'd2,
                          cnn_byte_sel == 2'd1, cnn_byte_sel == 2'd0};

    assign load_byte = (Mem_Address[1:0] == 2'd0) ? cpu_dout0 :
                       (Mem_Address[1:0] == 2'd1) ? cpu_dout1 :
                       (Mem_Address[1:0] == 2'd2) ? cpu_dout2 : cpu_dout3;
    assign load_half = Mem_Address[1] ? {cpu_dout3, cpu_dout2} : {cpu_dout1, cpu_dout0};
    assign Mem_Read_Data = Mem_Read_EX_MEM ? cpu_load_data : 32'd0;
    assign cnn_mem_read_data = (cnn_byte_sel == 2'd0) ? cnn_dout0 :
                               (cnn_byte_sel == 2'd1) ? cnn_dout1 :
                               (cnn_byte_sel == 2'd2) ? cnn_dout2 : cnn_dout3;

    always @(*) begin
        cpu_byte_we = 4'b0000;
        cpu_din0 = Mem_Write_Data[7:0];
        cpu_din1 = Mem_Write_Data[15:8];
        cpu_din2 = Mem_Write_Data[23:16];
        cpu_din3 = Mem_Write_Data[31:24];

        if (Mem_Write_EX_MEM) begin
            case (Mem_Funct3_EX_MEM)
                3'b000: begin // sb
                    cpu_byte_we = 4'b0001 << Mem_Address[1:0];
                    cpu_din0 = Mem_Write_Data[7:0];
                    cpu_din1 = Mem_Write_Data[7:0];
                    cpu_din2 = Mem_Write_Data[7:0];
                    cpu_din3 = Mem_Write_Data[7:0];
                end
                3'b001: begin // sh, naturally aligned
                    if (Mem_Address[1]) begin
                        cpu_byte_we = 4'b1100;
                        cpu_din2 = Mem_Write_Data[7:0];
                        cpu_din3 = Mem_Write_Data[15:8];
                    end else begin
                        cpu_byte_we = 4'b0011;
                    end
                end
                3'b010: cpu_byte_we = 4'b1111; // sw, naturally aligned
                default: cpu_byte_we = 4'b0000;
            endcase
        end
    end

    always @(*) begin
        case (Mem_Funct3_EX_MEM)
            3'b000: cpu_load_data = {{24{load_byte[7]}}, load_byte}; // lb
            3'b001: cpu_load_data = {{16{load_half[15]}}, load_half}; // lh
            3'b010: cpu_load_data = {cpu_dout3, cpu_dout2, cpu_dout1, cpu_dout0}; // lw
            3'b100: cpu_load_data = {24'd0, load_byte}; // lbu
            3'b101: cpu_load_data = {16'd0, load_half}; // lhu
            default: cpu_load_data = 32'd0;
        endcase
    end

    Byte_TDP_RAM #(.DATA_FILE(DATA_B0_FILE), .CNN_FILE(CNN_B0_FILE)) data_b0 (
        .clk(clk_cpu), .ena(cpu_access), .wea(cpu_byte_we[0]), .addra(cpu_word_addr),
        .dina(cpu_din0), .douta(cpu_dout0), .enb(cnn_port_en), .web(cnn_byte_we[0]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout0)
    );

    Byte_TDP_RAM #(.DATA_FILE(DATA_B1_FILE), .CNN_FILE(CNN_B1_FILE)) data_b1 (
        .clk(clk_cpu), .ena(cpu_access), .wea(cpu_byte_we[1]), .addra(cpu_word_addr),
        .dina(cpu_din1), .douta(cpu_dout1), .enb(cnn_port_en), .web(cnn_byte_we[1]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout1)
    );

    Byte_TDP_RAM #(.DATA_FILE(DATA_B2_FILE), .CNN_FILE(CNN_B2_FILE)) data_b2 (
        .clk(clk_cpu), .ena(cpu_access), .wea(cpu_byte_we[2]), .addra(cpu_word_addr),
        .dina(cpu_din2), .douta(cpu_dout2), .enb(cnn_port_en), .web(cnn_byte_we[2]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout2)
    );

    Byte_TDP_RAM #(.DATA_FILE(DATA_B3_FILE), .CNN_FILE(CNN_B3_FILE)) data_b3 (
        .clk(clk_cpu), .ena(cpu_access), .wea(cpu_byte_we[3]), .addra(cpu_word_addr),
        .dina(cpu_din3), .douta(cpu_dout3), .enb(cnn_port_en), .web(cnn_byte_we[3]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout3)
    );

endmodule

// ================================================================
// Byte_TDP_RAM - Vivado-friendly true dual-port RAM template
// ================================================================
module Byte_TDP_RAM #(
    parameter DATA_FILE = "",
    parameter CNN_FILE = ""
) (
    input wire clk,
    input wire ena,
    input wire wea,
    input wire [9:0] addra,
    input wire [7:0] dina,
    output reg [7:0] douta,
    input wire enb,
    input wire web,
    input wire [9:0] addrb,
    input wire [7:0] dinb,
    output reg [7:0] doutb
);
    localparam DATA_MEM_WORDS = 1024;
    localparam CPU_INIT_LAST  = 767;
    localparam CNN_INIT_BASE  = 768;
    (* ram_style = "block" *) reg [7:0] ram [0:DATA_MEM_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < DATA_MEM_WORDS; i = i + 1)
            ram[i] = 8'h00;
        $readmemh(DATA_FILE, ram, 0, CPU_INIT_LAST);
        $readmemh(CNN_FILE, ram, CNN_INIT_BASE, DATA_MEM_WORDS - 1);
    end

    always @(negedge clk) begin
        if (ena) begin
            if (wea)
                ram[addra] <= dina;
            douta <= ram[addra];
        end
    end

    always @(negedge clk) begin
        if (enb) begin
            if (web)
                ram[addrb] <= dinb;
            doutb <= ram[addrb];
        end
    end

endmodule
