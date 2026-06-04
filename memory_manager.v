`timescale 1ns / 1ps

/*
 * Module: memory_manager
 * ----------------------
 * Summary:
 * Manages the transfer of prime numbers from an internal FIFO to external memory.
 * * Strict "Logic-Free" Sequential Design:
 * 1. Sequential Block: Contains NO 'if', NO 'else', NO 'case'. It is purely a 
 * collection of non-blocking assignments (Sampling).
 * 2. Combinational Block: Contains ALL decision-making, including reset, 
 * FSM transitions, and write-enable signals.
 */

module memory_manager(
    input  wire         clk,
    input  wire         resetn,
 
    input  wire         start_engine,
    input  wire         prime_valid,
    input  wire         current_is_prime,
    input  wire [31:0]  current_num,
 
    input  wire         writefini,
    output reg  [27:0]  mem_addr_out,
    output reg  [63:0]  mem_data_out,
    output reg          wflag,
    
    output reg  [31:0]  primes_total,
    output wire         mm_idle
);

    // State Constants
    localparam [1:0] IDLE = 2'd0, WRITE_WAIT = 2'd1, WRITE_ACK_WAIT = 2'd2;

    // Registers (Flip-Flops)
    reg [31:0] fifo [0:1023];
    reg [9:0]  wr_ptr, rd_ptr;
    reg [1:0]  state_ff;
    reg [27:0] mem_addr_ff;
    reg [31:0] primes_total_ff;
    reg        wflag_ff;
    reg [63:0] mem_data_ff;
    reg        start_engine_d;

    // "Next" Wires (Outputs of Combinational Logic)
    reg [9:0]  next_wr_ptr, next_rd_ptr;
    reg [1:0]  next_state;
    reg [27:0] next_mem_addr;
    reg [31:0] next_primes_total;
    reg        next_wflag;
    reg [63:0] next_mem_data;
    reg        next_start_engine_d;

    // Helper logic for FIFO write control
    wire       fifo_we = (prime_valid && current_is_prime);
    assign     mm_idle = (state_ff == IDLE) && (wr_ptr == rd_ptr);

    // =========================================================================
    // SEQUENTIAL BLOCK
    // =========================================================================
    // No if-statements, no logic. Just direct sampling of next values.
    always @(posedge clk) begin
        wr_ptr          <= next_wr_ptr;
        rd_ptr          <= next_rd_ptr;
        state_ff        <= next_state;
        mem_addr_ff     <= next_mem_addr;
        primes_total_ff <= next_primes_total;
        wflag_ff        <= next_wflag;
        mem_data_ff     <= next_mem_data;
        start_engine_d  <= next_start_engine_d;
        
        
        fifo[wr_ptr]    <= fifo_we ? current_num : fifo[wr_ptr];
    end

    // =========================================================================
    // COMBINATIONAL BLOCK
    // =========================================================================
    always @(*) begin
        
        // --- 1. Default Assignments (Functional) ---
        next_wr_ptr         = wr_ptr;
        next_rd_ptr         = rd_ptr;
        next_state          = state_ff;
        next_mem_addr       = mem_addr_ff;
        next_primes_total   = primes_total_ff;
        next_wflag          = wflag_ff;
        next_mem_data       = mem_data_ff;
        next_start_engine_d = start_engine;

        // --- 2. Pointer/Engine Control ---
        // Edge detection for engine start resets local pointers
        if (start_engine && !start_engine_d) begin
            next_wr_ptr       = 10'd0;
            next_rd_ptr       = 10'd0;
            next_primes_total = 32'd0;
            next_mem_addr     = 28'd0;
        end else if (fifo_we) begin
            next_wr_ptr       = wr_ptr + 10'd1;
        end

        // --- 3. FSM Handshaking Logic ---
        case (state_ff)
            IDLE: begin
                if (rd_ptr != wr_ptr) begin
                    next_mem_data = {32'd0, fifo[rd_ptr]};
                    next_wflag    = 1'b1;
                    next_state    = WRITE_WAIT;
                end
            end

            WRITE_WAIT: begin
                if (writefini) begin
                    next_wflag        = 1'b0;
                    next_primes_total = primes_total_ff + 32'd1;
                    next_mem_addr     = mem_addr_ff + 28'd8;
                    next_rd_ptr       = rd_ptr + 10'd1;
                    next_state        = WRITE_ACK_WAIT;
                end
            end

            WRITE_ACK_WAIT: begin
                if (!writefini) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase

        // --- 4. Global Synchronous Reset Override ---
        // This multiplexes the final 'next' values to zero/idle on reset
        if (!resetn) begin
            next_wr_ptr         = 10'd0;
            next_rd_ptr         = 10'd0;
            next_state          = IDLE;
            next_mem_addr       = 28'd0;
            next_primes_total   = 32'd0;
            next_wflag          = 1'b0;
            next_mem_data       = 64'd0;
            next_start_engine_d = 1'b0;
        end

        // --- 5. Output Driver ---
        mem_addr_out = mem_addr_ff;
        mem_data_out = mem_data_ff;
        wflag        = wflag_ff;
        primes_total = primes_total_ff;
    end

endmodule
