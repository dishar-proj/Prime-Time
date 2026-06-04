`timescale 1ns / 1ps

module top_v(
    input  wire         clk100mhz,
    input  wire         resetn,
    input  wire         btnc,
    input  wire         btnu,
    input  wire         btnd,
    input  wire         btnl,
    input  wire         btnr,

    output wire [7:0]   anode,
    output wire [7:0]   cathode,

    output wire         sdcard_pwr_n,
    output wire         sdclk,
    inout               sdcmd,
    input  wire         sddat0,
    output wire         sddat1, sddat2, sddat3,
    output wire [15:0]  led,

    inout[15:0]         ddr2_dq,
    inout[1:0]          ddr2_dqs_n,
    inout[1:0]          ddr2_dqs_p,
    output[12:0]        ddr2_addr,
    output[2:0]         ddr2_ba,
    output              ddr2_ras_n,
    output              ddr2_cas_n,
    output              ddr2_we_n,
    output              ddr2_ck_p,
    output              ddr2_ck_n,
    output              ddr2_cke,
    output              ddr2_cs_n,
    output[1:0]         ddr2_dm,
    output              ddr2_odt,

    input  wire [2:0]   JA,
    output wire [3:0]   RED,
    output wire [3:0]   GRN,
    output wire [3:0]   BLU,
    output wire         HSYNC,
    output wire         VSYNC
);

    wire clk_mem, clk_cpu, clk_sd, clk_vga;
    wire pll_locked;

    pll pll1(
        .resetn(resetn),
        .locked(pll_locked),
        .clk_in(clk100mhz),
        .clk_mem(clk_mem),
        .clk_cpu(clk_cpu),
        .clk_sd(clk_sd),
        .clk_vga(clk_vga)
    );

    wire [31:0] encoder_count_wire;
    wire [1:0]  menu_idx_wire;
    wire [1:0]  endmode_idx_wire;
    wire        triggered_wire;
    wire [2:0]  speed_lvl_wire;
    wire        speed_pulse_wire;

    wire [1:0]  screen_state_wire;
    wire [2:0]  saved_menu_idx_wire;
    wire [2:0]  active_calc_mode_wire; 
    wire        menu_select_wire;
    wire        start_engine_wire;
    wire        latched_prime_wire;

    // Output wires from UI Controller
    wire        start_prime_wire;
    wire        input_screen_active_wire;

    wire        screen_is_active;

    wire        engine_done;
    wire [31:0] total_time_ms;
    wire [31:0] total_primes;
    wire        prime_valid;
    wire [31:0] current_num;
    wire        current_is_prime;

    wire [31:0] primes_total_boundary;

    wire [31:0] sd_data;
    wire        sd_run, sd_finish, sd_lineflag;
    wire [31:0] cpu_data;
    wire        cpu_lineflag_pulse;

    wire [31:0] test_log_ram_wire;
    wire [31:0] test_log_sd_wire;
    wire        test_log_pulse_wire;

    wire [27:0] mem_addr_in;
    wire [63:0] mem_d_to_ram_in, mem_d_from_ram_out;
    wire        ramflag, rflag, wflag, readfini, writefini;
    wire [15:0] ram_led;

    wire        test_done;
    wire        test_passed;
    wire [31:0] primes_checked;
    wire [31:0] fail_ram_val;
    wire [31:0] fail_sd_val;
    wire [27:0] test_ram_addr;
    wire        test_ram_rflag;

    wire        is_testing_mode;
    wire [27:0] final_ram_addr;
    wire        final_ram_rflag;
    wire        combined_engine_done;
    wire        sd_sys_resetn;
    wire        sd_cpu_resetn;

    system_router router_inst (
        .clk_sd(clk_sd),
        .resetn(resetn),
        .screen_state(screen_state_wire),
        .saved_menu_idx(saved_menu_idx_wire),
        .test_ram_addr(test_ram_addr),
        .test_ram_rflag(test_ram_rflag),
        .mem_addr_in(mem_addr_in),
        .rflag(rflag),
        .engine_done(engine_done),
        .test_done(test_done),
        .screen_is_active(screen_is_active),
        .is_testing_mode(is_testing_mode),
        .final_ram_addr(final_ram_addr),
        .final_ram_rflag(final_ram_rflag),
        .combined_engine_done(combined_engine_done),
        .sd_sys_resetn(sd_sys_resetn),
        .sd_cpu_resetn(sd_cpu_resetn)
    );

    ui_controller ui_ctrl (
        .clk(clk_cpu),
        .rst_n(resetn),
        .triggered(triggered_wire),
        .menu_idx_in(menu_idx_wire),
        .endmode_idx_in(endmode_idx_wire),
        .engine_done(combined_engine_done),
        .prime_valid(prime_valid),
        .is_prime_in(current_is_prime),
        .screen_state(screen_state_wire),
        .saved_idx(saved_menu_idx_wire),
        .menu_select(menu_select_wire),
        .start_engine(start_engine_wire),
        .is_prime_saved(latched_prime_wire),
        .last_calc_mode(active_calc_mode_wire),
        .start_prime(start_prime_wire),                   // Connected output
        .input_screen_active(input_screen_active_wire)    // Connected output
    );

    rotary_encoder my_encoder (
        .clk(clk_cpu),
        .rst_p(~resetn),
        .enc_clk(JA[0]),
        .enc_dt(JA[1]),
        .enc_sw(JA[2]),
        .speed_btn(btnc),
        .menu_select(menu_select_wire),
        .screen_active(screen_is_active),
        .input_screen_active(input_screen_active_wire), // Connected input
        .count(encoder_count_wire),
        .menu_idx(menu_idx_wire),
        .endmode_idx(endmode_idx_wire),
        .triggered(triggered_wire),
        .speed_lvl(speed_lvl_wire),
        .speed_pulse(speed_pulse_wire)
    );

    Module_7SD my_display (
        .clk(clk_cpu),
        .rst(~resetn),
        .count(encoder_count_wire),
        .speed_lvl(speed_lvl_wire),
        .speed_pulse(speed_pulse_wire),
        .seg(cathode),
        .an(anode)
    );

    sd_interface sd_interface1(
        .clk_sd(clk_sd), .resetn(sd_sys_resetn), .sdcard_pwr_n(sdcard_pwr_n),
        .sdclk(sdclk), .sdcmd(sdcmd), .sddat0(sddat0), .sddat1(sddat1),
        .sddat2(sddat2), .sddat3(sddat3), .led(led), .data(sd_data),
        .sd_run(sd_run), .sd_finish(sd_finish), .lineflag(sd_lineflag)
    );

    sd_sync sd_sync1(
        .clk_cpu(clk_cpu), .resetn(sd_cpu_resetn), .sd_data(sd_data),
        .sd_lineflag(sd_lineflag), .cpu_lineflag_pulse(cpu_lineflag_pulse),
        .cpu_data(cpu_data)
    );

    ram_interface ram_interface1(
        .clk_mem(clk_mem), .clk_cpu(clk_cpu), .resetn(resetn),
        .lineflag(1'b0), .mem_addr_in(final_ram_addr),
        .mem_d_to_ram_in(mem_d_to_ram_in), .mem_d_from_ram_out(mem_d_from_ram_out),
        .ramflag(1'b0), .rflag(final_ram_rflag), .wflag(wflag),
        .readfini(readfini), .writefini(writefini), .led(ram_led),
        .ddr2_dq(ddr2_dq), .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_ras_n(ddr2_ras_n),
        .ddr2_cas_n(ddr2_cas_n), .ddr2_we_n(ddr2_we_n), .ddr2_ck_p(ddr2_ck_p),
        .ddr2_ck_n(ddr2_ck_n), .ddr2_cke(ddr2_cke), .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt)
    );

    memory_manager memory_manager1(
        .clk(clk_cpu), .resetn(resetn),
        .start_engine(start_prime_wire), // Connected input
        .prime_valid(prime_valid),
        .current_is_prime(current_is_prime), .current_num(current_num),
        .writefini(writefini), .mem_addr_out(mem_addr_in),
        .mem_data_out(mem_d_to_ram_in), .wflag(wflag),
        .primes_total(primes_total_boundary) 
    );

    test_mode_wrapper test_wrapper (
        .clk(clk_cpu),
        .rst_n(resetn),
        .is_testing_mode(is_testing_mode),
        .active_calc_mode(active_calc_mode_wire),
        .primes_total(primes_total_boundary),
        .sd_data(cpu_data),
        .sd_lineflag(cpu_lineflag_pulse),
        .ram_read_data(mem_d_from_ram_out[31:0]),
        .ram_readfini(readfini),
        
        .ram_addr(test_ram_addr),
        .ram_rflag(test_ram_rflag),
        .test_done(test_done),
        .test_passed(test_passed),
        .lines_checked(primes_checked),
        .fail_ram_val(fail_ram_val),
        .fail_sd_val(fail_sd_val),
        .log_ram_val(test_log_ram_wire),
        .log_sd_val(test_log_sd_wire),
        .log_pulse(test_log_pulse_wire)
    );

    prime_mode prime_mode1 (
        .clk(clk_cpu), .rst_n(resetn),
        .start_engine(start_prime_wire), // Connected input
        .mode_select(saved_menu_idx_wire), .user_val(encoder_count_wire),
        .engine_done(engine_done), .total_time_ms(total_time_ms),
        .total_primes(total_primes), .prime_valid(prime_valid),
        .current_num(current_num), .current_is_prime(current_is_prime)
    );

    VGA_controller VGA_controller1(
        .clk_vga(clk_vga), .clk_cpu(clk_cpu), .resetn(resetn),
        .menu_idx(menu_idx_wire), .screen_state(screen_state_wire),
        .saved_idx(saved_menu_idx_wire), .endmode_idx(endmode_idx_wire),
        .count(encoder_count_wire), .speed_lvl(speed_lvl_wire),
        .is_prime(latched_prime_wire), .elapsed_sec(total_time_ms),
        .total_primes(total_primes), .prime_valid(prime_valid),
        .current_num(current_num), .current_is_prime(current_is_prime),

        .test_log_ram(test_log_ram_wire),
        .test_log_sd(test_log_sd_wire),
        .test_log_pulse(test_log_pulse_wire),

        .test_passed(test_passed), .primes_checked(primes_checked),
        .fail_ram_val(fail_ram_val), .fail_sd_val(fail_sd_val),

        .RED(RED), .GRN(GRN), .BLU(BLU), .HSYNC(HSYNC), .VSYNC(VSYNC)
    );
endmodule
