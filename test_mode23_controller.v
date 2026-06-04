`timescale 1ns / 1ps

// =============================================================================
// Module: test_mode23_controller
// -----------------------------------------------------------------------------
// Summary:
// Verifies RAM primes against SD card data using a FIFO-based queue.
// 
// ARCHITECTURE RULES (STRICT):
// 1. SEQUENTIAL BLOCK: Only captures values. No 'if', 'case', or ternary '?:'.
// 2. COMBINATIONAL BLOCK: ALL decision-making, logic, and reset overrides.
// 3. FIFO: Memory updates are determined in the brain (comb block).
// =============================================================================

module test_mode23_controller (
    input  wire         clk,
    input  wire         rst_n,           // Active-low synchronous reset
    input  wire         start_test,      
    input  wire [31:0]  sd_data,         
    input  wire [31:0]  primes_total,    
    input  wire         sd_lineflag,     
    input  wire [31:0]  ram_read_data,   
    input  wire         ram_readfini,    
    
    output reg  [27:0]  ram_addr,        
    output reg          ram_rflag,       
    output reg          test_done,       
    output reg          test_passed,     
    output reg  [31:0]  lines_checked,   
    output reg  [31:0]  fail_ram_val,    
    output reg  [31:0]  fail_sd_val,     
    output reg  [31:0]  log_ram_val,     
    output reg  [31:0]  log_sd_val,      
    output reg          log_pulse        
);

    // FSM State Definitions
    localparam [2:0] IDLE         = 3'd0, 
                     CHECK_AVAIL  = 3'd1, 
                     CHECK_SD     = 3'd2, 
                     REQ_RAM      = 3'd3, 
                     WAIT_RAM     = 3'd4, 
                     WAIT_RAM_ACK = 3'd5, 
                     COMPARE      = 3'd6, 
                     DONE         = 3'd7;

    // Flip-Flop Registers
    reg [31:0] sd_fifo [0:4095];
    reg [11:0] sd_wr_ptr, sd_rd_ptr;
    reg [2:0]  state_ff;
    reg [31:0] match_count_ff;
    reg [27:0] ram_addr_ff;
    reg [31:0] latched_sd_ff;
    reg [31:0] latched_ram_ff;
    reg [31:0] lines_ff;
    reg        done_ff, passed_ff, rflag_ff;
    reg [31:0] f_ram_ff, f_sd_ff, l_ram_ff, l_sd_ff;

    // Combinational Next-State Signals
    reg [11:0] next_sd_wr_ptr, next_sd_rd_ptr;
    reg [2:0]  next_state;
    reg [31:0] next_match_count;
    reg [27:0] next_ram_addr;
    reg [31:0] next_latched_sd;
    reg [31:0] next_latched_ram;
    reg [31:0] next_lines;
    reg        next_done, next_passed, next_rflag;
    reg [31:0] next_f_ram, next_f_sd, next_l_ram, next_l_sd;
    reg        next_log_pulse;
    
    // Memory Logic Signal
    reg [31:0] next_fifo_val;

    // =========================================================================
    // 1. SEQUENTIAL BLOCK (ZERO LOGIC)
    // =========================================================================
    // Strictly register-to-register transfers. 
    // Even memory writes sample a pre-determined value from the comb block.
    always @(posedge clk) begin
        state_ff        <= next_state;
        sd_wr_ptr       <= next_sd_wr_ptr;
        sd_rd_ptr       <= next_sd_rd_ptr;
        match_count_ff  <= next_match_count;
        ram_addr_ff     <= next_ram_addr;
        latched_sd_ff   <= next_latched_sd;
        latched_ram_ff  <= next_latched_ram;
        lines_ff        <= next_lines;
        done_ff         <= next_done;
        passed_ff       <= next_passed;
        rflag_ff        <= next_rflag;
        f_ram_ff        <= next_f_ram;
        f_sd_ff         <= next_f_sd;
        l_ram_ff        <= next_l_ram;
        l_sd_ff         <= next_l_sd;
        
        // Output Update
        ram_addr        <= next_ram_addr;
        ram_rflag       <= next_rflag;
        test_done       <= next_done;
        test_passed     <= next_passed;
        lines_checked   <= next_lines;
        fail_ram_val    <= next_f_ram;
        fail_sd_val     <= next_f_sd;
        log_ram_val     <= next_l_ram;
        log_sd_val      <= next_l_sd;
        log_pulse       <= next_log_pulse;

        // FIFO Update (Logic-Free)
        // Values are routed by the brain; the sequential block just captures.
        sd_fifo[sd_wr_ptr] <= next_fifo_val;
    end

    // =========================================================================
    // 2. COMBINATIONAL BLOCK (ALL LOGIC, RESET, & MULTIPLEXING)
    // =========================================================================
    always @(*) begin
        
        // --- Default Values (Hold current state) ---
        next_state       = state_ff;
        next_sd_wr_ptr   = sd_wr_ptr;
        next_sd_rd_ptr   = sd_rd_ptr;
        next_match_count = match_count_ff;
        next_ram_addr    = ram_addr_ff;
        next_latched_sd  = latched_sd_ff;
        next_latched_ram = latched_ram_ff;
        next_lines       = lines_ff;
        next_done        = done_ff;
        next_passed      = passed_ff;
        next_rflag       = rflag_ff;
        next_f_ram       = f_ram_ff;
        next_f_sd        = f_sd_ff;
        next_l_ram       = l_ram_ff;
        next_l_sd        = l_sd_ff;
        next_log_pulse   = 1'b0;

        // --- FIFO Memory Update Logic ---
        // Decides what the RAM should "see" on the next clock edge.
        if (sd_lineflag) begin
            next_fifo_val  = sd_data;
            next_sd_wr_ptr = sd_wr_ptr + 12'd1;
        end else begin
            next_fifo_val  = sd_fifo[sd_wr_ptr]; // Re-circulate current data
        end

        // --- FSM Transitions ---
        case (state_ff)
            IDLE: begin
                next_done  = 1'b0;
                next_rflag = 1'b0;
                if (start_test) begin
                    next_sd_wr_ptr   = 12'd0;
                    next_sd_rd_ptr   = 12'd0;
                    next_match_count = 32'd0;
                    next_lines       = 32'd0;
                    next_ram_addr    = 28'd0;
                    if (primes_total > 0) next_state = CHECK_AVAIL;
                    else begin
                        next_passed = 1'b0;
                        next_state  = DONE;
                    end
                end
            end

            CHECK_AVAIL: begin
                if (match_count_ff < primes_total) next_state = CHECK_SD;
                else begin
                    next_passed = 1'b1;
                    next_state  = DONE;
                end
            end

            CHECK_SD: begin
                if (sd_rd_ptr != sd_wr_ptr) begin
                    next_latched_sd = sd_fifo[sd_rd_ptr];
                    next_sd_rd_ptr  = sd_rd_ptr + 12'd1;
                    next_state      = REQ_RAM;
                end
            end

            REQ_RAM: begin
                next_rflag = 1'b1;
                next_state = WAIT_RAM;
            end

            WAIT_RAM: begin
                if (ram_readfini) begin
                    next_rflag       = 1'b0;
                    next_latched_ram = ram_read_data;
                    next_state       = WAIT_RAM_ACK;
                end
            end

            WAIT_RAM_ACK: begin
                next_state = COMPARE;
            end

            COMPARE: begin
                if (latched_sd_ff[7:0] == 8'h41 || latched_sd_ff == 32'd65) begin
                    next_passed = 1'b1;
                    next_state  = DONE;
                end
                else if (latched_ram_ff == latched_sd_ff) begin
                    next_l_ram       = latched_ram_ff;
                    next_l_sd        = latched_sd_ff;
                    next_log_pulse   = 1'b1;
                    next_match_count = match_count_ff + 32'd1;
                    next_lines       = match_count_ff + 32'd1;
                    next_ram_addr    = ram_addr_ff + 28'd8;
                    next_state       = CHECK_AVAIL;
                end
                else begin
                    next_passed = 1'b0;
                    next_f_ram  = latched_ram_ff;
                    next_f_sd   = latched_sd_ff;
                    next_state  = DONE;
                end
            end

            DONE: begin
                next_done = 1'b1;
                if (!start_test) next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase

        // --- Synchronous Reset Logic (Overrides everything above) ---
        if (!rst_n) begin
            next_state       = IDLE;
            next_sd_wr_ptr   = 12'd0;
            next_sd_rd_ptr   = 12'd0;
            next_match_count = 32'd0;
            next_ram_addr    = 28'd0;
            next_latched_sd  = 32'd0;
            next_latched_ram = 32'd0;
            next_lines       = 32'd0;
            next_done        = 1'b0;
            next_passed      = 1'b0;
            next_rflag       = 1'b0;
            next_f_ram       = 32'd0;
            next_f_sd        = 32'd0;
            next_l_ram       = 32'd0;
            next_l_sd        = 32'd0;
            next_log_pulse   = 1'b0;
            next_fifo_val    = 32'd0;
        end
    end

endmodule
