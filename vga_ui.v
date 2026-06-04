`timescale 1ns / 1ps

/*
 * MODULE: vga_ui
 * DESCRIPTION: This module handles the visual generation for the VGA display. 
 * It manages menu text, dynamic number rendering, background art, and a 
 * bouncing "Fun Mode" animation.
 * * LOGIC STRUCTURE:
 * - All state transitions and logic are handled in combinational blocks.
 * - Sequential blocks are used exclusively as registers for data storage.
 * - No logic is assigned directly to wires; all calculations occur in procedural blocks.
 */

module vga_ui(
    input wire clk_vga,
    input wire resetn,
    input wire video_on,
    input wire [9:0] h_count_ff,
    input wire [9:0] v_count_ff,
    input wire [1:0] menu_idx, 
    input wire [1:0] screen_state,
    input wire [2:0] saved_idx,    
    input wire [1:0] endmode_idx,  
    input wire [31:0] count,       
    input wire [2:0] speed_lvl,    
    input wire       is_prime,  
    input wire [31:0] elapsed_sec,
    input wire [31:0] total_primes,
    input wire       test_passed,
    input wire [31:0] history_data_in,
    input wire [31:0] primes_checked,
    input wire [31:0] fail_ram_val,
    input wire [31:0] fail_sd_val,
    output reg [4:0]  history_addr_out,
    output reg [3:0] RED, 
    output reg [3:0] GRN, 
    output reg [3:0] BLU
);

    // Internal Registers for Sequential Logic
    reg [9:0] bounce_x_ff, bounce_y_ff;
    reg       bounce_dx_ff, bounce_dy_ff;
    reg [23:0] blink_timer_ff;
    reg [31:0] latched_count_ff;
    reg [3:0] red_reg, grn_reg, blu_reg;

    // Internal Signals for Combinational Logic
    reg [9:0] bounce_x_next, bounce_y_next;
    reg       bounce_dx_next, bounce_dy_next;
    reg [23:0] blink_timer_next;
    reg [31:0] latched_count_next;
    reg [3:0] red_next, grn_next, blu_next;
    
    reg [9:0] eff_h, eff_v;
    reg [5:0] col;
    reg [4:0] row;
    reg [2:0] x_off;
    reg [3:0] y_off;
    reg [7:0] char_code;
    reg       pixel_on;
    reg       fun_mode_active;
    reg [31:0] active_number;
    
    reg is_t_black, is_t_grey, is_t_door, is_t_win, is_t_knob, is_digit_box;

    // 1. SEQUENTIAL BLOCK: Pure assignments to flip-flops
    always @(posedge clk_vga) begin
        bounce_x_ff      <= bounce_x_next;
        bounce_y_ff      <= bounce_y_next;
        bounce_dx_ff     <= bounce_dx_next;
        bounce_dy_ff     <= bounce_dy_next;
        blink_timer_ff   <= blink_timer_next;
        latched_count_ff <= latched_count_next;
        RED              <= red_next;
        GRN              <= grn_next;
        BLU              <= blu_next;
    end

    // 2. COMBINATIONAL BLOCK: State, Calculation, and Reset Logic
    always @(*) begin
        // --- Initialization and Mode Checks ---
        fun_mode_active = (screen_state == 2'b10 || screen_state == 2'b11) && (saved_idx == 3'd4);
        history_addr_out = 0;

        // --- Logic for Timers and Latches (including Reset) ---
        if (!resetn) begin
            blink_timer_next   = 24'd0;
            latched_count_next = 32'd0;
        end else begin
            blink_timer_next = blink_timer_ff + 24'd1;
            if (screen_state == 2'b01) latched_count_next = count;
            else                       latched_count_next = latched_count_ff;
        end

        // --- Logic for DVD Bounce Animation (including Reset) ---
        if (!resetn) begin
            bounce_x_next  = 10'd320;
            bounce_y_next  = 10'd64;
            bounce_dx_next = 1'b1;
            bounce_dy_next = 1'b1;
        end else if (fun_mode_active) begin
            bounce_x_next  = bounce_x_ff;
            bounce_y_next  = bounce_y_ff;
            bounce_dx_next = bounce_dx_ff;
            bounce_dy_next = bounce_dy_ff;
            if (h_count_ff == 0 && v_count_ff == 480) begin
                if (bounce_dx_ff) begin
                    if (bounce_x_ff + 320 + 2 >= 640) begin bounce_x_next = 640 - 320; bounce_dx_next = 1'b0; end
                    else bounce_x_next = bounce_x_ff + 2;
                end else begin
                    if (bounce_x_ff <= 2) begin bounce_x_next = 0; bounce_dx_next = 1'b1; end
                    else bounce_x_next = bounce_x_ff - 2;
                end
                if (bounce_dy_ff) begin
                    if (bounce_y_ff + 320 + 2 >= 480) begin bounce_y_next = 480 - 320; bounce_dy_next = 1'b0; end
                    else bounce_y_next = bounce_y_ff + 2;
                end else begin
                    if (bounce_y_ff <= 2) begin bounce_y_next = 0; bounce_dy_next = 1'b1; end
                    else bounce_y_next = bounce_y_ff - 2;
                end
            end
        end else begin
            bounce_x_next  = 10'd320;
            bounce_y_next  = 10'd64;
            bounce_dx_next = 1'b1;
            bounce_dy_next = 1'b1;
        end

        // --- Logic for Screen Coordinates and Character Mapping ---
        eff_h = fun_mode_active ? (h_count_ff - bounce_x_ff + 320) : h_count_ff;
        eff_v = fun_mode_active ? (v_count_ff - bounce_y_ff + 64)  : v_count_ff;
        col   = eff_h[9:4]; 
        row   = eff_v[8:5]; 
        x_off = eff_h[3:1]; 
        y_off = eff_v[4:1];

        // --- Logic for Number/Data Display Selection ---
        active_number = count;
        if ((screen_state == 2'b10 || screen_state == 2'b11)) begin
            if (saved_idx == 3'd3) begin
                if (test_passed) begin
                    if (row == 6) active_number = primes_checked;
                end else begin
                    if (row == 6)      active_number = fail_ram_val;
                    else if (row == 8) active_number = fail_sd_val;
                end
            end else begin
                if (row == 2)      active_number = (saved_idx == 3'd0) ? count : latched_count_ff;
                else if (row == 4) active_number = elapsed_sec;
                else if (row == 6) active_number = total_primes;
            end
        end
    end

    // Helper values for character generation
    wire [3:0] digit0 = (active_number % 10);
    wire [3:0] digit1 = (active_number / 10) % 10;
    wire [3:0] digit2 = (active_number / 100) % 10;
    wire [3:0] digit3 = (active_number / 1000) % 10;
    wire [3:0] digit4 = (active_number / 10000) % 10;
    wire [3:0] digit5 = (active_number / 100000) % 10;
    wire [3:0] digit6 = (active_number / 1000000) % 10;
    wire [3:0] digit7 = (active_number / 10000000) % 10;

    // 3. COMBINATIONAL BLOCK: Char Code Selection
    always @(*) begin
        char_code = 8'h20;
        case(screen_state)
            2'b00: begin 
                case(row)
                    2: case(col) 6:char_code="A"; 7:char_code="D"; 8:char_code="V"; 9:char_code="E"; 10:char_code="N"; 11:char_code="T"; 12:char_code="U"; 13:char_code="R"; 14:char_code="E"; 16:char_code="P"; 17:char_code="R"; 18:char_code="I"; 19:char_code="M"; 20:char_code="E"; endcase
                    4: begin if (col==3) char_code=(menu_idx==0)?">":" "; case(col) 5:char_code="M"; 6:char_code="O"; 7:char_code="D"; 8:char_code="E"; 10:char_code="1"; 11:char_code=":"; 13:char_code="I"; 14:char_code="S"; 16:char_code="I"; 17:char_code="T"; 19:char_code="P"; 20:char_code="R"; 21:char_code="I"; 22:char_code="M"; 23:char_code="E"; 24:char_code="?"; endcase end
                    6: begin if (col==3) char_code=(menu_idx==1)?">":" "; case(col) 5:char_code="M"; 6:char_code="O"; 7:char_code="D"; 8:char_code="E"; 10:char_code="2"; 11:char_code=":"; 13:char_code="P"; 14:char_code="R"; 15:char_code="I"; 16:char_code="M"; 17:char_code="E"; 18:char_code="S"; 20:char_code="<"; 22:char_code="M"; 23:char_code="A"; 24:char_code="X"; endcase end
                    8: begin if (col==3) char_code=(menu_idx==2)?">":" "; case(col) 5:char_code="M"; 6:char_code="O"; 7:char_code="D"; 8:char_code="E"; 10:char_code="3"; 11:char_code=":"; 13:char_code="T"; 14:char_code="I"; 15:char_code="M"; 16:char_code="E"; 17:char_code="D"; 19:char_code="P"; 20:char_code="R"; 21:char_code="I"; 22:char_code="M"; 23:char_code="E"; endcase end
                endcase
            end
            2'b01: begin 
                case(row)
                    4: begin
                        if (saved_idx == 3'd0)      case(col) 5:char_code="E"; 6:char_code="N"; 7:char_code="T"; 8:char_code="E"; 9:char_code="R"; 11:char_code="A"; 13:char_code="N"; 14:char_code="U"; 15:char_code="M"; 16:char_code="B"; 17:char_code="E"; 18:char_code="R"; 19:char_code=":"; endcase
                        else if (saved_idx == 3'd1) case(col) 5:char_code="E"; 6:char_code="N"; 7:char_code="T"; 8:char_code="E"; 9:char_code="R"; 11:char_code="A"; 13:char_code="M"; 14:char_code="A"; 15:char_code="X"; 17:char_code="N"; 18:char_code="U"; 19:char_code="M"; 20:char_code="B"; 21:char_code="E"; 22:char_code="R"; 23:char_code=":"; endcase
                        else if (saved_idx == 3'd2) case(col) 5:char_code="E"; 6:char_code="N"; 7:char_code="T"; 8:char_code="E"; 9:char_code="R"; 11:char_code="A"; 13:char_code="M"; 14:char_code="A"; 15:char_code="X"; 17:char_code="T"; 18:char_code="I"; 19:char_code="M"; 20:char_code="E"; 22:char_code="I"; 23:char_code="N"; 25:char_code="S"; 26:char_code="E"; 27:char_code="C"; 28:char_code="O"; 29:char_code="N"; 30:char_code="D"; 31:char_code="S"; 32:char_code=":"; endcase
                    end
                    6: case(col) 6:char_code="0"+digit7; 7:char_code="0"+digit6; 8:char_code=","; 9:char_code="0"+digit5; 10:char_code="0"+digit4; 11:char_code="0"+digit3; 12:char_code=","; 13:char_code="0"+digit2; 14:char_code="0"+digit1; 15:char_code="0"+digit0; endcase
                    8: case(col) 5:char_code="P"; 6:char_code="R"; 7:char_code="E"; 8:char_code="S"; 9:char_code="S"; 11:char_code="K"; 12:char_code="N"; 13:char_code="O"; 14:char_code="B"; 16:char_code="T"; 17:char_code="O"; 19:char_code="S"; 20:char_code="T"; 21:char_code="A"; 22:char_code="R"; 23:char_code="T"; endcase
                endcase
            end
            2'b10, 2'b11: begin 
                if (saved_idx == 3'd0) begin
                    if (screen_state == 2'b10 && row == 6) case(col) 8:char_code="L"; 9:char_code="O"; 10:char_code="A"; 11:char_code="D"; 12:char_code="I"; 13:char_code="N"; 14:char_code="G"; 15:char_code="."; 16:char_code="."; 17:char_code="."; endcase
                    if (screen_state == 2'b11 && row == 4) begin
                        if (is_prime) case(col) 8:char_code="Y"; 9:char_code="E"; 10:char_code="S"; 11:char_code="!"; 13:char_code="I"; 14:char_code="T"; 16:char_code="I"; 17:char_code="S"; 19:char_code="P"; 20:char_code="R"; 21:char_code="I"; 22:char_code="M"; 23:char_code="E"; endcase
                        else          case(col) 6:char_code="N"; 7:char_code="O"; 8:char_code="!"; 10:char_code="I"; 11:char_code="T"; 13:char_code="I"; 14:char_code="S"; 16:char_code="N"; 17:char_code="O"; 18:char_code="T"; 20:char_code="P"; 21:char_code="R"; 22:char_code="I"; 23:char_code="M"; 24:char_code="E"; endcase
                    end
                end 
                else if (saved_idx == 3'd3) begin
                    if (screen_state == 2'b10 && row == 6) case(col) 8:char_code="T"; 9:char_code="E"; 10:char_code="S"; 11:char_code="T"; 12:char_code="I"; 13:char_code="N"; 14:char_code="G"; 15:char_code="."; 16:char_code="."; 17:char_code="."; endcase
                    if (screen_state == 2'b11) begin
                        if (test_passed) begin
                            if (row == 4) case(col) 3:char_code="P"; 4:char_code="A"; 5:char_code="S"; 6:char_code="S"; 7:char_code="E"; 8:char_code="D"; endcase
                            if (row == 6) case(col) 1:char_code="C"; 2:char_code="H"; 3:char_code="E"; 4:char_code="C"; 5:char_code="K"; 6:char_code="E"; 7:char_code="D"; 8:char_code=":"; 10:char_code="0"+digit7; 11:char_code="0"+digit6; 12:char_code=","; 13:char_code="0"+digit5; 14:char_code="0"+digit4; 15:char_code="0"+digit3; 16:char_code=","; 17:char_code="0"+digit2; 18:char_code="0"+digit1; 19:char_code="0"+digit0; endcase
                        end else begin
                            if (row == 4) case(col) 3:char_code="F"; 4:char_code="A"; 5:char_code="I"; 6:char_code="L"; 7:char_code="E"; 8:char_code="D"; endcase
                        end
                    end
                end
                else begin
                    if (row == 2)      case(col) 2:char_code="M"; 3:char_code="A"; 4:char_code="X"; 5:char_code=":"; 7:char_code="0"+digit7; 8:char_code="0"+digit6; 9:char_code=","; 10:char_code="0"+digit5; 11:char_code="0"+digit4; 12:char_code="0"+digit3; 13:char_code=","; 14:char_code="0"+digit2; 15:char_code="0"+digit1; 16:char_code="0"+digit0; endcase
                    if (row == 4)      case(col) 2:char_code="T"; 3:char_code="I"; 4:char_code="M"; 5:char_code="E"; 6:char_code=":"; 8:char_code="0"+digit7; 9:char_code="0"+digit6; 10:char_code=","; 11:char_code="0"+digit5; 12:char_code="0"+digit4; 13:char_code="0"+digit3; 14:char_code=","; 15:char_code="0"+digit2; 16:char_code="0"+digit1; 17:char_code="0"+digit0; endcase
                    if (row == 6)      case(col) 2:char_code="F"; 3:char_code="O"; 4:char_code="U"; 5:char_code="N"; 6:char_code="D"; 7:char_code=":"; 9:char_code="0"+digit7; 10:char_code="0"+digit6; 11:char_code=","; 12:char_code="0"+digit5; 13:char_code="0"+digit4; 14:char_code="0"+digit3; 15:char_code=","; 16:char_code="0"+digit2; 17:char_code="0"+digit1; 18:char_code="0"+digit0; endcase
                end
                if (screen_state == 2'b11 && col < 20 && !fun_mode_active) begin
                    if (row == 10) begin if (col == 2) char_code = (endmode_idx == 0) ? ">" : " "; case(col) 4:char_code="T"; 5:char_code="E"; 6:char_code="S"; 7:char_code="T"; 9:char_code="M"; 10:char_code="O"; 11:char_code="D"; 12:char_code="E"; endcase end
                    if (row == 12) begin if (col == 2) char_code = (endmode_idx == 1) ? ">" : " "; case(col) 4:char_code="F"; 5:char_code="U"; 6:char_code="N"; 8:char_code="M"; 9:char_code="O"; 10:char_code="D"; 11:char_code="E"; endcase end
                    if (row == 14) begin if (col == 2) char_code = (endmode_idx == 2) ? ">" : " "; case(col) 4:char_code="M"; 5:char_code="A"; 6:char_code="I"; 7:char_code="N"; 9:char_code="M"; 10:char_code="E"; 11:char_code="N"; 12:char_code="U"; endcase end
                end
            end
        endcase
    end

    // 4. COMBINATIONAL BLOCK: Char Pixel Generation (Shape Drawing)
    always @(*) begin
        pixel_on = 1'b0;
        case (char_code)
            "A": case(y_off) 2:pixel_on=(x_off==4); 3:pixel_on=(x_off==3)|(x_off==5); 4,5,8,9,10,11:pixel_on=(x_off==2)|(x_off==6); 6,7:pixel_on=(x_off>1)&&(x_off<7); default:pixel_on=0; endcase
            "B": case(y_off) 2,6,11:pixel_on=(x_off>1)&&(x_off<6); 3,4,5,7,8,9,10:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "C": case(y_off) 2,11:pixel_on=(x_off>2)&&(x_off<6); 3,10:pixel_on=(x_off==2)|(x_off==6); 4,5,6,7,8,9:pixel_on=(x_off==2); default:pixel_on=0; endcase
            "D": case(y_off) 2,11:pixel_on=(x_off>1)&&(x_off<5); 3,10:pixel_on=(x_off>1)&&(x_off<6); 4,5,6,7,8,9:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "E": case(y_off) 2,11:pixel_on=(x_off>1)&&(x_off<7); 3,4,5,8,9,10:pixel_on=(x_off==2); 6,7:pixel_on=(x_off>1)&&(x_off<6); default:pixel_on=0; endcase
            "F": case(y_off) 2:pixel_on=(x_off>1)&&(x_off<7); 3,4,5,8,9,10,11:pixel_on=(x_off==2); 6,7:pixel_on=(x_off>1)&&(x_off<6); default:pixel_on=0; endcase
            "G": case(y_off) 2,11:pixel_on=(x_off>2)&&(x_off<6); 3,10:pixel_on=(x_off==2)|(x_off==6); 4,5,6:pixel_on=(x_off==2); 7:pixel_on=(x_off==2)|(x_off>3); 8,9:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "H": case(y_off) 2,3,4,5,6,8,9,10,11:pixel_on=(x_off==2)|(x_off==6); 7:pixel_on=(x_off>1)&&(x_off<7); default:pixel_on=0; endcase
            "I": case(y_off) 2,11:pixel_on=(x_off>2)&&(x_off<6); 3,4,5,6,7,8,9,10:pixel_on=(x_off==4); default:pixel_on=0; endcase
            "K": case(y_off) 2,11:pixel_on=(x_off==2)|(x_off==6); 3,10:pixel_on=(x_off==2)|(x_off==5); 4,9:pixel_on=(x_off==2)|(x_off==4); 5,6,7,8:pixel_on=(x_off==2)|(x_off==3); default:pixel_on=0; endcase
            "L": case(y_off) 2,3,4,5,6,7,8,9,10:pixel_on=(x_off==2); 11:pixel_on=(x_off>1)&&(x_off<7); default:pixel_on=0; endcase
            "M": case(y_off) 2,3,4,5,6,7,8,9,10,11:pixel_on=(x_off==1)|(x_off==7)||(y_off==3&&(x_off==2||x_off==6))||(y_off==4&&(x_off==3||x_off==5))||(y_off==5&&x_off==4); default:pixel_on=0; endcase
            "N": case(y_off) 2,3:pixel_on=(x_off==2)|(x_off==6); 4,5:pixel_on=(x_off==2)|(x_off==6)|(x_off==3); 6,7:pixel_on=(x_off==2)|(x_off==6)|(x_off==4); 8,9:pixel_on=(x_off==2)|(x_off==6)|(x_off==5); 10,11:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "O": case(y_off) 2,11:pixel_on=(x_off>2)&&(x_off<6); 3,10:pixel_on=(x_off==2)|(x_off==6); 4,5,6,7,8,9:pixel_on=(x_off==1)|(x_off==7); default:pixel_on=0; endcase
            "P": case(y_off) 2:pixel_on=(x_off>1)&&(x_off<6); 3,4,5,6:pixel_on=(x_off==2)|(x_off==6); 7:pixel_on=(x_off>1)&&(x_off<6); 8,9,10,11:pixel_on=(x_off==2); default:pixel_on=0; endcase
            "R": case(y_off) 2:pixel_on=(x_off>1)&&(x_off<6); 3,4,5,6:pixel_on=(x_off==2)|(x_off==6); 7:pixel_on=(x_off>1)&&(x_off<6); 8,9,10,11:pixel_on=(x_off==2)|(x_off==y_off-4); default:pixel_on=0; endcase
            "S": case(y_off) 2,6,11:pixel_on=(x_off>2)&&(x_off<6); 3,4,5:pixel_on=(x_off==2); 7,8,9,10:pixel_on=(x_off==6); default:pixel_on=0; endcase
            "T": case(y_off) 2:pixel_on=(x_off>0)&&(x_off<8); 3,4,5,6,7,8,9,10,11:pixel_on=(x_off==4); default:pixel_on=0; endcase
            "U": case(y_off) 2,3,4,5,6,7,8,9,10:pixel_on=(x_off==2)|(x_off==6); 11:pixel_on=(x_off>2)&&(x_off<6); default:pixel_on=0; endcase
            "V": case(y_off) 2,3,4,5,6,7,8:pixel_on=(x_off==2)|(x_off==6); 9:pixel_on=(x_off==3)|(x_off==5); 10,11:pixel_on=(x_off==4); default:pixel_on=0; endcase
            "X": case(y_off) 2,3,10,11:pixel_on=(x_off==2)|(x_off==6); 4,5,8,9:pixel_on=(x_off==3)|(x_off==5); 6,7:pixel_on=(x_off==4); default:pixel_on=0; endcase
            "Y": case(y_off) 2,3,4:pixel_on=(x_off==2)|(x_off==6); 5,6:pixel_on=(x_off==3)|(x_off==5); 7,8,9,10,11:pixel_on=(x_off==4); default:pixel_on=0; endcase
            "0": case(y_off) 2,11:pixel_on=(x_off>2)&&(x_off<6); 3,4,5,6,7,8,9,10:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "1": case(y_off) 2:pixel_on=(x_off==4); 3:pixel_on=(x_off==3)|(x_off==4); 4,5,6,7,8,9,10:pixel_on=(x_off==4); 11:pixel_on=(x_off>1)&&(x_off<7); default:pixel_on=0; endcase
            "2": case(y_off) 2,11:pixel_on=(x_off>1)&&(x_off<7); 3,10:pixel_on=(x_off==2)|(x_off==6); 4,9:pixel_on=(x_off==6); 5,6:pixel_on=(x_off==5)|(x_off==6); 7,8:pixel_on=(x_off==3)|(x_off==4); default:pixel_on=0; endcase
            "3": case(y_off) 2,6,11:pixel_on=(x_off>1)&&(x_off<7); 3,4,5,7,8,9,10:pixel_on=(x_off==6); default:pixel_on=0; endcase
            "4": case(y_off) 2,3,4,5:pixel_on=(x_off==2)|(x_off==6); 6:pixel_on=(x_off>1)&&(x_off<8); 7,8,9,10,11:pixel_on=(x_off==6); default:pixel_on=0; endcase
            "5": case(y_off) 2,6,11:pixel_on=(x_off>1)&&(x_off<7); 3,4,5:pixel_on=(x_off==2); 7,8,9,10:pixel_on=(x_off==6); default:pixel_on=0; endcase
            "6": case(y_off) 2,6,11:pixel_on=(x_off>1)&&(x_off<7); 3,4,5:pixel_on=(x_off==2); 7,8,9,10:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "7": case(y_off) 2:pixel_on=(x_off>1)&&(x_off<7); 3,4:pixel_on=(x_off==6); 5,6:pixel_on=(x_off==5); 7,8:pixel_on=(x_off==4); 9,10,11:pixel_on=(x_off==3); default:pixel_on=0; endcase
            "8": case(y_off) 2,6,11:pixel_on=(x_off>1)&&(x_off<7); 3,4,5,7,8,9,10:pixel_on=(x_off==2)|(x_off==6); default:pixel_on=0; endcase
            "9": case(y_off) 2,6,11:pixel_on=(x_off>1)&&(x_off<7); 3,4,5:pixel_on=(x_off==2)|(x_off==6); 7,8,9,10,11:pixel_on=(x_off==6); default:pixel_on=0; endcase
            ":": case(y_off) 4,5,8,9:pixel_on=(x_off==4); default:pixel_on=0; endcase
            ",": case(y_off) 9,10:pixel_on=(x_off==4); 11:pixel_on=(x_off==3); default:pixel_on=0; endcase
            "?": case(y_off) 2:pixel_on=(x_off>2)&&(x_off<6); 3:pixel_on=(x_off==2)|(x_off==6); 4,5:pixel_on=(x_off==6); 6,7:pixel_on=(x_off==4)|(x_off==5); 9,10:pixel_on=(x_off==4); default:pixel_on=0; endcase
            ">": case(y_off) 2,10:pixel_on=(x_off==2); 3,9:pixel_on=(x_off==3); 4,8:pixel_on=(x_off==4); 5,7:pixel_on=(x_off==5); 6:pixel_on=(x_off==6); default:pixel_on=0; endcase
            "<": case(y_off) 2,10:pixel_on=(x_off==6); 3,9:pixel_on=(x_off==5); 4,8:pixel_on=(x_off==4); 5,7:pixel_on=(x_off==3); 6:pixel_on=(x_off==2); default:pixel_on=0; endcase
            "!": case(y_off) 2,3,4,5,6,7,8:pixel_on=(x_off==4); 10,11:pixel_on=(x_off==4); default:pixel_on=0; endcase
            ".": case(y_off) 10,11:pixel_on=(x_off==4); default:pixel_on=0; endcase
            default: pixel_on = 0;
        endcase
    end

    // 5. COMBINATIONAL BLOCK: Background Art Logic
    always @(*) begin
        is_t_black = 0; is_t_grey = 0; is_t_door = 0; is_t_win = 0; is_t_knob = 0; is_digit_box = 0;
        if (video_on) begin
            if (v_count_ff >= 20 && v_count_ff < 50 && ((h_count_ff >= 420 && h_count_ff < 460) || (h_count_ff >= 500 && h_count_ff < 550) || (h_count_ff >= 590 && h_count_ff < 630))) is_t_grey = 1;
            if (v_count_ff >= 50 && v_count_ff < 90 && (h_count_ff >= 420 && h_count_ff < 630)) is_t_grey = 1;
            if (v_count_ff >= 90 && v_count_ff < 460 && (h_count_ff >= 440 && h_count_ff < 610)) is_t_grey = 1;
            if (v_count_ff >= 310 && v_count_ff < 460 && (h_count_ff >= 480 && h_count_ff < 570)) is_t_door = 1;
            if (v_count_ff >= 290 && v_count_ff < 310 && (h_count_ff >= 500 && h_count_ff < 550)) is_t_door = 1;
            if (v_count_ff >= 380 && v_count_ff < 390 && h_count_ff >= 540 && h_count_ff < 550) is_t_knob = 1;
            if (v_count_ff >= 140 && v_count_ff < 220 && (h_count_ff >= 490 && h_count_ff < 560)) is_t_win = 1;
            if (v_count_ff >= 120 && v_count_ff < 140 && (h_count_ff >= 510 && h_count_ff < 540)) is_t_win = 1;
            if (v_count_ff >= 90 && v_count_ff < 460 && ((h_count_ff >= 440 && h_count_ff < 450) || (h_count_ff >= 600 && h_count_ff < 610))) is_t_black = 1;
            if (v_count_ff >= 80 && v_count_ff < 90 && ((h_count_ff >= 420 && h_count_ff < 430) || (h_count_ff >= 620 && h_count_ff < 630))) is_t_black = 1;
            if (v_count_ff >= 50 && v_count_ff < 80 && ((h_count_ff >= 420 && h_count_ff < 430) || (h_count_ff >= 620 && h_count_ff < 630) || (h_count_ff >= 450 && h_count_ff < 460) || (h_count_ff >= 590 && h_count_ff < 600) || (h_count_ff >= 500 && h_count_ff < 510) || (h_count_ff >= 540 && h_count_ff < 550))) is_t_black = 1;
            if (v_count_ff >= 20 && v_count_ff < 50 && ((h_count_ff >= 420 && h_count_ff < 430) || (h_count_ff >= 450 && h_count_ff < 460) || (h_count_ff >= 500 && h_count_ff < 510) || (h_count_ff >= 540 && h_count_ff < 550) || (h_count_ff >= 590 && h_count_ff < 600) || (h_count_ff >= 620 && h_count_ff < 630))) is_t_black = 1;
            if (v_count_ff >= 10 && v_count_ff < 20 && ((h_count_ff >= 420 && h_count_ff < 460) || (h_count_ff >= 500 && h_count_ff < 550) || (h_count_ff >= 590 && h_count_ff < 630))) is_t_black = 1;
            if (v_count_ff >= 40 && v_count_ff < 50 && ((h_count_ff >= 460 && h_count_ff < 500) || (h_count_ff >= 550 && h_count_ff < 590))) is_t_black = 1;
            if (v_count_ff >= 310 && v_count_ff < 460 && ((h_count_ff >= 480 && h_count_ff < 490) || (h_count_ff >= 560 && h_count_ff < 570))) is_t_black = 1;
            if (v_count_ff >= 290 && v_count_ff < 300 && (h_count_ff >= 500 && h_count_ff < 550)) is_t_black = 1;
            if (v_count_ff >= 300 && v_count_ff < 310 && ((h_count_ff >= 490 && h_count_ff < 500) || (h_count_ff >= 550 && h_count_ff < 560))) is_t_black = 1;
            if (v_count_ff >= 140 && v_count_ff < 220 && ((h_count_ff >= 490 && h_count_ff < 500) || (h_count_ff >= 550 && h_count_ff < 560))) is_t_black = 1;
            if (v_count_ff >= 120 && v_count_ff < 130 && (h_count_ff >= 510 && h_count_ff < 540)) is_t_black = 1;
            if (v_count_ff >= 130 && v_count_ff < 140 && ((h_count_ff >= 500 && h_count_ff < 510) || (h_count_ff >= 540 && h_count_ff < 550))) is_t_black = 1;
            if (v_count_ff >= 220 && v_count_ff < 230 && (h_count_ff >= 490 && h_count_ff < 560)) is_t_black = 1;
        end
    end

    // 6. COMBINATIONAL BLOCK: Final Color Output Logic
    always @(*) begin
        red_next = 0; grn_next = 0; blu_next = 0;
        if (video_on) begin
            if (pixel_on) begin
                if (screen_state == 2'b00) begin
                    if (row == 4 && menu_idx == 0) begin red_next = 4'h0; grn_next = 4'hF; blu_next = 4'h0; end
                    else if (row == 6 && menu_idx == 1) begin red_next = 4'h0; grn_next = 4'hF; blu_next = 4'h0; end
                    else if (row == 8 && menu_idx == 2) begin red_next = 4'h0; grn_next = 4'hF; blu_next = 4'h0; end
                    else begin red_next = 4'hF; grn_next = 4'hF; blu_next = 4'hF; end
                end else if (screen_state == 2'b11 && col < 20 && !fun_mode_active && ((row == 10 && endmode_idx == 0) || (row == 12 && endmode_idx == 1) || (row == 14 && endmode_idx == 2))) begin red_next = 4'h0; grn_next = 4'hF; blu_next = 4'h0;
                end else if (screen_state == 2'b11 && saved_idx == 3'd3 && (row == 4 || row == 6 || row == 8) && col < 20) begin 
                    if (test_passed) begin red_next = 4'h0; grn_next = 4'hF; blu_next = 4'h0; end 
                    else             begin red_next = 4'hF; grn_next = 4'h0; blu_next = 4'h0; end 
                end else if (fun_mode_active) begin 
                    red_next = bounce_dx_ff ? 4'hF : 4'h3; grn_next = bounce_dy_ff ? 4'hF : 4'h8; blu_next = (!bounce_dx_ff && bounce_dy_ff) ? 4'hF : 4'h5; 
                end else begin red_next = 4'hF; grn_next = 4'hF; blu_next = 4'hF; end
            end 
            else if (is_digit_box) begin red_next = 4'hF; grn_next = 4'hF; blu_next = 4'hF; end
            else if (is_t_black) begin red_next = 4'h0; grn_next = 4'h0; blu_next = 4'h0; end
            else if (is_t_knob)  begin red_next = 4'hF; grn_next = 4'hD; blu_next = 4'h0; end
            else if (is_t_win)   begin red_next = 4'h0; grn_next = 4'hD; blu_next = 4'hF; end
            else if (is_t_door)  begin red_next = 4'h4; grn_next = 4'h2; blu_next = 4'h1; end
            else if (is_t_grey)  begin red_next = 4'h7; grn_next = 4'h7; blu_next = 4'h7; end
            else if (screen_state == 2'b00 && h_count_ff >= 330 && h_count_ff < 350 && v_count_ff >= 350 && v_count_ff < 440) begin red_next=4'h6; grn_next=4'h3; blu_next=4'h1; end 
            else if (screen_state == 2'b00 && h_count_ff >= 350 && h_count_ff < 390 && v_count_ff >= 330 && v_count_ff < 360) begin red_next=4'h6; grn_next=4'h3; blu_next=4'h1; end 
            else if (screen_state == 2'b00 && h_count_ff >= 300 && h_count_ff < 330 && v_count_ff >= 370 && v_count_ff < 390) begin red_next=4'h6; grn_next=4'h3; blu_next=4'h1; end 
            else if (screen_state == 2'b00 && ((h_count_ff >= 260 && h_count_ff < 320 && v_count_ff >= 310 && v_count_ff < 390) || (h_count_ff >= 300 && h_count_ff < 370 && v_count_ff >= 280 && v_count_ff < 340))) begin red_next=4'h0; grn_next=4'h7; blu_next=4'h0; end
            else begin red_next = 4'h0; grn_next = 4'h0; blu_next = 4'h4; end
        end
    end

endmodule
