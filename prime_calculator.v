`timescale 1ns / 1ps

/*
 * The prime_calculator module is a custom hardware math engine designed to 
 * determine if a given 32-bit integer is a prime number. To meet FPGA timing 
 * constraints, it avoids the generic modulo operator (%) for large variables.
 * Instead, it handles base cases (like divisibility by 2 and 3) efficiently 
 * in a single cycle, and then uses a custom 32-cycle shift-and-subtract hardware 
 * divider to test potential factors using the 6k +/- 1 primality optimization.
 */

module prime_calculator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_search,   // Trigger to begin prime evaluation
    input  wire [31:0] num_in,         // The number to evaluate
    output reg         search_done,    // Pulses HIGH when evaluation is complete
    output reg         is_prime,       // 1 if prime, 0 if composite
    output reg  [31:0] calc_prime      // Passes through the evaluated number
);

    // State Encodings for the evaluation FSM and hardware divider
    localparam [3:0] IDLE       = 4'd0, // Waiting for start signal
                     BASE_CHECK = 4'd1, // Fast elimination of evens, 3s, and small numbers
                     PREP_I     = 4'd2, // Setup division for factor 'i'
                     DIV_CALC   = 4'd3, // Execute 32-cycle shift-and-subtract division
                     EVAL_REM   = 4'd4, // Check if the remainder is 0 (meaning it divides evenly)
                     PREP_I2    = 4'd5, // Setup division for factor 'i+2'
                     REPORT     = 4'd6; // Output results and return to IDLE

    // Internal Registers (_ff)
    reg [3:0]  state_ff, state_in;
    reg [31:0] n_ff, n_in;
    reg [31:0] i_ff, i_in;
    reg        is_prime_ff, is_prime_in;
    reg        search_done_ff, search_done_in;
    reg [31:0] calc_prime_ff, calc_prime_in;
    
    // Multi-cycle Divider Registers
    reg [31:0] div_n_ff, div_n_in;
    reg [31:0] div_d_ff, div_d_in;
    reg [31:0] div_rem_ff, div_rem_in;
    reg [5:0]  div_count_ff, div_count_in;
    reg        check_i2_ff, check_i2_in;

    // Combinational intermediate for shift-and-subtract math
    reg [31:0] temp_rem;

    // ========================================================================
    // Sequential Logic (Purely Flip-Flops)
    // ========================================================================
    always @(posedge clk) begin
        state_ff       <= state_in;
        n_ff           <= n_in;
        i_ff           <= i_in;
        is_prime_ff    <= is_prime_in;
        search_done_ff <= search_done_in;
        calc_prime_ff  <= calc_prime_in;
        
        div_n_ff       <= div_n_in;
        div_d_ff       <= div_d_in;
        div_rem_ff     <= div_rem_in;
        div_count_ff   <= div_count_in;
        check_i2_ff    <= check_i2_in;
        
        // Drive physical outputs
        search_done    <= search_done_in;
        is_prime       <= is_prime_in;
        calc_prime     <= calc_prime_in;
    end

    // ========================================================================
    // Combinational Logic (Resets & State Machine)
    // ========================================================================
    always @(*) begin
        // Default assignments to prevent inferred latches
        state_in       = state_ff;
        n_in           = n_ff;
        i_in           = i_ff;
        is_prime_in    = is_prime_ff;
        search_done_in = 1'b0;          
        calc_prime_in  = calc_prime_ff;
        
        div_n_in       = div_n_ff;
        div_d_in       = div_d_ff;
        div_rem_in     = div_rem_ff;
        div_count_in   = div_count_ff;
        check_i2_in    = check_i2_ff;
        
        temp_rem       = (div_rem_ff << 1) | {31'd0, div_n_ff[31]};

        // 1. Reset logic forces next-state to defaults
        if (~rst_n) begin
            state_in       = IDLE;
            n_in           = 32'd0;
            i_in           = 32'd5;
            is_prime_in    = 1'b0;
            search_done_in = 1'b0;
            calc_prime_in  = 32'd0;
            
            div_n_in       = 32'd0;
            div_d_in       = 32'd0;
            div_rem_in     = 32'd0;
            div_count_in   = 6'd0;
            check_i2_in    = 1'b0;
        end 
        // 2. Start trigger overrides current state
        else if (start_search) begin
            n_in        = num_in;
            i_in        = 32'd5;  
            is_prime_in = 1'b1;   
            state_in    = BASE_CHECK;
        end 
        // 3. Main State Machine Logic
        else begin
            case (state_ff)
                
                IDLE: begin
                    state_in = IDLE;
                end

                BASE_CHECK: begin
                    // Eliminate 0 and 1
                    if (n_ff <= 32'd1) begin
                        is_prime_in = 1'b0;
                        state_in    = REPORT;
                    end 
                    // Automatically pass 2 and 3
                    else if (n_ff <= 32'd3) begin
                        is_prime_in = 1'b1;
                        state_in    = REPORT;
                    end 
                    // Eliminate multiples of 2 or 3 (Modulo by constants synthesizes cleanly)
                    else if ((n_ff % 32'd2 == 32'd0) || (n_ff % 32'd3 == 32'd0)) begin
                        is_prime_in = 1'b0;
                        state_in    = REPORT;
                    end else begin
                        state_in    = PREP_I;
                    end
                end

                PREP_I: begin
                    // Exit condition: if i*i > n, we have checked all possible factors
                    if ((i_ff * i_ff) > n_ff) begin
                        is_prime_in = 1'b1;
                        state_in    = REPORT;
                    end else begin
                        // Setup the hardware divider for n / i
                        div_n_in     = n_ff;
                        div_d_in     = i_ff;
                        div_rem_in   = 32'd0;
                        div_count_in = 6'd31;
                        check_i2_in  = 1'b0; // Flag that we are testing 'i', not 'i+2'
                        state_in     = DIV_CALC;
                    end
                end

                PREP_I2: begin
                    // Setup the hardware divider for n / (i+2)
                    div_n_in     = n_ff;
                    div_d_in     = i_ff + 32'd2;
                    div_rem_in   = 32'd0;
                    div_count_in = 6'd31;
                    check_i2_in  = 1'b1; // Flag that we are testing 'i+2'
                    state_in     = DIV_CALC;
                end

                DIV_CALC: begin
                    // 32-Cycle Shift-and-Subtract Division Core
                    if (temp_rem >= div_d_ff) begin
                        div_rem_in = temp_rem - div_d_ff;
                        div_n_in   = {div_n_ff[30:0], 1'b1};
                    end else begin
                        div_rem_in = temp_rem;
                        div_n_in   = {div_n_ff[30:0], 1'b0};
                    end
                    
                    if (div_count_ff == 0) begin
                        state_in = EVAL_REM; // Division complete, go check results
                    end else begin
                        div_count_in = div_count_ff - 1;
                    end
                end

                EVAL_REM: begin
                    // If the remainder is 0, the number divides evenly and is NOT prime
                    if (div_rem_ff == 32'd0) begin
                        is_prime_in = 1'b0;
                        state_in    = REPORT;
                    end else begin
                        // Remainder is > 0, decide what to check next
                        if (check_i2_ff == 1'b0) begin
                            state_in = PREP_I2; // Go check the (i+2) case
                        end else begin
                            i_in     = i_ff + 32'd6; // Increment i by 6 and loop back
                            state_in = PREP_I;
                        end
                    end
                end

                REPORT: begin
                    // Pulse the done flag and push the result
                    search_done_in = 1'b1;
                    calc_prime_in  = n_ff; 
                    state_in       = IDLE;
                end

                default: begin
                    state_in = IDLE;
                end
                
            endcase
        end
    end
endmodule
