`timescale 1ns / 1ns

// This module displays the rotary encoder count value on all 8 SSDs in decimal format (0-9).
module Module_7SD(
    input  wire clk,
    input  wire rst,
    input  wire [31:0] count,  // Connect to the output of rotary_encoder
    
    // Inputs for Blink Logic
    input  wire [2:0]  speed_lvl,   // 0 to 5 (Indicates which digit is being manipulated)
    input  wire        speed_pulse, // 1-cycle pulse that triggers the flash timer
    
    output reg  [7:0]  seg,      // Changed from 6:0 to 7:0 to include DP
    output reg  [7:0]  an
);

    // Internal Registers (_ff)
    reg [2:0]  sel_ff;    // FSM state (Cycles 0 to 7)
    reg [17:0] timer_ff;  // Refresh counter

    reg [2:0]  sel_in;    // FSM state
    reg [17:0] timer_in;  // timer
    reg [7:0]  seg_in;    // Changed from 6:0 to 7:0
    reg [7:0]  an_in;
    
    // Blink Timer Registers
    reg [26:0] blink_timer_ff, blink_timer_in; // 27 bits to count to 75,000,000 (0.75 seconds)
    reg        blink_active_ff, blink_active_in;

    // Extracting base-10 digits
    // Vivado will synthesize these into mathematical blocks
    wire [3:0] digit0 = (count % 10);
    wire [3:0] digit1 = (count / 10) % 10;
    wire [3:0] digit2 = (count / 100) % 10;
    wire [3:0] digit3 = (count / 1000) % 10;
    wire [3:0] digit4 = (count / 10000) % 10;
    wire [3:0] digit5 = (count / 100000) % 10;
    wire [3:0] digit6 = (count / 1000000) % 10;
    wire [3:0] digit7 = (count / 10000000) % 10;

    // This section encodes the states of the 7SD. 
    function [6:0] seg_encode;
        input [3:0] val;
        begin
            case (val)
                4'h0: seg_encode = 7'b1000000;
                4'h1: seg_encode = 7'b1111001;
                4'h2: seg_encode = 7'b0100100;
                4'h3: seg_encode = 7'b0110000;
                4'h4: seg_encode = 7'b0011001;
                4'h5: seg_encode = 7'b0010010;
                4'h6: seg_encode = 7'b0000010;
                4'h7: seg_encode = 7'b1111000;
                4'h8: seg_encode = 7'b0000000;
                4'h9: seg_encode = 7'b0010000;
                default: seg_encode = 7'b1111111; // Blank for values out of range
            endcase
        end
    endfunction
     
    // Sequential block
    always @(posedge clk) begin
        timer_ff        <= timer_in;
        sel_ff          <= sel_in;
        seg             <= seg_in;
        an              <= an_in;
        
        blink_timer_ff  <= blink_timer_in;
        blink_active_ff <= blink_active_in;
    end
   
    // Combinational block
    always @(*) begin
        // Default assignments (Holds state by default)
        timer_in        = timer_ff;
        sel_in          = sel_ff;
        seg_in          = 8'b11111111; 
        an_in           = 8'b1111_1111;
        
        blink_timer_in  = blink_timer_ff;
        blink_active_in = blink_active_ff;
        
        if (rst) begin
            // Synchronous reset overrides
            timer_in        = 18'd0;
            sel_in          = 3'd0;
            seg_in          = 8'b11111111; 
            an_in           = 8'b1111_1111;
            
            blink_timer_in  = 27'd0;
            blink_active_in = 1'b0;
        end else begin
            
            // Blink Timer Logic for Setting Speed
            if (speed_pulse) begin
                blink_active_in = 1'b1; // Turn on the blink flag
                blink_timer_in  = 27'd0; // Reset the 0.75-second countdown
            end 
            else if (blink_active_ff) begin
                if (blink_timer_ff >= 27'd75_000_000) begin
                    blink_active_in = 1'b0; // Time is up, turn off the blinking
                end else begin
                    blink_timer_in = blink_timer_ff + 27'd1;
                end
            end

            // Refresh Timer
            timer_in = timer_ff + 1;
            
            if (timer_ff == 100_000) begin
                timer_in = 18'd0; 
                
                if (sel_ff == 3'd7) 
                    sel_in = 3'd0;
                else
                    sel_in = sel_ff + 1; 
            end

            //FSM Logic for 7SD
            case (sel_ff)
                3'd0: begin // SSD8 (Rightmost, 1s place)
                    seg_in = {1'b1, seg_encode(digit0)}; 
                    an_in  = 8'b1111_1110; 
                end
                3'd1: begin // SSD7 (10s place)
                    seg_in = {1'b1, seg_encode(digit1)};
                    an_in  = 8'b1111_1101; 
                end
                3'd2: begin // SSD6 (100s place)
                    seg_in = {1'b1, seg_encode(digit2)}; 
                    an_in  = 8'b1111_1011; 
                end
                3'd3: begin // SSD5 (1,000s place)
                    seg_in = {1'b1, seg_encode(digit3)}; 
                    an_in  = 8'b1111_0111; 
                end
                3'd4: begin // SSD4 (10,000s place)
                    seg_in = {1'b1, seg_encode(digit4)};
                    an_in  = 8'b1110_1111; 
                end
                3'd5: begin // SSD3 (100,000s place)
                    seg_in = {1'b1, seg_encode(digit5)};
                    an_in  = 8'b1101_1111; 
                end
                3'd6: begin // SSD2 (1,000,000s place)
                    seg_in = {1'b1, seg_encode(digit6)};
                    an_in  = 8'b1011_1111; 
                end
                3'd7: begin // SSD1 (Leftmost, 10,000,000s place)
                    seg_in = {1'b1, seg_encode(digit7)};
                    an_in  = 8'b0111_1111; 
                end
                default: begin 
                    seg_in = 8'b11111111;  
                    an_in  = 8'b1111_1111;
                end
            endcase
            
            // Blink Numbers for Speed
            // Occurs when the blink timer is running and the display is trying
            // to draw on the digit for the set speed level
            if (blink_active_ff && (sel_ff == speed_lvl)) begin
                // Toggles back and forth roughly every 0.08 seconds
                // When it is 1, we forcefully turn the Anode OFF.
                if (blink_timer_ff[23] == 1'b1) begin
                    an_in = 8'b1111_1111; 
                end
            end
            
        end
    end
endmodule
