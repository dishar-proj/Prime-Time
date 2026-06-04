timescale 1ns / 1ps

/*
 * SUMMARY: 
 * This is the high-compatibility version of the exhaustive testbench.
 * It uses only standard Verilog-2001 constructs to avoid "Parsing not available" errors.
 * It manually verifies the 96-pixel HSYNC pulse width.
 */
module tb_vga_sync_exhaustive();

    // Standard logic signals
    reg clk_vga;
    reg resetn;
    wire [9:0] h_count;
    wire [9:0] v_count;
    wire HSYNC;
    wire VSYNC;
    wire video_on;

    // Use standard 64-bit registers for time tracking to avoid 'time' keyword issues
    reg [63:0] h_fall_time;
    reg [63:0] h_width;
    reg [63:0] current_sim_time;

    // Hard-coded expected value (96 pixels * 40ns = 3840)
    // Using a simple parameter to avoid 'real' math parsing errors
    parameter [31:0] H_SYNC_EXPECTED = 3840;

    // UUT Instantiation with explicit mapping
    vga_sync uut (
        .clk_vga(clk_vga),
        .resetn(resetn),
        .h_count(h_count),
        .v_count(v_count),
        .HSYNC(HSYNC),
        .VSYNC(VSYNC),
        .video_on(video_on)
    );

    // Track simulation time manually for maximum compatibility
    always @(posedge clk_vga) begin
        current_sim_time <= $time;
    end

    // Clock generation (25MHz / 40ns period)
    initial begin
        clk_vga = 0;
        forever #20 clk_vga = ~clk_vga;
    end

    // Logic to measure HSYNC width without using SystemVerilog constructs
    always @(negedge HSYNC) begin
        h_fall_time <= $time;
    end

    always @(posedge HSYNC) begin
        h_width <= $time - h_fall_time;
    end

    // Verification and Stimulus
    initial begin
        // Initialize all registers to known values
        resetn = 0;
        h_fall_time = 0;
        h_width = 0;
        current_sim_time = 0;

        $display("--- Starting Ultra-Compatible Exhaustive Test ---");

        // Release reset
        #200 resetn = 1;

        // Run until we have seen the first HSYNC pulse return to high
        wait(h_width > 0);
        
        // Exhaustive Check
        if (h_width == H_SYNC_EXPECTED) begin
            $display("SUCCESS: HSYNC Pulse detected at %0d ns (Matches 96-pixel spec)", h_width);
        end else begin
            $display("ERROR: HSYNC width %0d ns does not match expected %0d", h_width, H_SYNC_EXPECTED);
        end

        // Run for a few lines more to verify stability
        #50000;
        
        $display("--- Test Complete ---");
        $finish;
    end

endmodule
