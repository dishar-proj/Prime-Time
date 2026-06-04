`timescale 1ns / 1ps

/*
 * The prime_mode module serves as the master orchestrator for the mathematical 
 * calculation engine. It manages the prime_calculator (math) and execution_timer 
 * (clocking) sub-modules. It operates in three distinct user modes:
 * Mode 0: Single Check (Is X prime?)
 * Mode 1: Find Primes Up To X (Evaluate 2 through X)
 * Mode 2: Find Primes For X Seconds (Evaluate sequentially until time is up)
 */

module prime_mode (
    // System Clock and Reset
    input  wire        clk,               // 100MHz System Clock
    input  wire        rst_n,             // Synchronous reset (Active-Low)
    
    // UI Engine Controls
    input  wire        start_engine,      // High to trigger the FSM
    input  wire [1:0]  mode_select,       // 0 = Single, 1 = Up To N, 2 = Fun Mode (Time)
    input  wire [31:0] user_val,          // The target number or time limit inputted by user
    
    // Engine Status Outputs
    output reg         engine_done,       // High when the entire calculation run is complete
    output reg  [31:0] total_time_ms,     // Elapsed execution time in milliseconds
    output reg  [31:0] total_primes,      // Accumulator for total primes found in the run
    
    // Live Data Stream Outputs (Used by UI and Memory Manager)
    output reg         prime_valid,       // 1-cycle pulse when a single evaluation finishes
    output reg  [31:0] current_num,       // The number that was just evaluated
    output reg         current_is_prime   // 1 if current_num is prime, 0 if composite
);

    // FSM State Definitions
    localparam [2:0] IDLE       = 3'd0, 
                     CALC_START = 3'd1, 
                     CALC_WAIT  = 3'd2, 
                     EVALUATE   = 3'd3, 
                     DONE       = 3'd4; 

    // Internal Registers (_ff)
    reg [2:0]  state_ff, state_in;
    reg [31:0] num_to_check_ff, num_to_check_in; 
    reg [31:0] primes_count_ff, primes_count_in; 
    
    reg        engine_done_ff, engine_done_in;
    reg        prime_valid_pulse_ff, prime_valid_pulse_in;

    // Timer Control Registers
    reg        timer_en_ff, timer_en_in;
    reg        timer_clear_ff, timer_clear_in;
    reg [31:0] time_limit_ff, time_limit_in;

    // Input Latch (Secures the user input so it can't change mid-calculation)
    reg [31:0] user_val_latched_ff, user_val_latched_in;

    // Core Interconnect Wires
    wire        core_done;
    wire        core_is_prime;
    wire [31:0] core_calc_prime;
    wire [31:0] timer_elapsed_ms;
    wire [31:0] timer_elapsed_sec;
    wire        timer_time_is_up;
    
    // Trigger signal for the math core
    reg         trigger_math;

    // ========================================================================
    // Sub-Module Instantiations
    // ========================================================================
    
    // The hardware divider and prime evaluation engine
    prime_calculator math_core (
        .clk(clk),
        .rst_n(rst_n),
        .start_search(trigger_math), 
        .num_in(num_to_check_ff),
        .search_done(core_done),
        .is_prime(core_is_prime),
        .calc_prime(core_calc_prime)
    );

    // The execution stopwatch
    execution_timer timer_core (
        .clk(clk),
        .rst_n(rst_n),
        .timer_en(timer_en_ff),
        .timer_clear(timer_clear_ff),
        .time_limit_ms(time_limit_ff),
        .elapsed_ms(timer_elapsed_ms),
        .elapsed_sec(timer_elapsed_sec), 
        .time_is_up(timer_time_is_up)
    );

    // ========================================================================
    // Sequential Logic (Flip-Flops only)
    // ========================================================================
    always @(posedge clk) begin
        state_ff             <= state_in;
        num_to_check_ff      <= num_to_check_in;
        primes_count_ff      <= primes_count_in;
        engine_done_ff       <= engine_done_in;
        prime_valid_pulse_ff <= prime_valid_pulse_in;
        timer_en_ff          <= timer_en_in;
        timer_clear_ff       <= timer_clear_in;
        time_limit_ff        <= time_limit_in;
        user_val_latched_ff  <= user_val_latched_in;
        
        // Drive Outputs
        engine_done          <= engine_done_in;
        total_time_ms        <= timer_elapsed_ms; 
        total_primes         <= primes_count_in;
        prime_valid          <= prime_valid_pulse_in;
        current_num          <= core_calc_prime;
        current_is_prime     <= core_is_prime;
    end

    // ========================================================================
    // Combinational Logic (State Transitions & Logic)
    // ========================================================================
    always @(*) begin
        // Trigger the math core for 1 cycle when entering CALC_START
        trigger_math         = (state_ff == CALC_START);
        
        // Default assignments to hold state and prevent latches
        state_in             = state_ff;
        num_to_check_in      = num_to_check_ff;
        primes_count_in      = primes_count_ff;
        engine_done_in       = engine_done_ff;
        prime_valid_pulse_in = 1'b0; // Default to low (pulse behavior)
        
        timer_en_in          = timer_en_ff;
        timer_clear_in       = 1'b0; // Default to low (pulse behavior)
        time_limit_in        = time_limit_ff;
        user_val_latched_in  = user_val_latched_ff;

        // Constantly grab the user input as long as we are idle, catching it right before start
        if (state_ff == IDLE && ~start_engine) begin
            user_val_latched_in = user_val;
        end

        // Synchronous Reset
        if (~rst_n) begin
            state_in             = IDLE;
            num_to_check_in      = 32'd0;
            primes_count_in      = 32'd0;
            engine_done_in       = 1'b0;
            prime_valid_pulse_in = 1'b0;
            timer_en_in          = 1'b0;
            timer_clear_in       = 1'b0;
            time_limit_in        = 32'd0;
            user_val_latched_in  = 32'd0;
        end else begin
            case (state_ff)
                
                // ------------------------------------------------------------
                // STATE 0: IDLE
                // Wait for the UI controller to command a start. Setup parameters.
                // ------------------------------------------------------------
                IDLE: begin
                    engine_done_in = 1'b0;
                    if (start_engine) begin
                        timer_clear_in  = 1'b1;
                        primes_count_in = 32'd0;
                        
                        // Mode 0: Single Check
                        if (mode_select == 2'd0) begin 
                            num_to_check_in = user_val_latched_ff; 
                            time_limit_in   = 32'd0;    
                            state_in        = CALC_START;
                        end 
                        // Modes 1 & 2: Range / Time Checks (Start counting at 2)
                        else begin
                            num_to_check_in = 32'd2;    
                            
                            // Translating the Input to Seconds by multiplying by 1000
                            if (mode_select == 2'd2) time_limit_in = user_val_latched_ff * 32'd1000; 
                            else                     time_limit_in = 32'd0; 

                            // Protect Mode 1 from crashing on 0 or 1 input
                            if (mode_select == 2'd1 && user_val_latched_ff < 32'd2) begin
                                state_in = DONE;
                            end else begin
                                state_in = CALC_START;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // STATE 1: CALC_START
                // Fire the trigger_math flag and start the stopwatch.
                // ------------------------------------------------------------
                CALC_START: begin
                    timer_en_in = 1'b1;
                    state_in    = CALC_WAIT;
                end

                // ------------------------------------------------------------
                // STATE 2: CALC_WAIT
                // Wait for the math_core to finish division, or the time to run out.
                // ------------------------------------------------------------
                CALC_WAIT: begin
                    // Exit condition for Fun Mode (Time is up)
                    if ((mode_select == 2'd2) && timer_time_is_up) begin
                        timer_en_in = 1'b0;
                        state_in    = DONE;
                    end 
                    // Core finished evaluating the current number
                    else if (core_done) begin
                        prime_valid_pulse_in = 1'b1; 
                        
                        if (core_is_prime) begin
                            primes_count_in = primes_count_ff + 32'd1; 
                        end
                        state_in = EVALUATE;
                    end
                end

                // ------------------------------------------------------------
                // STATE 3: EVALUATE
                // Decide whether to loop back for another number, or finish up.
                // ------------------------------------------------------------
                EVALUATE: begin
                    // Exit condition for Mode 0 (Only checking 1 number)
                    if (mode_select == 2'd0) begin 
                        timer_en_in = 1'b0;
                        state_in    = DONE;
                    end 
                    // Exit condition for Mode 1 (Reached the target limit)
                    else if ((mode_select == 2'd1) && (num_to_check_ff >= user_val_latched_ff)) begin
                        timer_en_in = 1'b0;
                        state_in    = DONE;
                    end 
                    // Otherwise, increment the number and loop back
                    else begin
                        num_to_check_in = num_to_check_ff + 32'd1;
                        state_in        = CALC_START;
                    end
                end

                // ------------------------------------------------------------
                // STATE 4: DONE
                // Assert the engine_done flag and wait for the UI to drop start_engine.
                // ------------------------------------------------------------
                DONE: begin
                    engine_done_in = 1'b1; 
                    
                    // Handshake: stay DONE until the master state machine releases us
                    if (~start_engine) begin
                        state_in = IDLE; 
                    end
                end

                default: begin
                    state_in = IDLE;
                end
                
            endcase
        end
    end
endmodule
