/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
module cpu (
    input clk, sysrst,
    // ---- Old scanning display outputs (commented out) ----
    // output [7:0] Anode_Activate,
    // output [7:0] LED_out
    // ---- Second direct-drive display outputs (commented out) ----
    // output [7:0] seg0, seg1, seg2, seg3, seg4, seg5, seg6, seg7
    // ---- New 4-LED binary output (active-low) ----
    output [3:0] ledr
);
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    
    // Reset
    wire rst;
    assign rst = ~sysrst;
    
    // ================================================================
    // Temporarily unify the system clock to avoid clock domain crossing (CDC) issues.
    // Now in practice, these 2 clocks are both connected to a 50MHz external clock.
    // ================================================================
    wire clk_50MHZ;
    wire clk_20MHZ;
    assign clk_50MHZ = clk;
    assign clk_20MHZ = clk;
    
    // Flags
    wire Branch_Taken;

    //-----------------------Data Signals--------------------------
    wire [31:0] PC;                 // The current PC
    wire [31:0] Instruction;
    wire [31:0] Jump_Addr;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [3:0] ALU_Op;
    wire ALU_In1_PC;
    wire [2:0] Funct3;
    wire [31:0] RF_Out1, RF_Out2;
    wire [31:0] Imm_Value;
    wire [31:0] ALU_Result;
    wire [31:0] Store_Data;
    wire [31:0] Mem_Read_Data;
    wire [31:0] Data_Mem_Read_Data;
    wire [31:0] MMIO_Read_Data;
    wire [31:0] Reg_Write_Data;

    // Stage Register wires
    // IF_ID Stage
    wire [31:0] PC_IF_ID;
    wire [31:0] Instruction_IF_ID;
    wire [31:0] Jump_Addr_IF_ID;
    wire [31:0] Return_Addr_IF_ID;

    // ID_EX Stage
    wire [4:0] rs1_ID_EX;
    wire [4:0] rs2_ID_EX;
    wire [4:0] rd_ID_EX;
    wire [31:0] PC_ID_EX;
    wire [31:0] RF_Out1_ID_EX;
    wire [31:0] RF_Out2_ID_EX;
    wire [31:0] Imm_Value_ID_EX;
    wire [31:0] Return_Addr_ID_EX;
    wire ALU_In1_PC_ID_EX;
    wire [2:0] Funct3_ID_EX;

    // EX_MEM Stage
    wire [4:0] rd_EX_MEM;
    wire [31:0] ALU_Result_EX_MEM;
    wire [31:0] RF_Out2_EX_MEM;
    wire [31:0] Forward_Data_EX_MEM;
    wire [31:0] Return_Addr_EX_MEM;
    wire [2:0] Funct3_EX_MEM;

    // MEM_WB Stage
    wire [4:0] rd_MEM_WB;
    wire [31:0] ALU_Result_MEM_WB;
    wire [31:0] Mem_Read_Data_MEM_WB;
    wire [31:0] Return_Addr_MEM_WB;

    //---------------------Control Signals-------------------------
    //wire [1:0] PC_Src;              // Selects PC source (sequential or branch)
    wire Reg_Write;                 // Register write signal
    wire ALU_Src;                   // Selects ALU Source (Register or Immediate)
    wire Mem_Read;                  // Memory Read Control Signal
    wire Mem_Write;                 // Memory Write Control Signal
    wire Mem_to_Reg;                // Memory to Register Control Signal

    wire Signal_Flush;              // Pipeline flush
    wire Signal_Flush_Pipeline;     // Pipeline flush including EX-stage jumps
    wire Signal_Branch;             // Branch
    wire Signal_Jal;                // JAL
    wire Signal_Jalr;               // Register-indirect jump
    wire Signal_Stall;              // Stall
    wire Signal_Ecall;              // Ecall
    wire [1:0] State;               // Current state of branch predictor
    wire Outcome;
    wire [1:0] Entry;    

    // Stage Register wires
    // IF_ID Stage
    wire Signal_Branch_IF_ID;
    wire Signal_Jal_IF_ID;
    wire Signal_Jalr_IF_ID;
    wire [1:0] State_IF_ID;
    wire [1:0] Addr_IF_ID;

    // ID_EX Stage
    wire Signal_Branch_ID_EX;
    wire Signal_Jal_ID_EX;
    wire Signal_Jalr_ID_EX;
    wire [1:0] State_ID_EX;
    wire [1:0] Addr_ID_EX;
    wire [3:0] ALU_Op_ID_EX;
    wire Reg_Write_ID_EX;
    wire ALU_Src_ID_EX;
    wire Mem_Read_ID_EX;
    wire Mem_Write_ID_EX;
    wire Mem_to_Reg_ID_EX;

    // EX_MEM stage
    wire Signal_Jal_EX_MEM;
    wire Signal_Jalr_EX_MEM;
    wire Reg_Write_EX_MEM;
    wire Mem_Read_EX_MEM;
    wire Mem_Write_EX_MEM;
    wire Mem_to_Reg_EX_MEM;

    // MEM_WB Stage
    wire Signal_Jal_MEM_WB;
    wire Signal_Jalr_MEM_WB;
    wire Reg_Write_MEM_WB;
    wire Mem_to_Reg_MEM_WB;

    // Forwarding Unit
    wire [1:0] Forward_A;
    wire [1:0] Forward_B;

    // CNN and memory-mapped I/O
    wire mmio_hit;
    wire cnn_start;
    wire cnn_soft_reset;
    wire [11:0] cnn_base_addr;
    wire cnn_busy;
    wire cnn_done;
    wire cnn_error;
    wire [3:0] cnn_result;
    wire [3:0] led_value;
    wire cnn_mem_read_en;
    wire cnn_mem_write_en;
    wire [11:0] cnn_mem_addr;
    wire [7:0] cnn_mem_write_data;
    wire [7:0] cnn_mem_read_data;
    

    //------------------------Parameters---------------------------
    localparam [31:0] PC_exception = 32'h1C090000;  // Address to jump to in case of exceptions


    //-------------------------------------------------------------
    // Logic Definition
    //-------------------------------------------------------------

    // Defining fields from Instructions
    assign rs1 = Instruction_IF_ID[19:15];    // Register Select 1
    assign rs2 = Instruction_IF_ID[24:20];    // Register Select 1
    assign rd = Instruction_IF_ID[11:7];      // Destination Register Select
    assign Outcome = Signal_Branch_ID_EX && Branch_Taken;
    assign Signal_Flush_Pipeline = Signal_Flush | Signal_Jalr_ID_EX;
    assign Forward_Data_EX_MEM = (Signal_Jal_EX_MEM || Signal_Jalr_EX_MEM) ?
                                 Return_Addr_EX_MEM : ALU_Result_EX_MEM;
    assign Mem_Read_Data = mmio_hit ? MMIO_Read_Data : Data_Mem_Read_Data;
    
    //-------------------------------------------------------------
    // Module Instantiation
    //-------------------------------------------------------------

    
    /*
    CLK_Gen clk_generation (
        // Clock out ports
        .clk_50MHZ(clk_50MHZ),     // output clk_50MHZ
        .clk_20MHZ(clk_20MHZ),     // output clk_20MHZ
        // Status and control signals
        .rst(rst), // input reset
        // .locked(locked),       // output locked
        // Clock in ports
        .clk_in(clk)      // input clk_in
    );
    */

    // Mux takes in PC+4, Exception Cycle intialization address or Branch Address
    PC_Module m1 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Branch(Signal_Branch),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .Signal_Jal(Signal_Jal),
        .Signal_Jalr_ID_EX(Signal_Jalr_ID_EX),
        .Outcome(Outcome),
        .Signal_Stall(Signal_Stall),
        .Signal_Ecall(Signal_Ecall),
        .State(State),
        .State_ID_EX(State_ID_EX),
        .Jump_Addr(Jump_Addr),
        .PC_ID_EX(PC_ID_EX),
        .Return_Addr_ID_EX(Return_Addr_ID_EX),
        .Jalr_Target(ALU_Result),
        .PC(PC)
    );

    Instruction_Memory m2 (
        .clk_50MHZ(clk_50MHZ),
        .Mem_Address(PC),
        .Instruction(Instruction)
    );

    Branch_Jump m3 (
        .Instruction(Instruction),
        .Signal_Branch(Signal_Branch),
        .Signal_Jal(Signal_Jal),
        .Signal_Jalr(Signal_Jalr),
        .Signal_Ecall(Signal_Ecall),
        .Jump_Addr(Jump_Addr)
    );

    IF_ID_reg m4 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Flush(Signal_Flush_Pipeline),
        .Signal_Branch(Signal_Branch),
        .Signal_Jal(Signal_Jal),
        .Signal_Jalr(Signal_Jalr),
        .Signal_Stall(Signal_Stall),
        .State(State),
        .PC(PC),
        .Instruction(Instruction),
        .Jump_Addr(Jump_Addr),
        .Signal_Branch_IF_ID(Signal_Branch_IF_ID),
        .Signal_Jal_IF_ID(Signal_Jal_IF_ID),
        .Signal_Jalr_IF_ID(Signal_Jalr_IF_ID),
        .State_IF_ID(State_IF_ID),
        .Addr_IF_ID(Addr_IF_ID),
        .PC_IF_ID(PC_IF_ID),
        .Instruction_IF_ID(Instruction_IF_ID),
        .Jump_Addr_IF_ID(Jump_Addr_IF_ID),
        .Return_Addr_IF_ID(Return_Addr_IF_ID)
    );

    Register_File m5 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Reg_Write(Reg_Write_MEM_WB),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd_MEM_WB),
        .Reg_Write_Data(Reg_Write_Data),
        .RD_Data1_ID_EX(RF_Out1),
        .RD_Data2_ID_EX(RF_Out2)
    );

    Control_Unit m6 (
        .Signal_Stall(Signal_Stall),
        .Instruction_IF_ID(Instruction_IF_ID),
        .Reg_Write(Reg_Write),
        .ALU_Src(ALU_Src),
        .Mem_Read(Mem_Read),
        .Mem_Write(Mem_Write),
        .Mem_to_Reg(Mem_to_Reg),
        .ALU_Op(ALU_Op),
        .ALU_In1_PC(ALU_In1_PC),
        .Funct3(Funct3),
        .Imm_Value(Imm_Value)
    );

    ID_EX_reg m7 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Flush(Signal_Flush_Pipeline),
        .Signal_Branch_IF_ID(Signal_Branch_IF_ID),
        .Signal_Jal_IF_ID(Signal_Jal_IF_ID),
        .Signal_Jalr_IF_ID(Signal_Jalr_IF_ID),
        .Signal_Stall(Signal_Stall),
        .Addr_IF_ID(Addr_IF_ID),
        .State_IF_ID(State_IF_ID),
        .ALU_Op(ALU_Op),
        .Reg_Write(Reg_Write),
        .ALU_Src(ALU_Src),
        .Mem_Read(Mem_Read),
        .Mem_Write(Mem_Write),
        .Mem_to_Reg(Mem_to_Reg),
        .ALU_In1_PC(ALU_In1_PC),
        .Funct3(Funct3),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .PC_IF_ID(PC_IF_ID),
        .RF_Out1(RF_Out1),
        .RF_Out2(RF_Out2),
        .Jump_Addr_IF_ID(Jump_Addr_IF_ID),
        .Return_Addr_IF_ID(Return_Addr_IF_ID),
        .Imm_Value(Imm_Value),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .Signal_Jal_ID_EX(Signal_Jal_ID_EX),
        .Signal_Jalr_ID_EX(Signal_Jalr_ID_EX),
        .Addr_ID_EX(Addr_ID_EX),
        .State_ID_EX(State_ID_EX),
        .ALU_Op_ID_EX(ALU_Op_ID_EX),
        .Reg_Write_ID_EX(Reg_Write_ID_EX),
        .ALU_Src_ID_EX(ALU_Src_ID_EX),
        .Mem_Read_ID_EX(Mem_Read_ID_EX),
        .Mem_Write_ID_EX(Mem_Write_ID_EX),
        .Mem_to_Reg_ID_EX(Mem_to_Reg_ID_EX),
        .ALU_In1_PC_ID_EX(ALU_In1_PC_ID_EX),
        .Funct3_ID_EX(Funct3_ID_EX),
        .rs1_ID_EX(rs1_ID_EX),
        .rs2_ID_EX(rs2_ID_EX),
        .rd_ID_EX(rd_ID_EX),
        .PC_ID_EX(PC_ID_EX),
        .RF_Out1_ID_EX(RF_Out1_ID_EX),
        .RF_Out2_ID_EX(RF_Out2_ID_EX),
        .Return_Addr_ID_EX(Return_Addr_ID_EX),
        .Imm_Value_ID_EX(Imm_Value_ID_EX)
    );

    ALU m8 (
        .ALU_Op_ID_EX(ALU_Op_ID_EX),
        .ALU_In1_ID_EX(RF_Out1_ID_EX),     
        .ALU_In2_ID_EX(RF_Out2_ID_EX),
        .Forward_A(Forward_A),
        .Forward_B(Forward_B),
        .ALU_Src_ID_EX(ALU_Src_ID_EX),
        .ALU_In1_PC_ID_EX(ALU_In1_PC_ID_EX),
        .Funct3_ID_EX(Funct3_ID_EX),
        .PC_ID_EX(Return_Addr_ID_EX - 32'd4),
        .ALU_Result_EX_MEM(Forward_Data_EX_MEM),
        .Reg_Write_Data_MEM_WB(Reg_Write_Data),
        .Imm_Value_ID_EX(Imm_Value_ID_EX),
        .Branch_Taken(Branch_Taken),
        .Store_Data(Store_Data),
        .ALU_Result(ALU_Result)
    );

    EX_MEM_Reg m9 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Jal_ID_EX(Signal_Jal_ID_EX),
        .Signal_Jalr_ID_EX(Signal_Jalr_ID_EX),
        .Reg_Write_ID_EX(Reg_Write_ID_EX),
        .Mem_Read_ID_EX(Mem_Read_ID_EX),
        .Mem_Write_ID_EX(Mem_Write_ID_EX),
        .Mem_to_Reg_ID_EX(Mem_to_Reg_ID_EX),
        .rd_ID_EX(rd_ID_EX),
        .ALU_Result(ALU_Result),
        .RF_Out2_ID_EX(Store_Data),
        .Return_Addr_ID_EX(Return_Addr_ID_EX),
        .Funct3_ID_EX(Funct3_ID_EX),
        .Signal_Jal_EX_MEM(Signal_Jal_EX_MEM),
        .Signal_Jalr_EX_MEM(Signal_Jalr_EX_MEM),
        .Reg_Write_EX_MEM(Reg_Write_EX_MEM),
        .Mem_Read_EX_MEM(Mem_Read_EX_MEM),
        .Mem_Write_EX_MEM(Mem_Write_EX_MEM),
        .Mem_to_Reg_EX_MEM(Mem_to_Reg_EX_MEM),
        .rd_EX_MEM(rd_EX_MEM),
        .ALU_Result_EX_MEM(ALU_Result_EX_MEM),
        .RF_Out2_EX_MEM(RF_Out2_EX_MEM),
        .Return_Addr_EX_MEM(Return_Addr_EX_MEM),
        .Funct3_EX_MEM(Funct3_EX_MEM)
    );

    Data_Memory m10 (
        .clk_50MHZ(clk_50MHZ),
        .Mem_Write_EX_MEM(Mem_Write_EX_MEM && !mmio_hit),
        .Mem_Read_EX_MEM(Mem_Read_EX_MEM && !mmio_hit),
        .Mem_Write_Data(RF_Out2_EX_MEM),
        .Mem_Address(ALU_Result_EX_MEM),
        .Mem_Funct3_EX_MEM(Funct3_EX_MEM),
        .cnn_mem_read_en(cnn_mem_read_en),
        .cnn_mem_write_en(cnn_mem_write_en),
        .cnn_mem_addr(cnn_mem_addr),
        .cnn_mem_write_data(cnn_mem_write_data),
        .cnn_mem_read_data(cnn_mem_read_data),
        .Mem_Read_Data(Data_Mem_Read_Data)
    );

    Mapped_IO m19 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Mem_Write_EX_MEM(Mem_Write_EX_MEM),
        .Mem_Read_EX_MEM(Mem_Read_EX_MEM),
        .Mem_Write_Data(RF_Out2_EX_MEM),
        .Mem_Address(ALU_Result_EX_MEM),
        .Mem_Funct3_EX_MEM(Funct3_EX_MEM),
        .cnn_busy(cnn_busy),
        .cnn_done(cnn_done),
        .cnn_result(cnn_result),
        .mmio_hit(mmio_hit),
        .MMIO_Read_Data(MMIO_Read_Data),
        .cnn_start(cnn_start),
        .cnn_soft_reset(cnn_soft_reset),
        .cnn_base_addr(cnn_base_addr),
        .cnn_error(cnn_error),
        .led_value(led_value)
    );

    MEM_WB_Reg m11 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Jal_EX_MEM(Signal_Jal_EX_MEM),
        .Signal_Jalr_EX_MEM(Signal_Jalr_EX_MEM),
        .Reg_Write_EX_MEM(Reg_Write_EX_MEM),
        .Mem_to_Reg_EX_MEM(Mem_to_Reg_EX_MEM),
        .rd_EX_MEM(rd_EX_MEM),
        .ALU_Result_EX_MEM(ALU_Result_EX_MEM),
        .Mem_Read_Data(Mem_Read_Data),
        .Return_Addr_EX_MEM(Return_Addr_EX_MEM),
        .Signal_Jal_MEM_WB(Signal_Jal_MEM_WB),
        .Signal_Jalr_MEM_WB(Signal_Jalr_MEM_WB),
        .Reg_Write_MEM_WB(Reg_Write_MEM_WB),
        .Mem_to_Reg_MEM_WB(Mem_to_Reg_MEM_WB),
        .rd_MEM_WB(rd_MEM_WB),
        .ALU_Result_MEM_WB(ALU_Result_MEM_WB),
        .Mem_Read_Data_MEM_WB(Mem_Read_Data_MEM_WB),
        .Return_Addr_MEM_WB(Return_Addr_MEM_WB)
    );

    Forwarding_Unit m12 (
        .Reg_Write_EX_MEM(Reg_Write_EX_MEM),
        .Reg_Write_MEM_WB(Reg_Write_MEM_WB),
        .rd_EX_MEM(rd_EX_MEM),
        .rd_MEM_WB(rd_MEM_WB),
        .rs1_ID_EX(rs1_ID_EX),
        .rs2_ID_EX(rs2_ID_EX),
        .Forward_A(Forward_A),
        .Forward_B(Forward_B)
    );

    Hazard_Detection_Unit m13 (
        .rst(rst),
        .Mem_Read_ID_EX(Mem_Read_ID_EX),
        .rd_ID_EX(rd_ID_EX),
        .rs1_IF_ID(rs1),
        .rs2_IF_ID(rs2),
        .Signal_Stall(Signal_Stall)
    );

    Branch_Table m14 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .Addr(PC[4:3]),
        .Addr_ID_EX(Addr_ID_EX),
        .Entry(Entry),
        .State(State)
    );

    Branch_Predictor m15(
        .Outcome(Outcome),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .State_ID_EX(State_ID_EX),
        .Entry(Entry),
        .Signal_Flush(Signal_Flush)
    );

    Writeback_Unit m16 (
        .Mem_to_Reg_MEM_WB(Mem_to_Reg_MEM_WB),
        .Signal_Jal_MEM_WB(Signal_Jal_MEM_WB),
        .Signal_Jalr_MEM_WB(Signal_Jalr_MEM_WB),
        .ALU_Result_MEM_WB(ALU_Result_MEM_WB),
        .Mem_Read_Data_MEM_WB(Mem_Read_Data_MEM_WB),
        .Return_Addr_MEM_WB(Return_Addr_MEM_WB),
        .Reg_Write_Data(Reg_Write_Data)
    );

    // ---- Old scanning display module (commented out) ----
    /*
    Eight_Digit_Hex_Display m17 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Mem_LED_in(Mem_LED_out[27:0]),
        .predicted_class_LED(predicted_class_LED),
        .Anode_Activate(Anode_Activate),
        .LED_out(LED_out)
    );
    */
    
    // ---- Second direct-drive display module (commented out) ----
    // Each digit tube is independently driven with its own 8-bit segment signal.
    // Bit order: ABCDEFGP (bit[7]=A, bit[6]=B, bit[5]=C, bit[4]=D,
    //                      bit[3]=E, bit[2]=F, bit[1]=G, bit[0]=P)
    // Active-low: 0 = segment ON, 1 = segment OFF
    /*
    Eight_Digit_Hex_Display m17 (
        .predicted_class_LED(predicted_class_LED),
        .Mem_LED_in(Mem_LED_out[27:0]),
        .seg0(seg0),
        .seg1(seg1),
        .seg2(seg2),
        .seg3(seg3),
        .seg4(seg4),
        .seg5(seg5),
        .seg6(seg6),
        .seg7(seg7)
    );
    */

    // ---- New 4-LED binary display module ----
    // Shows the LED MMIO register in binary. LEDs are active-low:
    // output 0 lights the LED, output 1 turns it off.
    Four_LED_Binary_Display m17 (
        .predicted_class_LED(led_value),
        .ledr(ledr)
    );
    
    cnn_core m18 (
        .clk_20MHZ(clk_20MHZ),
        .rst(rst),
        .cnn_start(cnn_start),
        .cnn_soft_reset(cnn_soft_reset),
        .cnn_base_addr(cnn_base_addr),
        .cnn_mem_read_en(cnn_mem_read_en),
        .cnn_mem_write_en(cnn_mem_write_en),
        .cnn_mem_addr(cnn_mem_addr),
        .cnn_mem_write_data(cnn_mem_write_data),
        .cnn_mem_read_data(cnn_mem_read_data),
        .cnn_busy(cnn_busy),
        .cnn_done(cnn_done),
        .cnn_result(cnn_result)
    );

endmodule


// ================================================================
// CLK_Gen - Clock generation module
// Input:  clk_in = 100 MHz
// Output: clk_50MHZ = 50 MHz (div-by-2)
//         clk_20MHZ = 20 MHz (div-by-5)
// ================================================================
/*
module CLK_Gen (
    input clk_in,
    input rst,
    output reg clk_50MHZ,
    output reg clk_20MHZ
);
    // ---- 50 MHz generation: simple toggle (divide-by-2) ----
    always @(posedge clk_in or posedge rst) begin
        if (rst)
            clk_50MHZ <= 1'b0;
        else
            clk_50MHZ <= ~clk_50MHZ;
    end

    // ---- 20 MHz generation: divide-by-5 counter ----
    // 100 MHz / 5 = 20 MHz, 40% duty cycle (2 high, 3 low)
    reg [2:0] cnt_20m;

    always @(posedge clk_in or posedge rst) begin
        if (rst) begin
            cnt_20m   <= 3'd0;
            clk_20MHZ <= 1'b0;
        end else begin
            if (cnt_20m == 3'd4) begin
                cnt_20m   <= 3'd0;
                clk_20MHZ <= 1'b0;
            end else begin
                if (cnt_20m == 3'd2)
                    clk_20MHZ <= 1'b1;
                cnt_20m <= cnt_20m + 1'b1;
            end
        end
    end

endmodule
*/


module PC_Module (
    // Inputs
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Branch,
    input wire Signal_Branch_ID_EX,
    input wire Signal_Jal,
    input wire Signal_Jalr_ID_EX,
    input wire Outcome,
    input wire Signal_Stall,
    input wire Signal_Ecall,
    input wire [1:0] State,
    input wire [1:0] State_ID_EX,
    input wire [31:0] Jump_Addr,
    input wire [31:0] PC_ID_EX,
    input wire [31:0] Return_Addr_ID_EX,
    input wire [31:0] Jalr_Target,

    // Outputs
    output reg [31:0] PC
);
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    wire Prediction;
    wire Prediction_ID_EX;
    wire Branch_Mispredict;
    wire [31:0] Jalr_Target_Aligned;
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------    
    assign Prediction = State[1];
    assign Prediction_ID_EX = State_ID_EX[1];
    assign Branch_Mispredict = Signal_Branch_ID_EX && (Prediction_ID_EX ^ Outcome);
    assign Jalr_Target_Aligned = {Jalr_Target[31:1], 1'b0};
    
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst==1) begin
            PC <= 32'h0; // rst
        end
        else if (Signal_Jalr_ID_EX==1) begin
            PC <= Jalr_Target_Aligned;
        end
        else if (Branch_Mispredict==1) begin
            PC <= Outcome ? PC_ID_EX : Return_Addr_ID_EX;
        end
        else if (Signal_Stall==1 || Signal_Ecall==1) begin
            PC <= PC; // Stall
        end
        else if ((Signal_Branch==1 && Prediction==1) || Signal_Jal==1) begin
            PC <= PC + Jump_Addr; // JAL or predicted branch
        end
        else begin
            PC <= PC + 4; // Normal execution
        end
    end

endmodule

module Instruction_Memory (
    // Inputs
    input wire clk_50MHZ,
    input wire [31:0] Mem_Address,

    // Outputs
    output reg [31:0] Instruction
);

    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    localparam INSTR_MEM_WORDS = 256; // 1KB instruction memory
    (* ram_style = "block" *) reg [31:0] mem [0:INSTR_MEM_WORDS-1];

    wire [7:0] word_addr;
    integer i;

    assign word_addr = Mem_Address[9:2];

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    initial begin
        for (i = 0; i < INSTR_MEM_WORDS; i = i + 1)
            mem[i] = 32'h00000000;
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/instruction.mem", mem);
    end

    always @(negedge clk_50MHZ) begin
        Instruction <= mem[word_addr];
    end

endmodule
module Branch_Jump (
    // Inputs
    input wire [31:0] Instruction,

    // Outputs
    output reg Signal_Branch,
    output reg Signal_Jal,
    output reg Signal_Jalr,
    output reg Signal_Ecall,
    output reg [31:0] Jump_Addr
);
    
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    wire [6:0] Opcode;

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    assign Opcode = Instruction[6:0];

    always @* begin
        Signal_Branch = 0;
        Signal_Jal = 0;
        Signal_Jalr = 0;
        Signal_Ecall = 0;
        Jump_Addr = 32'd0;

        case (Opcode)
            7'b1100011: begin       // B-Type
                Signal_Branch = 1;
                Jump_Addr = {{19{Instruction[31]}}, Instruction[31], Instruction[7], Instruction[30:25], Instruction[11:8], 1'b0};
            end

            7'b1101111: begin       // JAL
                Signal_Jal = 1;
                Jump_Addr = {{11{Instruction[31]}}, Instruction[31], Instruction[19:12], Instruction[20], Instruction[30:21], 1'b0};
            end

            7'b1100111: begin       // JALR, resolved in EX when rs1 is available
                Signal_Jalr = 1;
            end

            7'b1110011: begin       // ECALL only; EBREAK is intentionally not implemented
                Signal_Ecall = (Instruction == 32'h00000073);
            end

            default: begin
                Signal_Branch = 0;
                Signal_Jal = 0;
                Signal_Jalr = 0;
                Signal_Ecall = 0;
                Jump_Addr = 32'd0;
            end
        endcase
    end
    
endmodule

module IF_ID_reg (
    // Inputs
    // Control Signals
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Flush,            // Pipeline flush
    input wire Signal_Branch,           // Branch
    input wire Signal_Jal,              // JAL
    input wire Signal_Jalr,             // Register-indirect jump
    input wire Signal_Stall,            // Stall
    input wire [1:0] State,             // Current state of branch predictor

    // Data Signals
    input wire [31:0] PC,       
    input wire [31:0] Instruction,
    input wire [31:0] Jump_Addr,

    // Outputs
    // Control Signals
    output reg Signal_Branch_IF_ID,
    output reg Signal_Jal_IF_ID,
    output reg Signal_Jalr_IF_ID,
    output reg [1:0] State_IF_ID,

    // Data Signals
    output reg [1:0] Addr_IF_ID,
    output reg [31:0] PC_IF_ID,
    output reg [31:0] Instruction_IF_ID,
    output reg [31:0] Jump_Addr_IF_ID,
    output reg [31:0] Return_Addr_IF_ID
);

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst == 1) begin
            // Control Signals
            Signal_Branch_IF_ID <= 0;
            Signal_Jal_IF_ID   <= 0;
            Signal_Jalr_IF_ID   <= 0;
            State_IF_ID         <= 0;

            // Data Signals
            Addr_IF_ID          <= 0;
            PC_IF_ID            <= 0;
            Instruction_IF_ID   <= 0;
            Jump_Addr_IF_ID     <= 0;
            Return_Addr_IF_ID   <= 0;
        end

        else if (Signal_Flush==1) begin

            // Control Signals
            Signal_Branch_IF_ID <= 0;
            Signal_Jal_IF_ID   <= 0;
            Signal_Jalr_IF_ID   <= 0;
            State_IF_ID         <= 0;

            // Data Signals
            Addr_IF_ID          <= 0;
            PC_IF_ID            <= 0;
            Instruction_IF_ID   <= 0;
            Jump_Addr_IF_ID     <= 0;
            Return_Addr_IF_ID   <= 0;
        end

        else if (!Signal_Stall) begin

            // Control Signals
            Signal_Branch_IF_ID <= Signal_Branch;
            Signal_Jal_IF_ID   <= Signal_Jal;
            Signal_Jalr_IF_ID   <= Signal_Jalr;
            State_IF_ID         <= State;

            // Data Signals
            Addr_IF_ID          <= PC[4:3];
            PC_IF_ID            <= PC;
            Instruction_IF_ID   <= Instruction;
            Jump_Addr_IF_ID     <= Jump_Addr;
            Return_Addr_IF_ID   <= PC + 4;
        end
    end
    
endmodule

module Register_File (
    // Inputs
    input wire clk_50MHZ,
    input wire rst,    
    input wire Reg_Write,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [4:0] rd,
    input wire [31:0] Reg_Write_Data,

    // Outputs
    output reg [31:0] RD_Data1_ID_EX, RD_Data2_ID_EX
);
    
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    reg [31:0] Reg_Mem [31:0];

    integer i;

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(*) begin
        RD_Data1_ID_EX = Reg_Mem[rs1];
        RD_Data2_ID_EX = Reg_Mem[rs2];
    end
        
    always @(negedge clk_50MHZ, posedge rst) begin
        if (rst == 1) begin
            for (i = 0; i < 32; i = i + 1)
                Reg_Mem[i] <= 0;
        end
   
        else begin
            if (Reg_Write & (rd != 5'b00000))
                Reg_Mem[rd] <= Reg_Write_Data;
        end
    end

endmodule

module Control_Unit (
    // Inputs
    input wire Signal_Stall,
    input wire [31:0] Instruction_IF_ID,

    // Outputs
    output reg Reg_Write, ALU_Src, Mem_Read, Mem_Write, Mem_to_Reg,
    output reg [3:0] ALU_Op,
    output reg ALU_In1_PC,
    output reg [2:0] Funct3,
    output reg [31:0] Imm_Value
);
    
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    wire [6:0] Opcode;
    wire [2:0] Instr_Funct3;
    wire [6:0] Instr_Funct7;

    localparam [3:0] ALU_ADD  = 4'h0;
    localparam [3:0] ALU_SUB  = 4'h1;
    localparam [3:0] ALU_SLL  = 4'h2;
    localparam [3:0] ALU_SRL  = 4'h3;
    localparam [3:0] ALU_SLT  = 4'h4;
    localparam [3:0] ALU_OR   = 4'h5;
    localparam [3:0] ALU_AND  = 4'h6;
    localparam [3:0] ALU_XOR  = 4'h7;
    localparam [3:0] ALU_SRA  = 4'h8;
    localparam [3:0] ALU_SLTU = 4'h9;
    localparam [3:0] ALU_COPY_B = 4'hA;

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    assign Opcode = Instruction_IF_ID[6:0];
    assign Instr_Funct3 = Instruction_IF_ID[14:12];
    assign Instr_Funct7 = Instruction_IF_ID[31:25];

    always @(*) begin
        Reg_Write  = 0;
        ALU_Src    = 0;
        Mem_Read   = 0;
        Mem_Write  = 0;
        Mem_to_Reg = 0;
        ALU_Op     = ALU_ADD;
        ALU_In1_PC = 1'b0;
        Funct3     = Instr_Funct3;
        Imm_Value  = 32'h00000000;

        if (!Signal_Stall) begin
            case (Opcode)
                7'b0110011: begin         // R-type
                    Reg_Write = 1;
                    case ({Instr_Funct7[5], Instr_Funct3})
                        4'b0_000: ALU_Op = ALU_ADD;
                        4'b1_000: ALU_Op = ALU_SUB;
                        4'b0_001: ALU_Op = ALU_SLL;
                        4'b0_010: ALU_Op = ALU_SLT;
                        4'b0_011: ALU_Op = ALU_SLTU;
                        4'b0_100: ALU_Op = ALU_XOR;
                        4'b0_101: ALU_Op = ALU_SRL;
                        4'b1_101: ALU_Op = ALU_SRA;
                        4'b0_110: ALU_Op = ALU_OR;
                        4'b0_111: ALU_Op = ALU_AND;
                        default: begin
                            Reg_Write = 0;
                            ALU_Op = ALU_ADD;
                        end
                    endcase
                end

                7'b0010011: begin         // I-type ALU
                    Reg_Write = 1;
                    ALU_Src = 1;
                    Imm_Value = {{20{Instruction_IF_ID[31]}}, Instruction_IF_ID[31:20]};
                    case (Instr_Funct3)
                        3'b000: ALU_Op = ALU_ADD;  // addi
                        3'b010: ALU_Op = ALU_SLT;  // slti
                        3'b011: ALU_Op = ALU_SLTU; // sltiu
                        3'b100: ALU_Op = ALU_XOR;  // xori
                        3'b110: ALU_Op = ALU_OR;   // ori
                        3'b111: ALU_Op = ALU_AND;  // andi
                        3'b001: begin              // slli
                            ALU_Op = (Instr_Funct7 == 7'b0000000) ? ALU_SLL : ALU_ADD;
                            Reg_Write = (Instr_Funct7 == 7'b0000000);
                        end
                        3'b101: begin              // srli/srai
                            ALU_Op = Instruction_IF_ID[30] ? ALU_SRA : ALU_SRL;
                            Reg_Write = (Instr_Funct7 == 7'b0000000) || (Instr_Funct7 == 7'b0100000);
                        end
                        default: begin
                            Reg_Write = 0;
                            ALU_Op = ALU_ADD;
                        end
                    endcase
                end

                7'b0000011: begin         // Loads
                    Reg_Write = 1;
                    ALU_Src = 1;
                    Mem_Read = 1;
                    Mem_to_Reg = 1;
                    ALU_Op = ALU_ADD;
                    Imm_Value = {{20{Instruction_IF_ID[31]}}, Instruction_IF_ID[31:20]};
                    case (Instr_Funct3)
                        3'b000, 3'b001, 3'b010, 3'b100, 3'b101: Reg_Write = 1;
                        default: Reg_Write = 0;
                    endcase
                end

                7'b0100011: begin         // Stores
                    ALU_Src = 1;
                    Mem_Write = 1;
                    ALU_Op = ALU_ADD;
                    Imm_Value = {{20{Instruction_IF_ID[31]}}, Instruction_IF_ID[31:25], Instruction_IF_ID[11:7]};
                    case (Instr_Funct3)
                        3'b000, 3'b001, 3'b010: Mem_Write = 1;
                        default: Mem_Write = 0;
                    endcase
                end

                7'b1100011: begin         // Branches
                    ALU_Src = 0;
                    ALU_Op = ALU_SUB;
                    Imm_Value = {{19{Instruction_IF_ID[31]}}, Instruction_IF_ID[31], Instruction_IF_ID[7], Instruction_IF_ID[30:25], Instruction_IF_ID[11:8], 1'b0};
                end

                7'b1101111: begin         // JAL
                    Reg_Write = 1;
                    Imm_Value = {{11{Instruction_IF_ID[31]}}, Instruction_IF_ID[31], Instruction_IF_ID[19:12], Instruction_IF_ID[20], Instruction_IF_ID[30:21], 1'b0};
                end

                7'b1100111: begin         // JALR
                    Reg_Write = (Instr_Funct3 == 3'b000);
                    ALU_Src = 1;
                    ALU_Op = ALU_ADD;
                    Imm_Value = {{20{Instruction_IF_ID[31]}}, Instruction_IF_ID[31:20]};
                end

                7'b0110111: begin         // LUI
                    Reg_Write = 1;
                    ALU_Src = 1;
                    ALU_Op = ALU_COPY_B;
                    Imm_Value = {Instruction_IF_ID[31:12], 12'b0};
                end

                7'b0010111: begin         // AUIPC
                    Reg_Write = 1;
                    ALU_Src = 1;
                    ALU_In1_PC = 1'b1;
                    ALU_Op = ALU_ADD;
                    Imm_Value = {Instruction_IF_ID[31:12], 12'b0};
                end

                7'b1110011: begin         // ECALL; EBREAK intentionally unsupported
                    Reg_Write  = 0;
                    Mem_Read   = 0;
                    Mem_Write  = 0;
                end

                default: begin
                    Reg_Write  = 0;
                    ALU_Src    = 0;
                    Mem_Read   = 0;
                    Mem_Write  = 0;
                    Mem_to_Reg = 0;
                    ALU_Op     = ALU_ADD;
                    ALU_In1_PC = 1'b0;
                    Imm_Value  = 32'h00000000;
                end
            endcase
        end
    end
    
endmodule

module ID_EX_reg (
    // Inputs
    // Control Signals
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Flush,            // Pipeline flush
    input wire Signal_Branch_IF_ID,     // Branch
    input wire Signal_Jal_IF_ID,        // JAL
    input wire Signal_Jalr_IF_ID,       // Register-indirect jump
    input wire Signal_Stall,            // Stall
    input wire [1:0] Addr_IF_ID,
    input wire [1:0] State_IF_ID,
    input wire [3:0] ALU_Op,
    input wire Reg_Write,
    input wire ALU_Src,
    input wire Mem_Read,
    input wire Mem_Write,
    input wire Mem_to_Reg,
    input wire ALU_In1_PC,
    input wire [2:0] Funct3,

    // Data Signals
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [4:0] rd,

    input wire [31:0] PC_IF_ID,
    input wire [31:0] RF_Out1,
    input wire [31:0] RF_Out2,
    input wire [31:0] Jump_Addr_IF_ID,
    input wire [31:0] Return_Addr_IF_ID,
    input wire [31:0] Imm_Value,

    // Outputs
    // Control Signals
    output reg Signal_Branch_ID_EX,
    output reg Signal_Jal_ID_EX,
    output reg Signal_Jalr_ID_EX,
    output reg [1:0] Addr_ID_EX,
    output reg [1:0] State_ID_EX,
    output reg [3:0] ALU_Op_ID_EX,
    output reg Reg_Write_ID_EX,
    output reg ALU_Src_ID_EX,
    output reg Mem_Read_ID_EX,
    output reg Mem_Write_ID_EX,
    output reg Mem_to_Reg_ID_EX,
    output reg ALU_In1_PC_ID_EX,
    output reg [2:0] Funct3_ID_EX,

    // Data Signals
    output reg [4:0] rs1_ID_EX,
    output reg [4:0] rs2_ID_EX,
    output reg [4:0] rd_ID_EX,

    output reg [31:0] PC_ID_EX,
    output reg [31:0] RF_Out1_ID_EX,
    output reg [31:0] RF_Out2_ID_EX,
    output reg [31:0] Return_Addr_ID_EX,
    output reg [31:0] Imm_Value_ID_EX
);

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst == 1) begin
            Signal_Branch_ID_EX <= 0;
            Signal_Jal_ID_EX    <= 0;
            Signal_Jalr_ID_EX   <= 0;
            Addr_ID_EX          <= 0;
            State_ID_EX         <= 0;
            ALU_Op_ID_EX        <= 0;
            Reg_Write_ID_EX     <= 0;
            ALU_Src_ID_EX       <= 0;
            Mem_Read_ID_EX      <= 0;
            Mem_Write_ID_EX     <= 0;
            Mem_to_Reg_ID_EX    <= 0;
            ALU_In1_PC_ID_EX    <= 0;
            Funct3_ID_EX        <= 0;

            rs1_ID_EX           <= 0;
            rs2_ID_EX           <= 0;
            rd_ID_EX            <= 0;

            PC_ID_EX            <= 0;
            RF_Out1_ID_EX       <= 0;
            RF_Out2_ID_EX       <= 0;
            Return_Addr_ID_EX   <= 0;
            Imm_Value_ID_EX     <= 0;
        end
        else if (Signal_Flush==1) begin
            Signal_Branch_ID_EX <= 0;
            Signal_Jal_ID_EX    <= 0;
            Signal_Jalr_ID_EX   <= 0;
            Addr_ID_EX          <= 0;
            State_ID_EX         <= 0;
            ALU_Op_ID_EX        <= 0;
            Reg_Write_ID_EX     <= 0;
            ALU_Src_ID_EX       <= 0;
            Mem_Read_ID_EX      <= 0;
            Mem_Write_ID_EX     <= 0;
            Mem_to_Reg_ID_EX    <= 0;
            ALU_In1_PC_ID_EX    <= 0;
            Funct3_ID_EX        <= 0;

            rs1_ID_EX           <= 0;
            rs2_ID_EX           <= 0;
            rd_ID_EX            <= 0;

            PC_ID_EX            <= 0;
            RF_Out1_ID_EX       <= 0;
            RF_Out2_ID_EX       <= 0;
            Return_Addr_ID_EX   <= 0;
            Imm_Value_ID_EX     <= 0;
        end
        else if (Signal_Stall==1) begin
            Signal_Branch_ID_EX <= 0;
            Signal_Jal_ID_EX    <= 0;
            Signal_Jalr_ID_EX   <= 0;
            Addr_ID_EX          <= 0;
            State_ID_EX         <= 0;
            ALU_Op_ID_EX        <= 0;
            Reg_Write_ID_EX     <= 0;
            ALU_Src_ID_EX       <= 0;
            Mem_Read_ID_EX      <= 0;
            Mem_Write_ID_EX     <= 0;
            Mem_to_Reg_ID_EX    <= 0;
            ALU_In1_PC_ID_EX    <= 0;
            Funct3_ID_EX        <= 0;

            rs1_ID_EX           <= rs1_ID_EX;
            rs2_ID_EX           <= rs2_ID_EX;
            rd_ID_EX            <= rd_ID_EX;

            PC_ID_EX            <= PC_ID_EX;
            RF_Out1_ID_EX       <= RF_Out1_ID_EX;
            RF_Out2_ID_EX       <= RF_Out2_ID_EX;
            Return_Addr_ID_EX   <= Return_Addr_ID_EX;
            Imm_Value_ID_EX     <= Imm_Value_ID_EX;
        end
        else begin
            Signal_Branch_ID_EX <= Signal_Branch_IF_ID;
            Signal_Jal_ID_EX    <= Signal_Jal_IF_ID;
            Signal_Jalr_ID_EX   <= Signal_Jalr_IF_ID;
            Addr_ID_EX          <= Addr_IF_ID;
            State_ID_EX         <= State_IF_ID;
            ALU_Op_ID_EX        <= ALU_Op;
            Reg_Write_ID_EX     <= Reg_Write;
            ALU_Src_ID_EX       <= ALU_Src;
            Mem_Read_ID_EX      <= Mem_Read;
            Mem_Write_ID_EX     <= Mem_Write;
            Mem_to_Reg_ID_EX    <= Mem_to_Reg;
            ALU_In1_PC_ID_EX    <= ALU_In1_PC;
            Funct3_ID_EX        <= Funct3;

            rs1_ID_EX           <= rs1;
            rs2_ID_EX           <= rs2;
            rd_ID_EX            <= rd;

            PC_ID_EX            <= PC_IF_ID + Jump_Addr_IF_ID;
            RF_Out1_ID_EX       <= RF_Out1;
            RF_Out2_ID_EX       <= RF_Out2;
            Return_Addr_ID_EX   <= Return_Addr_IF_ID;
            Imm_Value_ID_EX     <= Imm_Value;
        end
    end

endmodule

module ALU (
    // Inputs
    input wire [3:0] ALU_Op_ID_EX,
    input wire [31:0] ALU_In1_ID_EX, ALU_In2_ID_EX,
    input wire [1:0] Forward_A, Forward_B,
    input wire ALU_Src_ID_EX,
    input wire ALU_In1_PC_ID_EX,
    input wire [2:0] Funct3_ID_EX,
    input wire [31:0] PC_ID_EX,
    input wire [31:0] ALU_Result_EX_MEM, Reg_Write_Data_MEM_WB,
    input wire [31:0] Imm_Value_ID_EX,

    // Outputs
    output reg Branch_Taken,
    output wire [31:0] Store_Data,
    output reg [31:0] ALU_Result
);

    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    wire [31:0] Forwarded_In1;
    wire [31:0] Forwarded_In2;
    wire [31:0] ALU_In1;
    wire [31:0] ALU_In2;

    localparam [3:0] ALU_ADD  = 4'h0;
    localparam [3:0] ALU_SUB  = 4'h1;
    localparam [3:0] ALU_SLL  = 4'h2;
    localparam [3:0] ALU_SRL  = 4'h3;
    localparam [3:0] ALU_SLT  = 4'h4;
    localparam [3:0] ALU_OR   = 4'h5;
    localparam [3:0] ALU_AND  = 4'h6;
    localparam [3:0] ALU_XOR  = 4'h7;
    localparam [3:0] ALU_SRA  = 4'h8;
    localparam [3:0] ALU_SLTU = 4'h9;
    localparam [3:0] ALU_COPY_B = 4'hA;
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    assign Forwarded_In1 = (Forward_A == 2'b00) ? ALU_In1_ID_EX :
                           (Forward_A == 2'b01) ? Reg_Write_Data_MEM_WB :
                           (Forward_A == 2'b10) ? ALU_Result_EX_MEM :
                           ALU_In1_ID_EX;

    assign Forwarded_In2 = (Forward_B == 2'b00) ? ALU_In2_ID_EX :
                           (Forward_B == 2'b01) ? Reg_Write_Data_MEM_WB :
                           (Forward_B == 2'b10) ? ALU_Result_EX_MEM :
                           ALU_In2_ID_EX;

    assign ALU_In1 = ALU_In1_PC_ID_EX ? PC_ID_EX : Forwarded_In1;
    assign ALU_In2 = ALU_Src_ID_EX ? Imm_Value_ID_EX : Forwarded_In2;
    assign Store_Data = Forwarded_In2;

    always @(*) begin
        case (ALU_Op_ID_EX)
            ALU_ADD:    ALU_Result = ALU_In1 + ALU_In2;
            ALU_SUB:    ALU_Result = ALU_In1 - ALU_In2;
            ALU_SLL:    ALU_Result = ALU_In1 << ALU_In2[4:0];
            ALU_SRL:    ALU_Result = ALU_In1 >> ALU_In2[4:0];
            ALU_SLT:    ALU_Result = ($signed(ALU_In1) < $signed(ALU_In2)) ? 32'd1 : 32'd0;
            ALU_OR:     ALU_Result = ALU_In1 | ALU_In2;
            ALU_AND:    ALU_Result = ALU_In1 & ALU_In2;
            ALU_XOR:    ALU_Result = ALU_In1 ^ ALU_In2;
            ALU_SRA:    ALU_Result = $signed(ALU_In1) >>> ALU_In2[4:0];
            ALU_SLTU:   ALU_Result = (ALU_In1 < ALU_In2) ? 32'd1 : 32'd0;
            ALU_COPY_B: ALU_Result = ALU_In2;
            default:    ALU_Result = 32'h00000000;
        endcase
    end

    always @(*) begin
        case (Funct3_ID_EX)
            3'b000: Branch_Taken = (Forwarded_In1 == Forwarded_In2);                         // beq
            3'b001: Branch_Taken = (Forwarded_In1 != Forwarded_In2);                         // bne
            3'b100: Branch_Taken = ($signed(Forwarded_In1) < $signed(Forwarded_In2));         // blt
            3'b101: Branch_Taken = ($signed(Forwarded_In1) >= $signed(Forwarded_In2));        // bge
            3'b110: Branch_Taken = (Forwarded_In1 < Forwarded_In2);                          // bltu
            3'b111: Branch_Taken = (Forwarded_In1 >= Forwarded_In2);                         // bgeu
            default: Branch_Taken = 1'b0;
        endcase
    end
endmodule 

module EX_MEM_Reg (
    // Inputs
    // Control Signals
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Jal_ID_EX,
    input wire Signal_Jalr_ID_EX,
    input wire Reg_Write_ID_EX,
    input wire Mem_Read_ID_EX,
    input wire Mem_Write_ID_EX,
    input wire Mem_to_Reg_ID_EX,

    // Data Signals
    input wire [4:0]  rd_ID_EX,
    input wire [31:0] ALU_Result,
    input wire [31:0] RF_Out2_ID_EX,
    input wire [31:0] Return_Addr_ID_EX,
    input wire [2:0] Funct3_ID_EX,

    // Outputs
    // Control Signals
    output reg Signal_Jal_EX_MEM,
    output reg Signal_Jalr_EX_MEM,
    output reg Reg_Write_EX_MEM,
    output reg Mem_Read_EX_MEM,
    output reg Mem_Write_EX_MEM,
    output reg Mem_to_Reg_EX_MEM,

    // Data Signals
    output reg [4:0] rd_EX_MEM,
    output reg [31:0] ALU_Result_EX_MEM,
    output reg [31:0] RF_Out2_EX_MEM,
    output reg [31:0] Return_Addr_EX_MEM,
    output reg [2:0] Funct3_EX_MEM
);
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst==1) begin
            Signal_Jal_EX_MEM   <= 0;
            Signal_Jalr_EX_MEM  <= 0;
            Reg_Write_EX_MEM    <= 0;
            Mem_Read_EX_MEM     <= 0;
            Mem_Write_EX_MEM    <= 0;
            Mem_to_Reg_EX_MEM   <= 0;

            rd_EX_MEM           <= 0;
            ALU_Result_EX_MEM   <= 0;
            RF_Out2_EX_MEM      <= 0;
            Return_Addr_EX_MEM  <= 0;
            Funct3_EX_MEM       <= 0;
        end
        else begin
            Signal_Jal_EX_MEM   <= Signal_Jal_ID_EX;
            Signal_Jalr_EX_MEM  <= Signal_Jalr_ID_EX;
            Reg_Write_EX_MEM    <= Reg_Write_ID_EX;
            Mem_Read_EX_MEM     <= Mem_Read_ID_EX;
            Mem_Write_EX_MEM    <= Mem_Write_ID_EX;
            Mem_to_Reg_EX_MEM   <= Mem_to_Reg_ID_EX;

            rd_EX_MEM           <= rd_ID_EX;
            ALU_Result_EX_MEM   <= ALU_Result;
            RF_Out2_EX_MEM      <= RF_Out2_ID_EX;
            Return_Addr_EX_MEM  <= Return_Addr_ID_EX;
            Funct3_EX_MEM       <= Funct3_ID_EX;
        end
    end

endmodule

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
//
// Only naturally aligned lw/sw accesses are supported. The CNN image is
// 1024 bytes, so a valid base is aligned and no greater than 0xC00.
// ================================================================
module Mapped_IO (
    input wire clk_50MHZ,
    input wire rst,
    input wire Mem_Write_EX_MEM,
    input wire Mem_Read_EX_MEM,
    input wire [31:0] Mem_Write_Data,
    input wire [31:0] Mem_Address,
    input wire [2:0] Mem_Funct3_EX_MEM,
    input wire cnn_busy,
    input wire cnn_done,
    input wire [3:0] cnn_result,
    output wire mmio_hit,
    output reg [31:0] MMIO_Read_Data,
    output reg cnn_start,
    output reg cnn_soft_reset,
    output reg [11:0] cnn_base_addr,
    output wire cnn_error,
    output reg [3:0] led_value
);
    localparam [31:0] CNN_MMIO_BASE = 32'h8000_1000;
    localparam [31:0] LED_MMIO_ADDR = 32'h8000_2000;
    localparam [31:0] CNN_MMIO_LAST = 32'h8000_1FFF;
    localparam [11:0] DEFAULT_CNN_BASE = 12'hC00;
    localparam [11:0] MAX_CNN_BASE = 12'hC00;

    wire cnn_window_hit;
    wire led_window_hit;
    wire word_read;
    wire word_write;
    wire base_value_valid;
    reg error_reg;

    assign cnn_window_hit = (Mem_Address >= CNN_MMIO_BASE) &&
                            (Mem_Address <= CNN_MMIO_LAST);
    assign led_window_hit = (Mem_Address == LED_MMIO_ADDR);
    assign mmio_hit = (Mem_Read_EX_MEM || Mem_Write_EX_MEM) &&
                      (cnn_window_hit || led_window_hit);
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
                default:
                    MMIO_Read_Data = 32'd0;
            endcase
        end
    end

    always @(posedge clk_50MHZ or posedge rst) begin
        if (rst) begin
            cnn_start <= 1'b0;
            cnn_soft_reset <= 1'b0;
            cnn_base_addr <= DEFAULT_CNN_BASE;
            led_value <= 4'd0;
            error_reg <= 1'b0;
        end else begin
            cnn_start <= 1'b0;
            cnn_soft_reset <= 1'b0;

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
                    default: begin
                        // Unsupported offsets are harmless no-ops.
                    end
                endcase
            end
        end
    end
endmodule

// ================================================================
// Data_Memory - 4KB shared CPU/CNN data RAM
//
// The CPU port remains split into four 8-bit true dual-port RAMs so
// Vivado can infer block RAM. CPU funct3 selects byte/halfword/word
// loads and per-lane stores; the CNN port retains byte addressing.
// ================================================================
module Data_Memory #(
    parameter DATA_B0_FILE = "D:/_ProjectFile/Clone/RVCCC/mem_files/data_b0.mem",
    parameter DATA_B1_FILE = "D:/_ProjectFile/Clone/RVCCC/mem_files/data_b1.mem",
    parameter DATA_B2_FILE = "D:/_ProjectFile/Clone/RVCCC/mem_files/data_b2.mem",
    parameter DATA_B3_FILE = "D:/_ProjectFile/Clone/RVCCC/mem_files/data_b3.mem",
    parameter CNN_B0_FILE  = "D:/_ProjectFile/Clone/RVCCC/mem_files/cnn_b0.mem",
    parameter CNN_B1_FILE  = "D:/_ProjectFile/Clone/RVCCC/mem_files/cnn_b1.mem",
    parameter CNN_B2_FILE  = "D:/_ProjectFile/Clone/RVCCC/mem_files/cnn_b2.mem",
    parameter CNN_B3_FILE  = "D:/_ProjectFile/Clone/RVCCC/mem_files/cnn_b3.mem"
) (
    input wire clk_50MHZ,
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
        .clk(clk_50MHZ), .ena(cpu_access), .wea(cpu_byte_we[0]), .addra(cpu_word_addr),
        .dina(cpu_din0), .douta(cpu_dout0), .enb(cnn_port_en), .web(cnn_byte_we[0]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout0)
    );

    Byte_TDP_RAM #(.DATA_FILE(DATA_B1_FILE), .CNN_FILE(CNN_B1_FILE)) data_b1 (
        .clk(clk_50MHZ), .ena(cpu_access), .wea(cpu_byte_we[1]), .addra(cpu_word_addr),
        .dina(cpu_din1), .douta(cpu_dout1), .enb(cnn_port_en), .web(cnn_byte_we[1]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout1)
    );

    Byte_TDP_RAM #(.DATA_FILE(DATA_B2_FILE), .CNN_FILE(CNN_B2_FILE)) data_b2 (
        .clk(clk_50MHZ), .ena(cpu_access), .wea(cpu_byte_we[2]), .addra(cpu_word_addr),
        .dina(cpu_din2), .douta(cpu_dout2), .enb(cnn_port_en), .web(cnn_byte_we[2]),
        .addrb(cnn_word_addr), .dinb(cnn_mem_write_data), .doutb(cnn_dout2)
    );

    Byte_TDP_RAM #(.DATA_FILE(DATA_B3_FILE), .CNN_FILE(CNN_B3_FILE)) data_b3 (
        .clk(clk_50MHZ), .ena(cpu_access), .wea(cpu_byte_we[3]), .addra(cpu_word_addr),
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
module MEM_WB_Reg (
    // Inputs
    // Control Signals
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Jal_EX_MEM,
    input wire Signal_Jalr_EX_MEM,
    input wire Reg_Write_EX_MEM,
    input wire Mem_to_Reg_EX_MEM,

    // Data Signals
    input wire [4:0] rd_EX_MEM,
    input wire [31:0] ALU_Result_EX_MEM,
    input wire [31:0] Mem_Read_Data,
    input wire [31:0] Return_Addr_EX_MEM,

    // Outputs
    // Control Signals
    output reg Signal_Jal_MEM_WB,
    output reg Signal_Jalr_MEM_WB,
    output reg Reg_Write_MEM_WB,
    output reg Mem_to_Reg_MEM_WB,

    // Data Signals
    output reg [4:0] rd_MEM_WB,
    output reg [31:0] ALU_Result_MEM_WB,
    output reg [31:0] Mem_Read_Data_MEM_WB,
    output reg [31:0] Return_Addr_MEM_WB
);

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst==1) begin
            Signal_Jal_MEM_WB   <= 0;
            Signal_Jalr_MEM_WB  <= 0;
            Reg_Write_MEM_WB    <= 0;
            Mem_to_Reg_MEM_WB   <= 0;

            rd_MEM_WB           <= 0;
            ALU_Result_MEM_WB   <= 0;
            Mem_Read_Data_MEM_WB<= 0;
            Return_Addr_MEM_WB  <= 0;
        end
        else begin
            Signal_Jal_MEM_WB   <= Signal_Jal_EX_MEM;
            Signal_Jalr_MEM_WB  <= Signal_Jalr_EX_MEM;
            Reg_Write_MEM_WB    <= Reg_Write_EX_MEM;
            Mem_to_Reg_MEM_WB   <= Mem_to_Reg_EX_MEM;

            rd_MEM_WB           <= rd_EX_MEM;
            ALU_Result_MEM_WB   <= ALU_Result_EX_MEM;
            Mem_Read_Data_MEM_WB<= Mem_Read_Data;
            Return_Addr_MEM_WB  <= Return_Addr_EX_MEM;
        end
    end

endmodule

module Forwarding_Unit (
    // Inputs
    input wire Reg_Write_EX_MEM,
    input wire Reg_Write_MEM_WB,
    input wire [4:0] rd_EX_MEM,
    input wire [4:0] rd_MEM_WB,
    input wire [4:0] rs1_ID_EX,
    input wire [4:0] rs2_ID_EX,

    // Outputs
    output reg [1:0] Forward_A,
    output reg [1:0] Forward_B
);

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(*) begin
        // EX hazard
        if (Reg_Write_EX_MEM && (rd_EX_MEM != 0) && (rd_EX_MEM == rs1_ID_EX))
            Forward_A = 2'b10;
        else if (Reg_Write_MEM_WB && (rd_MEM_WB != 0) && (rd_MEM_WB == rs1_ID_EX))
            Forward_A = 2'b01;
        else
            Forward_A = 2'b00;

        // MEM hazard
        if (Reg_Write_EX_MEM && (rd_EX_MEM != 0) && (rd_EX_MEM == rs2_ID_EX))
            Forward_B = 2'b10;
        else if (Reg_Write_MEM_WB && (rd_MEM_WB != 0) && (rd_MEM_WB == rs2_ID_EX))
            Forward_B = 2'b01;
        else
            Forward_B = 2'b00;
    end

endmodule

module Hazard_Detection_Unit (
    // Inputs
    input wire rst,
    input wire Mem_Read_ID_EX,
    input wire [4:0] rd_ID_EX,
    input wire [4:0] rs1_IF_ID,
    input wire [4:0] rs2_IF_ID,

    // Outputs
    output reg Signal_Stall
);

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------    
    always @(*) begin
        if (rst==1)
            Signal_Stall = 1'b0;
        else if (Mem_Read_ID_EX && ((rd_ID_EX == rs1_IF_ID) || (rd_ID_EX == rs2_IF_ID))) begin
            Signal_Stall = 1'b1;
        end
        else begin
            Signal_Stall = 1'b0;
        end
    end

endmodule

module Branch_Table (
    // Inputs
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Branch_ID_EX,
    input wire [1:0] Addr,
    input wire [1:0] Addr_ID_EX,
    input wire [1:0] Entry,

    // Outputs
    output wire [1:0] State
);
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    reg [1:0] BranchTable[3:0];

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ) begin
        if (rst == 1) begin
            // Initialize BranchTable during rst
            BranchTable[0] <= 2'b00;
            BranchTable[1] <= 2'b00;
            BranchTable[2] <= 2'b00;
            BranchTable[3] <= 2'b00;
        end else begin
            // Write operation
            if (Signal_Branch_ID_EX == 1)
                BranchTable[Addr_ID_EX] <= Entry;
        end
    end

    assign State = BranchTable[Addr];
endmodule

module Branch_Predictor (
    // Inputs
    input wire Outcome,
    input wire Signal_Branch_ID_EX,
    input wire [1:0] State_ID_EX,

    // Outputs
    output reg [1:0] Entry,
    output wire Signal_Flush
);

    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    parameter s0=0, s1=1, s2=2, s3=3;
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    assign Signal_Flush = Signal_Branch_ID_EX && (State_ID_EX[1] ^ Outcome);
    
    always @(*) begin
        case(State_ID_EX)
        s0: Entry = Outcome ? s1 : s0;
        s1: Entry = Outcome ? s2 : s0;
        s2: Entry = Outcome ? s3 : s1;
        s3: Entry = Outcome ? s3 : s2;
        default: Entry = s0;
        endcase
    end

endmodule


module Writeback_Unit (
    // inputs
    input wire Mem_to_Reg_MEM_WB,
    input wire Signal_Jal_MEM_WB,
    input wire Signal_Jalr_MEM_WB,
    input wire [31:0] ALU_Result_MEM_WB,
    input wire [31:0] Mem_Read_Data_MEM_WB,
    input wire [31:0] Return_Addr_MEM_WB,
    
    // Outputs
    output reg [31:0] Reg_Write_Data
);
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(*) begin
        Reg_Write_Data = (Signal_Jal_MEM_WB || Signal_Jalr_MEM_WB) ? Return_Addr_MEM_WB :
                         (Mem_to_Reg_MEM_WB ? Mem_Read_Data_MEM_WB : ALU_Result_MEM_WB);
    end
    
endmodule


// ================================================================
// Old Eight_Digit_Hex_Display module (commented out)
// This module used refresh-scanning to drive 8 digit tubes via
// shared Anode_Activate and LED_out signals. Replaced by direct-
// drive logic (seg0-seg7) in the top-level pipeline_main module.
// ================================================================
/*
module Eight_Digit_Hex_Display(
    input clk_50MHZ,
    input rst,
    input [27:0] Mem_LED_in,
    input [3:0] predicted_class_LED,
    output reg [7:0] Anode_Activate,
    output reg [7:0] LED_out
);
    reg [26:0] one_second_counter;
    wire one_second_enable;
    reg [31:0] displayed_value;
    reg [3:0] LED_hex;
    reg [18:0] refresh_counter;
    wire [2:0] LED_activating_counter;

    always @(posedge clk_50MHZ or posedge rst) begin
        if (rst)
            one_second_counter <= 0;
        else begin
            if (one_second_counter >= 99999999)
                one_second_counter <= 0;
            else
                one_second_counter <= one_second_counter + 1;
        end
    end

    assign one_second_enable = (one_second_counter == 99999999) ? 1 : 0;

    always @(posedge clk_50MHZ or posedge rst) begin
        if (rst)
            displayed_value <= 0;
        else if (one_second_enable)
            displayed_value <= {predicted_class_LED, Mem_LED_in};
    end

    always @(posedge clk_50MHZ or posedge rst) begin
        if (rst)
            refresh_counter <= 0;
        else
            refresh_counter <= refresh_counter + 1;
    end

    assign LED_activating_counter = refresh_counter[18:16];

    always @(*) begin
        case (LED_activating_counter)
            3'b000: begin
                Anode_Activate = 8'b11111110;
                LED_hex = displayed_value[3:0];
            end
            3'b001: begin
                Anode_Activate = 8'b11111101;
                LED_hex = displayed_value[7:4];
            end
            3'b010: begin
                Anode_Activate = 8'b11111011;
                LED_hex = displayed_value[11:8];
            end
            3'b011: begin
                Anode_Activate = 8'b11110111;
                LED_hex = displayed_value[15:12];
            end
            3'b100: begin
                Anode_Activate = 8'b11101111;
                LED_hex = displayed_value[19:16];
            end
            3'b101: begin
                Anode_Activate = 8'b11011111;
                LED_hex = displayed_value[23:20];
            end
            3'b110: begin
                Anode_Activate = 8'b10111111;
                LED_hex = displayed_value[27:24];
            end
            3'b111: begin
                Anode_Activate = 8'b01111111;
                LED_hex = displayed_value[31:28];
            end
        endcase
    end

    always @(*) begin
        case (LED_hex)
            4'h0: LED_out = 8'b00000011; //a,b,c,d,e,f,g,dot (zero)
            4'h1: LED_out = 8'b10011111; //one
            4'h2: LED_out = 8'b00100101; //two
            4'h3: LED_out = 8'b00001101; //three
            4'h4: LED_out = 8'b10011001; //four
            4'h5: LED_out = 8'b01001001; //five
            4'h6: LED_out = 8'b01000001; //six
            4'h7: LED_out = 8'b00011111; //seven
            4'h8: LED_out = 8'b00000001; //eight
            4'h9: LED_out = 8'b00001001; //nine
            4'hA: LED_out = 8'b00010001; //A
            4'hB: LED_out = 8'b11000001; //b
            4'hC: LED_out = 8'b01100011; //C
            4'hD: LED_out = 8'b10000101; //d
            4'hE: LED_out = 8'b01100001; //E
            4'hF: LED_out = 8'b01110001; //F
            default: LED_out = 8'b00000011;
        endcase
    end
endmodule
*/


// ================================================================
// Eight_Digit_Hex_Display module (direct-drive version, commented out)
// Directly drives 8 individual digit tubes without refresh scanning.
// Bit order: ABCDEFGP (bit[7]=A, bit[6]=B, bit[5]=C, bit[4]=D,
//                      bit[3]=E, bit[2]=F, bit[1]=G, bit[0]=P)
// Active-low: 0 = segment ON, 1 = segment OFF
// ================================================================
/*
module Eight_Digit_Hex_Display(
    input [3:0] predicted_class_LED,
    input [27:0] Mem_LED_in,
    output [7:0] seg0, seg1, seg2, seg3, seg4, seg5, seg6, seg7
);
    // Concatenate predicted_class and Mem_LED_in into 32-bit display value (8 hex digits)
    wire [31:0] displayed_value;
    assign displayed_value = {predicted_class_LED, Mem_LED_in};

    // Hex digit to 7-segment decoder function (ABCDEFGP order, active-low)
    function [7:0] hex_to_7seg;
        input [3:0] hex_digit;
        begin
            case (hex_digit)
                4'h0: hex_to_7seg = 8'b00000011; // "0": A,B,C,D,E,F ON
                4'h1: hex_to_7seg = 8'b10011111; // "1": B,C ON
                4'h2: hex_to_7seg = 8'b00100101; // "2": A,B,D,E,G ON
                4'h3: hex_to_7seg = 8'b00001101; // "3": A,B,C,D,G ON
                4'h4: hex_to_7seg = 8'b10011001; // "4": B,C,F,G ON
                4'h5: hex_to_7seg = 8'b01001001; // "5": A,C,D,F,G ON
                4'h6: hex_to_7seg = 8'b01000001; // "6": A,C,D,E,F,G ON
                4'h7: hex_to_7seg = 8'b00011111; // "7": A,B,C ON
                4'h8: hex_to_7seg = 8'b00000001; // "8": A,B,C,D,E,F,G ON
                4'h9: hex_to_7seg = 8'b00001001; // "9": A,B,C,D,F,G ON
                4'hA: hex_to_7seg = 8'b00010001; // "A": A,B,C,E,F,G ON
                4'hB: hex_to_7seg = 8'b11000001; // "b": C,D,E,F,G ON
                4'hC: hex_to_7seg = 8'b01100011; // "C": A,D,E,F ON
                4'hD: hex_to_7seg = 8'b10000101; // "d": B,C,D,E,G ON
                4'hE: hex_to_7seg = 8'b01100001; // "E": A,D,E,F,G ON
                4'hF: hex_to_7seg = 8'b01110001; // "F": A,E,F,G ON
                default: hex_to_7seg = 8'b11111111; // All OFF
            endcase
        end
    endfunction

    // Drive each digit tube independently
    assign seg0 = hex_to_7seg(displayed_value[3:0]);    // Least significant hex digit
    assign seg1 = hex_to_7seg(displayed_value[7:4]);
    assign seg2 = hex_to_7seg(displayed_value[11:8]);
    assign seg3 = hex_to_7seg(displayed_value[15:12]);
    assign seg4 = hex_to_7seg(displayed_value[19:16]);
    assign seg5 = hex_to_7seg(displayed_value[23:20]);
    assign seg6 = hex_to_7seg(displayed_value[27:24]);
    assign seg7 = hex_to_7seg(displayed_value[31:28]);   // Most significant hex digit (predicted_class)

endmodule
*/


// ================================================================
// Four_LED_Binary_Display module
// Displays the predicted class as a 4-bit binary value on LEDs.
// Active-low: 0 = LED ON, 1 = LED OFF.
// ================================================================
module Four_LED_Binary_Display(
    input [3:0] predicted_class_LED,
    output [3:0] ledr
);
    assign ledr = ~predicted_class_LED;
endmodule


module cnn_core (
    input clk_20MHZ,
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
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/kernel1.mem", kernel1_rom);
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/kernel1_bias.mem", kernel1_bias_rom);
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/kernel2.mem", kernel2_rom);
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/kernel2_bias.mem", kernel2_bias_rom);
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/weights.mem", fc_weights_rom);
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/biases.mem", fc_biases_rom);
    end

    // ================================================================
    // Synchronous read and write
    // block RAM features limited read ports, so we need to divide 
    // the read operations across multiple clock cycles, otherwise 
    // vivado will use too many LUTs to implement the memory.
    // ================================================================
    always @(posedge clk_20MHZ) begin
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
    always @(posedge clk_20MHZ or posedge rst) begin
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
