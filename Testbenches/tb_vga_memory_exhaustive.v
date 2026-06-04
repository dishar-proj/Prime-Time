`timescale 1ns / 1ps

/*
 * SUMMARY: 
 * Exhaustive self-checking testbench for the vga_memory module.
 * - Validates Reset, Normal Mode (Prime History), and Test Mode (RAM/SD Logs).
 * - Implements a terminal-based scoreboard to track and print test results.
 * - Designed to avoid "Parsing Error" by using standard Verilog-2001 timing.
 */

module tb_vga_memory_exhaustive();

    // --- Signals ---
    reg        clk_cpu;
    reg        resetn;
    reg [1:0]  screen_state;
    reg [2:0]  saved_idx;
    reg        prime_valid;
    reg        current_is_prime;
    reg [31:0] current_num;
    reg [31:0] test_log_ram;
    reg [31:0] test_log_sd;
    reg        test_log_pulse;
    reg [4:0]  read_addr;

    wire [31:0] read_data;

    // --- Scoreboard Variables ---
    integer tests_passed = 0;
    integer total_tests  = 0;

    // --- UUT Instantiation ---
    vga_memory uut (
        .clk_cpu(clk_cpu), .resetn(resetn), .screen_state(screen_state),
        .saved_idx(saved_idx), .prime_valid(prime_valid), 
        .current_is_prime(current_is_prime), .current_num(current_num),
        .test_log_ram(test_log_ram), .test_log_sd(test_log_sd),
        .test_log_pulse(test_log_pulse), .read_addr(read_addr),
        .read_data(read_data)
    );

    // Clock Generation (100MHz)
    initial begin
        clk_cpu = 0;
        forever #5 clk_cpu = ~clk_cpu;
    end

    // Self-Checking Task
    task check_data(input [31:0] expected, input [127:0] msg);
        begin
            total_tests = total_tests + 1;
            #1; // Small delay to allow combinational logic to settle
            if (read_data === expected) begin
                $display("[PASS] %s | Received: %h", msg, read_data);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s | Expected: %h, Got: %h", msg, expected, read_data);
            end
        end
    endtask

    // --- Main Test Sequence ---
    initial begin
        // 1. FORCED INITIALIZATION (Eliminates 'X' states)
        resetn = 0;
        screen_state = 0;
        saved_idx = 0;
        prime_valid = 0;
        current_is_prime = 0;
        current_num = 0;
        test_log_ram = 0;
        test_log_sd = 0;
        test_log_pulse = 0;
        read_addr = 0;

        $display("\n--- STARTING EXHAUSTIVE MEMORY VERIFICATION ---");
        #100 resetn = 1;

        // TEST 1: Reset Check
        check_data(32'd0, "Initial Post-Reset Read");

        // TEST 2: Normal Mode Prime Shifting
        $display("\nTesting Normal Mode Prime Entry...");
        saved_idx = 3'd0;
        current_is_prime = 1;
        
        // Entry 1: 0x7
        current_num = 32'h00000007; prime_valid = 1; #10; prime_valid = 0; #10;
        // Entry 2: 0xB
        current_num = 32'h0000000B; prime_valid = 1; #10; prime_valid = 0; #10;
        
        read_addr = 0; check_data(32'h0000000B, "Index 0: Newest Prime");
        read_addr = 1; check_data(32'h00000007, "Index 1: Previous Prime");

        // TEST 3: Test Mode Dual Logging (saved_idx == 3)
        $display("\nTesting Hardware Test Mode (Dual Grid)...");
        saved_idx = 3'd3;
        test_log_ram = 32'hA1A1A1A1;
        test_log_sd  = 32'hB2B2B2B2;
        test_log_pulse = 1; #10; test_log_pulse = 0; #10;
        
        read_addr = 0;  check_data(32'hA1A1A1A1, "RAM Column: Entry 0");
        read_addr = 10; check_data(32'hB2B2B2B2, "SD Column: Entry 0");

        // TEST 4: Screen State Wipe
        $display("\nTesting Screen Reset Condition...");
        screen_state = 2'b01; #20; screen_state = 2'b00;
        read_addr = 0; check_data(32'd0, "Memory Wipe Verification");

        // --- FINAL SUMMARY ---
        $display("\n========================================");
        $display("  SIMULATION RESULTS");
        $display("  Total Passed: %0d / %0d", tests_passed, total_tests);
        if (tests_passed == total_tests)
            $display("  VERIFICATION STATUS: SUCCESS");
        else
            $display("  VERIFICATION STATUS: FAILED");
        $display("========================================\n");

        $finish;
    end

endmodule
