`timescale 1ns / 1ps

//It is used to reliably transmit a single-clock-cycle  "flag" from one clock domain (a_clk) to another (b_clk) when the two clocks are asynchronous.
module flag_sync(
    input wire a_rst_n,
    input wire a_clk,
    input wire a_flag,
    input wire b_rst_n,
    input wire b_clk,
    output reg  b_flag  // Changed to reg to fit the two-block output style
);

    // Clock Domain A: Input Toggle Logic
    // ========================================================================
    reg flag_ff, flag_next;

    // Sequential Block (Flops only)
    always @(posedge a_clk) begin
        flag_ff <= flag_next;
    end

    // Combinational Block (Logic & Reset)
    always @(*) begin
        if (~a_rst_n) begin
            flag_next = 1'b0;
        end else begin
            flag_next = flag_ff ^ a_flag;
        end
    end

    
    // Clock Domain B: Synchronizer and Edge Detection
    // ========================================================================
    (* ASYNC_REG = "TRUE" *) reg [2:0] b_sync_ff;
    reg [2:0] b_sync_next;
    reg b_flag_next;

    // Sequential Block (Flops only)
    always @(posedge b_clk) begin
        b_sync_ff <= b_sync_next;
        b_flag    <= b_flag_next;
    end

    // Combinational Block (Logic & Reset)
    always @(*) begin
        // Default assignments
        b_sync_next = b_sync_ff;
        b_flag_next = 1'b0;

        if (~b_rst_n) begin
            b_sync_next = 3'b000;
            b_flag_next = 1'b0;
        end else begin
            // Shift register logic: {flag_sync[1:0], flag}
            b_sync_next = {b_sync_ff[1:0], flag_ff};
            // Output XOR logic: flag_sync[1] ^ flag_sync[2]
            b_flag_next = b_sync_ff[1] ^ b_sync_ff[2];
        end
    end
endmodule
