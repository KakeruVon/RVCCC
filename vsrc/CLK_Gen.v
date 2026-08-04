// ================================================================
// CLK_Gen - Clock generation module
// Input:  clk_in = 50 MHz (cristal oscillator)
// Output: clk_cpu = 25 MHz (divide-by-2)
//         clk_cnn = 25 MHz (divide-by-2)
// Temporarily unify the system clock to avoid clock domain crossing (CDC) issues.
// During current validation, both paths use the 25MHz clock.
// ================================================================
module CLK_Gen (
    input clk_in,
    input rst,
    output reg clk_cpu,
    output reg clk_cnn
);
    // ---- 25 MHz generation: simple toggle (divide-by-2) ----
    always @(posedge clk_in or posedge rst) begin
        if (rst) begin
            clk_cpu <= 1'b0;
            clk_cnn <= 1'b0;
        end else begin
            clk_cpu <= ~clk_cpu;
            clk_cnn <= ~clk_cnn;
        end
    end
endmodule
