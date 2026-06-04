`timescale 1ns / 1ps

/*
 * This testbench verifies the hardware stopwatch logic in the execution_timer.
 * It tests five specific scenarios:
 * 1. Synchronous Reset behavior.
 * 2. Timer Clear behavior (including Dr. Herring's note to default sec to 1).
 * 3. Accurate 1ms tick generation.
 * 4. 1-second rollover logic (Fast-forwarded using Time Travel).
 * 5. The Time Limit interrupt generation.
 */

module tb_execution_timer();

    // ========================================================================
    // Sandbox Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;
    reg         timer_en;
    reg         timer_clear;
    reg  [31:0] time_limit_ms;

    wire [31:0] elapsed_ms;
    wire [31:0] elapsed_sec;
    wire        time_is_up;

    integer passed_count = 0;
    integer failed_count = 0;

    // ========================================================================
    // Unit Under Test (UUT)
    // ========================================================================
    execution_timer uut (
        .clk(clk),
        .rst_n(rst_n),
        .timer_en(timer_en),
        .timer_clear(timer_clear),
        .time_limit_ms(time_limit_ms),
        .elapsed_ms(elapsed_ms),
        .elapsed_sec(elapsed_sec),
        .time_is_up(time_is_up)
    );

    // ========================================================================
    // Clock Generation (100 MHz -> 10ns period)
    // ========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // ========================================================================
    // Helper Task for Verification
    // ========================================================================
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

    // ========================================================================
    // Main Stimulus
    // ========================================================================
    initial begin
        $display("==================================================");
        $display("--- Starting Execution Timer Verification ---");
        $display("==================================================");

        // 0. Initialize Inputs
        rst_n         = 0;
        timer_en      = 0;
        timer_clear   = 0;
        time_limit_ms = 32'd0;

        #100 rst_n = 1;

        // ---------------------------------------------------------
        // TEST 1: Synchronous Reset
        // ---------------------------------------------------------
        $display("\n--- TEST 1: Reset Initialization ---");
        check("1.0: elapsed_ms is 0", elapsed_ms === 32'd0);
        check("1.1: elapsed_sec is 0", elapsed_sec === 32'd0);
        check("1.2: time_is_up is 0", time_is_up === 1'b0);

        // ---------------------------------------------------------
        // TEST 2: Timer Clear
        // ---------------------------------------------------------
        $display("\n--- TEST 2: Timer Clear Pulse ---");
        @(posedge clk);
        timer_clear = 1'b1;
        @(posedge clk);
        timer_clear = 1'b0;
        @(posedge clk);

        check("2.0: elapsed_ms reset to 0", elapsed_ms === 32'd0);
        check("2.1: elapsed_sec rounds up to 1 (Per Dr. Herring's Note)", elapsed_sec === 32'd1);

        // ---------------------------------------------------------
        // TEST 3: 1ms Tick Generator
        // ---------------------------------------------------------
        $display("\n--- TEST 3: 1ms Tick Generation ---");
        @(posedge clk);
        timer_en = 1'b1; // Start the stopwatch

        // Wait exactly 100,000 clock cycles (1 millisecond at 100MHz)
        repeat(100000) @(posedge clk); 
        
        #1; // <--- FIX: Wait 1ns for the non-blocking assignments to physically settle!
        check("3.0: 1ms successfully counted", elapsed_ms === 32'd1);

        // ---------------------------------------------------------
        // TEST 4: 1-Second Rollover (Using Time Travel)
        // ---------------------------------------------------------
        $display("\n--- TEST 4: 1-Second Rollover (Fast Forwarded) ---");
        
        timer_en = 1'b0; // Pause stopwatch
        
        // Time Travel: Force the internal millisecond counter to 999 ms
        $display("         [Time Travel] Forcing internal ms counter to 999...");
        force uut.ms_cnt_ff = 10'd999;
        @(posedge clk);
        release uut.ms_cnt_ff; // Release so it can normally roll over on the next tick

        timer_en = 1'b1; // Resume stopwatch
        
        // Wait exactly 1 more millisecond to trigger the rollover
        repeat(100000) @(posedge clk); 
        
        #1; // <--- FIX: Wait 1ns for the non-blocking assignments to physically settle!
        check("4.0: elapsed_sec incremented to 2", elapsed_sec === 32'd2);

        // ---------------------------------------------------------
        // TEST 5: Time Limit Interrupt
        // ---------------------------------------------------------
        $display("\n--- TEST 5: Time Limit (Mode 2) Interrupt ---");
        
        timer_en = 1'b0; // Pause
        time_limit_ms = 32'd5; // Set limit to 5ms
        
        // Clear the timer back to 0
        @(posedge clk);
        timer_clear = 1'b1;
        @(posedge clk);
        timer_clear = 1'b0;

        // Enable and wait for the time_is_up flag to trigger
        timer_en = 1'b1;
        
        wait(time_is_up == 1'b1);
        @(posedge clk);

        check("5.0: time_is_up flag correctly asserted", time_is_up === 1'b1);
        check("5.1: Stopwatch successfully halted at exactly 5ms", elapsed_ms === 32'd5);

        // -----------------------------------------
        // Final Results Summary
        // -----------------------------------------
        $display("\n==================================================");
        $display("TEST SUMMARY");
        $display("Total Passed: %0d", passed_count);
        $display("Total Failed: %0d", failed_count);
        
        if (failed_count == 0) begin
            $display(">>> ALL TESTS PASSED! <<<");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        $display("==================================================");

        $finish;
    end

    // Safety Watchdog (100 ms limit)
    initial begin
        #100000000; 
        $display("[ERROR] Watchdog Timer Expired!");
        $finish;
    end

endmodule
