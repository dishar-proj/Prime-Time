`timescale 1ns / 1ps

// =============================================================================
// Module: test_mode_wrapper
// -----------------------------------------------------------------------------
// Summary:
// This module serves as a purely combinational routing wrapper that switches 
// control and data paths between Test Mode 1 and Test Modes 2/3 controllers.
// It handles all reset (rst_n) and main menu wipe logic (is_testing_mode = 0) 
// strictly using a combinational always block. No sequential (always @posedge clk) 
// blocks are used in this wrapper. If a system reset occurs or testing mode is 
// exited, all output signals are immediately driven low to prevent corrupted 
// memory accesses or erroneous logging.
// =============================================================================

module test_mode_wrapper (
    // -- Clock and Reset --
    input  wire        clk,             // System clock (passed down to sub-modules)
    input  wire        rst_n,           // Active-low asynchronous reset

    // -- Global Control Signals --
    input  wire        engine_done,     // High when the prime generation engine finishes
    input  wire        is_testing_mode, // High when a test mode is currently active (not Main Menu)
    input  wire [2:0]  active_calc_mode,// Indicates calculation mode (0 = Mode 1, 1/2 = Mode 2/3)
    
    // -- Data & Status Inputs --
    input  wire [31:0] primes_total,    // Total number of primes found by the engine
    input  wire [31:0] sd_data,         // 32-bit data read from the SD card
    input  wire        sd_lineflag,     // Pulse indicating a new valid line from the SD card
    input  wire [31:0] ram_read_data,   // 32-bit data read from the RAM
    input  wire        ram_readfini,    // Flag indicating RAM read operation is complete

    // -- Ram Interface Outputs (Must be reg for always @* block) --
    output reg  [27:0] ram_addr,        // Address out to RAM for verification reading
    output reg         ram_rflag,       // Read enable flag out to RAM

    // -- Test Result Outputs (Must be reg for always @* block) --
    output reg         test_done,       // High when the active test sequence is completely finished
    output reg         test_passed,     // High if the test completes with zero mismatches
    output reg  [31:0] lines_checked,   // Running tally of lines/entries compared
    output reg  [31:0] fail_ram_val,    // Stores the RAM value that caused a mismatch
    output reg  [31:0] fail_sd_val,     // Stores the SD card value that caused a mismatch
    output reg  [31:0] log_ram_val,     // Current RAM value passed out to UART logging
    output reg  [31:0] log_sd_val,      // Current SD card value passed out to UART logging
    output reg         log_pulse        // Trigger pulse to tell UART to transmit the log values
);

    // =========================================================================
    // Internal Control Signals (Must be reg for always @* block)
    // =========================================================================
    reg is_mode1;
    reg start_test_1;
    reg start_test_23;

    // =========================================================================
    // Mode 1 Controller Interconnects
    // =========================================================================
    
    // Wires to catch the continuous outputs driven by the Mode 1 controller
    wire [27:0] w1_ram_addr;
    wire        w1_ram_rflag;
    wire        w1_test_done;
    wire        w1_test_passed;
    wire [31:0] w1_lines_checked;
    wire [31:0] w1_fail_ram_val;
    wire [31:0] w1_fail_sd_val;
    wire [31:0] w1_log_ram_val;
    wire [31:0] w1_log_sd_val;
    wire        w1_log_pulse;

    // Instantiate Mode 1 Controller
    test_mode1_ctrl test1_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_test      (start_test_1),
        .sd_data         (sd_data),
        .primes_total    (primes_total),
        .sd_lineflag     (sd_lineflag),
        .ram_read_data   (ram_read_data),
        .ram_readfini    (ram_readfini),
        .ram_addr        (w1_ram_addr),
        .ram_rflag       (w1_ram_rflag),
        .test_done       (w1_test_done),
        .test_passed     (w1_test_passed),
        .lines_checked   (w1_lines_checked),
        .fail_ram_val    (w1_fail_ram_val),
        .fail_sd_val     (w1_fail_sd_val),
        .log_ram_val     (w1_log_ram_val),
        .log_sd_val      (w1_log_sd_val),
        .log_pulse       (w1_log_pulse)
    );

    // =========================================================================
    // Mode 2 & 3 Controller Interconnects
    // =========================================================================
    
    // Wires to catch the continuous outputs driven by the Mode 2/3 controller
    wire [27:0] w23_ram_addr;
    wire        w23_ram_rflag;
    wire        w23_test_done;
    wire        w23_test_passed;
    wire [31:0] w23_lines_checked;
    wire [31:0] w23_fail_ram_val;
    wire [31:0] w23_fail_sd_val;
    wire [31:0] w23_log_ram_val;
    wire [31:0] w23_log_sd_val;
    wire        w23_log_pulse;

    // Instantiate Mode 2/3 Controller
    test_mode23_controller test23_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_test      (start_test_23),
        .engine_done     (engine_done),
        .sd_data         (sd_data),
        .primes_total    (primes_total),
        .sd_lineflag     (sd_lineflag),
        .ram_read_data   (ram_read_data),
        .ram_readfini    (ram_readfini),
        .ram_addr        (w23_ram_addr),
        .ram_rflag       (w23_ram_rflag),
        .test_done       (w23_test_done),
        .test_passed     (w23_test_passed),
        .lines_checked   (w23_lines_checked),
        .fail_ram_val    (w23_fail_ram_val),
        .fail_sd_val     (w23_fail_sd_val),
        .log_ram_val     (w23_log_ram_val),
        .log_sd_val      (w23_log_sd_val),
        .log_pulse       (w23_log_pulse)
    );

    // =========================================================================
    // Combinational Logic Block (Control & Output Multiplexing)
    // =========================================================================
    always @(*) begin
        // 1. Evaluate internal control signals combinationally
        is_mode1      = (active_calc_mode == 3'd0);
        start_test_1  = rst_n && is_testing_mode && is_mode1;
        start_test_23 = rst_n && is_testing_mode && !is_mode1;

        // 2. Output Multiplexer with Combinational Reset & MASTER WIPE Logic
        // Priority A: If reset (!rst_n) or Main Menu (!is_testing_mode), force 0.
        // Priority B: Route Controller 1 (if is_mode1).
        // Priority C: Route Controller 2/3 (else).
        if (!rst_n || !is_testing_mode) begin
            ram_addr      = 28'd0;
            ram_rflag     = 1'b0;
            test_done     = 1'b0;
            test_passed   = 1'b0;
            lines_checked = 32'd0;
            fail_ram_val  = 32'd0;
            fail_sd_val   = 32'd0;
            log_ram_val   = 32'd0;
            log_sd_val    = 32'd0;
            log_pulse     = 1'b0;
        end 
        else if (is_mode1) begin
            ram_addr      = w1_ram_addr;
            ram_rflag     = w1_ram_rflag;
            test_done     = w1_test_done;
            test_passed   = w1_test_passed;
            lines_checked = w1_lines_checked;
            fail_ram_val  = w1_fail_ram_val;
            fail_sd_val   = w1_fail_sd_val;
            log_ram_val   = w1_log_ram_val;
            log_sd_val    = w1_log_sd_val;
            log_pulse     = w1_log_pulse;
        end 
        else begin
            ram_addr      = w23_ram_addr;
            ram_rflag     = w23_ram_rflag;
            test_done     = w23_test_done;
            test_passed   = w23_test_passed;
            lines_checked = w23_lines_checked;
            fail_ram_val  = w23_fail_ram_val;
            fail_sd_val   = w23_fail_sd_val;
            log_ram_val   = w23_log_ram_val;
            log_sd_val    = w23_log_sd_val;
            log_pulse     = w23_log_pulse;
        end
    end

endmodule
