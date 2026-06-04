`timescale 1ns / 1ps

/* The system_router manages the signal paths between the Calculation Engine and 
 * the Testing Subsystem. It handles multiplexing for the DDR2 RAM addresses 
 * and ensures the SD card reset signals are synchronized. This prevents 
 * the SD card from reading data before the system is ready to compare it 
 * against the memory.
 */

module system_router (
    input  wire        clk_sd,          // Clock for synchronization
    input  wire        resetn,          // Global active-low reset

    // Mode Status Inputs
    input  wire [1:0]  screen_state,    // Current UI state
    input  wire [2:0]  saved_menu_idx,  // Selected menu option

    // RAM Multiplexer Inputs
    input  wire [27:0] test_ram_addr,   // RAM address from Test FSM
    input  wire        test_ram_rflag,  // Read request from Test FSM
    input  wire [27:0] mem_addr_in,     // RAM address from Memory Manager
    input  wire        rflag,           // Read request from Memory Manager

    // Engine Done Inputs
    input  wire        engine_done,     // Math engine finished
    input  wire        test_done,       // Test engine finished

    // Routing Outputs
    output reg         screen_is_active,     // Lock encoder if not on Menu
    output reg         is_testing_mode,      // System is in Test Mode
    output reg  [27:0] final_ram_addr,       // Multiplexed address to MIG
    output reg         final_ram_rflag,      // Multiplexed request to MIG
    output reg         combined_engine_done, // Global done signal for UI

    // Safe Reset Outputs
    output reg         sd_sys_resetn,        // Synchronized SD reset
    output reg         sd_cpu_resetn         // SD Parser enable
);

    // Synchronizer registers for timing stability
    reg test_mode_sync1_ff, test_mode_sync1_in;
    reg test_mode_sync2_ff, test_mode_sync2_in;

    // Sequential Logic: Flip-Flop updates
    always @(posedge clk_sd) begin
        test_mode_sync1_ff <= test_mode_sync1_in;
        test_mode_sync2_ff <= test_mode_sync2_in;
    end

    // Combinational Logic: Routing and Resets
    always @(*) begin
        // Default sync values
        test_mode_sync1_in = test_mode_sync1_ff;
        test_mode_sync2_in = test_mode_sync2_ff;

        // Enable screen lock if not on the main menu
        screen_is_active = (screen_state != 2'b00);

        // Flag if user is in Test Mode (saved_idx 3) and off-menu
        is_testing_mode = (saved_menu_idx == 3'd3 && screen_state != 2'b00);

        // RAM Multiplexer: Choose between Test Mode or normal operation
        if (is_testing_mode) begin
            final_ram_addr  = test_ram_addr;
            final_ram_rflag = test_ram_rflag;
        end else begin
            final_ram_addr  = mem_addr_in;
            final_ram_rflag = 1'b0; // Force low when not testing
        end
        
        // Merge done signals from different modules
        combined_engine_done = engine_done | test_done;

        // Reset and SD timing logic
        if (!resetn) begin
            test_mode_sync1_in = 1'b0;
            test_mode_sync2_in = 1'b0;
            sd_sys_resetn      = 1'b0;
            sd_cpu_resetn      = 1'b0;
        end else begin
            test_mode_sync1_in = is_testing_mode;
            test_mode_sync2_in = test_mode_sync1_ff;
            
            // Hold SD in reset until Loading or Result screen is active
            if (is_testing_mode && (screen_state == 2'b10 || screen_state == 2'b11)) begin
                sd_sys_resetn = test_mode_sync2_ff; // 2-cycle sync release
                sd_cpu_resetn = 1'b1;
            end else begin
                sd_sys_resetn = 1'b0;
                sd_cpu_resetn = 1'b0;
            end
        end
    end

endmodule
