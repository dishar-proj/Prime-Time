`timescale 1ns / 1ps
//This module integrates the VGA timing, memory logging, and UI rendering components.
// It takes system-level data (test results, prime calculations, and menu states)
// and outputs VGA signals (RED, GRN, BLU, HSYNC, VSYNC) to display a graphical user interface.

module VGA_controller(
    input wire clk_vga,           // Pixel clock (e.g., 25.175 MHz for 640x480)
    input wire clk_cpu,           // System/Logic clock for memory updates
    input wire resetn,            // Active-low reset
    
    // UI and State Inputs
    input wire [1:0] menu_idx,    // Current selection in the menu
    input wire [1:0] screen_state,// Current active screen (Main, Test, Results, etc.)
    input wire [2:0] saved_idx,   // Index for saved configurations
    input wire [1:0] endmode_idx, // Index for the "Test End" state
    input wire [31:0] count,      // General purpose counter value
    input wire [2:0] speed_lvl,   // Speed setting for the generator
    input wire       is_prime,    // Current status of prime calculation
    
    // Performance and Statistics
    input wire [31:0] elapsed_sec,   // Time elapsed in seconds
    input wire [31:0] total_primes,  // Running total of primes found
    input wire        prime_valid,   // Strobe indicating a new prime result
    input wire [31:0] current_num,   // Current number being tested
    input wire        current_is_prime, // Result for current_num
    
    // Hardware Test Status
    input wire        test_passed,     // Success/Fail flag for memory/SD tests
    input wire [31:0] primes_checked,  // Count of primes verified
    input wire [31:0] fail_ram_val,    // Expected/Observed value on RAM failure
    input wire [31:0] fail_sd_val,     // Expected/Observed value on SD failure
    
    // Logging Inputs
    input wire [31:0] test_log_ram,    // Logging data for RAM tests
    input wire [31:0] test_log_sd,     // Logging data for SD tests
    input wire        test_log_pulse,  // Strobe to trigger a new log entry
    
    // VGA Physical Outputs
    output wire [3:0] RED, 
    output wire [3:0] GRN, 
    output wire [3:0] BLU, 
    output wire HSYNC,     
    output wire VSYNC      
);

    // Internal Wires for Inter-module communication
    wire [9:0] h_count_wire;       // Current horizontal pixel position
    wire [9:0] v_count_wire;       // Current vertical pixel position
    wire       video_on_wire;      // High when within visible area
    
    wire [4:0]  history_addr_wire; // Address for reading previous test logs
    wire [31:0] history_data_wire; // Data returned from history memory

    // Timing Generator: Produces HSYNC, VSYNC, and pixel coordinates
    vga_sync sync_inst (
        .clk_vga(clk_vga),
        .resetn(resetn),
        .h_count(h_count_wire),
        .v_count(v_count_wire),
        .HSYNC(HSYNC),
        .VSYNC(VSYNC),
        .video_on(video_on_wire)
    );

    // Memory Logic: Stores historical data and logs for display
    vga_memory memory_inst (
        .clk_cpu(clk_cpu),           
        .resetn(resetn),
        .screen_state(screen_state), 
        .saved_idx(saved_idx),       
        .prime_valid(prime_valid),
        .current_is_prime(current_is_prime),
        .current_num(current_num),
        .test_log_ram(test_log_ram),
        .test_log_sd(test_log_sd),
        .test_log_pulse(test_log_pulse),
        .read_addr(history_addr_wire),
        .read_data(history_data_wire)
    );

    // UI Rendering: Determines the color of each pixel based on state and timing
    vga_ui ui_inst (
        .clk_vga(clk_vga),
        .resetn(resetn),
        .video_on(video_on_wire),
        .h_count_ff(h_count_wire),
        .v_count_ff(v_count_wire),
        .menu_idx(menu_idx),
        .screen_state(screen_state),
        .saved_idx(saved_idx),
        .endmode_idx(endmode_idx), 
        .count(count),
        .speed_lvl(speed_lvl),
        .is_prime(is_prime),
        .elapsed_sec(elapsed_sec),
        .total_primes(total_primes),
        .test_passed(test_passed),
        .primes_checked(primes_checked), 
        .fail_ram_val(fail_ram_val),     
        .fail_sd_val(fail_sd_val),       
        .history_data_in(history_data_wire),
        .history_addr_out(history_addr_wire),
        .RED(RED),
        .GRN(GRN),
        .BLU(BLU)
    );
endmodule
