`timescale 1ns / 1ps

/*
 * This module generates standard VGA timing signals (640x480 @ 60Hz).
 * It calculates the horizontal and vertical scan positions and creates
 * the synchronization pulses needed for a monitor to display an image.
 */
module vga_sync(
    input wire clk_vga,      // 25.175 MHz clock for 640x480
    input wire resetn,       // Active-low reset
    output reg [9:0] h_count,// Current horizontal pixel coordinate
    output reg [9:0] v_count,// Current vertical line coordinate
    output reg HSYNC,        // Horizontal Sync pulse (Active Low)
    output reg VSYNC,        // Vertical Sync pulse (Active Low)
    output reg video_on      // High when within the 640x480 visible area
);
    // Standard VGA Timing Constants
    localparam H_WIDTH = 640, H_RIGHT = 16, H_SYNC = 96, H_LEFT = 48, H_TOTAL = 800; 
    localparam V_HEIGHT = 480, V_BOTTOM = 10, V_SYNC = 2, V_TOP = 33, V_TOTAL = 525;  
    
    // Next-state registers for combinational-to-sequential handoff
    reg [9:0] h_count_in, v_count_in;
    reg       HSYNC_in, VSYNC_in;

    // --- Sequential Logic Block ---
    // Updates the output registers on every clock edge
    always @(posedge clk_vga) begin
        h_count <= h_count_in;
        v_count <= v_count_in;
        HSYNC   <= HSYNC_in;
        VSYNC   <= VSYNC_in;
    end

    // --- Combinational Logic Block ---
    // Calculates counting logic, resets, and sync pulse timing
    always @(*) begin
        // Default values to prevent inferred latches
        h_count_in = h_count; 
        v_count_in = v_count;
        HSYNC_in   = HSYNC;
        VSYNC_in   = VSYNC;

        // Synchronous Reset logic
        if (!resetn) begin
            h_count_in = 10'd0;
            v_count_in = 10'd0;
            HSYNC_in   = 1'b1; // Sync pulses are idle high
            VSYNC_in   = 1'b1;
        end 
        else begin
            // Increment Horizontal counter; wrap at 800
            if (h_count < H_TOTAL - 1) begin
                h_count_in = h_count + 1;
            end else begin
                h_count_in = 10'd0;
                // Increment Vertical counter; wrap at 525
                if (v_count < V_TOTAL - 1) 
                    v_count_in = v_count + 1;
                else 
                    v_count_in = 10'd0;
            end
            
            // Generate HSYNC and VSYNC pulses based on timing constants
            HSYNC_in = ~(h_count_in >= H_WIDTH + H_RIGHT && h_count_in < H_WIDTH + H_RIGHT + H_SYNC);
            VSYNC_in = ~(v_count_in >= V_HEIGHT + V_BOTTOM && v_count_in < V_HEIGHT + V_BOTTOM + V_SYNC);
        end

        // Define the visible display region (640 pixels x 480 lines)
        video_on = (h_count < H_WIDTH && v_count < V_HEIGHT);
    end

endmodule
