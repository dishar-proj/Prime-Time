`timescale 1ns / 1ps
//This module is a flop synchronizer. It helps to take the button signals and different clock domains and prevent metastability. 
//The inputs are: clk,rest_p, and [WIDTH-1:0] in_async.
//the outputs are: [WIDTH-1:0] out.
module ff_sync #(parameter WIDTH=1)(
    input wire clk,
    input wire rst_p,
    input wire [WIDTH-1:0] in_async,
    output reg [WIDTH-1:0] out
);

    // Registers (_ff) and Next-State Logic (_in)
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_reg_ff, sync_reg_in;
    reg [WIDTH-1:0] out_ff, out_in;

    // Sequential Logic
    always @(posedge clk) begin
        sync_reg_ff <= sync_reg_in;
        out_ff      <= out_in;
        // Physical output assignment
        out         <= out_in;
    end

    // Combinational Logic
    always @(*) begin
        // Default state
        sync_reg_in = sync_reg_ff;
        out_in      = out_ff;
        // Reset Handling
        if (rst_p) begin
            sync_reg_in = {WIDTH{1'b0}};
            out_in      = {WIDTH{1'b0}};
        end else begin
            sync_reg_in = in_async;
            out_in      = sync_reg_ff;
        end
    end

endmodule
