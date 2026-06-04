`timescale 1ns / 1ns

/*
 * This testbench verifies the 7-Segment Display multiplexer. It checks 
 * four critical operations: 1) System reset overrides to keep the display 
 * off, 2) The decoder properly translates Base-10 integers into 7-segment 
 * hex codes, 3) Zeros are properly padded across empty digits, and 4) The 
 * 0.75-second blink timer successfully overrides the anode to provide 
 * visual feedback when changing calculation speeds.
 */

module tb_Module_7SD(); 

    // Sandbox Inputs
    reg         clk;
    reg         rst;
    reg  [31:0] count;
    reg  [2:0]  speed_lvl;
    reg         speed_pulse;
    
    // Sandbox Outputs
    wire [7:0]  seg;
    wire [7:0]  an;

    integer passed_count = 0;
    integer failed_count = 0;
    
    // Device Under Test (DUT)
    Module_7SD dut (
        .clk(clk),
        .rst(rst),
        .count(count),
        .speed_lvl(speed_lvl),
        .speed_pulse(speed_pulse),
        .seg(seg),
        .an(an)
    );

    // 100MHz System Clock Generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper task to cleanly print pass/fail results to the console
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
        $dumpfile("tb_Module_7SD.vcd");
        $dumpvars(0, tb_Module_7SD);

        // 0. Initialize Inputs
        rst = 1'b0;
        count = 32'd0;
        speed_lvl = 3'd0;
        speed_pulse = 1'b0;

        $display("Starting Exhaustive Tests");
        $display("========================================");

        // TEST 1: Synchronous Reset
        // Verify that triggering the reset safely blanks out all Anodes and Segments
        @(negedge clk);
        rst = 1'b1;
        count = 32'd12345678; 
        
        repeat(5) @(negedge clk); // Flush the pipeline
        
        check("TEST 1.0: Reset overrides AN to 8'hFF (Off)", an === 8'hFF);
        check("TEST 1.1: Reset overrides SEG to 8'hFF (Off)", seg === 8'hFF);
        
        rst = 1'b0;

        // TEST 2: Digit Decoding
        // Wait for the multiplexer to cycle through the states and verify
        // that the mathematical values translate to the correct physical LED layouts.
        wait(dut.sel_ff == 3'd0);
        repeat(2) @(negedge clk); 
        check("TEST 2.0: Digit 0 AN is active (8'hFE)", an === 8'hFE);
        check("TEST 2.0: Digit 0 SEG decodes '8'", seg === 8'h80);

        wait(dut.sel_ff == 3'd1);
        repeat(2) @(negedge clk);
        check("TEST 2.1: Digit 1 AN is active (8'hFD)", an === 8'hFD);
        check("TEST 2.1: Digit 1 SEG decodes '7'", seg === 8'hF8);

        wait(dut.sel_ff == 3'd2);
        repeat(2) @(negedge clk);
        check("TEST 2.2: Digit 2 AN is active (8'hFB)", an === 8'hFB);
        check("TEST 2.2: Digit 2 SEG decodes '6'", seg === 8'h82);

        wait(dut.sel_ff == 3'd3);
        repeat(2) @(negedge clk);
        check("TEST 2.3: Digit 3 AN is active (8'hF7)", an === 8'hF7);
        check("TEST 2.3: Digit 3 SEG decodes '5'", seg === 8'h92);

        wait(dut.sel_ff == 3'd4);
        repeat(2) @(negedge clk);
        check("TEST 2.4: Digit 4 AN is active (8'hEF)", an === 8'hEF);
        check("TEST 2.4: Digit 4 SEG decodes '4'", seg === 8'h99);

        // TEST 3: Zero Padding
        // Verify that leading empty spaces default to "0" instead of glitching
        count = 32'd0;
        
        wait(dut.sel_ff == 3'd0); 
        repeat(2) @(negedge clk);
        check("TEST 3.0: Zero padding sets Digit 0 to '0'", seg === 8'hC0); 
        
        wait(dut.sel_ff == 3'd7); 
        repeat(2) @(negedge clk);
        check("TEST 3.1: Zero padding sets Digit 7 to '0'", seg === 8'hC0); 

        // TEST 4: Speed UI Blink Override
        // Trigger the speed pulse, then force the timer forward to ensure
        // the target anode is forcefully turned off during the "blink" phase
        speed_lvl = 3'd1;
        speed_pulse = 1'b1;
        @(negedge clk);
        speed_pulse = 1'b0;

        $display("--- Forcing blink_timer_ff to skip 8 million cycles ---");
        force dut.blink_timer_ff = 27'h800000; // Force Bit 23 HIGH (Blink OFF phase)
        
        wait(dut.sel_ff == 3'd1);
        repeat(2) @(negedge clk);
        check("TEST 4.0: Blink override correctly forces AN to 8'hFF", an === 8'hFF);
        
        release dut.blink_timer_ff;

        // TEST 5: Timer Expiration
        // Force the timer to its maximum value and verify that the anode 
        // control is successfully returned to the main multiplexer.
        $display("--- Forcing blink_timer_ff to skip 67 million cycles ---");
        force dut.blink_timer_ff = 27'd74_999_995; 
        release dut.blink_timer_ff; 
        
        // Allow the timer to organically cross the 75,000,000 shutdown threshold
        repeat(10) @(negedge clk);

        wait(dut.sel_ff == 3'd1);
        repeat(2) @(negedge clk);
        check("TEST 5.0: Blink timer expires and restores AN correctly (8'hFD)", an === 8'hFD);

        // -----------------------------------------
        // Final Results Summary
        // -----------------------------------------
        $display("=====================================");
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
