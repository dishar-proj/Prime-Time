`timescale 1ns / 1ps

// =============================================================================
// Module: test_mode1_ctrl
// -----------------------------------------------------------------------------
// Summary:
// This module controls the Test Mode 1 sequence. It verifies the very first
// prime number in RAM against the very first prime number read from the SD card.
// 
// Architecture Rules Applied:
// - Strict Separation: The sequential block contains NO logic or conditionals; 
//   it strictly registers the 'next_' state signals to their flip-flops on the 
//   clock edge.
// - Combinational Reset & Logic: All reset logic (rst_n), default assignments, 
//   and FSM transitions are handled entirely within the combinational always block.
// =============================================================================

module test_mode1_ctrl (
    // -- Clock & Reset --
    input  wire        clk,
    input  wire        rst_n,           // Active-low reset (handled combinationally)
    input  wire        start_test,      // Triggers the test sequence
    
    // -- Data Inputs --
    input  wire [31:0] sd_data,         // Data read from SD card
    input  wire [31:0] primes_total,    // Total primes calculated by engine
    input  wire        sd_lineflag,     // Pulse indicating new SD data is available
    input  wire [31:0] ram_read_data,   // Data read from RAM
    input  wire        ram_readfini,    // Flag indicating RAM read is complete
    
    // -- Control Outputs --
    output reg  [27:0] ram_addr,        // Address requested from RAM
    output reg         ram_rflag,       // RAM read enable flag
    
    // -- Status & Result Outputs --
    output reg         test_done,       // High when test sequence finishes
    output reg         test_passed,     // High if SD matches RAM
    output reg  [31:0] lines_checked,   // Number of entries compared
    output reg  [31:0] fail_ram_val,    // RAM value that caused mismatch
    output reg  [31:0] fail_sd_val,     // SD value that caused mismatch
    output reg  [31:0] log_ram_val,     // Value to log to UART (RAM)
    output reg  [31:0] log_sd_val,      // Value to log to UART (SD)
    output reg         log_pulse        // Trigger pulse for UART transmission
);

    // =========================================================================
    // FSM State Parameters
    // =========================================================================
    localparam [2:0] IDLE     = 3'd0, 
                     REQ_RAM  = 3'd1, 
                     WAIT_RAM = 3'd2, 
                     WAIT_SD  = 3'd3, 
                     COMPARE  = 3'd4, 
                     DONE     = 3'd5;

    // =========================================================================
    // Internal Registers and Next-State Wires
    // =========================================================================
    reg [2:0]  state_ff,            next_state;
    reg [31:0] lines_checked_ff,    next_lines_checked_ff;
    reg [31:0] latched_sd_data_ff,  next_latched_sd_data_ff;
    reg [31:0] latched_ram_data_ff, next_latched_ram_data_ff;
    reg        sd_ready_ff,         next_sd_ready;
    
    reg [27:0] next_ram_addr;
    reg        next_ram_rflag;
    reg        next_test_done;
    reg        next_test_passed;
    reg [31:0] next_lines_checked;
    reg [31:0] next_fail_ram_val;
    reg [31:0] next_fail_sd_val;
    reg [31:0] next_log_ram_val;
    reg [31:0] next_log_sd_val;
    reg        next_log_pulse;

    // =========================================================================
    // Sequential Logic Block (STRICTLY REGISTERS ONLY)
    // -------------------------------------------------------------------------
    // No resets or if-statements here. Simply passes the combinational 
    // 'next_' values into the flip-flops on the rising edge of the clock.
    // =========================================================================
    always @(posedge clk) begin
        state_ff            <= next_state;
        lines_checked_ff    <= next_lines_checked_ff;
        latched_sd_data_ff  <= next_latched_sd_data_ff;
        latched_ram_data_ff <= next_latched_ram_data_ff;
        sd_ready_ff         <= next_sd_ready;

        ram_addr            <= next_ram_addr;
        ram_rflag           <= next_ram_rflag;
        test_done           <= next_test_done;
        test_passed         <= next_test_passed;
        lines_checked       <= next_lines_checked;
        fail_ram_val        <= next_fail_ram_val;
        fail_sd_val         <= next_fail_sd_val;
        log_ram_val         <= next_log_ram_val;
        log_sd_val          <= next_log_sd_val;
        log_pulse           <= next_log_pulse;
    end

    // =========================================================================
    // Combinational Logic Block (HANDLES ALL RESET AND FSM LOGIC)
    // -------------------------------------------------------------------------
    // Evaluates the next state of the system asynchronously. Handles default
    // assignments, active-low reset forcing, and FSM behavior.
    // =========================================================================
    always @(*) begin
        // 1. Default Assignments (Prevents latches by maintaining current state)
        next_state               = state_ff;
        next_lines_checked_ff    = lines_checked_ff;
        next_latched_sd_data_ff  = latched_sd_data_ff;
        next_latched_ram_data_ff = latched_ram_data_ff;
        next_sd_ready            = sd_ready_ff;
        
        next_ram_addr            = ram_addr;
        next_ram_rflag           = ram_rflag;
        next_test_done           = test_done;
        next_test_passed         = test_passed;
        next_lines_checked       = lines_checked;
        next_fail_ram_val        = fail_ram_val;
        next_fail_sd_val         = fail_sd_val;
        next_log_ram_val         = log_ram_val;
        next_log_sd_val          = log_sd_val;
        next_log_pulse           = 1'b0; // Auto-clear log pulse every cycle

        // 2. Combinational Reset Handling
        // If reset is pulled low, force all next-state registers to 0 / IDLE
        if (!rst_n) begin
            next_state               = IDLE;
            next_lines_checked_ff    = 32'd0;
            next_latched_sd_data_ff  = 32'd0;
            next_latched_ram_data_ff = 32'd0;
            next_sd_ready            = 1'b0;
            
            next_ram_addr            = 28'd0;
            next_ram_rflag           = 1'b0;
            next_test_done           = 1'b0;
            next_test_passed         = 1'b0;
            next_lines_checked       = 32'd0;
            next_fail_ram_val        = 32'd0;
            next_fail_sd_val         = 32'd0;
            next_log_ram_val         = 32'd0;
            next_log_sd_val          = 32'd0;
            next_log_pulse           = 1'b0;
        end 
        
        // 3. Main FSM and Operational Logic
        else begin
            // Global SD Capture Logic
            if (sd_lineflag) begin
                next_sd_ready           = 1'b1;
                next_latched_sd_data_ff = sd_data;
            end

            // FSM State Behavior
            case (state_ff)
                IDLE: begin
                    next_test_done = 1'b0;
                    if (start_test) begin
                        next_sd_ready         = 1'b0;
                        next_lines_checked_ff = 32'd0;
                        next_lines_checked    = 32'd0;
                        
                        // Check if engine found any primes before starting
                        if (primes_total > 0) begin
                            next_state = REQ_RAM;
                        end else begin
                            next_test_passed = 1'b0; // Fail instantly if no primes exist
                            next_state       = DONE;
                        end
                    end
                end

                REQ_RAM: begin
                    // Request the first prime at RAM address 0
                    next_ram_addr  = 28'd0;
                    next_ram_rflag = 1'b1;
                    next_state     = WAIT_RAM;
                end

                WAIT_RAM: begin
                    // Wait for RAM to signal that data is ready
                    if (ram_readfini) begin
                        next_ram_rflag           = 1'b0;
                        next_latched_ram_data_ff = ram_read_data;
                        next_state               = WAIT_SD;
                    end
                end

                WAIT_SD: begin
                    // Wait for SD card line reader to assert ready flag
                    if (sd_ready_ff) begin
                        next_state = COMPARE;
                    end
                end

                COMPARE: begin
                    next_sd_ready         = 1'b0; 
                    next_lines_checked_ff = lines_checked_ff + 1;
                    next_lines_checked    = lines_checked_ff + 1; 

                    // Check for End-of-File 'A' to avoid hangs
                    if (latched_sd_data_ff == 32'd65 || latched_sd_data_ff[7:0] == 8'h41) begin
                        next_test_passed = 1'b0;  // FAIL: Reached EOF without matching
                        next_state       = DONE;  
                    end
                    // Successful Match logic
                    else if (latched_sd_data_ff == latched_ram_data_ff) begin
                        next_test_passed = 1'b1;
                        next_log_ram_val = latched_ram_data_ff;
                        next_log_sd_val  = latched_sd_data_ff;
                        next_log_pulse   = 1'b1;  // Trigger UART logging
                        next_state       = DONE;
                    end 
                    // Timeout limit to prevent infinite looping
                    else if (next_lines_checked_ff >= 32'd1000000) begin 
                        next_test_passed = 1'b0;
                        next_state       = DONE;
                    end 
                    // No match yet, loop back and wait for next SD line
                    else begin
                        next_state = WAIT_SD; 
                    end
                end

                DONE: begin
                    // Assert done flag and wait for test signal to deassert
                    next_test_done = 1'b1;
                    if (!start_test) begin
                        next_state = IDLE;
                    end
                end
                
                default: begin
                    next_state = IDLE;
                end
            endcase
        end
    end

endmodule
