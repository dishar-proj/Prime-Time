`timescale 1ns / 1ps

/*
 * This testbench verifies the prime_mode wrapper. Because this module 
 * instantiates the actual math and timer cores, we test it using 
 * real mathematical scenarios. 
 * * Note: An explicit wait block is used during teardown to prevent a 
 * "ghost signal" race condition where a leftover 'engine_done' flag 
 * accidentally triggers the next test too early.
 */

module tb_prime_mode();

    // Sandbox Inputs
    reg         clk;
    reg         rst_n;
    reg         start_engine;
    reg  [1:0]  mode_select;
    reg  [31:0] user_val;

    // Sandbox Outputs
    wire        engine_done;
    wire [31:0] total_time_ms;
    wire [31:0] total_primes;
    wire        prime_valid;
    wire [31:0] current_num;
    wire        current_is_prime;

    integer passed_count = 0;
    integer failed_count = 0;

    // Device Under Test (DUT)
    prime_mode dut (
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
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper task to cleanly print pass/fail results
    task check;
        input [800:0] test_name; 
        input condition;
        begin
            if (condition) begin
                $display("[PASS] %0s", test_name);
                passed_count = passed_count + 1;
            end else begin
                $display("[FAIL] %0s", test_name);
                failed_count = failed_count + 1;
            end
        end
    endtask

    // --- Main Verification Sequence ---
    initial begin
        $display("========================================");
        $display("Starting Prime Mode Engine Tests");
        $display("========================================");

        // 0. Initialize & Reset
        rst_n = 0;
        start_engine = 0;
        mode_select = 2'd0;
        user_val = 32'd0;
        
        #100 rst_n = 1;

        // ---------------------------------------------------------
        // TEST 1: Mode 0 (Single Check)
        // ---------------------------------------------------------
        $display("\n--- Testing Mode 0 (Single Check: 7 is Prime) ---");
        mode_select = 2'd0;
        user_val = 32'd7; 
        
        @(posedge clk);
        start_engine = 1; // Pull trigger
        
        // Wait for the engine to finish the calculation
        wait(engine_done == 1'b1);
        @(posedge clk);
        
        check("TEST 1.0: Engine reports DONE", engine_done === 1'b1);
        check("TEST 1.1: Correctly evaluated 7", current_num === 32'd7);
        check("TEST 1.2: Correctly identified as PRIME (1)", current_is_prime === 1'b1);

        // TEARDOWN & RACE CONDITION FIX
        start_engine = 0; 
        wait(dut.state_ff == 3'd0); // Wait for FSM to return to IDLE
        wait(engine_done == 1'b0);  // Wait for the DONE flag flip-flop to physically clear
        repeat(2) @(posedge clk);   // Buffer cycles before next test starts
        
        // ---------------------------------------------------------
        // TEST 2: Mode 1 (Range Check)
        // ---------------------------------------------------------
        $display("\n--- Testing Mode 1 (Primes up to 10) ---");
        mode_select = 2'd1;
        user_val = 32'd10; // Should find 4 primes: 2, 3, 5, 7
        
        @(posedge clk);
        start_engine = 1; 
        
        wait(engine_done == 1'b1);
        @(posedge clk);
        
        check("TEST 2.0: Engine reports DONE", engine_done === 1'b1);
        check("TEST 2.1: Total primes found is 4", total_primes === 32'd4);

        // TEARDOWN & RACE CONDITION FIX
        start_engine = 0; 
        wait(dut.state_ff == 3'd0); 
        wait(engine_done == 1'b0);  
        repeat(2) @(posedge clk);   

        // ---------------------------------------------------------
        // TEST 3: Mode 2 (Time/Fun Mode Exit Logic)
        // Note: Simulating full seconds takes too long, so we force
        // the timer's 'time_is_up' wire to verify the FSM exit hatch.
        // ---------------------------------------------------------
        $display("\n--- Testing Mode 2 (Timeout Exit Logic) ---");
        mode_select = 2'd2;
        user_val = 32'd5; // 5 seconds
        
        @(posedge clk);
        start_engine = 1; 
        
        // Let it calculate for a few clock cycles
        repeat(50) @(posedge clk);
        
        // Force the timer to report time is up
        force dut.timer_time_is_up = 1'b1;
        
        wait(engine_done == 1'b1);
        @(posedge clk);
        
        check("TEST 3.0: Engine successfully exits on timeout", engine_done === 1'b1);
        
        // TEARDOWN
        release dut.timer_time_is_up;
        start_engine = 0; 
        wait(dut.state_ff == 3'd0);
        wait(engine_done == 1'b0);

        // -----------------------------------------
        // Final Results Summary
        // -----------------------------------------
        $display("\n=====================================");
        $display("TEST SUMMARY");
        $display("Total Passed: %0d", passed_count);
        $display("Total Failed: %0d", failed_count);
        
        if (failed_count == 0) begin
            $display(">>> ALL TESTS PASSED! <<<");
        end else begin
            $display("SOME TESTS FAILED!");
        end

        $finish;
    end

endmodule
