`timescale 1ns / 1ps

/*
 * TESTBENCH SUMMARY: tb_sd_reader
 * This testbench simulates the SD card initialization and sector read process.
 * It provides a mock response for the sdcmd_ctrl sub-module and simulates 
 * serial data on the sddat0 line.
 * It tracks passed/failed assertions and prints a final report to the terminal.
 */

module tb_sd_reader();

    // Testbench signals
    reg rstn;
    reg clk;
    reg sddat0;
    reg rstart;
    reg [31:0] rsector;
    
    wire sdclk;
    wire [3:0] card_stat;
    wire [1:0] card_type;
    wire rbusy, rdone, outen;
    wire [8:0] outaddr;
    wire [7:0] outbyte;

    // Simulation control
    integer tests_passed = 0;
    integer total_tests = 0;

    // Mock SD Command Controller Signals (usually internal to sd_reader)
    // We will use 'force' or provide a mock sdcmd_ctrl if necessary.
    // For this TB, we simulate the 'busy' and 'done' wires inside the reader.
    
    sd_reader #(.SIMULATE(1)) uut (
        .rstn(rstn),
        .clk(clk),
        .sdclk(sdclk),
        .sddat0(sddat0),
        .card_stat(card_stat),
        .card_type(card_type),
        .rstart(rstart),
        .rsector(rsector),
        .rbusy(rbusy),
        .rdone(rdone),
        .outen(outen),
        .outaddr(outaddr),
        .outbyte(outbyte)
    );

    // Clock Generation: 100MHz
    always #5 clk = ~clk;

    // Reporting Task
    task check_result(input condition, input [127:0] test_name);
    begin
        total_tests = total_tests + 1;
        if (condition) begin
            $display("[PASS] %s", test_name);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] %s", test_name);
        end
    end
    endtask

    // Mocking the low-level sdcmd_ctrl responses
    // In a real simulation, we would instantiate the actual sdcmd_ctrl.
    // Here we manipulate the signals via the hierarchy for a self-contained TB.
    initial begin
        force uut.busy = 0;
        force uut.done = 0;
        force uut.timeout = 0;
        force uut.syntaxe = 0;
        force uut.resparg = 32'h0;
    end

    initial begin
        // --- Initialization ---
        clk = 0;
        rstn = 0;
        sddat0 = 1;
        rstart = 0;
        rsector = 32'h00000001;

        #100 rstn = 1;
        check_result(uut.sdcmd_stat_ff == 4'd0, "Module initialized to CMD0");

        // --- Simulate Initialization Sequence ---
        // CMD0 -> CMD8
        #50 release uut.busy; force uut.busy = 1; #50 force uut.busy = 0; force uut.done = 1;
        #10 force uut.done = 0;
        check_result(uut.sdcmd_stat_ff == 4'd1, "Transitioned to CMD8");

        // CMD8 -> CMD55
        force uut.resparg = 32'h000001aa; // Card confirms voltage
        #50 force uut.done = 1; #10 force uut.done = 0;
        check_result(uut.sdcmd_stat_ff == 4'd2, "Transitioned to CMD55");

        // ACMD41 (Ready) -> CMD2
        force uut.sdcmd_stat_ff = 4'd3; // Force state to skip loop
        force uut.resparg = 32'hC0000000; // Ready bit + SDHC bit
        #50 force uut.done = 1; #10 force uut.done = 0;
        check_result(card_type == 2'd3, "Card detected as SDHCv2");

        // Skip to CMD17 (Idle state ready for read)
        force uut.sdcmd_stat_ff = 4'd8; 
        #100;
        check_result(rbusy == 0, "Controller idle and ready for read");

        // --- Sector Read Test ---
        rstart = 1;
        #10 rstart = 0;
        check_result(uut.sdcmd_stat_ff == 4'd9, "State changed to READING");

        // Mock Serial Data on sddat0
        #50 sddat0 = 0; // Start bit
        
        // Send 8 bits (Value 8'hA5 = 10100101)
        #10 sddat0 = 1; #10 sddat0 = 0; #10 sddat0 = 1; #10 sddat0 = 0;
        #10 sddat0 = 0; #10 sddat0 = 1; #10 sddat0 = 0; #10 sddat0 = 1;
        
        #100; // Wait for processing
        check_result(outbyte == 8'hA5, "Byte 0 read correctly as 0xA5");
        check_result(outen == 1, "Output enable pulsed for byte 0");

        // --- Final Report ---
        $display("\n========================================");
        $display("   TEST SUMMARY");
        $display("   Passed: %d", tests_passed);
        $display("   Total:  %d", total_tests);
        if (tests_passed == total_tests) 
            $display("   STATUS: ALL TESTS PASSED");
        else 
            $display("   STATUS: FAILED");
        $display("========================================\n");
        $finish;
    end

endmodule
