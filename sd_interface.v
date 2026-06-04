`timescale 1ns / 1ps

module sd_interface(
    input  wire        clk_sd,
    input  wire        resetn,
    output wire        sdcard_pwr_n,
    output wire        sdclk,
    inout              sdcmd,
    input  wire        sddat0,
    output wire        sddat1, sddat2, sddat3,
    output wire [15:0] led,
    output reg  [31:0] data,
    output reg         sd_run,      
    output reg         sd_finish,
    output wire        lineflag
);
    
    // Internal Wires 
    wire [7:0]  outbyte;
    wire [15:0] ledout;
    wire [2:0]  filesystem_state;
    wire        outen;
    
    // State Constants
    localparam [3:0] FIRST   = 4'd0, SECOND  = 4'd1, THIRD   = 4'd2,
                     FOURTH  = 4'd3, FIFTH   = 4'd4, SIXTH   = 4'd5,
                     SEVENTH = 4'd6, EIGHTH  = 4'd7, NINTH   = 4'd8;
    
    // Internal Logic Registers 
    reg [3:0]  sdstate_ff,   sdstate_in;
    reg [31:0] data_ff,      data_in;
    reg        lineflag_ff,  lineflag_in;
    reg        sd_finish_ff, sd_finish_in;
    reg        sd_run_in;
    
    // Logic-only regs (not registered in sequential block)
    reg [3:0]  ascii2dec;
    reg [3:0]  ascii2hex;

    // Output Assignments
    assign led      = ledout;
    assign lineflag = lineflag_ff;

    // Combinational Logic
    always @(*) begin
        // Static Combinational Math 
        ascii2dec = outbyte - 8'd48;
        ascii2hex = outbyte - 8'd87;

        // Fundamental Defaults
        sdstate_in   = sdstate_ff;
        data_in      = data_ff;
        lineflag_in  = lineflag_ff;
        sd_finish_in = sd_finish_ff;
        sd_run_in    = 1'b1;

        // Unified Synchronous Reset
        if (!resetn) begin
            sdstate_in   = FIRST;
            data_in      = 32'h0;
            lineflag_in  = 1'b0;
            sd_finish_in = 1'b0;
            sd_run_in    = 1'b0;
        end else begin
            
            // Operational Logic
            sd_finish_in = (filesystem_state == 3'd6);

            if (outen) begin
                case (sdstate_ff)
                    FIRST: begin
                        if (outbyte > 8'd60) data_in[31:28] = ascii2hex;
                        else                 data_in[31:28] = ascii2dec;
                        sdstate_in = SECOND;
                    end
                    
                    SECOND: begin
                        if (outbyte > 8'd60) data_in[27:24] = ascii2hex;
                        else                 data_in[27:24] = ascii2dec;
                        sdstate_in = THIRD;
                    end
                    
                    THIRD: begin
                        if (outbyte > 8'd60) data_in[23:20] = ascii2hex;
                        else                 data_in[23:20] = ascii2dec;
                        sdstate_in = FOURTH;
                    end
                    
                    FOURTH: begin
                        if (outbyte > 8'd60) data_in[19:16] = ascii2hex;
                        else                 data_in[19:16] = ascii2dec;
                        sdstate_in = FIFTH;
                    end
                    
                    FIFTH: begin
                        if (outbyte > 8'd60) data_in[15:12] = ascii2hex;
                        else                 data_in[15:12] = ascii2dec;
                        sdstate_in = SIXTH;
                    end
                    
                    SIXTH: begin
                        if (outbyte > 8'd60) data_in[11:8] = ascii2hex;
                        else                 data_in[11:8] = ascii2dec;
                        sdstate_in = SEVENTH;
                    end
                    
                    SEVENTH: begin
                        if (outbyte > 8'd60) data_in[7:4] = ascii2hex;
                        else                 data_in[7:4] = ascii2dec;
                        sdstate_in = EIGHTH;
                    end
                    
                    EIGHTH: begin
                        if (outbyte > 8'd60) data_in[3:0] = ascii2hex;
                        else                 data_in[3:0] = ascii2dec;
                        
                        lineflag_in = ~lineflag_ff;
                        sdstate_in  = NINTH;
                    end
                    
                    NINTH: begin
                        sdstate_in = FIRST;
                    end
                    
                    default: sdstate_in = FIRST;
                endcase
            end
        end
    end

    // Sequential Logic
    always @(posedge clk_sd) begin
        sdstate_ff   <= sdstate_in;
        data_ff      <= data_in;
        lineflag_ff  <= lineflag_in;
        sd_finish_ff <= sd_finish_in;

        // Drive Output Regs
        data         <= data_in;
        sd_finish    <= sd_finish_in;
        sd_run       <= sd_run_in;
    end

    // Component Instantiation
    fpga_top u_fpga_top (
        .clk (clk_sd),
        .resetn (sd_run),
        .sdcard_pwr_n (sdcard_pwr_n),
        .sdclk (sdclk),
        .sdcmd (sdcmd),
        .sddat0 (sddat0),
        .sddat1 (sddat1),
        .sddat2 (sddat2),
        .sddat3 (sddat3),
        .ledout (ledout),
        .outen (outen),
        .outbyte (outbyte),
        .filesystem_state (filesystem_state)
    );

endmodule
