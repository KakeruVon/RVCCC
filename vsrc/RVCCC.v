/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
module RVCCC (
    input clk, sysrst,
    // ---- Old scanning display outputs (commented out) ----
    // output [7:0] Anode_Activate,
    // output [7:0] LED_out
    // ---- Second direct-drive display outputs (commented out) ----
    // output [7:0] seg0, seg1, seg2, seg3, seg4, seg5, seg6, seg7
    // ---- New 4-LED binary output (active-low) ----
    output [3:0] ledr,
    output uart_tx,
    input uart_rx
);
    //-------------------------------------------------------------
    // Registers / Wires
    //-------------------------------------------------------------
    
    // Reset
    wire rst;
    assign rst = ~sysrst;
    
    // Clock signals
    wire clk_cpu;
    wire clk_cnn;
    
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
    wire uart_tx_valid;
    wire [7:0] uart_tx_data;
    wire uart_tx_busy;
    wire uart_rx_valid;
    wire [7:0] uart_rx_data;
    

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

    CLK_Gen clk_generation_inst (
        // Clock out ports
        .clk_cpu(clk_cpu),     // output clk_cpu
        .clk_cnn(clk_cnn),     // output clk_cnn
        // Status and control signals
        .rst(rst), // input reset
        // .locked(locked),       // output locked
        // Clock in ports
        .clk_in(clk)      // input clk_in
    );

    // Mux takes in PC+4, Exception Cycle intialization address or Branch Address
    PC_Module pc_inst (
        .clk_cpu(clk_cpu),
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

    Instruction_Memory instruction_memory_inst (
        .clk_cpu(clk_cpu),
        .Mem_Address(PC),
        .Instruction(Instruction)
    );

    Branch_Jump branch_jump_inst (
        .Instruction(Instruction),
        .Signal_Branch(Signal_Branch),
        .Signal_Jal(Signal_Jal),
        .Signal_Jalr(Signal_Jalr),
        .Signal_Ecall(Signal_Ecall),
        .Jump_Addr(Jump_Addr)
    );

    IF_ID_reg if_id_reg_inst (
        .clk_cpu(clk_cpu),
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

    Register_File register_file_inst (
        .clk_cpu(clk_cpu),
        .rst(rst),
        .Reg_Write(Reg_Write_MEM_WB),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd_MEM_WB),
        .Reg_Write_Data(Reg_Write_Data),
        .RD_Data1_ID_EX(RF_Out1),
        .RD_Data2_ID_EX(RF_Out2)
    );

    Control_Unit control_unit_inst (
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

    ID_EX_reg id_ex_reg_inst (
        .clk_cpu(clk_cpu),
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

    ALU alu_inst (
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

    EX_MEM_Reg ex_mem_reg_inst (
        .clk_cpu(clk_cpu),
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

    Data_Memory data_memory_inst (
        .clk_cpu(clk_cpu),
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

    Mapped_IO mapped_io_inst (
        .clk_cpu(clk_cpu),
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
        .led_value(led_value),
        .uart_tx_busy(uart_tx_busy),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data),
        .uart_tx_valid(uart_tx_valid),
        .uart_tx_data(uart_tx_data)
    );

    MEM_WB_Reg mem_wb_reg_inst (
        .clk_cpu(clk_cpu),
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

    Forwarding_Unit forwarding_unit_inst (
        .Reg_Write_EX_MEM(Reg_Write_EX_MEM),
        .Reg_Write_MEM_WB(Reg_Write_MEM_WB),
        .rd_EX_MEM(rd_EX_MEM),
        .rd_MEM_WB(rd_MEM_WB),
        .rs1_ID_EX(rs1_ID_EX),
        .rs2_ID_EX(rs2_ID_EX),
        .Forward_A(Forward_A),
        .Forward_B(Forward_B)
    );

    Hazard_Detection_Unit hazard_detection_unit_inst (
        .rst(rst),
        .Mem_Read_ID_EX(Mem_Read_ID_EX),
        .rd_ID_EX(rd_ID_EX),
        .rs1_IF_ID(rs1),
        .rs2_IF_ID(rs2),
        .Signal_Stall(Signal_Stall)
    );

    Branch_Table branch_table_inst (
        .clk_cpu(clk_cpu),
        .rst(rst),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .Addr(PC[4:3]),
        .Addr_ID_EX(Addr_ID_EX),
        .Entry(Entry),
        .State(State)
    );

    Branch_Predictor branch_predictor_inst(
        .Outcome(Outcome),
        .Signal_Branch_ID_EX(Signal_Branch_ID_EX),
        .State_ID_EX(State_ID_EX),
        .Entry(Entry),
        .Signal_Flush(Signal_Flush)
    );

    Writeback_Unit writeback_unit_inst (
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
    Eight_Digit_Hex_Display eight_digit_hex_display_inst (
        .clk_cpu(clk_cpu),
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
    Eight_Digit_Hex_Display eight_digit_hex_display_inst (
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
    Four_LED_Binary_Display four_led_binary_display_inst (
        .predicted_class_LED(led_value),
        .ledr(ledr)
    );

    uart_top uart_inst (
        .clk(clk_cpu),
        .rst(rst),
        .tx_valid(uart_tx_valid),
        .tx_data(uart_tx_data),
        .tx_busy(uart_tx_busy),
        .tx(uart_tx),
        .rx(uart_rx),
        .rx_valid(uart_rx_valid),
        .rx_data(uart_rx_data)
    );
    
    cnn_core cnn_core_inst (
        .clk_cnn(clk_cnn),
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
