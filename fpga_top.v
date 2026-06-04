`timescale 1ns / 1ps

// ====================================================================================================
// Module Summary: fpga_top
// ----------------------------------------------------------------------------------------------------
// This is the top-level hardware wrapper for an FPGA-based SD Card File Reader system.
// Its primary roles are:
// 1. Hardware Pin Mapping: Connects physical FPGA pins (SD Card, LEDs) to internal logic.
// 2. Power Management: Forces the SD Card power-on signal (active low).
// 3. SD Interface Config: Sets the SD card to 1-bit SPI/SD mode by pulling unused data lines (D1-D3) HIGH.
// 4. File Reader Instantiation: Orchestrates the 'sd_file_reader' module to search for a specific 
//    file on a FAT-formatted SD card and stream its contents byte-by-byte.
// 5. Diagnostics: Maps internal state signals (file found, card status, etc.) to physical LEDs.
// ====================================================================================================

module fpga_top (
    input  wire           clk,              // Main system clock
    input  wire           resetn,           // Active-low global reset
    output wire           sdcard_pwr_n,     // SD Card Power Enable (Active Low)
    output wire           sdclk,            // Serial Clock for SD Card
    inout  wire           sdcmd,            // Command/Response line (Bidirectional)
    input  wire           sddat0,           // Data Line 0 (MISO in SPI mode)
    output wire           sddat1, sddat2, sddat3, // Data Lines 1-3 (Pulled high for 1-bit mode)
    output wire [15:0]    ledout,           // 16-bit LED output for debugging/status
    
    // External interface for streaming file data
    output wire           outen,            // High when 'outbyte' contains valid data
    output wire [7:0]     outbyte,          // The current byte being read from the file
    output wire [2:0]     filesystem_state  // Internal FSM state of the FAT reader
);

    // --- Hardwired Logic ---
    assign ledout[15:9] = 0;                 // Turn off unused upper LEDs
    assign sdcard_pwr_n = 1'b0;              // Drive low to provide power to the SD Card slot
    assign {sddat1, sddat2, sddat3} = 3'b111; // Pull unused data lines high (required for SD protocol)

    //----------------------------------------------------------------------------------------------------
    // Submodule: sd_file_reader
    //----------------------------------------------------------------------------------------------------
    // This module handles the complexity of the SPI protocol and the FAT32/FAT16 file system.
    //----------------------------------------------------------------------------------------------------
    sd_file_reader #(
        .FILE_NAME_LEN    ( 11              ), // FAT standard requires exactly 11 characters for name+ext
        .FILE_NAME        ( "TXT       A"   ), // "A.TXT" formatted for directory entry (NAME[8] + EXT[3])
        .CLK_DIV          ( 3'd7            )  // Clock divider: 7 ensures a slow, stable SPI clock (approx 400kHz-1MHz)
    ) u_sd_file_reader (
        // System Connections
        .rstn             ( resetn          ), // Connect global reset
        .clk              ( clk             ), // Connect system clock
        
        // Physical SD Card Pins
        .sdclk            ( sdclk           ), // Output serial clock to card
        .sdcmd            ( sdcmd           ), // Command line
        .sddat0           ( sddat0          ), // Input data line from card
        
        // Status Mapping to LEDs
        .card_stat        ( ledout[3:0]     ), // Bits 0-3: SD initialization status
        .card_type        ( ledout[5:4]     ), // Bits 4-5: Detected card type (SDHC, SDv2, etc)
        .filesystem_type  ( ledout[7:6]     ), // Bits 6-7: Detected FAT type (FAT16 vs FAT32)
        .file_found       ( ledout[8]       ), // Bit 8: High if the specified filename exists
        
        // Data Output Stream
        .outen            ( outen           ), // Connect to top-level output enable
        .outbyte          ( outbyte         ), // Connect to top-level data byte
        .filesystem_state ( filesystem_state)  // Connect to top-level FSM monitor
    );

endmodule
