module PC_Module (
    // Inputs
    input wire clk_cpu,
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
    
    initial begin
        PC = 32'h0;
    end
    
    always @(posedge clk_cpu, posedge rst) begin
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
    input wire clk_cpu,
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
    always @(posedge clk_cpu, posedge rst) begin
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
    input wire clk_cpu,
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
        
    always @(negedge clk_cpu, posedge rst) begin
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
    input wire clk_cpu,
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
    always @(posedge clk_cpu, posedge rst) begin
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
    input wire clk_cpu,
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
    always @(posedge clk_cpu, posedge rst) begin
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

module MEM_WB_Reg (
    // Inputs
    // Control Signals
    input wire clk_cpu,
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
    always @(posedge clk_cpu, posedge rst) begin
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
    input wire clk_cpu,
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
    always @(posedge clk_cpu) begin
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
