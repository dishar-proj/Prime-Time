//The ram_interface acts as a bridge between a CPU (or system logic) and a DDR2 SDRAM memory controller and simplifies memory access by providing a high-level handshaking interface (read/write flags) 
//while passing the complex physical signaling—such as row/column addressing and differential 
//strobes—to a dedicated Memory Interface Generator (MIG) core.
module ram_interface(
    // Clock and Reset Signals
    input wire clk_mem,      // High-speed memory clock
    input wire clk_cpu,      // CPU/System side clock
    input resetn,            // Active-low system reset
    
    // User Logic Interface
    input lineflag,          // Signal to indicate specific memory operations (e.g., cache line)
    input [27:0] mem_addr_in,        // Physical address for memory access
    input [63:0] mem_d_to_ram_in,    // Data to be written to RAM
    output [63:0] mem_d_from_ram_out,// Data read back from RAM
    output ramflag,          // Status flag from the RAM controller
    
    // Control Handshaking
    input rflag,             // Read request pulse
    input wflag,             // Write request pulse
    output readfini,         // Read operation finished acknowledgment
    output writefini,        // Write operation finished acknowledgment
    output wire [15:0] led,  // Diagnostic LEDs for hardware debugging
    
    // Physical DDR2 External Pins (Connects to PCB RAM chip)
    inout[15:0] ddr2_dq,     // Data bus
    inout[1:0] ddr2_dqs_n,   // Differential data strobes (negative)
    inout[1:0] ddr2_dqs_p,   // Differential data strobes (positive)
    output[12:0] ddr2_addr,  // Address bus
    output[2:0] ddr2_ba,     // Bank address
    output ddr2_ras_n,       // Row Address Strobe
    output ddr2_cas_n,       // Column Address Strobe
    output ddr2_we_n,        // Write Enable
    output ddr2_ck_p,        // Differential clock to RAM (positive)
    output ddr2_ck_n,        // Differential clock to RAM (negative)
    output ddr2_cke,         // Clock Enable
    output ddr2_cs_n,        // Chip Select
    output[1:0] ddr2_dm,     // Data mask bits
    output ddr2_odt          // On-Die Termination control
);

    // Internal wiring for handshaking signals
    wire writingstart;
    wire readingstart;
    wire rflagf;
    wire wflagf;
    
    // Logic Mapping: Direct pass-through of control flags
    assign writingstart = wflag;
    assign readingstart = rflag;
    assign readfini = rflagf;
    assign writefini = wflagf;
    
    // Instantiate the Memory Interface Generator (MIG) top-level module
    // This connects the user logic to the actual DDR2 hardware controller
    mig_example_top u_mig_example_top (
        .clk_mem(clk_mem),
        .clk_cpu(clk_cpu),
        .CPU_RESETN(resetn),
        .lineflag(lineflag),
        .mem_addr_in(mem_addr_in),
        .mem_d_to_ram_in(mem_d_to_ram_in),
        .mem_d_from_ram(mem_d_from_ram_out),
        .ramflag(ramflag),
        .rflag(rflag),
        .wflag(wflag),
        .writingstart(writingstart),
        .readingstart(readingstart),
        .rflagf(rflagf),
        .wflagf(wflagf),
        .led(led),
        
        // Physical DDR2 pin connections
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt)
    );

endmodule
