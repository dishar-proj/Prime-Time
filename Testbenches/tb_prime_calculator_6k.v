`timescale 1ns / 1ps

/*
 * This testbench verifies the raw mathematical logic of the 'prime_calculator' 
 * core. It utilizes a "Software Truth" reference function to independently 
 * calculate prime numbers and compares those results against the hardware's 
 * output. 
 *
 * It features two modes:
 * 1. Visualizer Mode: Traces the hardware's internal state machine to physically 
 * watch the 6k +/- 1 algorithm skip multiples of 2 and 3 in real-time.
 * 2. Exhaustive Mode: Silently tests tens of thousands of numbers in a loop 
 * to guarantee there are no mathematical edge-case failures.
 */

module tb_prime_calculator_6k();

    // ========================================================================
    // Sandbox Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;
    reg         start_search;
    reg  [31:0] num_in;

    wire        search_done;
    wire        is_prime;
    wire [31:0] calc_prime;

    // Testbench Control Variables
    reg         verbose_mode;
    integer     total_tests_run = 0;
    integer     total_errors = 0;

    // ========================================================================
    // Unit Under Test (UUT)
    // ========================================================================
    prime_calculator uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_search(start_search),
        .num_in(num_in),
        .search_done(search_done),
        .is_prime(is_prime),
        .calc_prime(calc_prime)
    );

    // 100MHz System Clock Generation
    always #5 clk = ~clk;

    // ========================================================================
    // Behavioral Reference Function (The "Software Truth")
    // ========================================================================
    function automatic reg is_prime_ref;
        input [31:0] n;
        integer i;
        begin
            if (n <= 1) is_prime_ref = 0;
            else if (n == 2 || n == 3) is_prime_ref = 1;
            else if (n % 2 == 0 || n % 3 == 0) is_prime_ref = 0;
            else begin
                is_prime_ref = 1; 
                for (i = 5; (i * i <= n) && (is_prime_ref == 1); i = i + 6) begin
                    if (n % i == 0 || n % (i + 2) == 0) begin
                        is_prime_ref = 0;
                    end
                end
            end
        end
    endfunction

    // ========================================================================
    // Hardware State Monitor (Visualizes the 6k +/- 1 jumps)
    // ========================================================================
    always @(posedge clk) begin
        if (verbose_mode && !uut.search_done_ff && uut.state_ff != 4'd0) begin
            if (uut.state_ff == 4'd1) begin
                $display("   [Trace] BASE_CHECK: Testing if %0d <= 3, or divisible by 2 or 3...", uut.n_ff);
            end
            else if (uut.state_ff == 4'd2) begin
                $display("   [Trace] 6k-1 Check: Is %0d divisible by %0d?", uut.n_ff, uut.i_ff);
            end 
            else if (uut.state_ff == 4'd5) begin
                $display("   [Trace] 6k+1 Check: Is %0d divisible by %0d?", uut.n_ff, uut.i_ff + 32'd2);
            end
        end
    end

    // ========================================================================
    // Core Testing Task
    // ========================================================================
    task check_prime;
        input [31:0] test_num;
        input        v_mode;    // 1 to print the trace, 0 for silent testing
        reg          expected_result;
        begin
            // 1. Get the correct answer from the software function
            expected_result = is_prime_ref(test_num);
            verbose_mode    = v_mode;
            
            if (verbose_mode) $display("\n>>> Starting Search for N = %0d <<<", test_num);

            // 2. Trigger the hardware
            @(posedge clk);
            num_in       = test_num;
            start_search = 1'b1;
            
            @(posedge clk);
            start_search = 1'b0; 

            // 3. Wait for hardware completion
            wait(search_done);
            @(posedge clk); 
            verbose_mode = 1'b0; // Turn off trace to prevent clutter

            // 4. Compare Results
            total_tests_run = total_tests_run + 1;
            if ((is_prime !== expected_result) || (calc_prime !== test_num)) begin
                $display("[FAIL] Num: %d | Expected: %b | Got: %b", test_num, expected_result, is_prime);
                total_errors = total_errors + 1;
            end else if (v_mode) begin
                $display("[PASS] Result: %0d is %s", test_num, is_prime ? "PRIME" : "COMPOSITE");
            end
            
            #10; // Buffer between tests
        end
    endtask

    // ========================================================================
    // Main Stimulus
    // ========================================================================
    integer num;

    initial begin
        // 1. Initialize
        clk          = 0;
        rst_n        = 0;
        start_search = 0;
        num_in       = 0;
        verbose_mode = 0;

        #20 rst_n = 1; #20;

        $display("===============================================================");
        $display("--- Adventure Prime Time: 6k +/- 1 Algorithm Visualizer ---");
        $display("===============================================================");

        // --- PART 1: Visualizing the Algorithm (Verbose Mode = 1) ---
        
        // Example 1: A Prime Number (79)
        check_prime(32'd79, 1'b1);

        // Example 2: A Composite Number sitting on a 6k +/- 1 spot (77)
        check_prime(32'd77, 1'b1);

        // Example 3: A Fast Exit (Even number, instantly eliminated)
        check_prime(32'd100, 1'b1);

        // --- PART 2: Exhaustive Verification (Verbose Mode = 0) ---
        $display("\n===============================================================");
        $display("--- Running Silent Exhaustive Check: 0 to 10,000 ---");
        
        for (num = 0; num <= 10000; num = num + 1) begin
            check_prime(num, 1'b0); 
        end

        // Final Report
        $display("===============================================================");
        if (total_errors == 0) begin
            $display("[SUCCESS] All %0d numbers tested flawlessly!", total_tests_run);
        end else begin
            $display("[ERROR] %0d failures detected.", total_errors);
        end
        $display("===============================================================");
        $finish;
    end

endmodule
