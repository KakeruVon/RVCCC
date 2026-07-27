`timescale 1ns / 1ps

module cpu_rv32i_tb;
    reg clk = 1'b0;
    reg sysrst = 1'b0;
    wire [3:0] ledr;
    integer i;
    integer failures = 0;

    cpu uut (
        .clk(clk),
        .sysrst(sysrst),
        .ledr(ledr)
    );

    always #5 clk = ~clk;



    function [31:0] rtype;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin rtype = {funct7, rs2, rs1, funct3, rd, 7'b0110011}; end
    endfunction

    function [31:0] itype;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin itype = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function [31:0] stype;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin stype = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011}; end
    endfunction

    function [31:0] btype;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin btype = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 7'b1100011}; end
    endfunction

    function [31:0] utype;
        input [19:0] imm;
        input [4:0] rd;
        input [6:0] opcode;
        begin utype = {imm, rd, opcode}; end
    endfunction

    function [31:0] jtype;
        input [20:0] imm;
        input [4:0] rd;
        begin jtype = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111}; end
    endfunction

    task expect_reg;
        input [4:0] reg_index;
        input [31:0] expected;
        begin
            if (uut.m5.Reg_Mem[reg_index] !== expected) begin
                $display("FAIL x%0d: expected %h, got %h", reg_index, expected, uut.m5.Reg_Mem[reg_index]);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        #1;
        for (i = 0; i < 256; i = i + 1)
            uut.m2.mem[i] = 32'h00000013;
        for (i = 0; i < 1024; i = i + 1) begin
            uut.m10.data_b0.ram[i] = 8'd0;
            uut.m10.data_b1.ram[i] = 8'd0;
            uut.m10.data_b2.ram[i] = 8'd0;
            uut.m10.data_b3.ram[i] = 8'd0;
        end

        // Integer ALU operations.
        uut.m2.mem[0]  = itype(12'd5,  5'd0, 3'b000, 5'd1,  7'b0010011); // addi x1, x0, 5
        uut.m2.mem[1]  = itype(-12'sd3,5'd0, 3'b000, 5'd2,  7'b0010011); // addi x2, x0, -3
        uut.m2.mem[2]  = rtype(7'b0,   5'd1, 5'd1, 3'b000, 5'd3);         // add x3, x1, x1
        uut.m2.mem[3]  = rtype(7'b0100000,5'd1,5'd3,3'b000,5'd4);          // sub x4, x3, x1
        uut.m2.mem[4]  = rtype(7'b0,   5'd1, 5'd1, 3'b001, 5'd31);         // sll x5, x1, x1
        uut.m2.mem[5]  = rtype(7'b0,   5'd1, 5'd2, 3'b010, 5'd6);         // slt x6, x2, x1
        uut.m2.mem[6]  = rtype(7'b0,   5'd1, 5'd2, 3'b011, 5'd7);         // sltu x7, x2, x1
        uut.m2.mem[7]  = rtype(7'b0,   5'd4, 5'd1, 3'b100, 5'd8);         // xor x8, x1, x4
        uut.m2.mem[8]  = rtype(7'b0,   5'd2, 5'd1, 3'b110, 5'd9);         // or x9, x1, x2
        uut.m2.mem[9]  = rtype(7'b0,   5'd2, 5'd1, 3'b111, 5'd10);        // and x10, x1, x2
        uut.m2.mem[10] = rtype(7'b0,   5'd1, 5'd9, 3'b101, 5'd11);        // srl x11, x9, x1
        uut.m2.mem[11] = rtype(7'b0100000,5'd1,5'd9,3'b101,5'd12);         // sra x12, x9, x1
        uut.m2.mem[12] = itype(12'd0,  5'd2, 3'b010, 5'd13, 7'b0010011); // slti x13, x2, 0
        uut.m2.mem[13] = itype(12'd1,  5'd2, 3'b011, 5'd14, 7'b0010011); // sltiu x14, x2, 1
        uut.m2.mem[14] = itype(12'd6,  5'd1, 3'b100, 5'd15, 7'b0010011); // xori x15, x1, 6
        uut.m2.mem[15] = itype(12'd8,  5'd1, 3'b110, 5'd16, 7'b0010011); // ori x16, x1, 8
        uut.m2.mem[16] = itype(12'd7,  5'd9, 3'b111, 5'd17, 7'b0010011); // andi x17, x9, 7
        uut.m2.mem[17] = itype(12'd3,  5'd1, 3'b001, 5'd18, 7'b0010011); // slli x18, x1, 3
        uut.m2.mem[18] = itype(12'd2,  5'd9, 3'b101, 5'd19, 7'b0010011); // srli x19, x9, 2
        uut.m2.mem[19] = itype(12'b010000000010,5'd9,3'b101,5'd20,7'b0010011); // srai x20, x9, 2
        uut.m2.mem[20] = utype(20'h12345,5'd21,7'b0110111);               // lui x21, 0x12345
        uut.m2.mem[21] = utype(20'h00000,5'd22,7'b0010111);               // auipc x22, 0

        // Byte, halfword, and word stores/loads.
        uut.m2.mem[22] = itype(12'd128, 5'd0, 3'b000, 5'd23, 7'b0010011); // addi x23, x0, 128
        uut.m2.mem[23] = itype(-12'sd128,5'd0,3'b000,5'd24, 7'b0010011); // addi x24, x0, -128
        uut.m2.mem[24] = stype(12'd0,   5'd24,5'd23,3'b000);              // sb x24, 0(x23)
        uut.m2.mem[25] = stype(12'd2,   5'd24,5'd23,3'b001);              // sh x24, 2(x23)
        uut.m2.mem[26] = utype(20'h11223,5'd25,7'b0110111);               // lui x25, 0x11223
        uut.m2.mem[27] = itype(12'h344, 5'd25,3'b000,5'd25,7'b0010011);  // addi x25, x25, 0x344
        uut.m2.mem[28] = stype(12'd4,   5'd25,5'd23,3'b010);              // sw x25, 4(x23)
        uut.m2.mem[29] = itype(12'd0,   5'd23,3'b000,5'd26,7'b0000011);  // lb x26, 0(x23)
        uut.m2.mem[30] = itype(12'd0,   5'd23,3'b100,5'd27,7'b0000011);  // lbu x27, 0(x23)
        uut.m2.mem[31] = itype(12'd2,   5'd23,3'b001,5'd28,7'b0000011);  // lh x28, 2(x23)
        uut.m2.mem[32] = itype(12'd2,   5'd23,3'b101,5'd29,7'b0000011);  // lhu x29, 2(x23)
        uut.m2.mem[33] = itype(12'd4,   5'd23,3'b010,5'd30,7'b0000011);  // lw x30, 4(x23)

        // All six conditional branch comparisons.
        uut.m2.mem[34] = itype(12'd0,  5'd0, 3'b000, 5'd3, 7'b0010011); // addi x3, x0, 0
        uut.m2.mem[35] = btype(13'd8,  5'd2, 5'd1, 3'b000);              // beq x1, x2, +8 (not taken)
        uut.m2.mem[36] = itype(12'd1,  5'd3, 3'b000, 5'd3, 7'b0010011); // addi x3, x3, 1
        uut.m2.mem[37] = btype(13'd8,  5'd2, 5'd1, 3'b001);              // bne x1, x2, +8
        uut.m2.mem[38] = itype(12'd2,  5'd3, 3'b000, 5'd3, 7'b0010011); // skipped
        uut.m2.mem[39] = btype(13'd8,  5'd1, 5'd2, 3'b100);              // blt x2, x1, +8
        uut.m2.mem[40] = itype(12'd4,  5'd3, 3'b000, 5'd3, 7'b0010011); // skipped
        uut.m2.mem[41] = btype(13'd8,  5'd2, 5'd1, 3'b101);              // bge x1, x2, +8
        uut.m2.mem[42] = itype(12'd8,  5'd3, 3'b000, 5'd3, 7'b0010011); // skipped
        uut.m2.mem[43] = btype(13'd8,  5'd2, 5'd1, 3'b110);              // bltu x1, x2, +8
        uut.m2.mem[44] = itype(12'd16, 5'd3, 3'b000, 5'd3, 7'b0010011); // skipped
        uut.m2.mem[45] = btype(13'd8,  5'd1, 5'd2, 3'b111);              // bgeu x2, x1, +8
        uut.m2.mem[46] = itype(12'd32, 5'd3, 3'b000, 5'd3, 7'b0010011); // skipped

        // Direct and register-indirect jumps.
        uut.m2.mem[47] = jtype(21'd8, 5'd4);                             // jal x4, +8
        uut.m2.mem[48] = itype(12'd64, 5'd3, 3'b000, 5'd3, 7'b0010011); // skipped
        uut.m2.mem[49] = itype(12'd0,  5'd4, 3'b000, 5'd5, 7'b0010011); // addi x5, x4, 0
        uut.m2.mem[50] = itype(12'd212,5'd0,3'b000,5'd6, 7'b0010011);   // target address
        uut.m2.mem[51] = itype(12'd0,  5'd6, 3'b000,5'd7, 7'b1100111); // jalr x7, 0(x6)
        uut.m2.mem[52] = itype(12'd128,5'd3,3'b000,5'd3, 7'b0010011);  // skipped
        uut.m2.mem[53] = itype(12'd0,  5'd7, 3'b000,5'd8, 7'b0010011); // addi x8, x7, 0
        uut.m2.mem[54] = 32'h00000073;                                  // ecall

        #12 sysrst = 1'b1;
        repeat (220) @(posedge clk);
        #1;

        expect_reg(5'd1,  32'd5);
        expect_reg(5'd2,  32'hffff_fffd);
        expect_reg(5'd31, 32'd160);
        expect_reg(5'd6,  32'd212);
        expect_reg(5'd7,  32'd208);
        expect_reg(5'd9,  32'hffff_fffd);
        expect_reg(5'd10, 32'd5);
        expect_reg(5'd11, 32'h07ff_ffff);
        expect_reg(5'd12, 32'hffff_ffff);
        expect_reg(5'd13, 32'd1);
        expect_reg(5'd14, 32'd0);
        expect_reg(5'd15, 32'd3);
        expect_reg(5'd16, 32'd13);
        expect_reg(5'd17, 32'd5);
        expect_reg(5'd18, 32'd40);
        expect_reg(5'd19, 32'h3fff_ffff);
        expect_reg(5'd20, 32'hffff_ffff);
        expect_reg(5'd21, 32'h1234_5000);
        expect_reg(5'd22, 32'd84);
        expect_reg(5'd25, 32'h1122_3344);
        expect_reg(5'd26, 32'hffff_ff80);
        expect_reg(5'd27, 32'h0000_0080);
        expect_reg(5'd28, 32'hffff_ff80);
        expect_reg(5'd29, 32'h0000_ff80);
        expect_reg(5'd30, 32'h1122_3344);
        expect_reg(5'd3,  32'd1);
        expect_reg(5'd4,  32'd192);
        expect_reg(5'd5,  32'd192);
        expect_reg(5'd8,  32'd208);

        if (failures == 0)
            $display("RV32I SELF-TEST PASS");
        else
            $display("RV32I SELF-TEST FAIL: %0d mismatches", failures);
        $finish_and_return(failures != 0);
    end
endmodule