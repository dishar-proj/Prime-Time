`timescale 1ns / 1ps

module ram_interface_tb();

    // -- Clock and Reset signals --
    reg clk_mem;
    reg clk_cpu;
    reg resetn;
    
    // -- Data and Control signals --
    reg [27:0] mem_addr_in;
    reg [63:0] mem_d_to_ram_in;
    wire [63:0] mem_d_from_ram_out;
    reg rflag;
    reg wflag;
    reg lineflag;
    
    // -- Status signals --
    wire ramflag;
    wire readfini;
    wire writefini;
    wire [15:0] led;

    // -- DDR2 physical interface wires --
    wire [15:0] ddr2_dq;
    wire [1:0]  ddr2_dqs_n;
    wire [1:0]  ddr2_dqs_p;
    wire [12:0] ddr2_addr;
    wire [2:0]  ddr2_ba;
    wire        ddr2_ras_n;
    wire        ddr2_cas_n;
    wire        ddr2_we_n;
    wire        ddr2_ck_p;
    wire        ddr2_ck_n;
    wire        ddr2_cke;
    wire        ddr2_cs_n;
    wire [1:0]  ddr2_dm;
    wire        ddr2_odt;

    // -- Testbench variables --
    integer pass_count = 0;
    integer fail_count = 0;

    // ---------------------------------------------------------
    // DUT Instance (Explicit Mapping to avoid errors)
    // ---------------------------------------------------------
    ram_interface dut (
        .clk_mem(clk_mem),
        .clk_cpu(clk_cpu),
        .resetn(resetn),
        .lineflag(lineflag),
        .mem_addr_in(mem_addr_in),
        .mem_d_to_ram_in(mem_d_to_ram_in),
        .mem_d_from_ram_out(mem_d_from_ram_out),
        .ramflag(ramflag),
        .rflag(rflag),
        .wflag(wflag),
        .readfini(readfini),
        .writefini(writefini),
        .led(led),
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt)
    );

    // -- Clock Generation --
    initial clk_cpu = 0;
    always #5 clk_cpu = ~clk_cpu; // 100MHz CPU Clock

    initial clk_mem = 0;
    always #2.5 clk_mem = ~clk_mem; // 200MHz Mem Clock

    // ---------------------------------------------------------
    // Task: verify_memory
    // Writes data and then reads it back to check if it matches
    // ---------------------------------------------------------
    task verify_memory(input [27:0] addr, input [63:0] data);
        begin
            // 1. Start the Write
            @(posedge clk_cpu);
            mem_addr_in = addr;
            mem_d_to_ram_in = data;
            wflag = 1;
            
            // Wait for write to finish (with a simple timeout)
            fork : write_wait
                begin
                    wait(writefini == 1);
                    disable write_wait;
                end
                begin
                    #10000; // Wait 10us then give up
                    $display("Error: Write timed out at addr %h", addr);
                    $finish;
                end
            join
            
            wflag = 0;
            repeat(10) @(posedge clk_cpu); // Gap between commands

            // 2. Start the Read
            rflag = 1;
            fork : read_wait
                begin
                    wait(readfini == 1);
                    disable read_wait;
                end
                begin
                    #10000; // Wait 10us then give up
                    $display("Error: Read timed out at addr %h", addr);
                    $finish;
                end
            join
            
            // 3. Compare Data
            if (mem_d_from_ram_out === data) begin
                $display("Success: Addr %h | Data matches: %h", addr, data);
                pass_count = pass_count + 1;
            end else begin
                $display("Failure: Addr %h | Sent %h | Got %h", addr, data, mem_d_from_ram_out);
                fail_count = fail_count + 1;
            end
            
            rflag = 0;
            repeat(10) @(posedge clk_cpu);
        end
    endtask

    // ---------------------------------------------------------
    // Main Simulation Flow
    // ---------------------------------------------------------
    initial begin
        // Startup values
        resetn = 0;
        lineflag = 0;
        mem_addr_in = 0;
        mem_d_to_ram_in = 0;
        rflag = 0;
        wflag = 0;

        $display("Starting testing...");
        #100 resetn = 1; // Release reset

        // Wait for Calibration
        $display("Waiting for RAM to calibrate...");
        wait(ramflag == 1);
        $display("RAM is ready for commands.");

        // Test multiple addresses
        verify_memory(28'h0001000, 64'h1234567887654321);
        verify_memory(28'h0001008, 64'hAAAA5555AAAA5555);
        verify_memory(28'h0001010, 64'h00000000FFFFFFFF);

        // Final Report
        $display("---------------------------------------");
        $display("Test Complete: %d Passed, %d Failed", pass_count, fail_count);
        $display("---------------------------------------");

        #100 $finish;
    end

endmodule
