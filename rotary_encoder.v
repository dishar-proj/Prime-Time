`timescale 1ns / 1ps

// This module reads a physical rotary encoder and its push button, providing
// debounced and synchronized outputs. It manages Menu Navigation and Number Input,
// and includes a ping-pong speed multiplier mapped to a separate button.
module rotary_encoder (
    input  wire        clk,                  // 100MHz FPGA System Clock 
    input  wire        rst_p,                // Synchronous reset (Active-High)
    
    // Physical Pins
    input  wire        enc_clk,              // Phase A from encoder (used for clocking rotation)
    input  wire        enc_dt,               // Phase B from encoder (used for direction)
    input  wire        enc_sw,               // Encoder Button (Active-Low) -> Confirm / Trigger FSM
    input  wire        speed_btn,            // FPGA BTNC (Active-High) -> Shift Speeds
    
    // State Control Inputs
    input  wire        menu_select,          // 0 = Prime Menu, 1 = End Menu
    input  wire        screen_active,        // 1 = Mode Screen is active (locks menu navigation)
    input  wire        input_screen_active,  // 1 = Input Screen is active (unlocks count adjustment)
    
    // Data Outputs
    output reg  [31:0] count,                // The mathematical number selected by the user
    output reg  [1:0]  menu_idx,             // Current position on the 3-mode main menu (0, 1, or 2)
    output reg  [1:0]  endmode_idx,          // Current position on the 2-mode end menu (0 or 1)
    output reg         triggered,            // 1-cycle HIGH pulse telling the UI state machine to advance
    
    // Outputs for 7SD Flashing
    output reg  [2:0]  speed_lvl,            // 0 to 7. Tells the 7SD which specific digit to flash
    output reg         speed_pulse           // 1-cycle HIGH pulse that restarts the 7SD's blink timer
);

    // Internal Registers (_ff)
    
    // 2-Stage Synchronizers for physical pins to prevent metastability
    reg [1:0]  a_sync_ff, b_sync_ff, btn_sync_ff, spd_sync_ff;
    
    // History registers track the state of the pins from the previous debounce cycle
    reg        a_hist_ff, a_hist_in;
    reg        btn_hist_ff, btn_hist_in;
    reg        spd_hist_ff, spd_hist_in; 
    
    // 2ms Hardware Debounce Timer
    reg [17:0] tick_cnt_ff, tick_cnt_in;

    // Ping-Pong Speed Registers
    reg [2:0]  speed_lvl_ff, speed_lvl_in;   // Tracks the current 10^x multiplier
    reg        speed_dir_ff, speed_dir_in;   // Tracks if the multiplier is moving UP (0) or DOWN (1)

    // Data Registers
    reg [31:0] count_ff, count_in;
    reg [1:0]  menu_idx_ff, menu_idx_in;
    reg [1:0]  endmode_idx_ff, endmode_idx_in;
    reg        triggered_ff, triggered_in;
    reg        speed_pulse_ff, speed_pulse_in;

    // Sequential Logic (Flip-Flops only)
    always @(posedge clk) begin
        // Shift external signals into the LSB, move older data to MSB
        a_sync_ff      <= {a_sync_ff[0], enc_clk};
        b_sync_ff      <= {b_sync_ff[0], enc_dt};
        btn_sync_ff    <= {btn_sync_ff[0], enc_sw};
        spd_sync_ff    <= {spd_sync_ff[0], speed_btn};
        
        a_hist_ff      <= a_hist_in;
        btn_hist_ff    <= btn_hist_in;
        spd_hist_ff    <= spd_hist_in;
        
        tick_cnt_ff    <= tick_cnt_in;
        
        speed_lvl_ff   <= speed_lvl_in;
        speed_dir_ff   <= speed_dir_in;

        count_ff       <= count_in;
        menu_idx_ff    <= menu_idx_in;
        endmode_idx_ff <= endmode_idx_in;
        triggered_ff   <= triggered_in;
        speed_pulse_ff <= speed_pulse_in;

        // Drive the physical outputs
        count          <= count_in;
        menu_idx       <= menu_idx_in;
        endmode_idx    <= endmode_idx_in;
        triggered      <= triggered_in;
        speed_lvl      <= speed_lvl_in;
        speed_pulse    <= speed_pulse_in;
    end

    // Speed Increment Decoder 
    // Translates the 0-7 speed level into a mathematical multiplier (Base-10)
    reg [31:0] inc_val;
    always @(*) begin
        case(speed_lvl_ff)
            3'd0: inc_val = 32'd1;           // Speed 0: x1
            3'd1: inc_val = 32'd10;          // Speed 1: x10
            3'd2: inc_val = 32'd100;         // Speed 2: x100
            3'd3: inc_val = 32'd1000;        // Speed 3: x1,000
            3'd4: inc_val = 32'd10000;       // Speed 4: x10,000
            3'd5: inc_val = 32'd100000;      // Speed 5: x100,000
            3'd6: inc_val = 32'd1000000;     // Speed 6: x1,000,000
            3'd7: inc_val = 32'd10000000;    // Speed 7: x10,000,000
            default: inc_val = 32'd1;
        endcase
    end

    // Combinational Logic
    always @(*) begin
        // Default assignments to prevent inferred latches
        a_hist_in      = a_hist_ff;
        btn_hist_in    = btn_hist_ff;
        spd_hist_in    = spd_hist_ff;
        tick_cnt_in    = tick_cnt_ff;
        speed_lvl_in   = speed_lvl_ff;
        speed_dir_in   = speed_dir_ff;
        count_in       = count_ff;
        menu_idx_in    = menu_idx_ff;
        endmode_idx_in = endmode_idx_ff;
        triggered_in   = 1'b0; 
        speed_pulse_in = 1'b0; 

        // Synchronous Reset
        if (rst_p) begin
            a_hist_in      = 1'b1; // Encoders usually rest HIGH
            btn_hist_in    = 1'b1; // Active-low button rests HIGH
            spd_hist_in    = 1'b0; // Active-high button rests LOW
            tick_cnt_in    = 18'd0;
            speed_lvl_in   = 3'd0; 
            speed_dir_in   = 1'b0;
            count_in       = 32'd0;
            menu_idx_in    = 2'd0;
            endmode_idx_in = 2'd0;
        end else begin
            
            // The Hardware Debounce Filter
            if (tick_cnt_ff >= 18'd199_999) begin
                tick_cnt_in = 18'd0; 
                
                // Rotation Logic (Rising Edge Method on Phase A)
                if (a_hist_ff == 1'b0 && a_sync_ff[1] == 1'b1) begin
                    
                    // Clockwise (Phase B is LOW during Phase A rising edge)
                    if (b_sync_ff[1] == 1'b0) begin
                        if (!screen_active) begin
                            // MENU MODE: Only change menu index
                            if (menu_idx_ff < 2'd2) menu_idx_in = menu_idx_ff + 2'd1;
                        end else if (menu_select) begin
                            if (endmode_idx_ff < 2'd2) endmode_idx_in = endmode_idx_ff + 2'd1;
                        end else if (input_screen_active) begin
                            // INPUT MODE: Only change the number count
                            count_in = count_ff + inc_val;
                        end
                    end 
                    // Counter-Clockwise (Phase B is HIGH during Phase A rising edge)
                    else begin
                        if (!screen_active) begin
                            // MENU MODE: Only change menu index
                            if (menu_idx_ff > 2'd0) menu_idx_in = menu_idx_ff - 2'd1;
                        end else if (menu_select) begin
                            if (endmode_idx_ff > 2'd0) endmode_idx_in = endmode_idx_ff - 2'd1;
                        end else if (input_screen_active) begin
                            // INPUT MODE: Subtract count, preventing underflow
                            if (count_ff >= inc_val) count_in = count_ff - inc_val;
                            else                     count_in = 32'd0;
                        end
                    end
                end

                // Encoder Button (Trigger FSM) - Detects falling edge
                if (btn_hist_ff == 1'b1 && btn_sync_ff[1] == 1'b0) begin
                    triggered_in = 1'b1; 
                    
                    // Force the number count to 0 when entering an active mode
                    if (!screen_active) begin
                        count_in = 32'd0;
                    end
                end
                
                // Speed Button (Ping-Pong Multiplier) - Detects rising edge
                if (spd_hist_ff == 1'b0 && spd_sync_ff[1] == 1'b1) begin
                    if (input_screen_active) begin
                        speed_pulse_in = 1'b1; 
                        
                        if (speed_dir_ff == 1'b0) begin 
                            // Counting UP towards 7
                            if (speed_lvl_ff == 3'd7) begin
                                speed_lvl_in = 3'd6;     
                                speed_dir_in = 1'b1;     
                            end else begin
                                speed_lvl_in = speed_lvl_ff + 3'd1; 
                            end
                        end else begin 
                            // Counting DOWN towards 0
                            if (speed_lvl_ff == 3'd0) begin
                                speed_lvl_in = 3'd1;     
                                speed_dir_in = 1'b0;     
                            end else begin
                                speed_lvl_in = speed_lvl_ff - 3'd1; 
                            end
                        end
                    end
                end

                // Update history registers for edge detection on the next cycle
                a_hist_in   = a_sync_ff[1];
                btn_hist_in = btn_sync_ff[1];
                spd_hist_in = spd_sync_ff[1];

            end else begin
                // Increment debounce timer
                tick_cnt_in = tick_cnt_ff + 18'd1;
            end
        end
    end
endmodule
