`timescale 1ns / 1ps

module sd_file_reader #(
    parameter            FILE_NAME_LEN = 8,
    parameter [52*8-1:0] FILE_NAME     = "data.txt",
    parameter      [2:0] CLK_DIV       = 3'd2,
    parameter            SIMULATE      = 0
) (
    input  wire       rstn,
    input  wire       clk,
    output wire       sdclk,
    inout             sdcmd,
    input  wire       sddat0,
    output wire [3:0] card_stat,
    output wire [1:0] card_type,
    output wire [1:0] filesystem_type,
    output reg        file_found,
    output reg        outen,
    output reg  [7:0] outbyte,
    output reg  [2:0] filesystem_state
);

    localparam [2:0] RESET=3'd0, SEARCH_MBR=3'd1, SEARCH_DBR=3'd2, LS_ROOT_FAT16=3'd3, LS_ROOT_FAT32=3'd4, READ_A_FILE=3'd5, DONE=3'd6;
    localparam [1:0] UNASSIGNED=2'd0, UNKNOWN_FS=2'd1, FAT16=2'd2, FAT32=2'd3;

    //Helper function that converts to uppercase
    function [7:0] toUpperCase;
        input [7:0] in;
        toUpperCase = (in >= 8'h61 && in <= 8'h7A) ? (in & 8'b11011111) : in;
    endfunction

    reg [52*8-1:0] FILE_NAME_UPPER;
    integer k;
    initial begin
        for (k=0; k<52; k=k+1) FILE_NAME_UPPER[k*8 +: 8] = toUpperCase(FILE_NAME[k*8 +: 8]);
    end

    //registers
    reg [2:0]  fstate_ff,     fstate_in;
    reg [1:0]  fs_type_ff,    fs_type_in;
    reg        rstart_ff,     rstart_in;
    reg [31:0] rsector_ff,    rsector_in;
    reg        search_fat_ff, search_fat_in;
    reg [7:0]  clus_sz_ff,    clus_sz_in;
    reg [31:0] f_fat_ff,      f_fat_in;
    reg [31:0] f_data_ff,     f_data_in;
    reg [31:0] curr_clus_ff,  curr_clus_in;
    reg [7:0]  clus_off_ff,   clus_off_in;
    reg [31:0] root_sec_ff,   root_sec_in;
    reg [15:0] root_cnt_ff,   root_cnt_in;
    reg [31:0] target_ff,     target_in;
    reg [15:0] target16_ff,   target16_in;
    reg [31:0] fsize_ff,      fsize_in;
    reg [31:0] fptr_ff,       fptr_in;
    reg        found_ff,      found_in;
    reg        outen_ff,      outen_in;
    reg [7:0]  outbyte_ff,    outbyte_in;
    reg [415:0] fname_buf_ff, fname_buf_in;

    //memory
    reg [4095:0] sector_content_ff, sector_content_in;

    wire read_done, rvalid;
    wire [8:0] raddr;
    wire [7:0] rdata;

    assign filesystem_type = fs_type_ff;

    //combinational
    always @(*) begin
        //default
        fstate_in = fstate_ff; fs_type_in = fs_type_ff; rstart_in = 1'b0; rsector_in = rsector_ff;
        search_fat_in = search_fat_ff; clus_sz_in = clus_sz_ff; f_fat_in = f_fat_ff; f_data_in = f_data_ff;
        curr_clus_in = curr_clus_ff; clus_off_in = clus_off_ff; root_sec_in = root_sec_ff; root_cnt_in = root_cnt_ff;
        target_in = target_ff; target16_in = target16_ff; fsize_in = fsize_ff; fptr_in = fptr_ff;
        found_in = found_ff; outen_in = 1'b0; outbyte_in = outbyte_ff; fname_buf_in = fname_buf_ff;
        sector_content_in = sector_content_ff; // Logic-free default

        //RAM
        if (rvalid) begin
            sector_content_in[raddr*8 +: 8] = rdata;
        end

        //reset
        if (~rstn) begin
            fstate_in = RESET; fs_type_in = UNASSIGNED; rsector_in = 0; found_in = 1'b0; fptr_in = 0;
            fname_buf_in = 416'h0; sector_content_in = 4096'h0;
        end else if (read_done) begin
            case (fstate_ff)
                SEARCH_MBR: begin
                    if ({sector_content_ff[510*8 +: 8], sector_content_ff[511*8 +: 8]} == 16'h55AA) begin
                        fstate_in = SEARCH_DBR;
                        if (sector_content_ff[0 +: 8] != 8'hEB && sector_content_ff[0 +: 8] != 8'hE9)
                            rsector_in = {sector_content_ff[457*8 +: 8], sector_content_ff[456*8 +: 8], sector_content_ff[455*8 +: 8], sector_content_ff[454*8 +: 8]};
                    end else rsector_in = rsector_ff + 1;
                end

                SEARCH_DBR: begin
                    clus_sz_in = sector_content_ff[13*8 +: 8];
                    f_fat_in = rsector_ff + {sector_content_ff[15*8 +: 8], sector_content_ff[14*8 +: 8]};
                    if ({sector_content_ff[23*8 +: 8], sector_content_ff[22*8 +: 8]} > 0) begin
                        fs_type_in = FAT16;
                        root_cnt_in = {sector_content_ff[18*8 +: 8], sector_content_ff[17*8 +: 8]} / 16;
                        root_sec_in = f_fat_in + ({16'h0, sector_content_ff[23*8 +: 8], sector_content_ff[22*8 +: 8]} * sector_content_ff[16*8 +: 8]);
                        f_data_in = root_sec_in + root_cnt_in - (clus_sz_in * 2);
                        rsector_in = root_sec_in; fstate_in = LS_ROOT_FAT16;
                    end else begin
                        fs_type_in = FAT32;
                        f_data_in = f_fat_in + ({sector_content_ff[39*8 +: 8], sector_content_ff[38*8 +: 8], sector_content_ff[37*8 +: 8], sector_content_ff[36*8 +: 8]} * sector_content_ff[16*8 +: 8]) - (clus_sz_in * 2);
                        curr_clus_in = {sector_content_ff[47*8 +: 8], sector_content_ff[46*8 +: 8], sector_content_ff[45*8 +: 8], sector_content_ff[44*8 +: 8]};
                        rsector_in = f_data_in + (clus_sz_in * curr_clus_in); fstate_in = LS_ROOT_FAT32;
                    end
                end

                LS_ROOT_FAT16, LS_ROOT_FAT32: begin
                    if (found_ff) begin
                        curr_clus_in = target_ff; clus_off_in = 0;
                        rsector_in = f_data_ff + (clus_sz_ff * target_ff); fstate_in = READ_A_FILE;
                    end else begin
                        clus_off_in = clus_off_ff + 1;
                        rsector_in = (fstate_ff == LS_ROOT_FAT16) ? root_sec_ff + clus_off_in : f_data_ff + (clus_sz_ff * curr_clus_ff) + clus_off_in;
                    end
                end

                READ_A_FILE: begin
                    if (~search_fat_ff) begin
                        if (clus_off_ff < (clus_sz_ff-1)) begin
                            clus_off_in = clus_off_ff + 1; rsector_in = f_data_ff + (clus_sz_ff * curr_clus_ff) + clus_off_in;
                        end else begin
                            search_fat_in = 1'b1; clus_off_in = 0;
                            rsector_in = f_fat_ff + (fs_type_ff == FAT16 ? (curr_clus_ff >> 8) : (curr_clus_ff >> 7));
                        end
                    end else begin
                        search_fat_in = 1'b0;
                        if (fs_type_ff == FAT16) begin
                            if (target16_ff >= 16'hFFF8) fstate_in = DONE;
                            else begin curr_clus_in = {16'h0, target16_ff}; rsector_in = f_data_ff + (clus_sz_ff * target16_ff); end
                        end else begin
                            if (target_ff >= 32'h0FFF_FFF8) fstate_in = DONE;
                            else begin curr_clus_in = target_ff; rsector_in = f_data_ff + (clus_sz_ff * target_ff); end
                        end
                    end
                end
                
                DONE: fstate_in = DONE;
            endcase
        end else begin
            if (fstate_ff != RESET && fstate_ff != DONE) rstart_in = 1'b1;
            if (fstate_ff == RESET) fstate_in = SEARCH_MBR;
        end

        //file parsinf
        if (rvalid) begin
            if ((fstate_ff == LS_ROOT_FAT16 || fstate_ff == LS_ROOT_FAT32) && ~search_fat_ff) begin
                if (raddr[4:0] < 11) fname_buf_in[raddr[4:0]*8 +: 8] = rdata;
                if (raddr[4:0] == 5'h1F) begin
                    found_in = (fname_buf_ff[0 +: FILE_NAME_LEN*8] == FILE_NAME_UPPER[0 +: FILE_NAME_LEN*8]);
                    target_in = {16'h0, sector_content_ff[27*8 +: 8], sector_content_ff[26*8 +: 8]};
                    fsize_in  = {sector_content_ff[31*8 +: 8], sector_content_ff[30*8 +: 8], sector_content_ff[29*8 +: 8], sector_content_ff[28*8 +: 8]};
                end
            end
            
            if (fstate_ff == READ_A_FILE && ~search_fat_ff && fptr_ff < fsize_ff) begin
                fptr_in = fptr_ff + 1; outen_in = 1'b1; outbyte_in = rdata;
            end
        end
    end

    //seuqnetial
    always @(posedge clk) begin
        fstate_ff         <= fstate_in;
        fs_type_ff        <= fs_type_in;
        rstart_ff         <= rstart_in;
        rsector_ff        <= rsector_in;
        search_fat_ff     <= search_fat_in;
        clus_sz_ff        <= clus_sz_in;
        f_fat_ff          <= f_fat_in;
        f_data_ff         <= f_data_in;
        curr_clus_ff      <= curr_clus_in;
        clus_off_ff       <= clus_off_in;
        root_sec_ff       <= root_sec_in;
        root_cnt_ff       <= root_cnt_in;
        target_ff         <= target_in;
        target16_ff       <= target16_in;
        fsize_ff          <= fsize_in;
        fptr_ff           <= fptr_in;
        found_ff          <= found_in;
        outen_ff          <= outen_in;
        outbyte_ff        <= outbyte_in;
        fname_buf_ff      <= fname_buf_in;
        sector_content_ff <= sector_content_in; // Massive single-line transfer

        //port Outputs
        file_found       <= found_in;
        outen            <= outen_in;
        outbyte          <= outbyte_in;
        filesystem_state <= fstate_in;
    end
  
    sd_reader #(.CLK_DIV(CLK_DIV), .SIMULATE(SIMULATE)) u_sd_reader (
        .rstn(rstn), .clk(clk), .sdclk(sdclk), .sdcmd(sdcmd), .sddat0(sddat0),
        .card_type(card_type), .card_stat(card_stat), .rstart(rstart_ff), .rsector(rsector_ff),
        .rdone(read_done), .outen(rvalid), .outaddr(raddr), .outbyte(rdata)
    );

endmodule
