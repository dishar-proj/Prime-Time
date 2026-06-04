`timescale 1ns / 1ps

module sd_sync_tb();

    // -------------------------------------------------------------------------
    // 1. Interface Signals
    // -------------------------------------------------------------------------
    reg         clk_cpu;
    reg         resetn;
    reg  [31:0] sd_data;
    reg         sd_lineflag;
    
    wire [31:0] cpu_data;
    wire        cpu_lineflag_pulse;

    // Testbench tracking
    integer tests_passed = 0;
    integer tests_failed = 0;

    // -------------------------------------------------------------------------
    // 2. Device Under Test (DUT)
    // -------------------------------------------------------------------------
    sd_sync dut (
        .clk_cpu            (clk_cpu),
        .resetn             (resetn),
        .sd_data            (sd_data),
        .sd_lineflag        (sd_lineflag),
        .cpu_data           (cpu_data),
        .cpu_lineflag_pulse (cpu_lineflag_pulse)
    );

    // -------------------------------------------------------------------------
    // 3. Clock Generation (100MHz / 10ns period)
    // -------------------------------------------------------------------------
    initial clk_cpu = 0;
    always #5 clk_cpu = ~clk_cpu;

    // -------------------------------------------------------------------------
    // 4. Verification Task: check_capture
    // -------------------------------------------------------------------------
    // This task waits for the pulse and verifies if the data matches
    task check_capture(input [31:0] expected_data);
        begin
            // Wait for the pulse (with a timeout to prevent infinite hangs)
            fork : timeout_block
                begin
                    wait(cpu_lineflag_pulse === 1'b1);
                    disable timeout_block;
                end
                begin
                    repeat (20) @(posedge clk_cpu); // 20 cycle timeout
                    $display("ERROR: Timeout waiting for cpu_lineflag_pulse!");
                    tests_failed = tests_failed + 1;
                    disable timeout_block;
                end
            join

            // Pulse detected, check data
            if (cpu_data === expected_data) begin
                $display("[PASS] Pulse detected. Data: 0x%h", cpu_data);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] Data mismatch! Expected: 0x%h, Got: 0x%h", expected_data, cpu_data);
                tests_failed = tests_failed + 1;
            end
            
            // Ensure pulse only lasts 1 cycle
            @(posedge clk_cpu);
            if (cpu_lineflag_pulse !== 1'b0) begin
                $display("[FAIL] Pulse lasted longer than 1 cycle!");
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // 5. Main Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // --- Initialize ---
        resetn      = 0;
        sd_data     = 32'h0;
        sd_lineflag = 0;
        
        $display("--- Starting sd_sync Exhaustive Test ---");
        repeat (5) @(posedge clk_cpu);
        resetn = 1;
        repeat (2) @(posedge clk_cpu);

        // --- Test 1: Simple Transfer ---
        $display("Test 1: Single data transfer...");
        sd_data     = 32'hDEADBEEF;
        sd_lineflag = 1;
        check_capture(32'hDEADBEEF);
        
        // Return flag to low (Simulating SD domain finishing a line)
        repeat (5) @(posedge clk_cpu);
        sd_lineflag = 0;
        repeat (5) @(posedge clk_cpu);

        // --- Test 2: Rapid Change (Stability Test) ---
        $display("Test 2: Ensure data is captured on edge only...");
        sd_data     = 32'h12345678;
        sd_lineflag = 1;
        
        // Immediately change sd_data after flag (simulating bad timing)
        // Note: Because of 3-stage sync, the DUT should capture the data 
        // present near the flag assertion.
        @(posedge clk_cpu);
        sd_data     = 32'hFFFFFFFF; 
        
        check_capture(32'h12345678); 
        sd_lineflag = 0;
        repeat (5) @(posedge clk_cpu);

        // --- Test 3: Reset During Operation ---
        $display("Test 3: Synchronous Reset Test...");
        sd_data     = 32'hA5A5A5A5;
        sd_lineflag = 1;
        repeat (1) @(posedge clk_cpu);
        resetn = 0; // Trigger reset before sync finishes
        repeat (5) @(posedge clk_cpu);
        
        if (cpu_data == 0 && cpu_lineflag_pulse == 0) begin
            $display("[PASS] Reset cleared registers.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Reset failed to clear registers.");
            tests_failed = tests_failed + 1;
        end
        
        resetn = 1;
        sd_lineflag = 0;
        repeat (5) @(posedge clk_cpu);

        // --- Test 4: Back-to-Back Transfers ---
        $display("Test 4: Sequential transfers...");
        
        // Transfer A
        sd_data = 32'h11112222; sd_lineflag = 1;
        check_capture(32'h11112222);
        sd_lineflag = 0;
        repeat (5) @(posedge clk_cpu);
        
        // Transfer B
        sd_data = 32'h33334444; sd_lineflag = 1;
        check_capture(32'h33334444);
        sd_lineflag = 0;

        // --- Final Report ---
        $display("---------------------------------------");
        $display("Verification Complete");
        $display("Tests Passed: %d", tests_passed);
        $display("Tests Failed: %d", tests_failed);
        $display("---------------------------------------");
        
        if (tests_failed == 0) $display("RESULT: ALL TESTS PASSED");
        else                  $display("RESULT: TEST SUITE FAILED");
        
        $finish;
    end

endmodule
