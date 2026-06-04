//--------------------------------------------------------------------------------------------------------
// Module  : sdcmd_ctrl
// Type    : synthesizable, IP's sub module
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: sdcmd signal control,
//           instantiated by sd_reader
//--------------------------------------------------------------------------------------------------------

`timescale 1ns / 1ps

module sdcmd_ctrl (
    input  wire         rstn,
    input  wire         clk,
    // SDcard signal
    output reg          sdclk,
    inout               sdcmd,
    input  wire  [15:0] clkdiv,
    //user input signal
    input  wire         start,
    input  wire  [15:0] precnt,
    input  wire  [ 5:0] cmd,
    input  wire  [31:0] arg,
    //user output signal
    output reg          busy,
    output reg          done,
    output reg          timeout,
    output reg          syntaxe,
    output reg   [31:0] resparg  // Changed to reg for sequential loading
);

    localparam [7:0] TIMEOUT = 8'd250;

    reg         busy_ff,     busy_in;
    reg         done_ff,     done_in;
    reg         timeout_ff,  timeout_in;
    reg         syntaxe_ff,  syntaxe_in;
    reg         sdclk_ff,    sdclk_in;
    reg         sdcmdoe_ff,  sdcmdoe_in;
    reg         sdcmdout_ff, sdcmdout_in;
    reg  [ 5:0] req_cmd_ff,  req_cmd_in;
    reg  [31:0] req_arg_ff,  req_arg_in;
    reg  [ 6:0] req_crc_ff,  req_crc_in;
    reg         resp_st_ff,  resp_st_in;
    reg  [ 5:0] resp_cmd_ff, resp_cmd_in;
    reg  [31:0] resp_arg_ff, resp_arg_in;
    reg  [17:0] clkdivr_ff,  clkdivr_in;
    reg  [17:0] clkcnt_ff,   clkcnt_in;
    reg  [15:0] cnt1_ff,     cnt1_in;
    reg  [ 5:0] cnt2_ff,     cnt2_in;
    reg  [ 7:0] cnt3_ff,     cnt3_in;
    reg  [ 7:0] cnt4_ff,     cnt4_in;
    wire [51:0] request_v;
    wire        sdcmd_in_val;

    //IO
    // bufif1 (out, in, control) - Structural, no combo logic used
    bufif1 tri_driver (sdcmd, sdcmdout_ff, sdcmdoe_ff);
    assign sdcmd_in_val = sdcmd;
    assign request_v    = {6'b111101, req_cmd_ff, req_arg_ff, req_crc_ff, 1'b1};

    function [6:0] CalcCrc7;
        input [6:0] crc;
        input [0:0] inbit;
        begin
            CalcCrc7 = ( {crc[5:0],crc[6]^inbit} ^ {3'b0,crc[6]^inbit,3'b0} );
        end
    endfunction

    //Combinational
    always @(*) begin
        // Default State (Hold current ff values)
        busy_in     = busy_ff;
        done_in     = 1'b0; 
        timeout_in  = 1'b0;
        syntaxe_in  = 1'b0;
        sdclk_in    = sdclk_ff;
        sdcmdoe_in  = sdcmdoe_ff;
        sdcmdout_in = sdcmdout_ff;
        req_cmd_in  = req_cmd_ff;
        req_arg_in  = req_arg_ff;
        req_crc_in  = req_crc_ff;
        resp_st_in  = resp_st_ff;
        resp_cmd_in = resp_cmd_ff;
        resp_arg_in = resp_arg_ff;
        clkdivr_in  = clkdivr_ff;
        clkcnt_in   = clkcnt_ff;
        cnt1_in     = cnt1_ff;
        cnt2_in     = cnt2_ff;
        cnt3_in     = cnt3_ff;
        cnt4_in     = cnt4_ff;

        //reset
        if (~rstn) begin
            busy_in     = 1'b0;
            done_in     = 1'b0;
            timeout_in  = 1'b0;
            syntaxe_in  = 1'b0;
            sdclk_in    = 1'b0;
            sdcmdoe_in  = 1'b0; 
            sdcmdout_in = 1'b1;
            req_cmd_in  = 6'd0;
            req_arg_in  = 32'd0;
            req_crc_in  = 7'd0;
            resp_st_in  = 1'b0;
            resp_cmd_in = 6'd0;
            resp_arg_in = 32'd0;
            clkdivr_in  = 18'h3FFFF;
            clkcnt_in   = 18'd0;
            cnt1_in     = 16'd0;
            cnt2_in     = 6'h3F;
            cnt3_in     = 8'd0;
            cnt4_in     = 8'hFF;
        end else begin
            // Protocol Logic
            clkcnt_in = (clkcnt_ff < {clkdivr_ff[16:0], 1'b1}) ? (clkcnt_ff + 18'd1) : 18'd0;
            
            if (clkcnt_ff == 18'd0)
                clkdivr_in = {2'h0, clkdiv} + 18'd1;
            
            if (clkcnt_ff == clkdivr_ff)
                sdclk_in = 1'b0;
            else if (clkcnt_ff == {clkdivr_ff[16:0], 1'b1})
                sdclk_in = 1'b1;

            if (~busy_ff) begin
                if (start) busy_in = 1'b1;
                req_cmd_in = cmd;
                req_arg_in = arg;
                req_crc_in = 7'd0;
                cnt1_in    = precnt;
                cnt2_in    = 6'd51;
                cnt3_in    = TIMEOUT;
                cnt4_in    = 8'd134;
            end else if (done_ff) begin
                busy_in = 1'b0;
            end else if (clkcnt_ff == clkdivr_ff) begin
                sdcmdoe_in  = 1'b1;
                sdcmdout_in = 1'b1;
                if (cnt1_ff != 16'd0) begin
                    cnt1_in = cnt1_ff - 16'd1;
                end else if (cnt2_ff != 6'h3F) begin
                    cnt2_in     = cnt2_ff - 6'd1;
                    sdcmdout_in = request_v[cnt2_ff];
                    if (cnt2_ff >= 8 && cnt2_ff < 48) 
                        req_crc_in = CalcCrc7(req_crc_ff, request_v[cnt2_ff]);
                end
            end else if (clkcnt_ff == {clkdivr_ff[16:0], 1'b1} && cnt1_ff == 16'd0 && cnt2_ff == 6'h3F) begin
                if (cnt3_ff != 8'd0) begin
                    cnt3_in = cnt3_ff - 8'd1;
                    if (~sdcmd_in_val)
                        cnt3_in = 8'd0;
                    else if (cnt3_ff == 8'd1) begin
                        done_in = 1'b1; timeout_in = 1'b1;
                    end
                end else if (cnt4_ff != 8'hFF) begin
                    cnt4_in = cnt4_ff - 8'd1;
                    if (cnt4_ff >= 8'd96)
                        {resp_st_in, resp_cmd_in, resp_arg_in} = {resp_cmd_ff, resp_arg_ff, sdcmd_in_val};
                    if (cnt4_ff == 8'd0) begin
                        done_in    = 1'b1;
                        syntaxe_in = resp_st_ff || ((resp_cmd_ff != req_cmd_ff) && (resp_cmd_ff != 6'h3F) && (resp_cmd_ff != 6'd0));
                    end
                end
            end
        end
    end

    //Sequential Logic 
    always @(posedge clk) begin
        // Internal Registers
        busy_ff      <= busy_in;
        done_ff      <= done_in;
        timeout_ff   <= timeout_in;
        syntaxe_ff   <= syntaxe_in;
        sdclk_ff     <= sdclk_in;
        sdcmdoe_ff   <= sdcmdoe_in;
        sdcmdout_ff  <= sdcmdout_in;
        req_cmd_ff   <= req_cmd_in;
        req_arg_ff   <= req_arg_in;
        req_crc_ff   <= req_crc_in;
        resp_st_ff   <= resp_st_in;
        resp_cmd_ff  <= resp_cmd_in;
        resp_arg_ff  <= resp_arg_in;
        clkdivr_ff   <= clkdivr_in;
        clkcnt_ff    <= clkcnt_in;
        cnt1_ff      <= cnt1_in;
        cnt2_ff      <= cnt2_in;
        cnt3_ff      <= cnt3_in;
        cnt4_ff      <= cnt4_in;

        //Loading Output Registers
        busy         <= busy_in;
        done         <= done_in;
        timeout      <= timeout_in;
        syntaxe      <= syntaxe_in;
        sdclk        <= sdclk_in;
        resparg      <= resp_arg_in;
    end

endmodule
