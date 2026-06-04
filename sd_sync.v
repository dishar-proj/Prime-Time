//Credit to Blake for her file
//This module uses a "Control Signal with Data" method that synchronizes the control flag and the data is only sampled once the flag is stable
//Provides the very important flag_sync_ff functionallity which is a 3-stage chain synchronizer creating a clean 1 cycle pulse 
`timescale 1ns / 1ps

module sd_sync(
    input  wire        clk_cpu,
    input  wire        resetn,
    input  wire [31:0] sd_data,
    input  wire        sd_lineflag,
    
    output reg  [31:0] cpu_data,
    output reg         cpu_lineflag_pulse
);

    // Internal "Next-State" signals for the combinational block
    reg [2:0]  flag_sync_next;
    reg [31:0] cpu_data_next;
    reg        cpu_lineflag_pulse_next;

    // Registers for the sequential block
    reg [2:0]  flag_sync_ff;

//sequential logic block with assignments only 
    always @(posedge clk_cpu) begin
        flag_sync_ff       <= flag_sync_next;
        cpu_data           <= cpu_data_next;
        cpu_lineflag_pulse <= cpu_lineflag_pulse_next;
    end

    //combinational logic block 
    always @(*) begin
        if (!resetn) begin
            // Reset Logic integrated here
            flag_sync_next          = 3'b000;
            cpu_data_next           = 32'd0;
            cpu_lineflag_pulse_next = 1'b0;
        end else begin
            // 1. Shift the flag into the synchronizer
            flag_sync_next = {flag_sync_ff[1:0], sd_lineflag};

            // 2. Edge detection and data capture logic
            if (flag_sync_next[1] && !flag_sync_ff[2]) begin
                cpu_data_next           = sd_data;
                cpu_lineflag_pulse_next = 1'b1;
            end else begin
                cpu_data_next           = cpu_data; // Maintain state
                cpu_lineflag_pulse_next = 1'b0;     // Clear pulse
            end
        end
    end

endmodule
