`timescale 1ns / 1ps

// UI_controller is a module that has an FSM to manage the flow of the UI and 
// specifies the UI screen to be displayed based on menu selection and user entry.
// The module also ensures calculation resulted are saved for the dplay and making synchronous
// start and stop signals for the display.
module ui_controller(
    input  wire        clk,              
    input  wire        rst_n,            
    input  wire        triggered,        
    input  wire [1:0]  menu_idx_in,      
    input  wire [1:0]  endmode_idx_in,   
    input  wire        engine_done,      
    input  wire        prime_valid,      
    input  wire        is_prime_in,      
    output reg  [1:0]  screen_state,     
    output reg  [2:0]  saved_idx,        
    output reg         menu_select,      
    output reg         start_engine,     
    output reg         is_prime_saved,   
    output reg  [2:0]  last_calc_mode,   
    output reg         start_prime,
    output reg         input_screen_active
);

// temporary variables
    reg [1:0] screen_state_next;
    reg [2:0] saved_idx_next;
    reg       menu_select_next;
    reg       start_engine_next;
    reg       is_prime_saved_next;
    reg [2:0] last_calc_mode_next;
    reg       is_calc_mode;

    // sequential block, only loading to registers
    always @(posedge clk) begin
        screen_state   <= screen_state_next;
        saved_idx      <= saved_idx_next;
        menu_select    <= menu_select_next;
        start_engine   <= start_engine_next;
        is_prime_saved <= is_prime_saved_next;
        last_calc_mode <= last_calc_mode_next;
    end

    //combinational logic block
    always @(*) begin
        is_calc_mode        = (saved_idx == 3'd0 || saved_idx == 3'd1 || saved_idx == 3'd2);
        start_prime         = start_engine & is_calc_mode;
        input_screen_active = (screen_state == 2'b01);

        //reset logic
        if (!rst_n) begin
            // Reset state evaluations
            screen_state_next   = 2'b00;
            saved_idx_next      = 3'd0;
            menu_select_next    = 1'b0;
            start_engine_next   = 1'b0;
            is_prime_saved_next = 1'b0;
            last_calc_mode_next = 3'd0;
        end else begin
            //default assignments
            screen_state_next   = screen_state;
            saved_idx_next      = saved_idx;
            menu_select_next    = menu_select;
            start_engine_next   = start_engine;
            is_prime_saved_next = is_prime_saved;
            last_calc_mode_next = last_calc_mode;

            //main menu screen, user waits here until triggered is 1,
            // indicating a selection.
            case (screen_state)
                2'b00: begin
                    menu_select_next = 1'b0;
                    if (triggered) begin
                        saved_idx_next    = {1'b0, menu_idx_in}; 
                        screen_state_next = 2'b01;
                    end
                end
                //input screen for number, move to next mode based on triggered
                2'b01: begin
                    if (triggered) begin
                        start_engine_next = 1'b1;
                        screen_state_next = 2'b10;
                        
                        if (saved_idx == 3'd0 || saved_idx == 3'd1 || saved_idx == 3'd2) begin
                            last_calc_mode_next = saved_idx;
                        end
                    end
                end
                // active screen, calculation, fun mode. waits for engine done or manual exit
                2'b10: begin
                    //checkfor manual exit F
                    if (saved_idx == 3'd4 && triggered) begin 
                        screen_state_next = 2'b00; 
                        saved_idx_next    = 3'd0;
                        start_engine_next = 1'b0;
                    end
                    //check calculation engine
                    else if (engine_done) begin
                        start_engine_next   = 1'b0;     
                        is_prime_saved_next = is_prime_in; 
                        screen_state_next   = 2'b11;    
                    end
                end 
                // end screen results, activate sub-menu
                2'b11: begin 
                    start_engine_next = 1'b0;         
                    menu_select_next  = 1'b1; 
                    
                    if (triggered) begin
                        if (endmode_idx_in == 2'd0) begin
                            saved_idx_next    = 3'd3;  
                            screen_state_next = 2'b10; 
                        end else if (endmode_idx_in == 2'd1) begin
                            saved_idx_next    = 3'd4;  
                            screen_state_next = 2'b10; 
                        end else begin
                            screen_state_next = 2'b00; 
                            saved_idx_next    = 3'd0;
                        end
                    end
                end
            endcase
        end
    end
endmodule
