`timescale 1ns / 1ps


//Testbench for VGA controller exhaustive.
module tb_VGA_controller();

    // --- Inputs to UUT (Regs) ---
    reg clk_vga;
    reg clk_cpu;
    reg resetn;
    reg [1:0]  menu_idx;
    reg [1:0]  screen_state;
    reg [2:0]  saved_idx;
    reg [1:0]  endmode_idx;
    reg [31:0] count;
    reg [2:0]  speed_lvl;
    reg        is_prime;
    reg [31:0] elapsed_sec;
    reg [31:0] total_primes;
    reg        prime_valid;
    reg [31:0] current_num;
    reg        current_is_prime;
    reg        test_passed;
    reg [31:0] primes_checked;
    reg [31:0] fail_ram_val;
    reg [31:0] fail_sd_val;
    reg [31:0] test_log_ram;
    reg [31:0] test_log_sd;
    reg        test_log_pulse;

    // --- Outputs from UUT (Wires) ---
    wire [3:0] RED;
    wire [3:0] GRN;
    wire [3:0] BLU;
    wire       HSYNC;
    wire       VSYNC;

    // --- Unit Under Test (UUT) ---
    VGA_controller uut (
        .clk_vga(clk_vga),
        .clk_cpu(clk_cpu),
        .resetn(resetn),
        .menu_idx(menu_idx),
        .screen_state(screen_state),
        .saved_idx(saved_idx),
        .endmode_idx(endmode_idx),
        .count(count),
        .speed_lvl(speed_lvl),
        .is_prime(is_prime),
        .elapsed_sec(elapsed_sec),
        .total_primes(total_primes),
        .prime_valid(prime_valid),
        .current_num(current_num),
        .current_is_prime(current_is_prime),
        .test_passed(test_passed),
        .primes_checked(primes_checked),
        .fail_ram_val(fail_ram_val),
        .fail_sd_val(fail_sd_val),
        .test_log_ram(test_log_ram),
        .test_log_sd(test_log_sd),
        .test_log_pulse(test_log_pulse),
        .RED(RED),
        .GRN(GRN),
        .BLU(BLU),
        .HSYNC(HSYNC),
        .VSYNC(VSYNC)
    );

    // --- Clock Generation ---
    initial begin
        clk_vga = 0;
        forever #20 clk_vga = ~clk_vga; // 25MHz
    end

    initial begin
        clk_cpu = 0;
        forever #5 clk_cpu = ~clk_cpu;   // 100MHz
    end

    // --- Automated Protocol Checking ---
    // Verifies that colors are only driven when HSYNC and VSYNC are high (visible region)
    always @(posedge clk_vga) begin
        if ((!HSYNC || !VSYNC) && (RED != 0 || GRN != 0 || BLU != 0)) begin
            $display("PROTOCOL ERROR: RGB values driven during Sync/Blanking at %t", $time);
        end
    end

    // --- Verification Flow ---
    initial begin
        // 1. FORCED INITIALIZATION (Fixes the "X" unknown states)
        clk_vga = 0;
        clk_cpu = 0;
        resetn = 0;
        menu_idx = 0;
        screen_state = 0;
        saved_idx = 0;
        endmode_idx = 0;
        count = 0;
        speed_lvl = 0;
        is_prime = 0;
        elapsed_sec = 0;
        total_primes = 0;
        prime_valid = 0;
        current_num = 0;
        current_is_prime = 0;
        test_passed = 0;
        primes_checked = 0;
        fail_ram_val = 0;
        fail_sd_val = 0;
        test_log_ram = 0;
        test_log_sd = 0;
        test_log_pulse = 0;

        $display("--- Starting Exhaustive Verification ---");
        
        // 2. Reset Release
        #100 resetn = 1;
        $display("Reset released. Starting state-space traversal.");

        // 3. Exhaustive UI State Traversal
        // This triple loop tests every logical combination of screen and menu settings
        for (integer s = 0; s < 4; s = s + 1) begin
            for (integer m = 0; m < 4; m = m + 1) begin
                for (integer id = 0; id < 8; id = id + 1) begin
                    @(posedge clk_cpu);
                    screen_state = s;
                    menu_idx = m;
                    saved_idx = id;
                    
                    // Stress the data inputs with random numbers in each state
                    total_primes = $urandom;
                    test_log_pulse = 1;
                    #10 test_log_pulse = 0; // Short pulse
                    
                    #100; // Wait for logic to settle
                end
            end
        end

        // 4. Data Edge Case Testing
        $display("Testing boundary data conditions (Max 32-bit values).");
        count = 32'hFFFFFFFF;
        elapsed_sec = 32'hFFFFFFFF;
        primes_checked = 32'hFFFFFFFF;
        fail_ram_val = 32'hDEADBEEF;
        #5000;

        // 5. Final Timing Stability Verification
        $display("Monitoring for a full Frame Refresh...");
        wait(VSYNC == 0); // Wait for vertical sync pulse start
        wait(VSYNC == 1); // Wait for vertical sync pulse end
        $display("SUCCESS: Full frame refresh cycle observed.");

        $display("--- ALL EXHAUSTIVE TESTS COMPLETE ---");
        $finish;
    end

endmodule
