`timescale 1ns / 1ps

/*
 * MODULE SUMMARY: sd_reader
 * This module acts as an SD Card Controller capable of initializing 
 * SDv1, SDv2, and SDHCv2 cards and reading 512-byte sectors.
 * It uses a command state machine to handle the SD initialization 
 * sequence and a data state machine to capture bit-serial data 
 * from sddat0 and convert it into 8-bit bytes.
 */

module sd_reader # (
    parameter [2:0] CLK_DIV  = 3'd2,
    parameter        SIMULATE = 0
) (
    input  wire         rstn,      // Active low reset
    input  wire         clk,       // System clock
    output wire         sdclk,     // Clock provided to SD card
    inout               sdcmd,     // Bidirectional Command line
    input  wire         sddat0,    // Data line 0 from SD card
    output wire [ 3:0]  card_stat, // Current state of the command FSM
    output reg  [ 1:0]  card_type, // Detected card type (SDv1, SDv2, SDHC)
    input  wire         rstart,    // Trigger to start a sector read
    input  wire [31:0]  rsector,   // Sector address to read
    output reg          rbusy,     // High when controller is busy
    output reg          rdone,     // High for one cycle when read completes
    output reg          outen,     // Write enable for output buffer
    output reg  [ 8:0]  outaddr,   // Byte address in output buffer (0-511)
    output reg  [ 7:0]  outbyte    // 8-bit data output
);

    // Card Type Constants
    localparam [1:0] UNKNOWN = 2'd0, SDv1 = 2'd1, SDv2 = 2'd2, SDHCv2 = 2'd3;
    
    // Command State Machine States
    localparam [3:0] CMD0=4'd0, CMD8=4'd1, CMD55_41=4'd2, ACMD41=4'd3, CMD2=4'd4,
                     CMD3=4'd5, CMD7=4'd6, CMD16=4'd7, CMD17=4'd8, READING=4'd9, READING2=4'd10;
    
    // Data Path State Machine States
    localparam [2:0] RWAIT=3'd0, RDURING=3'd1, RTAIL=3'd2, RDONE=3'd3, RTIMEOUT=3'd4;

    // Internal Registers (Next-state and Flip-Flop pairs)
    reg [ 1:0] card_type_ff,   card_type_in;
    reg        outen_ff,       outen_in;
    reg [ 8:0] outaddr_ff,     outaddr_in;
    reg [ 7:0] outbyte_ff,     outbyte_in;
    reg        start_ff,       start_in;
    reg [15:0] precnt_ff,      precnt_in;
    reg [ 5:0] cmd_ff,         cmd_in;
    reg [31:0] arg_ff,         arg_in;
    reg [15:0] clkdiv_ff,      clkdiv_in;
    reg [31:0] rsectoraddr_ff, rsectoraddr_in;
    reg        sdv1_maybe_ff,  sdv1_maybe_in;
    reg [ 2:0] cmd8_cnt_ff,    cmd8_cnt_in;
    reg [15:0] rca_ff,         rca_in;
    reg [3:0]  sdcmd_stat_ff,  sdcmd_stat_in;
    reg        sdclkl_ff,      sdclkl_in;
    reg [2:0]  sddat_stat_ff,  sddat_stat_in;
    reg [31:0] ridx_ff,        ridx_in;
    reg        rbusy_in,       rdone_in;

    reg [15:0] fast_clk_v;
    reg [15:0] slow_clk_v;

    wire busy, done, timeout, syntaxe;
    wire [31:0] resparg;

    assign card_stat = sdcmd_stat_ff;

    // Sub-module to handle low-level SD Command/Response timing
    sdcmd_ctrl u_sdcmd_ctrl (
        .rstn    (rstn),
        .clk     (clk),
        .sdclk   (sdclk),
        .sdcmd   (sdcmd),
        .clkdiv  (clkdiv_ff),
        .start   (start_ff),
        .precnt  (precnt_ff),
        .cmd     (cmd_ff),
        .arg     (arg_ff),
        .busy    (busy),
        .done    (done),
        .timeout (timeout),
        .syntaxe (syntaxe),
        .resparg (resparg)
    );

    // Combinational Logic for FSM transitions
    always @(*) begin
        // Clock speed calculations
        fast_clk_v = (16'd1 << CLK_DIV);
        if (SIMULATE)
            slow_clk_v = fast_clk_v * 16'd5;
        else
            slow_clk_v = fast_clk_v * 16'd48;

        // Default state retention
        card_type_in   = card_type_ff;
        outen_in       = 1'b0;
        outaddr_in     = 9'd0;
        outbyte_in     = outbyte_ff;
        start_in       = 1'b0; 
        precnt_in      = 16'd0;
        cmd_in         = 6'd0;
        arg_in         = 32'd0;
        clkdiv_in      = clkdiv_ff;
        rsectoraddr_in = rsectoraddr_ff;
        sdv1_maybe_in  = sdv1_maybe_ff;
        cmd8_cnt_in    = cmd8_cnt_ff;
        rca_in         = rca_ff;
        sdcmd_stat_in  = sdcmd_stat_ff;
        sdclkl_in      = sdclk;
        sddat_stat_in  = sddat_stat_ff;
        ridx_in        = ridx_ff;
        
        // Output status generation
        rbusy_in = (sdcmd_stat_ff != CMD17);
        rdone_in = (sdcmd_stat_ff == READING2) && (sddat_stat_ff == RDONE);

        // State Machine logic
        if (~rstn) begin
            // Reset values
            card_type_in   = UNKNOWN;
            clkdiv_in      = slow_clk_v; 
            rsectoraddr_in = 32'd0;
            rca_in         = 16'd0;
            sdv1_maybe_in  = 1'b0;
            sdcmd_stat_in  = CMD0;
            cmd8_cnt_in    = 3'd0;
            outbyte_in     = 8'd0;
            sdclkl_in      = 1'b0;
            sddat_stat_in  = RWAIT;
            ridx_in        = 32'd0;
        end else begin
            // SD Command sequence FSM
            if (sdcmd_stat_ff == READING2) begin
                if (sddat_stat_ff == RTIMEOUT) begin
                    {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd96, 6'd17, rsectoraddr_ff};
                    sdcmd_stat_in = READING;
                end else if (sddat_stat_ff == RDONE) begin
                    sdcmd_stat_in = CMD17;
                end
            end else if (~busy) begin
                // Trigger commands when the low-level controller is free
                case (sdcmd_stat_ff)
                    CMD0    : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, (SIMULATE?16'd512:16'd64000), 6'd0,  32'h00000000};
                    CMD8    : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd512,                     6'd8,  32'h000001aa};
                    CMD55_41: {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd512,                     6'd55, 32'h00000000};
                    ACMD41  : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd256,                     6'd41, 32'h40100000};
                    CMD2    : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd256,                     6'd2,  32'h00000000};
                    CMD3    : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd256,                     6'd3,  32'h00000000};
                    CMD7    : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd256,                     6'd7,  {rca_ff, 16'h0}};
                    CMD16   : {start_in, precnt_in, cmd_in, arg_in} = {1'b1, (SIMULATE?16'd512:16'd64000), 6'd16, 32'h00000200};
                    CMD17   : if (rstart) begin
                                 rsectoraddr_in = (card_type_ff == SDHCv2) ? rsector : (rsector << 9);
                                 {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd96, 6'd17, rsectoraddr_in};
                                 sdcmd_stat_in = READING;
                              end
                endcase
            end else if (done) begin
                // Process responses once command is done
                case (sdcmd_stat_ff)
                    CMD0    : sdcmd_stat_in = CMD8;
                    CMD8    : if (~timeout && ~syntaxe && resparg[7:0] == 8'haa) begin
                                 sdcmd_stat_in = CMD55_41;
                              end else if (timeout) begin
                                 cmd8_cnt_in = cmd8_cnt_ff + 3'd1;
                                 if (cmd8_cnt_ff == 3'b111) begin
                                     sdv1_maybe_in = 1'b1;
                                     sdcmd_stat_in = CMD55_41;
                                 end
                              end
                    CMD55_41: if (~timeout && ~syntaxe) sdcmd_stat_in = ACMD41;
                    ACMD41  : if (~timeout && ~syntaxe && resparg[31]) begin
                                 card_type_in  = sdv1_maybe_ff ? SDv1 : (resparg[30] ? SDHCv2 : SDv2);
                                 sdcmd_stat_in = CMD2;
                              end else sdcmd_stat_in = CMD55_41;
                    CMD2    : if (~timeout && ~syntaxe) sdcmd_stat_in = CMD3;
                    CMD3    : if (~timeout && ~syntaxe) begin
                                 rca_in = resparg[31:16];
                                 sdcmd_stat_in = CMD7;
                              end
                    CMD7    : if (~timeout && ~syntaxe) begin
                                 clkdiv_in = fast_clk_v; 
                                 sdcmd_stat_in = CMD16;
                              end
                    CMD16   : if (~timeout && ~syntaxe) sdcmd_stat_in = CMD17;
                    default : if (~timeout && ~syntaxe) sdcmd_stat_in = READING2;
                              else {start_in, precnt_in, cmd_in, arg_in} = {1'b1, 16'd128, 6'd17, rsectoraddr_ff};
                endcase
            end

            // Data Path logic: Bit serial to Parallel conversion
            if (sdcmd_stat_ff != READING && sdcmd_stat_ff != READING2) begin
                sddat_stat_in = RWAIT;
                ridx_in = 32'd0;
            end else if (~sdclkl_ff & sdclk) begin
                case (sddat_stat_ff)
                    RWAIT: begin
                        // Wait for start bit (low) on sddat0
                        if (~sddat0) begin
                            sddat_stat_in = RDURING;
                            ridx_in = 32'd0;
                        end else begin
                            if (ridx_ff > 1000000) sddat_stat_in = RTIMEOUT;
                            ridx_in = ridx_ff + 32'd1;
                        end
                    end
                    RDURING: begin
                        // Sample bits on rising edge of sdclk
                        outbyte_in[3'd7 - ridx_ff[2:0]] = sddat0;
                        if (ridx_ff[2:0] == 3'd7) begin
                            outen_in   = 1'b1;
                            outaddr_in = ridx_ff[11:3];
                        end
                        if (ridx_ff >= 512*8-1) begin
                            sddat_stat_in = RTAIL;
                            ridx_in = 32'd0;
                        end else ridx_in = ridx_ff + 32'd1;
                    end
                    RTAIL: begin
                        // Skip the 64-bit CRC at the end of the block
                        if (ridx_ff >= 8*8-1) sddat_stat_in = RDONE;
                        ridx_in = ridx_ff + 32'd1;
                    end
                endcase
            end
        end
    end

    // Sequential Logic Block
    always @(posedge clk) begin
        card_type_ff   <= card_type_in;
        outen_ff       <= outen_in;
        outaddr_ff     <= outaddr_in;
        outbyte_ff     <= outbyte_in;
        start_ff       <= start_in;
        precnt_ff      <= precnt_in;
        cmd_ff         <= cmd_in;
        arg_ff         <= arg_in;
        clkdiv_ff      <= clkdiv_in;
        rsectoraddr_ff <= rsectoraddr_in;
        sdv1_maybe_ff  <= sdv1_maybe_in;
        cmd8_cnt_ff    <= cmd8_cnt_in;
        rca_ff         <= rca_in;
        sdcmd_stat_ff  <= sdcmd_stat_in;
        sdclkl_ff      <= sdclkl_in;
        sddat_stat_ff  <= sddat_stat_in;
        ridx_ff        <= ridx_in;

        // Drive module output pins
        card_type      <= card_type_in;
        rbusy          <= rbusy_in;
        rdone          <= rdone_in;
        outen          <= outen_in;
        outaddr        <= outaddr_in;
        outbyte        <= outbyte_in;
    end

endmodule
