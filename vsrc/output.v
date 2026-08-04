// ================================================================
// shared Anode_Activate and LED_out signals. Replaced by direct-
// drive logic (seg0-seg7) in the top-level pipeline_main module.
// ================================================================
/*
module Eight_Digit_Hex_Display(
    input clk_cpu,
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

    always @(posedge clk_cpu or posedge rst) begin
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

    always @(posedge clk_cpu or posedge rst) begin
        if (rst)
            displayed_value <= 0;
        else if (one_second_enable)
            displayed_value <= {predicted_class_LED, Mem_LED_in};
    end

    always @(posedge clk_cpu or posedge rst) begin
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
