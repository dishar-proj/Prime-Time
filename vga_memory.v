`timescale 1ns / 1ps

/*
 * A shift-register memory module for VGA data history.
 * Logic is split: Combinational for calculations/reset, 
 * Sequential for direct register assignments (no loops).
 */

module vga_memory(
    input  wire        clk_cpu,
    input  wire        resetn,
    input  wire [1:0]  screen_state,
    input  wire [2:0]  saved_idx,

    input  wire        prime_valid,
    input  wire        current_is_prime,
    input  wire [31:0] current_num,

    input  wire [31:0] test_log_ram,
    input  wire [31:0] test_log_sd,
    input  wire        test_log_pulse,

    input  wire [4:0]  read_addr,
    output reg  [31:0] read_data
);

    // Memory Arrays
    reg [31:0] prime_history_ff [0:19];
    reg [31:0] prime_history_in [0:19];
    reg [31:0] sd_buffer_ff [0:9];
    reg [31:0] sd_buffer_in [0:9];

    // Edge Detection Registers
    reg prime_valid_ff, prime_valid_prev_ff;
    reg prime_valid_in, prime_valid_prev_in;

    integer i;

    
    // COMBINATIONAL LOGIC: Calculations and Reset
   
    always @(*) begin
        // Default Assignments
        prime_valid_in      = prime_valid;
        prime_valid_prev_in = prime_valid_ff;

        for (i = 0; i < 20; i = i + 1) prime_history_in[i] = prime_history_ff[i];
        for (i = 0; i < 10; i = i + 1) sd_buffer_in[i]      = sd_buffer_ff[i];

        // Reset Logic
        if (!resetn) begin
            prime_valid_in      = 1'b0;
            prime_valid_prev_in = 1'b0;
            for (i = 0; i < 20; i = i + 1) prime_history_in[i] = 32'd0;
            for (i = 0; i < 10; i = i + 1) sd_buffer_in[i]      = 32'd0;
        end
        else begin
            // Screen Reset
            if (screen_state == 2'b01) begin
                for (i = 0; i < 20; i = i + 1) prime_history_in[i] = 32'd0;
                for (i = 0; i < 10; i = i + 1) sd_buffer_in[i]      = 32'd0;
            end
            // Normal Mode Shift
            else if (saved_idx != 3'd3 && prime_valid_ff && !prime_valid_prev_ff && current_is_prime) begin
                for (i = 19; i > 0; i = i - 1) prime_history_in[i] = prime_history_ff[i-1];
                prime_history_in[0] = current_num;
            end
            // Test Mode Shift
            else if (saved_idx == 3'd3 && test_log_pulse) begin
                for (i = 9; i > 0; i = i - 1) begin
                    prime_history_in[i] = prime_history_ff[i-1];
                    sd_buffer_in[i]     = sd_buffer_ff[i-1];
                end
                prime_history_in[0] = test_log_ram;
                sd_buffer_in[0]     = test_log_sd;
            end
        end

        // Read Mux
        if (saved_idx == 3'd3) begin
            if (read_addr < 10) read_data = prime_history_ff[read_addr];
            else if (read_addr >= 10 && read_addr < 20) read_data = sd_buffer_ff[read_addr - 10];
            else read_data = 32'd0;
        end else begin
            if (read_addr < 20) read_data = prime_history_ff[read_addr];
            else read_data = 32'd0;
        end
    end

    
    // SEQUENTIAL LOGIC: Direct Register Assignment (No Loops)
   
    always @(posedge clk_cpu) begin
        prime_valid_ff      <= prime_valid_in;
        prime_valid_prev_ff <= prime_valid_prev_in;

        // Manually mapping the arrays to flip-flops
        prime_history_ff[0]  <= prime_history_in[0];
        prime_history_ff[1]  <= prime_history_in[1];
        prime_history_ff[2]  <= prime_history_in[2];
        prime_history_ff[3]  <= prime_history_in[3];
        prime_history_ff[4]  <= prime_history_in[4];
        prime_history_ff[5]  <= prime_history_in[5];
        prime_history_ff[6]  <= prime_history_in[6];
        prime_history_ff[7]  <= prime_history_in[7];
        prime_history_ff[8]  <= prime_history_in[8];
        prime_history_ff[9]  <= prime_history_in[9];
        prime_history_ff[10] <= prime_history_in[10];
        prime_history_ff[11] <= prime_history_in[11];
        prime_history_ff[12] <= prime_history_in[12];
        prime_history_ff[13] <= prime_history_in[13];
        prime_history_ff[14] <= prime_history_in[14];
        prime_history_ff[15] <= prime_history_in[15];
        prime_history_ff[16] <= prime_history_in[16];
        prime_history_ff[17] <= prime_history_in[17];
        prime_history_ff[18] <= prime_history_in[18];
        prime_history_ff[19] <= prime_history_in[19];

        sd_buffer_ff[0] <= sd_buffer_in[0];
        sd_buffer_ff[1] <= sd_buffer_in[1];
        sd_buffer_ff[2] <= sd_buffer_in[2];
        sd_buffer_ff[3] <= sd_buffer_in[3];
        sd_buffer_ff[4] <= sd_buffer_in[4];
        sd_buffer_ff[5] <= sd_buffer_in[5];
        sd_buffer_ff[6] <= sd_buffer_in[6];
        sd_buffer_ff[7] <= sd_buffer_in[7];
        sd_buffer_ff[8] <= sd_buffer_in[8];
        sd_buffer_ff[9] <= sd_buffer_in[9];
    end

endmodule
