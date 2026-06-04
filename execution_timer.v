`timescale 1ns / 1ps

// This module acts as a precise hardware stopwatch for the prime calculation 
// engine. It generates 1-millisecond and 1-second ticks from the 100MHz clock, 
// tracks total elapsed time, and asserts a flag if a user-defined time limit is reached.
module execution_timer (
    input  wire        clk,           // 100 MHz system clock
    input  wire        rst_n,         // Active low reset
    input  wire        timer_en,      // High when a search is actively running
    input  wire        timer_clear,   // Pulses high to zero out the timer
    input  wire [31:0] time_limit_ms, // Time limit in ms (for Mode 2)
    
    output reg  [31:0] elapsed_ms,    // Internal high-res time
    output reg  [31:0] elapsed_sec,   // Output for the VGA Display
    output reg         time_is_up     
);

    // Internal Registers and Next-State Logic
    reg [16:0] tick_cnt_ff, tick_cnt_in;       // Counts 100,000 clock cycles (1ms)
    reg [9:0]  ms_cnt_ff, ms_cnt_in;           // Counts 1,000 milliseconds (1 sec)
    
    reg [31:0] elapsed_ms_ff, elapsed_ms_in;
    reg [31:0] elapsed_sec_ff, elapsed_sec_in;
    reg        time_is_up_ff, time_is_up_in;

    // Sequential Logic
    always @(posedge clk) begin
        tick_cnt_ff    <= tick_cnt_in;
        ms_cnt_ff      <= ms_cnt_in;
        elapsed_ms_ff  <= elapsed_ms_in;
        elapsed_sec_ff <= elapsed_sec_in;
        time_is_up_ff  <= time_is_up_in;

        elapsed_ms     <= elapsed_ms_in;
        elapsed_sec    <= elapsed_sec_in;
        time_is_up     <= time_is_up_in;
    end

    // Combinational Logic
    always @(*) begin
        // Default assignments to prevent inferred latches
        tick_cnt_in    = tick_cnt_ff;
        ms_cnt_in      = ms_cnt_ff;
        elapsed_ms_in  = elapsed_ms_ff;
        elapsed_sec_in = elapsed_sec_ff;
        time_is_up_in  = time_is_up_ff;

        // Synchronous Reset
        if (~rst_n) begin
            tick_cnt_in    = 17'd0;
            ms_cnt_in      = 10'd0;
            elapsed_ms_in  = 32'd0;
            elapsed_sec_in = 32'd0;
            time_is_up_in  = 1'b0;
        end else if (timer_clear) begin
            tick_cnt_in    = 17'd0;
            ms_cnt_in      = 10'd0;
            elapsed_ms_in  = 32'd0;
            // Requirement: Round up so <1s shows as 1s (per Dr. Herring's note)
            elapsed_sec_in = 32'd1; 
            time_is_up_in  = 1'b0;
        end else if (timer_en && ~time_is_up_ff) begin
            
            // 1ms Tick Generator
            if (tick_cnt_ff >= 17'd99999) begin
                tick_cnt_in   = 17'd0;
                elapsed_ms_in = elapsed_ms_ff + 32'd1;
                
                // 1-Second Generator (Triggers every 1000 ms)
                if (ms_cnt_ff >= 10'd999) begin
                    ms_cnt_in      = 10'd0;
                    elapsed_sec_in = elapsed_sec_ff + 32'd1;
                end else begin
                    ms_cnt_in = ms_cnt_ff + 10'd1;
                end
                
            end else begin
                tick_cnt_in = tick_cnt_ff + 17'd1;
            end

            // Time Limit Check (Internal logic still uses precise ms)
            if ((time_limit_ms > 32'd0) && (elapsed_ms_in >= time_limit_ms)) begin
                time_is_up_in = 1'b1;
            end
        end
    end

endmodule
