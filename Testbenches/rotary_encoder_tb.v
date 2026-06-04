`timescale 1ns / 1ps

/*
 * This testbench verifies the physical-to-digital translation logic of the 
 * rotary encoder. Instead of running millions of clock cycles to test the 
 * 2ms hardware debounce filter, it uses a calculated `DEBOUNCE_DELAY` to 
 * simulate real-world human interaction delays. This streamlines the test 
 * to quickly verify math inputs, speed multipliers, state-based lockouts, 
 * and menu navigation.
 */

module tb_rotary_encoder();

    // Sandbox Inputs (Driven by testbench)
    reg clk;
    reg rst_p;
    reg enc_clk;
    reg enc_dt;
    reg enc_sw;
    reg speed_btn;
    reg menu_select;
    reg screen_active;
    reg input_screen_active; 

    // Sandbox Outputs (Observed from DUT)
    wire [31:0] count;
    wire [1:0]  menu_idx;
    wire [1:0]  endmode_idx; 
    wire        triggered;
    wire [2:0]  speed_lvl;
    wire        speed_pulse;

    // Device Under Test (DUT)
    rotary_encoder dut (
        .clk(clk), 
        .rst_p(rst_p), 
        .enc_clk(enc_clk), 
        .enc_dt(enc_dt),
        .enc_sw(enc_sw), 
        .speed_btn(speed_btn),
        .menu_select(menu_select), 
        .screen_active(screen_active), 
        .input_screen_active(input_screen_active),
        .count(count),
        .menu_idx(menu_idx), 
        .endmode_idx(endmode_idx), 
        .triggered(triggered),
        .speed_lvl(speed_lvl),
        .speed_pulse(speed_pulse)
    );

    // 100MHz System Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // The physical 2.1ms delay required to bypass the hardware debounce timer
    localparam DEBOUNCE_DELAY = 2100000; 

    // --- Physical Interaction Simulation Tasks ---
    
    // Simulate twisting the knob Clockwise
    task rotate_cw;
        begin
            enc_dt = 1;  #DEBOUNCE_DELAY;
            enc_clk = 0; #DEBOUNCE_DELAY;
            enc_dt = 0;  #DEBOUNCE_DELAY;
            enc_clk = 1; #DEBOUNCE_DELAY;
        end
    endtask

    // Simulate twisting the knob Counter-Clockwise
    task rotate_ccw;
        begin
            enc_dt = 0;  #DEBOUNCE_DELAY;
            enc_clk = 0; #DEBOUNCE_DELAY;
            enc_dt = 1;  #DEBOUNCE_DELAY;
            enc_clk = 1; #DEBOUNCE_DELAY;
        end
    endtask

    // Simulate pushing the encoder knob down
    task press_knob;
        begin
            enc_sw = 0; #DEBOUNCE_DELAY; // Active-low component
            enc_sw = 1; #DEBOUNCE_DELAY;
        end
    endtask

    // Simulate pressing the physical C-button on the FPGA board
    task press_speed;
        begin
            speed_btn = 1; #DEBOUNCE_DELAY; // Active-high component
            speed_btn = 0; #DEBOUNCE_DELAY;
        end
    endtask

    // --- Main Verification Sequence ---
    initial begin
        $display("--------------------------------------------------");
        $display("Starting Streamlined Rotary Encoder Verification");
        $display("--------------------------------------------------");
        
        // 0. Initialize lines to their physical resting states
        rst_p = 1; 
        enc_clk = 1; enc_dt = 1; 
        enc_sw = 1; speed_btn = 0; 
        menu_select = 0; screen_active = 0; input_screen_active = 0;
        #1000;
        rst_p = 0;
        #DEBOUNCE_DELAY;

        // TEST 1: Basic Math Input
        // Verify the encoder adds 1 per click when on the input screen
        $display("TEST 1: Number Input at 1x Speed...");
        screen_active = 1; 
        input_screen_active = 1; 
        rotate_cw();       
        rotate_cw();       
        
        if (count != 2) $display("  -> ERROR: Expected count=2, got %d", count);
        else $display("  -> SUCCESS: Count is 2");

        // TEST 2: Speed Multiplier
        // Verify the C-button shifts the math increment from 1s to 10s
        $display("TEST 2: Speed Multiplier (Shift to 10x)...");
        press_speed();     
        rotate_cw();       
        
        if (count != 12) $display("  -> ERROR: Expected count=12, got %d", count);
        else $display("  -> SUCCESS: Count is 12");

        // TEST 3: State Lockouts & Reset
        // Verify the math count is safely wiped when leaving the input screen
        $display("TEST 3: Auto-Zero on Mode Exit/Entry...");
        screen_active = 0;       
        input_screen_active = 0; 
        press_knob();            
        
        if (count != 0) $display("  -> ERROR: Expected count=0, got %d", count);
        else $display("  -> SUCCESS: Count Auto-Zeroed to 0");

        // TEST 4: Menu Navigation
        // Verify knob twists route to the menu index when screen is inactive
        $display("TEST 4: Menu Navigation...");
        rotate_cw();       
        
        if (menu_idx != 1) $display("  -> ERROR: Expected menu_idx=1, got %d", menu_idx);
        else $display("  -> SUCCESS: Menu incremented to 1");

        $display("--------------------------------------------------");
        $display("Verification Complete. Safe to close simulation.");
        $display("--------------------------------------------------");
        
        $finish;
    end

endmodule

