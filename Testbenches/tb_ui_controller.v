`timescale 1ns / 1ps

// This testbench exhausively tests ui_controller.
// It verifies that normal flow from state to state occurs, end screen switches as expected, and fun mode allows for a manual exit.
// The status of if a test case passed or failed is printed to the terminal. 

module tb_ui_controller();
    reg        clk;
    reg        rst_n;
    reg        triggered;
    reg  [1:0] menu_idx_in;
    reg  [1:0] endmode_idx_in;
    reg        engine_done;
    reg        prime_valid; 
    reg        is_prime_in;

    wire [1:0] screen_state;
    wire [2:0] saved_idx;
    wire       menu_select;
    wire       start_engine;
    wire       is_prime_saved;
    wire [2:0] last_calc_mode;
    wire       start_prime;
    wire       input_screen_active;

    //test counts for tracking
    integer tests_passed = 0;
    integer total_tests  = 0;

    //dut
    ui_controller uut (
        .clk(clk),
        .rst_n(rst_n),
        .triggered(triggered),
        .menu_idx_in(menu_idx_in),
        .endmode_idx_in(endmode_idx_in),
        .engine_done(engine_done),
        .prime_valid(prime_valid),
        .is_prime_in(is_prime_in),
        .screen_state(screen_state),
        .saved_idx(saved_idx),
        .menu_select(menu_select),
        .start_engine(start_engine),
        .is_prime_saved(is_prime_saved),
        .last_calc_mode(last_calc_mode),
        .start_prime(start_prime),
        .input_screen_active(input_screen_active)
    );

    //simulate clk. 
    always #5 clk = ~clk; // 100MHz

    // testing verification task
    task check_state;
        input [1:0] exp_state;
        input [2:0] exp_saved_idx;
        input       exp_start_eng;
        input [150:0] test_name;
        begin
            total_tests = total_tests + 1;
            if (screen_state === exp_state && 
                saved_idx === exp_saved_idx && 
                start_engine === exp_start_eng) begin
                $display("[PASS] %s", test_name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s", test_name);
                $display("       Expected: State=%b, Idx=%d, StartEng=%b", exp_state, exp_saved_idx, exp_start_eng);
                $display("       Got     : State=%b, Idx=%d, StartEng=%b", screen_state, saved_idx, start_engine);
            end
        end
    endtask

    //main test algorithm 
    initial begin
        clk = 0;
        rst_n = 0;
        triggered = 0;
        menu_idx_in = 0;
        endmode_idx_in = 0;
        engine_done = 0;
        prime_valid = 0;
        is_prime_in = 0;

        //reset
        #20 rst_n = 1;
        #10 check_state(2'b00, 3'd0, 1'b0, "Initial Reset State (00)");

        // TEST 1: Normal  Flow 
        $display("\nStarting Test 1: Normal Flow");
        
        //main menu, select mode 1
        menu_idx_in = 2'd1;
        triggered = 1; #10 triggered = 0; #10;
        check_state(2'b01, 3'd1, 1'b0, "Transition to Input Screen (01)");
        
        if (input_screen_active !== 1'b1) $display("[FAIL] input_screen_active not set");
        else tests_passed = tests_passed + 1; total_tests = total_tests + 1;

        //input screen
        triggered = 1; #10 triggered = 0; #10;
        check_state(2'b10, 3'd1, 1'b1, "Transition to Calc State (10), Engine Started");
        
        if (last_calc_mode !== 3'd1) $display("[FAIL] last_calc_mode not updated");
        else tests_passed = tests_passed + 1; total_tests = total_tests + 1;

      //finish prime calc (simulate)
        is_prime_in = 1'b1;
        engine_done = 1; #10 engine_done = 0; #10;
        check_state(2'b11, 3'd1, 1'b0, "Transition to End Screen (11), Engine Stopped");
        
        if (is_prime_saved !== 1'b1) $display("[FAIL] is_prime_saved not captured");
        else tests_passed = tests_passed + 1; total_tests = total_tests + 1;

      //end screen
        endmode_idx_in = 2'd2;
        triggered = 1; #10 triggered = 0; #10;
        check_state(2'b00, 3'd0, 1'b0, "Exit to Main Menu from End Screen");

        // TEST 2: End Screen  Edge Cases
        $display("\nStarting Test 2: End Screen");
        
      //end screen
        triggered = 1; #10 triggered = 0; #10; // To 01
        triggered = 1; #10 triggered = 0; #10; // To 10
        engine_done = 1; #10 engine_done = 0; #10; // To 11
        
      //end_idx = 0
        endmode_idx_in = 2'd0;
        triggered = 1; #10 triggered = 0; #10;
        check_state(2'b10, 3'd3, 1'b0, "End Screen Re-route to State 10 (idx 3)");

        // finish calc
        engine_done = 1; #10 engine_done = 0; #10; // Back to 11
        
        // end_idx = 1 
        endmode_idx_in = 2'd1;
        triggered = 1; #10 triggered = 0; #10;
        check_state(2'b10, 3'd4, 1'b0, "End Screen Re-route to Fun Mode (idx 4)");

        // TEST 3: Fun Mode Manual Exit
        $display("\nStarting Test 3: Fun Mode Manual Exit");
        
        // force exit
        triggered = 1; #10 triggered = 0; #10;
        check_state(2'b00, 3'd0, 1'b0, "Manual Exit from Fun Mode Edge Case passed");

        // TEST 4: Asynchronous Reset Mid-Operation Edge Case
        $display("\nStarting Test 4: Mid-Operation Reset");
        
        //state 01
        menu_idx_in = 2'd2;
        triggered = 1; #10 triggered = 0; #10;
        
        //state 10
        triggered = 1; #10 triggered = 0; #5;
        
        //sync reset
        rst_n = 0; #15 rst_n = 1; #10;
        check_state(2'b00, 3'd0, 1'b0, " Reset cleanly returned FSM to idle");


        //test summary
        $display("   EXHAUSTIVE TEST SUMMARY");
        $display("   Passed: %d / %d", tests_passed, total_tests);
        if (tests_passed == total_tests) 
            $display("   STATUS: ALL TESTS PASSED SUCCESSFULLY");
        else 
            $display("   STATUS: SIMULATION FAILED");
        $finish;
    end

endmodule
