//We have configured the MIG in 2:1 mode to simplify the clocking
//requirements. Note that the underlying transaction size is still 128-bits.
//In 2:1 mode, we are required to read and write our data across 2 cycles
//in 64-bit chunks. This can be done internal to the module so we still present
//128-bit ports to the rest of the design.
//
//As the 128-bit mode is a bit of overkill for this example, the upper 64-bits are
//always masked off and aren't available external to the module.
//
//A happy side-effect of the 2:1 mode (vs 4:1 mode) is that ui_clk runs at
//double the speed, decreasing the delay of the clock domain crossing from the
//CPU into the ui_*/app_* memory controller domain.

`include "io_def.vh"

module mem_example(
    input clk_mem,
    input rst_n,

    inout[15:0] ddr2_dq,
    inout[1:0] ddr2_dqs_n,
    inout[1:0] ddr2_dqs_p,
    output[12:0] ddr2_addr,
    output[2:0] ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output[0:0] ddr2_ck_p,
    output[0:0] ddr2_ck_n,
    output[0:0] ddr2_cke,
    output[0:0] ddr2_cs_n,
    output[1:0] ddr2_dm,
    output[0:0] ddr2_odt,

    input cpu_clk,
    input[27:0] addr,
    input[1:0] width,
    input[63:0] data_in,
    output reg[63:0] data_out,
    input rstrobe,
    input wstrobe,
    output init_calib_complete,
    output transaction_complete,
    output ready
);

    //Internal Wires
    wire ui_clk, ui_clk_sync_rst;
    wire rstrobe_sync, wstrobe_sync;
    wire mem_rdy, mem_wdf_rdy, mem_rd_data_end, mem_rd_data_valid;
    wire [63:0] mem_rd_data;

    //Pipeline
    reg [63:0] mem_rd_data_pipe;
    reg        mem_rd_data_valid_pipe;
    reg        mem_rd_data_end_pipe;

    //State Machine Registers
    reg [2:0]  state_ff, state_next;
    reg [2:0]  mem_cmd_ff, mem_cmd_next;
    reg        mem_en_ff, mem_en_next;
    reg        complete_ff, complete_next;
    reg [63:0] mem_wdf_data_ff, mem_wdf_data_next;
    reg        mem_wdf_end_ff, mem_wdf_end_next;
    reg        mem_wdf_wren_ff, mem_wdf_wren_next;
    reg [7:0]  mem_wdf_mask_ff, mem_wdf_mask_next;
    reg [63:0] data_out_next;

    //states
    localparam STATE_IDLE = 3'h0, STATE_PREREAD = 3'h1, STATE_READ = 3'h2;
    localparam STATE_WRITE = 3'h4, STATE_WRITEDATA_H = 3'h5, STATE_WRITEDATA_L = 3'h6;
    localparam CMD_READ = 3'h1, CMD_WRITE = 3'h0;

    //MIG IP
    mig1 mig1_inst (
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n), .ddr2_ck_p(ddr2_ck_p), .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n), .ddr2_we_n(ddr2_we_n), .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p), .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt),
        .app_addr(addr[27:1]), .app_cmd(mem_cmd_ff), .app_en(mem_en_ff),
        .app_wdf_data(mem_wdf_data_ff), .app_wdf_end(mem_wdf_end_ff),
        .app_wdf_wren(mem_wdf_wren_ff), .app_wdf_mask(mem_wdf_mask_ff),
        .app_rd_data(mem_rd_data), .app_rd_data_end(mem_rd_data_end),
        .app_rd_data_valid(mem_rd_data_valid), .app_rdy(mem_rdy),
        .app_wdf_rdy(mem_wdf_rdy), .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst), .sys_clk_i(clk_mem), .sys_rst(rst_n),
        .init_calib_complete(init_calib_complete), .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
        .app_sr_active(), .app_ref_ack(), .app_zq_ack()
    );

    //Synchronizers
    flag_sync rs_sync(.a_rst_n(rst_n), .a_clk(cpu_clk), .a_flag(rstrobe), .b_rst_n(~ui_clk_sync_rst), .b_clk(ui_clk), .b_flag(rstrobe_sync));
    flag_sync ws_sync(.a_rst_n(rst_n), .a_clk(cpu_clk), .a_flag(wstrobe), .b_rst_n(~ui_clk_sync_rst), .b_clk(ui_clk), .b_flag(wstrobe_sync));
    flag_sync complete_sync(.a_rst_n(~ui_clk_sync_rst), .a_clk(ui_clk), .a_flag(complete_ff), .b_rst_n(rst_n), .b_clk(cpu_clk), .b_flag(transaction_complete));
    ff_sync ready_sync(.clk(cpu_clk), .rst_p(~rst_n), .in_async(~ui_clk_sync_rst), .out(ready));

    //Sequential
    always @(posedge ui_clk) begin
        state_ff        <= state_next;
        mem_cmd_ff      <= mem_cmd_next;
        mem_en_ff       <= mem_en_next;
        complete_ff     <= complete_next;
        mem_wdf_data_ff  <= mem_wdf_data_next;
        mem_wdf_end_ff   <= mem_wdf_end_next;
        mem_wdf_wren_ff  <= mem_wdf_wren_next;
        mem_wdf_mask_ff  <= mem_wdf_mask_next;
        data_out        <= data_out_next;

        // Pipeline MIG outputs to meet timing
        mem_rd_data_pipe       <= mem_rd_data;
        mem_rd_data_valid_pipe <= mem_rd_data_valid;
        mem_rd_data_end_pipe   <= mem_rd_data_end;
    end

    // Combinational Logic (Next-State & Reset)
    always @(*) begin
        //Default Assignments
        state_next        = state_ff;
        mem_cmd_next      = mem_cmd_ff;
        mem_en_next       = mem_en_ff;
        complete_next     = 1'b0;
        mem_wdf_data_next = mem_wdf_data_ff;
        mem_wdf_end_next  = mem_wdf_end_ff;
        mem_wdf_wren_next = 1'b0; 
        mem_wdf_mask_next = mem_wdf_mask_ff;
        data_out_next     = data_out;

        //Reser
        if (ui_clk_sync_rst) begin
            state_next        = STATE_IDLE;
            mem_cmd_next      = 3'b0;
            mem_en_next       = 1'b0;
            mem_wdf_data_next = 64'b0;
            mem_wdf_end_next  = 1'b0;
            mem_wdf_wren_next = 1'b0;
            mem_wdf_mask_next = 8'hFF;
            data_out_next     = 64'b0;
        end else begin
            //Width Handling)
            if (mem_rd_data_valid_pipe) begin
                if (~addr[0]) begin
                    case(width)
                        `RAM_WIDTH64: data_out_next = {mem_rd_data_pipe[7:0],mem_rd_data_pipe[15:8],mem_rd_data_pipe[23:16],mem_rd_data_pipe[31:24],mem_rd_data_pipe[39:32],mem_rd_data_pipe[47:40],mem_rd_data_pipe[55:48],mem_rd_data_pipe[63:56]};
                        `RAM_WIDTH32: data_out_next = {mem_rd_data_pipe[7:0],mem_rd_data_pipe[15:8],mem_rd_data_pipe[23:16],mem_rd_data_pipe[31:24],32'h0};
                        `RAM_WIDTH16: data_out_next = {mem_rd_data_pipe[7:0],mem_rd_data_pipe[15:8],48'h0};
                        `RAM_WIDTH8:  data_out_next = {mem_rd_data_pipe[7:0],56'h0};
                    endcase
                end else begin
                    if (mem_rd_data_end_pipe) begin
                         if (width == `RAM_WIDTH64) data_out_next[7:0] = mem_rd_data_pipe[7:0];
                    end else begin
                        case(width)
                            `RAM_WIDTH64: data_out_next[63:8] = {mem_rd_data_pipe[15:8],mem_rd_data_pipe[23:16],mem_rd_data_pipe[31:24],mem_rd_data_pipe[39:32],mem_rd_data_pipe[47:40],mem_rd_data_pipe[55:48],mem_rd_data_pipe[63:56]};
                            `RAM_WIDTH32: data_out_next = {mem_rd_data_pipe[15:8],mem_rd_data_pipe[23:16],mem_rd_data_pipe[31:24],mem_rd_data_pipe[39:32],32'h0};
                            `RAM_WIDTH16: data_out_next = {mem_rd_data_pipe[15:8],mem_rd_data_pipe[23:16],48'h0};
                            `RAM_WIDTH8:  data_out_next = {mem_rd_data_pipe[15:8],56'h0};
                        endcase
                    end
                end
            end

            //FSM 
            case(state_ff)
                STATE_IDLE: begin
                    mem_wdf_end_next = 1'b0;
                    if (wstrobe_sync) begin
                        mem_en_next = 1'b1; mem_cmd_next = CMD_WRITE; state_next = STATE_WRITE;
                    end else if (rstrobe_sync) begin
                        mem_en_next = 1'b1; mem_cmd_next = CMD_READ; state_next = STATE_PREREAD;
                    end
                end

                STATE_WRITE: if (mem_rdy) begin mem_en_next = 1'b0; state_next = STATE_WRITEDATA_H; end

                STATE_WRITEDATA_H: if (mem_wdf_rdy) begin
                    mem_wdf_wren_next = 1'b1; state_next = STATE_WRITEDATA_L;
                    if (~addr[0]) begin
                        case(width)
                            `RAM_WIDTH64: begin mem_wdf_mask_next = 8'h00; mem_wdf_data_next = {data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24],data_in[39:32],data_in[47:40],data_in[55:48],data_in[63:56]}; end
                            `RAM_WIDTH32: begin mem_wdf_mask_next = 8'hF0; mem_wdf_data_next = {32'h0,data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24]}; end
                            `RAM_WIDTH16: begin mem_wdf_mask_next = 8'hFC; mem_wdf_data_next = {48'h0,data_in[7:0],data_in[15:8]}; end
                            `RAM_WIDTH8:  begin mem_wdf_mask_next = 8'hFE; mem_wdf_data_next = {56'h0,data_in[7:0]}; end
                        endcase
                    end else begin
                        case(width)
                            `RAM_WIDTH64: begin mem_wdf_mask_next = 8'h01; mem_wdf_data_next = {data_in[15:8],data_in[23:16],data_in[31:24],data_in[39:32],data_in[47:40],data_in[55:48],data_in[63:56],8'h0}; end
                            `RAM_WIDTH32: begin mem_wdf_mask_next = 8'hE1; mem_wdf_data_next = {24'h0,data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24],8'h0}; end
                            `RAM_WIDTH16: begin mem_wdf_mask_next = 8'hF9; mem_wdf_data_next = {40'h0,data_in[7:0],data_in[15:8],8'h0}; end
                            `RAM_WIDTH8:  begin mem_wdf_mask_next = 8'hFD; mem_wdf_data_next = {48'h0,data_in[7:0],8'h0}; end
                        endcase
                    end
                end

                STATE_WRITEDATA_L: if (mem_wdf_rdy) begin
                    mem_wdf_wren_next = 1'b1; mem_wdf_end_next = 1'b1; complete_next = 1'b1; state_next = STATE_IDLE;
                    if (~addr[0]) begin mem_wdf_mask_next = 8'hFF; mem_wdf_data_next = 64'h0; end
                    else begin mem_wdf_mask_next = 8'hFE; mem_wdf_data_next = {56'h0, data_in[7:0]}; end
                end

                STATE_PREREAD: if (mem_rdy) begin
                    mem_en_next = 1'b0; state_next = STATE_READ;
                    if (mem_rd_data_valid_pipe && mem_rd_data_end_pipe) begin state_next = STATE_IDLE; complete_next = 1'b1; end
                end

                STATE_READ: if (mem_rd_data_valid_pipe && mem_rd_data_end_pipe) begin state_next = STATE_IDLE; complete_next = 1'b1; end
            endcase
        end
    end
endmodule
