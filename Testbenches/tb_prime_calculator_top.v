`timescale 1ns / 1ps

/*
 * This testbench verifies the top-level FSM ('prime_mode') which orchestrates 
 * both the math engine and the execution timer. It independently tests all 
 * three operational modes:
 * - Mode 0: Single Number Evaluation
 * - Mode 1: Search for primes up to a numerical limit
 * - Mode 2: Search for primes until a timer runs out
 *
 * * Note: An explicit 1-cycle setup time is used before pulling the start trigger 
 * to ensure the hardware input latches catch the new data.
 */

module tb_prime_calculator_top();

    // ========================================================================
    // Sandbox Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;
    reg         start_engine;
    reg  [1:0]  mode_select;
    reg  [31:0] user_val;

    wire        engine_done;
    wire [31:0] total_time_ms;
    wire [31:0] total_primes;
    wire        prime_valid;
    wire [31:0] current_num;
    wire        current_is_prime;

    // ========================================================================
    // Unit Under Test (UUT)
    // ========================================================================
    prime_mode uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_engine(start_engine),
        .mode_select(mode_select),
        .user_val(user_val),
        .engine_done(engine_done),
        .total_time_ms(total_time_ms),
        .total_primes(total_primes),
        .prime_valid(prime_valid),
        .current_num(current_num),
        .current_is_prime(current_is_prime)
    );

    // 100MHz System Clock Generation
    always #5 clk = ~clk;

    // ========================================================================
    // Test Tasks for Each Operating Mode
    // ========================================================================

    // --- Task: Test Mode 0 (Specific Number Check) ---
    task test_mode_0;
        input [31:0] test_num;
        input        expected_is_prime;
        begin
            $display("--- Testing Mode 0 (Single Check): Number %d ---", test_num);
            
            // 1. Setup Data and give it 1 clock cycle to lock into the UUT's safety latch
            mode_select  = 2'd0; 
            user_val     = test_num;
            @(posedge clk); 
            
            // 2. Pull the Trigger
            start_engine = 1'b1;
            @(posedge clk);
            start_engine = 1'b0;

            // 3. Wait for calculation to finish
            wait(engine_done);
            @(posedge clk);

            // 4. Verify
            if (current_is_prime === expected_is_prime && current_num === test_num) begin
                $display("[PASS] Mode 0: Correctly identified %d as prime=%b", test_num, expected_is_prime);
            end else begin
                $display("[FAIL] Mode 0: Failed on %d. Expected: %b, Got: %b", test_num, expected_is_prime, current_is_prime);
            end
            
            // 5. Teardown logic to allow flip-flops to clear (prevents ghost signals)
            wait(uut.state_ff == 3'd0);
            wait(engine_done == 1'b0);
            repeat(2) @(posedge clk);
        end
    endtask

    // --- Task: Test Mode 1 (Numerical Limit) ---
    task test_mode_1;
        input [31:0] limit_val;
        input [31:0] expected_total_primes;
        begin
            $display("--- Testing Mode 1 (Numerical Limit): Up to %d ---", limit_val);
            
            // 1. Setup Data and Latch
            mode_select  = 2'd1;
            user_val     = limit_val;
            @(posedge clk); 
            
            // 2. Trigger
            start_engine = 1'b1;
            @(posedge clk);
            start_engine = 1'b0;

            // 3. Wait
            wait(engine_done);
            @(posedge clk);

            // 4. Verify accumulator count
            if (total_primes === expected_total_primes) begin
                $display("[PASS] Mode 1: Found exactly %d primes up to %d", total_primes, limit_val);
            end else begin
                $display("[FAIL] Mode 1: Expected %d primes, but found %d", expected_total_primes, total_primes);
            end
            
            // 5. Teardown
            wait(uut.state_ff == 3'd0);
            wait(engine_done == 1'b0);
            repeat(2) @(posedge clk);
        end
    endtask

    // --- Task: Test Mode 2 (Time Limit) FAST FORWARDED ---
    task test_mode_2;
        input [31:0] time_limit_sec;
        begin
            $display("--- Testing Mode 2 (Time Limit): %d seconds (FAST FORWARDED) ---", time_limit_sec);
            
            // 1. Setup Data and Latch
            mode_select  = 2'd2;
            user_val     = time_limit_sec;
            @(posedge clk); 
            
            // 2. Trigger
            start_engine = 1'b1;
            @(posedge clk);
            start_engine = 1'b0;

            // Let the hardware calculate normally for 50 cycles to prove the state machine works
            repeat(50) @(posedge clk);

            // 3. TIME TRAVEL: Force the internal timer wires to simulate time running out instantly
            $display("         [Time Travel] Forcing the internal clock to %d ms...", time_limit_sec * 1000);
            force uut.timer_time_is_up = 1'b1;
            force uut.timer_elapsed_ms = time_limit_sec * 1000;

            // Wait for the FSM to catch the forced timeout and gracefully exit
            wait(engine_done);
            @(posedge clk);

            // 4. Drop the forces so the hardware returns to its normal physical behavior
            release uut.timer_time_is_up;
            release uut.timer_elapsed_ms;

            // 5. Verify
            if (total_time_ms === (time_limit_sec * 1000)) begin
                $display("[PASS] Mode 2: Engine correctly halted at exactly %d ms.", total_time_ms);
            end else begin
                $display("[FAIL] Mode 2: Engine halted at %d ms instead of %d ms.", total_time_ms, (time_limit_sec * 1000));
            end
            
            // 6. Teardown
            wait(uut.state_ff == 3'd0);
            wait(engine_done == 1'b0);
            repeat(2) @(posedge clk);
        end
    endtask
    // ========================================================================
    // Main Stimulus
    // ========================================================================
    initial begin
        // 1. Initialize Inputs
        clk          = 0;
        rst_n        = 0;
        start_engine = 0;
        mode_select  = 2'd0;
        user_val     = 32'd0;

        $dumpfile("prime_top_tb.vcd");
        $dumpvars(0, tb_prime_calculator_top);

        #20 rst_n = 1; #20;

        $display("===============================================================");
        $display("--- Starting Adventure Prime Time: Top-Level Testbench ---");
        $display("===============================================================");

        // --- Run Mode 0 Tests ---
        test_mode_0(32'd5, 1'b1);
        test_mode_0(32'd25, 1'b0);
        test_mode_0(32'd104729, 1'b1); 

        // --- Run Mode 1 Tests ---
        // Primes up to 20: 2, 3, 5, 7, 11, 13, 17, 19 (Total = 8)
        test_mode_1(32'd20, 32'd8);
        test_mode_1(32'd100, 32'd25);

        // --- Run Mode 2 Test ---
        // Warning: Simulating 1 full second takes real-world time in Vivado!
        test_mode_2(32'd1); 

        $display("===============================================================");
        $display("--- Testbench Complete ---");
        $display("===============================================================");
        $finish;
    end

    // ========================================================================
    // Safety Watchdog Timer
    // ========================================================================
    // Expanded to 2 seconds (2,000,000,000 ns) to allow the Mode 2 test to finish.
    initial begin
        #2000000000; 
        $display("[ERROR] Watchdog Timer Expired! Simulation stuck in an infinite loop.");
        $finish;
    end

endmodule
