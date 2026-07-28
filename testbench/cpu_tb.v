`timescale 1ns / 1ps
// ================================================================
// cpu_tb.v -Testbench for the RISC-V CPU with Integrated CNN Accelerator
//
// Clock:    clk toggles every 5 ns (100 MHz input)
// Reset:    sysrst = 1 for first 10 ns, then sysrst = 0
// Behavior: Clock runs until all outputs stabilize, then stops toggling.
//           Simulation finishes shortly after.
//
// Usage in ModelSim:
//   1. Compile cpu.v and cpu_tb.v
//   2. Start simulation: vsim cpu_tb
//   3. Add waves:   add wave -r /*
//   4. Run:         run -all
// ================================================================

module cpu_tb;

    //-------------------------------------------------------------
    // Inputs
    //-------------------------------------------------------------
    reg       clk;
    reg       sysrst;

    //-------------------------------------------------------------
    // Outputs
    //-------------------------------------------------------------
    wire [3:0] ledr;
    wire [3:0] predicted_class_bits;

    //-------------------------------------------------------------
    // Clock enable -used to stop toggling when outputs are stable
    //-------------------------------------------------------------
    reg       clk_en;

    //-------------------------------------------------------------
    // Predicted class decoder: LED outputs are active-low, so invert
    // ledr[3:0] to recover the predicted binary digit.
    //-------------------------------------------------------------
    assign predicted_class_bits = ~ledr;

    //-------------------------------------------------------------
    // Real-time monitor: print whenever ledr changes
    //-------------------------------------------------------------
    always @(ledr) begin
        $display("[%0t ns] *** CNN Prediction: digit = %0d (ledr = %b, active-low) ***",
                 $time, predicted_class_bits, ledr);
    end

    //-------------------------------------------------------------
    // Device Under Test
    //-------------------------------------------------------------
    cpu uut (
        .clk (clk),
        .sysrst (sysrst),
        .ledr(ledr)
    );

    //-------------------------------------------------------------
    // Clock generation: toggle every 5 ns -> 100 MHz
    //-------------------------------------------------------------
    initial begin
        clk    = 1'b0;
        clk_en = 1'b1;
    end

    always begin
        #5;
        if (clk_en) begin
            clk = ~clk;
        end
    end

    //-------------------------------------------------------------
    // Main stimulus sequence
    //-------------------------------------------------------------
    initial begin
        // ---- Assert reset ----
        sysrst = 1'b0;

        $display("========================================");
        $display("  CPU + CNN Accelerator Testbench");
        $display("========================================");
        $display("[%0t ns] Reset asserted", $time);

        // ---- Hold reset for 10 ns ----
        #10;
        sysrst = 1'b1;
        $display("[%0t ns] Reset de-asserted -CPU starts running", $time);
        $display("[%0t ns] Program: CNN MMIO base write -start -poll done -LED write", $time);

        // ---- Wait for program to complete ----
        // The CPU pipeline runs at 50 MHz (derived internally from 100 MHz clk).
        // The shared-MAC CNN accelerator runs at 20 MHz and needs about 20k cycles (~1 ms).
        // We wait 2 ms total to guarantee all outputs have stabilized.
        // After the ecall instruction, the PC stalls permanently; the program
        // reaches it only after polling STATUS.done and writing the LED register.

        #1000000;  // 1 ms
        $display("[%0t ns]  1 ms elapsed -CNN should be finishing...", $time);

        #1000000;  // 2 ms total
        $display("[%0t ns] 2 ms elapsed -outputs should be stable", $time);

        // ---- Stop the clock ----
        clk_en = 1'b0;
        $display("[%0t ns] Clock stopped (clk_en = 0)", $time);

        // ---- Report final output values ----
        $display("----------------------------------------");
        $display("Final 4-LED Binary Output (active-low):");
        $display("  ledr = %b  (lit pattern = %b, predicted_class_LED[3:0])",
                 ledr, predicted_class_bits);
        $display("----------------------------------------");
        $display("========================================");
        $display("  >>> CNN Predicted Class = %0d <<<", predicted_class_bits);
        $display("========================================");

        // ---- Hold final state for observation, then finish ----
        #2000;
        $display("[%0t ns] Simulation finished", $time);
        $display("========================================");
        $finish;
    end

    //-------------------------------------------------------------
    // Optional: Dump waveforms to VCD file for GTKWave
    // Uncomment the following lines if waveform dumping is needed:
    //-------------------------------------------------------------
    // initial begin
    //     $dumpfile("cpu_tb.vcd");
    //     $dumpvars(0, cpu_tb);
    // end

endmodule
