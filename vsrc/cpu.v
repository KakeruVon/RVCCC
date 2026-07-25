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
    
    // Clocks
    wire clk_50MHZ;
    wire clk_20MHZ;
    // wire locked;
    
    // Flags
    wire Zero_Flag;
    wire Sign_Flag;

    //-----------------------Data Signals--------------------------
    wire [31:0] PC;                 // The current PC
    wire [31:0] Instruction;
    wire [31:0] Jump_Addr;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [3:0] ALU_Op;
    wire [31:0] RF_Out1, RF_Out2;
    wire [31:0] Imm_Value;
    wire [31:0] ALU_Result;
    wire [31:0] Mem_Read_Data;
    wire [31:0] Reg_Write_Data;
    wire [31:0] Mem_LED_out;

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
    wire Instruction_14_ID_EX;

    // EX_MEM Stage
    wire [4:0] rd_EX_MEM;
    wire [31:0] ALU_Result_EX_MEM;
    wire [31:0] RF_Out2_EX_MEM;
    wire [31:0] Return_Addr_EX_MEM;

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
    wire Signal_Branch;             // Branch
    wire Signal_Jump;               // Jump
    wire Signal_Stall;              // Stall
    wire Signal_Ecall;              // Ecall
    wire [1:0] State;               // Current state of branch predictor
    wire Outcome;
    wire [1:0] Entry;    

    // Stage Register wires
    // IF_ID Stage
    wire Signal_Branch_IF_ID;
    wire Signal_Jump_IF_ID;
    wire [1:0] State_IF_ID;
    wire [1:0] Addr_IF_ID;

    // ID_EX Stage
    wire Signal_Branch_ID_EX;
    wire Signal_Jump_ID_EX;
    wire [1:0] State_ID_EX;
    wire [1:0] Addr_ID_EX;
    wire [3:0] ALU_Op_ID_EX;
    wire Reg_Write_ID_EX;
    wire ALU_Src_ID_EX;
    wire Mem_Read_ID_EX;
    wire Mem_Write_ID_EX;
    wire Mem_to_Reg_ID_EX;

    // EX_MEM stage
    wire Signal_Jump_EX_MEM;
    wire Reg_Write_EX_MEM;
    wire Mem_Read_EX_MEM;
    wire Mem_Write_EX_MEM;
    wire Mem_to_Reg_EX_MEM;

    // MEM_WB Stage
    wire Signal_Jump_MEM_WB;
    wire Reg_Write_MEM_WB;
    wire Mem_to_Reg_MEM_WB;

    // Forwarding Unit
    wire [1:0] Forward_A;
    wire [1:0] Forward_B;

    // CNN
    wire cnn_en;
    wire [3:0] predicted_class_LED;
    

    //------------------------Parameters---------------------------
    localparam [31:0] PC_exception = 32'h1C090000;  // Address to jump to in case of exceptions


    //-------------------------------------------------------------
    // Logic Definition
    //-------------------------------------------------------------

    // Defining fields from Instructions
    assign rs1 = Instruction_IF_ID[19:15];    // Register Select 1
    assign rs2 = Instruction_IF_ID[24:20];    // Register Select 1
    assign rd = Instruction_IF_ID[11:7];      // Destination Register Select
    assign Outcome = Instruction_14_ID_EX ? (Signal_Branch_ID_EX && Sign_Flag) : (Signal_Branch_ID_EX && Zero_Flag);
    
    //-------------------------------------------------------------
    // Module Instantiation
    //-------------------------------------------------------------

    // Mux takes in PC+4, Exception Cycle intialization address or Branch Address
    
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


    PC_Module m1 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Branch(Signal_Branch),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .Signal_Jump(Signal_Jump),
        .Outcome(Outcome),
        .Signal_Stall(Signal_Stall),
        .Signal_Ecall(Signal_Ecall),
        .State(State),
        .Jump_Addr(Jump_Addr),
        .PC_ID_EX(PC_ID_EX),
        .PC(PC)
    );

    Instruction_Memory m2 (
        .Mem_Address(PC),
        .Instruction(Instruction)
    );

    Branch_Jump m3 (
        .Instruction(Instruction),
        .Signal_Branch(Signal_Branch),
        .Signal_Jump(Signal_Jump),
        .Signal_Ecall(Signal_Ecall),
        .Jump_Addr(Jump_Addr)
    );

    IF_ID_reg m4 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Flush(Signal_Flush),
        .Signal_Branch(Signal_Branch),
        .Signal_Jump(Signal_Jump),
        .Signal_Stall(Signal_Stall),
        .State(State),
        .PC(PC),
        .Instruction(Instruction),
        .Jump_Addr(Jump_Addr),
        .Signal_Branch_IF_ID(Signal_Branch_IF_ID),
        .Signal_Jump_IF_ID(Signal_Jump_IF_ID),
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
        .Imm_Value(Imm_Value),
        .cnn_en(cnn_en)
    );

    ID_EX_reg m7 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Flush(Signal_Flush),
        .Signal_Branch_IF_ID(Signal_Branch_IF_ID),
        .Signal_Jump_IF_ID(Signal_Jump_IF_ID),
        .Signal_Stall(Signal_Stall),
        .Addr_IF_ID(Addr_IF_ID),
        .State_IF_ID(State_IF_ID),
        .ALU_Op(ALU_Op),
        .Reg_Write(Reg_Write),
        .ALU_Src(ALU_Src),
        .Mem_Read(Mem_Read),
        .Mem_Write(Mem_Write),
        .Mem_to_Reg(Mem_to_Reg),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .PC_IF_ID(PC_IF_ID),
        .RF_Out1(RF_Out1),
        .RF_Out2(RF_Out2),
        .Jump_Addr_IF_ID(Jump_Addr_IF_ID),
        .Return_Addr_IF_ID(Return_Addr_IF_ID),
        .Instruction_14_IF_ID(Instruction_IF_ID[14]),
        .Imm_Value(Imm_Value),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .Signal_Jump_ID_EX(Signal_Jump_ID_EX),
        .Addr_ID_EX(Addr_ID_EX),
        .State_ID_EX(State_ID_EX),
        .ALU_Op_ID_EX(ALU_Op_ID_EX),
        .Reg_Write_ID_EX(Reg_Write_ID_EX),
        .ALU_Src_ID_EX(ALU_Src_ID_EX),
        .Mem_Read_ID_EX(Mem_Read_ID_EX),
        .Mem_Write_ID_EX(Mem_Write_ID_EX),
        .Mem_to_Reg_ID_EX(Mem_to_Reg_ID_EX),
        .rs1_ID_EX(rs1_ID_EX),
        .rs2_ID_EX(rs2_ID_EX),
        .rd_ID_EX(rd_ID_EX),
        .PC_ID_EX(PC_ID_EX),
        .RF_Out1_ID_EX(RF_Out1_ID_EX),
        .RF_Out2_ID_EX(RF_Out2_ID_EX),
        .Return_Addr_ID_EX(Return_Addr_ID_EX),
        .Instruction_14_ID_EX(Instruction_14_ID_EX),
        .Imm_Value_ID_EX(Imm_Value_ID_EX)
    );

    ALU m8 (
        .ALU_Op_ID_EX(ALU_Op_ID_EX),
        .ALU_In1_ID_EX(RF_Out1_ID_EX),     
        .ALU_In2_ID_EX(RF_Out2_ID_EX),
        .Forward_A(Forward_A),
        .Forward_B(Forward_B),
        .ALU_Src_ID_EX(ALU_Src_ID_EX),
        .ALU_Result_EX_MEM(ALU_Result_EX_MEM),
        .Reg_Write_Data_MEM_WB(Reg_Write_Data),
        .Imm_Value_ID_EX(Imm_Value_ID_EX),     
        .Zero_Flag(Zero_Flag),
        .Sign_Flag(Sign_Flag),
        .ALU_Result(ALU_Result)
    );

    EX_MEM_Reg m9 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Jump_ID_EX(Signal_Jump_ID_EX),
        .Reg_Write_ID_EX(Reg_Write_ID_EX),
        .Mem_Read_ID_EX(Mem_Read_ID_EX),
        .Mem_Write_ID_EX(Mem_Write_ID_EX),
        .Mem_to_Reg_ID_EX(Mem_to_Reg_ID_EX),
        .rd_ID_EX(rd_ID_EX),
        .ALU_Result(ALU_Result),
        .RF_Out2_ID_EX(RF_Out2_ID_EX),
        .Return_Addr_ID_EX(Return_Addr_ID_EX),
        .Signal_Jump_EX_MEM(Signal_Jump_EX_MEM),
        .Reg_Write_EX_MEM(Reg_Write_EX_MEM),
        .Mem_Read_EX_MEM(Mem_Read_EX_MEM),
        .Mem_Write_EX_MEM(Mem_Write_EX_MEM),
        .Mem_to_Reg_EX_MEM(Mem_to_Reg_EX_MEM),
        .rd_EX_MEM(rd_EX_MEM),
        .ALU_Result_EX_MEM(ALU_Result_EX_MEM),
        .RF_Out2_EX_MEM(RF_Out2_EX_MEM),
        .Return_Addr_EX_MEM(Return_Addr_EX_MEM)
    );

    Data_Memory m10 (
        .clk_50MHZ(clk_50MHZ),
        .Mem_Write_EX_MEM(Mem_Write_EX_MEM),
        .Mem_Read_EX_MEM(Mem_Read_EX_MEM),
        .Mem_Write_Data(RF_Out2_EX_MEM),
        .Mem_Address(ALU_Result_EX_MEM),
        .Mem_Read_Data(Mem_Read_Data),
        .Mem_LED_out(Mem_LED_out)
    );

    MEM_WB_Reg m11 (
        .clk_50MHZ(clk_50MHZ),
        .rst(rst),
        .Signal_Jump_EX_MEM(Signal_Jump_EX_MEM),
        .Reg_Write_EX_MEM(Reg_Write_EX_MEM),
        .Mem_to_Reg_EX_MEM(Mem_to_Reg_EX_MEM),
        .rd_EX_MEM(rd_EX_MEM),
        .ALU_Result_EX_MEM(ALU_Result_EX_MEM),
        .Mem_Read_Data(Mem_Read_Data),
        .Return_Addr_EX_MEM(Return_Addr_EX_MEM),
        .Signal_Jump_MEM_WB(Signal_Jump_MEM_WB),
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
        .State_ID_EX(State_ID_EX),
        .Entry(Entry),
        .Signal_Flush(Signal_Flush)
    );

    Writeback_Unit m16 (
        .Mem_to_Reg_MEM_WB(Mem_to_Reg_MEM_WB),
        .Signal_Jump_MEM_WB(Signal_Jump_MEM_WB),
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
    // Shows predicted_class_LED[3:0] in binary. LEDs are active-low:
    // output 0 lights the LED, output 1 turns it off.
    Four_LED_Binary_Display m17 (
        .predicted_class_LED(predicted_class_LED),
        .ledr(ledr)
    );
    
    cnn_core m18 (
        .clk_20MHZ(clk_20MHZ),
        .rst(rst),
        .cnn_en(cnn_en),
        .predicted_class_LED(predicted_class_LED)
    );

endmodule


// ================================================================
// CLK_Gen - Clock generation module
// Input:  clk_in = 100 MHz
// Output: clk_50MHZ = 50 MHz (div-by-2)
//         clk_20MHZ = 20 MHz (div-by-5)
// ================================================================
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


module PC_Module (
    // Inputs
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Branch,
    input wire Signal_Branch_ID_EX,
    input wire Signal_Jump,
    input wire Outcome,
    input wire Signal_Stall,
    input wire Signal_Ecall,
    input wire [1:0] State,
    input wire [31:0] Jump_Addr,
    input wire [31:0] PC_ID_EX,

    // Outputs
    output reg [31:0] PC
);
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    wire Prediction;
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------    
    assign Prediction = State[1];
    
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst==1) begin
            PC <= 32'h0; // rst
        end
        else if (Signal_Stall==1 || Signal_Ecall==1) begin
            PC <= PC+0; // Stall
        end
        else if (Signal_Branch_ID_EX==1 && Outcome==1) begin
            PC <= PC_ID_EX; // Hazard
        end
        else if ((Signal_Branch==1 && Prediction==1) || Signal_Jump==1) begin
            PC <= PC + Jump_Addr; // Jump
        end
        else if (Signal_Branch_ID_EX==0 || (Signal_Branch_ID_EX==1 && Outcome==0) || (Signal_Branch==1 && Prediction==0) || Signal_Branch==0 || Signal_Jump==0) begin
            PC <= PC + 4; // Normal execution
        end
    end

endmodule

module Instruction_Memory (
    // Inputs
    input wire [31:0] Mem_Address,

    // Outputs
    output reg [31:0] Instruction
);

    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    (*ram_style = "block"*) reg [7:0] mem [47:0];

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(*) begin
        Instruction = {mem[Mem_Address+3], mem[Mem_Address+2], mem[Mem_Address+1], mem[Mem_Address]};
    end
    
    initial begin
            mem[3]  = 8'h00; mem[2]  = 8'h02; mem[1]  = 8'ha3; mem[0]  = 8'h03; // lw t1,0(t0)
            mem[7]  = 8'h00; mem[6]  = 8'h42; mem[5]  = 8'h82; mem[4]  = 8'h93; // addi t0,t0,4
            mem[11] = 8'h00; mem[10] = 8'h02; mem[9]  = 8'ha3; mem[8]  = 8'h83; // lw t2,0(t0)
            mem[15] = 8'h00; mem[14] = 8'h73; mem[13] = 8'h0c; mem[12] = 8'h63; // loop: beq t1,t2,exit
            mem[19] = 8'h00; mem[18] = 8'h73; mem[17] = 8'h46; mem[16] = 8'h63; // blt t1,t2,L1
            mem[23] = 8'h40; mem[22] = 8'h73; mem[21] = 8'h03; mem[20] = 8'h33; // sub t1,t1,t2
            mem[27] = 8'hff; mem[26] = 8'h5f; mem[25] = 8'hf0; mem[24] = 8'h6f; // j loop
            mem[31] = 8'h40; mem[30] = 8'h63; mem[29] = 8'h83; mem[28] = 8'hb3; // L1: sub t2,t2,t1
            mem[35] = 8'hfe; mem[34] = 8'hdf; mem[33] = 8'hf0; mem[32] = 8'h6f; // j loop
            mem[39] = 8'h00; mem[38] = 8'h62; mem[37] = 8'ha2; mem[36] = 8'h23; // exit: sw t1,4(t0)
            // mem[43] = 8'h00; mem[42] = 8'h00; mem[41] = 8'h00; mem[40] = 8'h73; // ecall
            mem[43] = 8'hFE; mem[42] = 8'h00; mem[41] = 8'h70; mem[40] = 8'h7F; // cnn FE00707F 11111110000000000111000001111111
            mem[47] = 8'h00; mem[46] = 8'h00; mem[45] = 8'h00; mem[44] = 8'h73; // ecall
            
    end
    
endmodule

module Branch_Jump (
    // Inputs
    input wire [31:0] Instruction,

    // Outputs
    output reg Signal_Branch,
    output reg Signal_Jump,
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
        case (Opcode)
            7'b1100011: begin       // B-Type
                Signal_Branch = 1;
                Signal_Jump = 0;
                Signal_Ecall = 0;
                Jump_Addr = {{20{Instruction[31]}}, Instruction[7], Instruction[30:25], Instruction[11:8], 1'b0};      
            end

            7'b1101111: begin       // J-Type
                Signal_Branch = 0;
                Signal_Jump = 1;
                Signal_Ecall = 0;
                Jump_Addr = {{12{Instruction[31]}}, Instruction[19:12], Instruction[20], Instruction[30:21], 1'b0};    
            end

            7'b1110011: begin       // Ecall
                Signal_Branch = 0;
                Signal_Jump = 0;
                Signal_Ecall = 1;
                Jump_Addr = 32'dx;                                                  
            end

            default: begin      // Rest of the instructions
                Signal_Branch = 0;
                Signal_Jump = 0;
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
    input wire Signal_Jump,             // Jump
    input wire Signal_Stall,            // Stall
    input wire [1:0] State,             // Current state of branch predictor

    // Data Signals
    input wire [31:0] PC,       
    input wire [31:0] Instruction,
    input wire [31:0] Jump_Addr,

    // Outputs
    // Control Signals
    output reg Signal_Branch_IF_ID,
    output reg Signal_Jump_IF_ID,
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
            Signal_Jump_IF_ID   <= 0;
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
            Signal_Jump_IF_ID   <= 0;
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
            Signal_Jump_IF_ID   <= Signal_Jump;
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
    output reg Reg_Write, ALU_Src, Mem_Read, Mem_Write, Mem_to_Reg, cnn_en,
    output reg [3:0] ALU_Op,
    output reg [31:0] Imm_Value
);
    
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    wire [6:0] Opcode;
    wire [10:0] Control;

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------

    // Defining opcode and control fields
    assign Opcode = Instruction_IF_ID[6:0];
    assign Control = {Instruction_IF_ID[30], Instruction_IF_ID[14:12], Instruction_IF_ID[6:0]};

    // Control Signals decode (except ALU_Op)
    always @(*) begin
        if (Signal_Stall) begin
            Reg_Write   = 0;
            ALU_Src     = 0;
            Mem_Read    = 0;
            Mem_Write   = 0;
            Mem_to_Reg  = 0;
            Imm_Value   = 32'h00000000;
            cnn_en      = 1'b0;
        end

        else begin
            case (Opcode)
                7'b0110011:         // R-type instructions
                    begin
                        Reg_Write   = 1;
                        ALU_Src     = 0;
                        Mem_Read    = 0;
                        Mem_Write   = 0;
                        Mem_to_Reg  = 0;
                        Imm_Value   = 32'hxxxxxxxx;
                        cnn_en      = 1'b0;
                    end
                7'b0000011:         // I-type instructions (LW)
                    begin
                        Reg_Write   = 1;
                        ALU_Src     = 1;
                        Mem_Read    = 1;
                        Mem_Write   = 0;
                        Mem_to_Reg  = 1;
                        Imm_Value[31:0] = {{21{Instruction_IF_ID[31]}}, Instruction_IF_ID[30:20]};
                        cnn_en      = 1'b0;
                    end
                7'b0010011:         // I-type instructions (ADDI)
                    begin 
                        Reg_Write   = 1;
                        ALU_Src     = 1;
                        Mem_Read    = 0;
                        Mem_Write   = 0;
                        Mem_to_Reg  = 0;
                        Imm_Value[31:0] = {{21{Instruction_IF_ID[31]}}, Instruction_IF_ID[30:20]};
                        cnn_en      = 1'b0;
                    end
                7'b0100011:         // S-type instructions
                    begin 
                        Reg_Write   = 0;
                        ALU_Src     = 1;
                        Mem_Read    = 0;
                        Mem_Write   = 1;
                        Mem_to_Reg  = 1'bx;
                        Imm_Value[31:0] = {{21{Instruction_IF_ID[31]}}, Instruction_IF_ID[30:25], Instruction_IF_ID[11:7]};
                        cnn_en      = 1'b0;
                    end
                7'b1100011:         // B-types instructions
                    begin 
                        Reg_Write   = 0;
                        ALU_Src     = 0;
                        Mem_Read    = 0;
                        Mem_Write   = 0;
                        Mem_to_Reg  = 1'bx;
                        Imm_Value   = 32'hxxxxxxxx;
                        cnn_en      = 1'b0;
                    end
                7'b1101111:         // J-type instructions
                    begin 
                        Reg_Write   = 1;
                        ALU_Src     = 1'bx;
                        Mem_Read    = 0;
                        Mem_Write   = 0;
                        Mem_to_Reg  = 1'bx;
                        Imm_Value   = 32'hxxxxxxxx;
                        cnn_en      = 1'b0;
                    end
                7'b1110011:         // ecall
                    begin
                        Reg_Write   = 1'bx;
                        ALU_Src     = 1'bx;
                        Mem_Read    = 1'bx;
                        Mem_Write   = 1'b0;
                        Mem_to_Reg  = 1'bx;
                        Imm_Value   = 32'hxxxxxxxx;
                        cnn_en      = 1'b0;
                    end
                7'b1111111:         // Convo
                    begin
                        Reg_Write   = 1'bx;
                        ALU_Src     = 1'bx;
                        Mem_Read    = 1'bx;
                        Mem_Write   = 1'b0;
                        Mem_to_Reg  = 1'bx;
                        Imm_Value   = 32'hxxxxxxxx;
                        cnn_en      = 1'b1;
                    end
                default:
                    begin
                        Reg_Write   = 1'bx;
                        ALU_Src     = 1'bx;
                        Mem_Read    = 1'bx;
                        Mem_Write   = 1'bx;
                        Mem_to_Reg  = 1'bx;
                        Imm_Value   = 32'hxxxxxxxx;
                        cnn_en      = 1'bx;
                    end
            endcase
        end
    end

    // ALU_Op decode
    always @(*) begin
        if (Signal_Stall) begin
            ALU_Op = 4'b0000;
        end

        else begin
            casez (Control)
                11'b0_000_0110011: ALU_Op = 4'b0000; //add
                11'b1_000_0110011: ALU_Op = 4'b0001; //sub
                11'b0_001_0110011: ALU_Op = 4'b0010; //sll
                11'b0_101_0110011: ALU_Op = 4'b0011; //srl
                11'b0_010_0110011: ALU_Op = 4'b0100; //slt
                11'b?_000_0010011: ALU_Op = 4'b0000; //addi
                11'b0_110_0110011: ALU_Op = 4'b0101; //or
                11'b0_111_0110011: ALU_Op = 4'b0110; //and
                11'b?_010_0000011: ALU_Op = 4'b0000; //lw
                11'b?_010_0100011: ALU_Op = 4'b0000; //sw
                11'b?_000_1100011: ALU_Op = 4'b0001; //beq
                11'b?_100_1100011: ALU_Op = 4'b0001; //blt
                11'b?_???_1101111: ALU_Op = 4'bxxxx; //jal
                11'b0_000_1110011: ALU_Op = 4'bxxxx; //ecall
                default: ALU_Op = 4'bxxxx;
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
    input wire Signal_Jump_IF_ID,       // Jump
    input wire Signal_Stall,            // Stall
    input wire [1:0] Addr_IF_ID,
    input wire [1:0] State_IF_ID,
    input wire [3:0] ALU_Op,
    input wire Reg_Write,
    input wire ALU_Src,
    input wire Mem_Read,
    input wire Mem_Write,
    input wire Mem_to_Reg,

    // Data Signals
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [4:0] rd,

    input wire [31:0] PC_IF_ID,
    input wire [31:0] RF_Out1,
    input wire [31:0] RF_Out2,
    input wire [31:0] Jump_Addr_IF_ID,
    input wire [31:0] Return_Addr_IF_ID,
    input wire Instruction_14_IF_ID,
    input wire [31:0] Imm_Value,

    // Outputs
    // Control Signals
    output reg Signal_Branch_ID_EX,
    output reg Signal_Jump_ID_EX,
    output reg [1:0] Addr_ID_EX,
    output reg [1:0] State_ID_EX,
    output reg [3:0] ALU_Op_ID_EX,
    output reg Reg_Write_ID_EX,
    output reg ALU_Src_ID_EX,
    output reg Mem_Read_ID_EX,
    output reg Mem_Write_ID_EX,
    output reg Mem_to_Reg_ID_EX,

    // Data Signals
    output reg [4:0] rs1_ID_EX,
    output reg [4:0] rs2_ID_EX,
    output reg [4:0] rd_ID_EX,

    output reg [31:0] PC_ID_EX,
    output reg [31:0] RF_Out1_ID_EX,
    output reg [31:0] RF_Out2_ID_EX,
    output reg [31:0] Return_Addr_ID_EX,
    output reg Instruction_14_ID_EX,
    output reg [31:0] Imm_Value_ID_EX
);

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst == 1) begin
            // Control Signals
            Signal_Branch_ID_EX <= 0;
            Signal_Jump_ID_EX   <= 0;
            Addr_ID_EX          <= 0;
            State_ID_EX         <= 0;
            ALU_Op_ID_EX        <= 0;
            Reg_Write_ID_EX     <= 0;
            ALU_Src_ID_EX       <= 0;
            Mem_Read_ID_EX      <= 0;
            Mem_Write_ID_EX     <= 0;
            Mem_to_Reg_ID_EX    <= 0;

            // Data Signals
            rs1_ID_EX           <= 0;
            rs2_ID_EX           <= 0;
            rd_ID_EX            <= 0;

            PC_ID_EX            <= 0;
            RF_Out1_ID_EX       <= 0;
            RF_Out2_ID_EX       <= 0;
            Return_Addr_ID_EX   <= 0;
            Instruction_14_ID_EX<= 0;
            Imm_Value_ID_EX     <= 0;
        end

        else if (Signal_Flush==1) begin
            // Control Signals
            Signal_Branch_ID_EX <= 0;
            Signal_Jump_ID_EX   <= 0;
            Addr_ID_EX          <= 0;
            State_ID_EX         <= 0;
            ALU_Op_ID_EX        <= 0;
            Reg_Write_ID_EX     <= 0;
            ALU_Src_ID_EX       <= 0;
            Mem_Read_ID_EX      <= 0;
            Mem_Write_ID_EX     <= 0;
            Mem_to_Reg_ID_EX    <= 0;

            // Data Signals
            rs1_ID_EX           <= 0;
            rs2_ID_EX           <= 0;
            rd_ID_EX            <= 0;

            PC_ID_EX            <= 0;
            RF_Out1_ID_EX       <= 0;
            RF_Out2_ID_EX       <= 0;
            Return_Addr_ID_EX   <= 0;
            Instruction_14_ID_EX<= 0;
            Imm_Value_ID_EX     <= 0;
        end

        else if (Signal_Stall==1) begin
            // Control Signals
            Signal_Branch_ID_EX <= 0;
            Signal_Jump_ID_EX   <= 0;
            Addr_ID_EX          <= 0;
            State_ID_EX         <= 0;
            ALU_Op_ID_EX        <= 0;
            Reg_Write_ID_EX     <= 0;
            ALU_Src_ID_EX       <= 0;
            Mem_Read_ID_EX      <= 0;
            Mem_Write_ID_EX     <= 0;
            Mem_to_Reg_ID_EX    <= 0;

            // Data Signals
            rs1_ID_EX           <= rs1_ID_EX;
            rs2_ID_EX           <= rs2_ID_EX;
            rd_ID_EX            <= rd_ID_EX;

            PC_ID_EX            <= PC_ID_EX;
            RF_Out1_ID_EX       <= RF_Out1_ID_EX;
            RF_Out2_ID_EX       <= RF_Out2_ID_EX;
            Return_Addr_ID_EX   <= Return_Addr_ID_EX;
            Instruction_14_ID_EX<= Instruction_14_ID_EX;
            Imm_Value_ID_EX     <= Imm_Value_ID_EX;
        end
        
        else begin
            // Control Signals
            Signal_Branch_ID_EX <= Signal_Branch_IF_ID;
            Signal_Jump_ID_EX   <= Signal_Jump_IF_ID;
            Addr_ID_EX          <= Addr_IF_ID;
            State_ID_EX         <= State_IF_ID;
            ALU_Op_ID_EX        <= ALU_Op;
            Reg_Write_ID_EX     <= Reg_Write;
            ALU_Src_ID_EX       <= ALU_Src;
            Mem_Read_ID_EX      <= Mem_Read;
            Mem_Write_ID_EX     <= Mem_Write;
            Mem_to_Reg_ID_EX    <= Mem_to_Reg;

            // Data Signals
            rs1_ID_EX           <= rs1;
            rs2_ID_EX           <= rs2;
            rd_ID_EX            <= rd;

            PC_ID_EX            <= PC_IF_ID + Jump_Addr_IF_ID;
            RF_Out1_ID_EX       <= RF_Out1;
            RF_Out2_ID_EX       <= RF_Out2;
            Return_Addr_ID_EX   <= Return_Addr_IF_ID;
            Instruction_14_ID_EX<= Instruction_14_IF_ID;
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
    input wire [31:0] ALU_Result_EX_MEM, Reg_Write_Data_MEM_WB,
    input wire [31:0] Imm_Value_ID_EX,

    // Outputs
    output reg Zero_Flag, Sign_Flag,
    output reg [31:0] ALU_Result
);

    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------

    wire [31:0] ALU_In1, ALU_In2;
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------

    assign ALU_In1 = (Forward_A == 2'b00) ? ALU_In1_ID_EX :
                     (Forward_A == 2'b01) ? Reg_Write_Data_MEM_WB :
                     (Forward_A == 2'b10) ? ALU_Result_EX_MEM :
                     ALU_In1_ID_EX;

    assign ALU_In2 = ALU_Src_ID_EX ? Imm_Value_ID_EX :((Forward_B == 2'b00) ? ALU_In2_ID_EX :
                                                       (Forward_B == 2'b01) ? Reg_Write_Data_MEM_WB :
                                                       (Forward_B == 2'b10) ? ALU_Result_EX_MEM : ALU_In2_ID_EX);

     

    always @(*) begin
        case (ALU_Op_ID_EX)
            4'b0000: ALU_Result = ALU_In1 + ALU_In2;              //add, addi, lw, sw
            4'b0001: ALU_Result = ALU_In1 - ALU_In2;              //sub, beq, blt
            4'b0010: ALU_Result = ALU_In1 << ALU_In2[4:0];        //sll
            4'b0011: ALU_Result = ALU_In1 >> ALU_In2[4:0];        //srl
            4'b0100: ALU_Result = (ALU_In1 < ALU_In2) ? 1 : 0;    //slt
            4'b0101: ALU_Result = ALU_In1 | ALU_In2;              //or
            4'b0110: ALU_Result = ALU_In1 & ALU_In2;              //and
            default: ALU_Result = 32'h00000000;
        endcase
    end

    always @(ALU_Result) begin
        if (ALU_Result==0) begin
            Zero_Flag = 1;
            Sign_Flag = 0;
        end

        else if (ALU_Result[31]==1) begin
            Zero_Flag = 0;
            Sign_Flag = 1;
        end

        else begin 
            Zero_Flag = 0;
            Sign_Flag = 0;
        end
    end
endmodule 

module EX_MEM_Reg (
    // Inputs
    // Control Signals
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Jump_ID_EX,
    input wire Reg_Write_ID_EX,
    input wire Mem_Read_ID_EX,
    input wire Mem_Write_ID_EX,
    input wire Mem_to_Reg_ID_EX,

    // Data Signals
    input wire [4:0]  rd_ID_EX,
    input wire [31:0] ALU_Result,
    input wire [31:0] RF_Out2_ID_EX,
    input wire [31:0] Return_Addr_ID_EX,

    // Outputs
    // Control Signals
    output reg Signal_Jump_EX_MEM,
    output reg Reg_Write_EX_MEM,
    output reg Mem_Read_EX_MEM,
    output reg Mem_Write_EX_MEM,
    output reg Mem_to_Reg_EX_MEM,

    // Data Signals
    output reg [4:0] rd_EX_MEM,
    output reg [31:0] ALU_Result_EX_MEM,
    output reg [31:0] RF_Out2_EX_MEM,
    output reg [31:0] Return_Addr_EX_MEM
);
    
    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    always @(posedge clk_50MHZ, posedge rst) begin
        if (rst==1) begin

            // Control Signals
            Signal_Jump_EX_MEM  <= 0;
            Reg_Write_EX_MEM    <= 0;
            Mem_Read_EX_MEM     <= 0;
            Mem_Write_EX_MEM    <= 0;
            Mem_to_Reg_EX_MEM   <= 0;

            // Data Signals
            rd_EX_MEM           <= 0;
            ALU_Result_EX_MEM   <= 0;
            RF_Out2_EX_MEM      <= 0;
            Return_Addr_EX_MEM  <= 0;
        end

        else begin

            // Control Signals
            Signal_Jump_EX_MEM  <= Signal_Jump_ID_EX;
            Reg_Write_EX_MEM    <= Reg_Write_ID_EX;
            Mem_Read_EX_MEM     <= Mem_Read_ID_EX;
            Mem_Write_EX_MEM    <= Mem_Write_ID_EX;
            Mem_to_Reg_EX_MEM   <= Mem_to_Reg_ID_EX;

            // Data Signals
            rd_EX_MEM           <= rd_ID_EX;
            ALU_Result_EX_MEM   <= ALU_Result;
            RF_Out2_EX_MEM      <= RF_Out2_ID_EX;
            Return_Addr_EX_MEM  <= Return_Addr_ID_EX;
        end
    end

endmodule

module Data_Memory (
    // Inputs
    input wire clk_50MHZ,
    input wire Mem_Write_EX_MEM,
    input wire Mem_Read_EX_MEM,

    input wire [31:0] Mem_Write_Data,
    input wire [31:0] Mem_Address, // Limit the size of Mem_Address to 5 bits

    // Outputs
    output reg [31:0] Mem_Read_Data,
    output [31:0] Mem_LED_out
);
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    reg [7:0] mem [19:0];

    //-------------------------------------------------------------
    // Functionality
    //-------------------------------------------------------------
    
    initial begin
            mem[3]  = 0; mem[2]  = 0; mem[1]  = 0; mem[0]  = 15; 
            mem[7]  = 0; mem[6]  = 0; mem[5]  = 0; mem[4]  = 6; 
            mem[11] = 0; mem[10] = 0; mem[9]  = 0; mem[8]  = 0;
            mem[15] = 0; mem[14] = 0; mem[13] = 0; mem[12] = 0;
            mem[19] = 0; mem[18] = 0; mem[17] = 0; mem[16] = 0;
    end
    
    assign Mem_LED_out = {mem[11], mem[10], mem[9],  mem[8]};

    always @(negedge clk_50MHZ) begin
        // Write operation
            if (Mem_Write_EX_MEM == 1) begin
                mem[Mem_Address]    <= Mem_Write_Data[7:0];
                mem[Mem_Address+1]  <= Mem_Write_Data[15:8];
                mem[Mem_Address+2]  <= Mem_Write_Data[23:16];
                mem[Mem_Address+3]  <= Mem_Write_Data[31:24];
            end
            // Read operation
            else if (Mem_Read_EX_MEM == 1) begin
                Mem_Read_Data <= {mem[Mem_Address+3], mem[Mem_Address+2], mem[Mem_Address+1], mem[Mem_Address]};
            end
            // Default value
            else begin
                Mem_Read_Data <= 32'd0;
            end
        end

endmodule

module MEM_WB_Reg (
    // Inputs
    // Control Signals
    input wire clk_50MHZ,
    input wire rst,
    input wire Signal_Jump_EX_MEM,
    input wire Reg_Write_EX_MEM,
    input wire Mem_to_Reg_EX_MEM,

    // Data Signals
    input wire [4:0] rd_EX_MEM,
    input wire [31:0] ALU_Result_EX_MEM,
    input wire [31:0] Mem_Read_Data,
    input wire [31:0] Return_Addr_EX_MEM,

    // Outputs
    // Control Signals
    output reg Signal_Jump_MEM_WB,
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

            // Control Signals
            Signal_Jump_MEM_WB  <= 0;
            Reg_Write_MEM_WB    <= 0;
            Mem_to_Reg_MEM_WB   <= 0;

            // Data Signals
            rd_MEM_WB           <= 0;
            ALU_Result_MEM_WB   <= 0;
            Mem_Read_Data_MEM_WB<= 0;
            Return_Addr_MEM_WB  <= 0;
        end

        else begin
            
            // Control Signals
            Signal_Jump_MEM_WB  <= Signal_Jump_EX_MEM;
            Reg_Write_MEM_WB    <= Reg_Write_EX_MEM;
            Mem_to_Reg_MEM_WB   <= Mem_to_Reg_EX_MEM;

            // Data Signals
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
    assign Signal_Flush = State_ID_EX[1] ^ Outcome; // Assigning Flush
    
    always @(*) begin
        case(State_ID_EX)
        s0: Entry = Outcome ? s1 : s0;
        s1: Entry = Outcome ? s2 : s0;
        s2: Entry = Outcome ? s3 : s1;
        s3: Entry = Outcome ? s3 : s2;
        endcase
    end

endmodule


module Writeback_Unit (
    // inputs
    input wire Mem_to_Reg_MEM_WB,
    input wire Signal_Jump_MEM_WB,
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
        Reg_Write_Data = Signal_Jump_MEM_WB ? Return_Addr_MEM_WB : (Mem_to_Reg_MEM_WB ? Mem_Read_Data_MEM_WB : ALU_Result_MEM_WB);
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
    input cnn_en,
    output reg [3:0] predicted_class_LED
);

    wire cnn_en_int;

    clock_cycle_counter t1(
        .clk_20MHZ(clk_20MHZ),
        .cnn_en(cnn_en),
        .cnn_en_int(cnn_en_int)
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

    // ================================================================
    // Shared memory for CNN weights, biases, and intermediate results
    // Use block RAM to reduce LUT and MUX usage.
    // ================================================================
    (* rom_style = "block" *) reg [7:0] image_rom [0:1023];
    (* rom_style = "block" *) reg signed [15:0] kernel1_rom [0:8];
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
    reg [7:0] pool1_addr;
    reg [5:0] pool2_addr;
    reg [8:0] fc_weight_addr;
    reg [3:0] fc_bias_addr;

    reg [7:0] image_dout;
    reg signed [15:0] kernel1_dout;
    reg signed [31:0] kernel1_bias_dout;
    reg signed [15:0] kernel2_dout;
    reg signed [31:0] kernel2_bias_dout;
    reg signed [31:0] pool1_dout;
    reg signed [31:0] pool2_dout;
    reg signed [15:0] fc_weight_dout;
    reg signed [31:0] fc_bias_dout;

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
    assign mac_operand_a = (state == S_C1_ACCUM) ? $signed({24'd0, image_dout}) :
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
        $readmemh("D:/_ProjectFile/Clone/RVCCC/mem_files/cnn.mem", image_rom);
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
        image_dout <= image_rom[image_addr];
        kernel1_dout <= kernel1_rom[kernel1_addr];
        kernel1_bias_dout <= kernel1_bias_rom[0];
        kernel2_dout <= kernel2_rom[kernel2_addr];
        kernel2_bias_dout <= kernel2_bias_rom[0];
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
    // FSM for CNN processing
    // Given that the inference process is not an actual pipeline, 
    // we can use an FSM to control a sequential operation instead of a parallel one.
    // ================================================================
    always @(posedge clk_20MHZ or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            predicted_class_LED <= 0;
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
                    if (cnn_en_int) begin
                        predicted_class_LED <= 0;
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
                            predicted_class_LED <= arg_idx;
                    end else if (arg_idx == 9) begin
                        predicted_class_LED <= best_idx;
                    end

                    if (arg_idx == 9) begin
                        state <= S_DONE;
                    end else begin
                        arg_idx <= arg_idx + 1;
                    end
                end

                S_DONE: begin
                    predicted_class_LED <= predicted_class_LED;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule

module clock_cycle_counter(
    input clk_20MHZ,
    input cnn_en,
    output reg cnn_en_int
);

    parameter TARGET_CYCLES = 30000; // Shared-MAC CNN latency guard at 20 MHz

    reg [15:0] counter; // 4-bit counter to count clock cycles

    always @(posedge clk_20MHZ or posedge cnn_en) begin
        if (cnn_en) begin
            counter <= 0;
            cnn_en_int <= 1;
        end else begin
            if (counter == TARGET_CYCLES - 1) begin
                counter <= 0;
                cnn_en_int <= 0;
            end else begin
                counter <= counter + 1;
                cnn_en_int <= cnn_en_int;
            end
        end
    end

endmodule