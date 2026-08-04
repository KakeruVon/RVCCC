module Instruction_Memory (
    // Inputs
    input wire clk_cpu,
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
        $readmemh("instruction.mem", mem);
    end

    always @(negedge clk_cpu) begin
        Instruction <= mem[word_addr];
    end

endmodule
