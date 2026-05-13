/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 18-9-2021 */

module jtcps2_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        clk_gfx, rst_gfx, hold_rst;
wire        snd_cs, qsnd_cs,
            main_ram_cs, main_vram_cs, main_oram_cs, main_rom_cs,
            rom0_cs, rom1_cs,
            vram_dma_cs;
wire        obank;  // OBJ bank
wire [15:0] oram_base;
wire [18:0] snd_addr;
wire [22:0] qsnd_addr;
wire        prog_qsnd;
wire [22:0] cps_prog_addr;
wire [ 7:0] snd_data, qsnd_data;
wire [17:1] ram_addr;
wire [21:1] main_rom_addr;
wire [15:0] main_ram_data, main_rom_data, main_dout, mmr_dout;
wire        main_rom_ok, main_ram_ok;
wire        ppu1_cs, ppu2_cs, ppu_rstn, objcfg_cs;
wire        raster;
wire [19:0] rom1_addr, rom0_addr;
wire [ 1:0] rom0_bank;
wire [31:0] rom0_data, rom1_data;
// Video RAM interface
wire [17:1] vram_dma_addr;
wire [15:0] vram_dma_data;
wire        vram_dma_ok, rom0_ok, rom1_ok, snd_ok, qsnd_ok;
wire [15:0] cpu_dout;
wire        cpu_speed;
wire        z80_rstn, star_bank;

wire        main_rnw, busreq, busack;

wire        vram_clr, vram_rfsh_en;
wire [ 8:0] hdump;
wire [ 8:0] vdump, vrender;

wire        rom0_half, rom1_half;
wire        cfg_we, key_we;
wire [ 1:0] joymode;

// CPS2 Objects
wire [12:0] gfx_oram_addr;
wire [15:0] gfx_oram_data;
wire        gfx_oram_ok, gfx_oram_clr, gfx_oram_cs;

// M68k - Sound subsystem communication
wire [ 7:0] main2qs_din;
wire [23:1] main2qs_addr;
wire        main2qs_cs, main_busakn, main_waitn;
wire [12:0] volume;

// EEPROM
wire        sclk, sdi, sdo, scs;

`ifdef JTFRAME_MEMGEN
`ifdef JTFRAME_SDRAM_LARGE
wire [22:0] cps_post_addr;
`else
wire [21:0] cps_post_addr;
`endif
wire [ 7:0] cps_post_data;
wire [ 1:0] cps_post_ba;
wire [ 1:0] cps_post_mask;
wire        cps_post_we;

always @(*) begin
    post_addr = cps_post_addr;
    post_data = cps_post_data;
    post_ba   = cps_post_ba;
    post_mask = cps_post_mask;
    post_we   = cps_post_we;
end

wire [15:0] main_ram_data_cpu = main_ram_data;
wire [15:0] main_rom_data_cpu = main_rom_data;
wire        main_ram_ok_cpu   = main_ram_ok;
wire        main_rom_ok_cpu   = main_rom_ok;
reg [31:0] dipsw_cpu;
reg [12:0] volume_cpu;
reg [ 9:0] joystick1_cpu, joystick2_cpu, joystick3_cpu, joystick4_cpu;
reg [ 3:0] cab_1p_cpu, coin_cpu;
reg [ 1:0] dial_x_cpu, dial_y_cpu, joymode_cpu;
reg        service_cpu, dip_test_cpu, dip_pause_cpu, skip_en_cpu;

always @(posedge clk48) begin
    dipsw_cpu         <= dipsw;
    volume_cpu        <= volume;
    joystick1_cpu     <= joystick1;
    joystick2_cpu     <= joystick2;
    joystick3_cpu     <= joystick3;
    joystick4_cpu     <= joystick4;
    cab_1p_cpu        <= cab_1p;
    coin_cpu          <= coin;
    dial_x_cpu        <= dial_x;
    dial_y_cpu        <= dial_y;
    joymode_cpu       <= joymode;
    service_cpu       <= service;
    dip_test_cpu      <= dip_test;
    dip_pause_cpu     <= dip_pause;
    skip_en_cpu       <= skip_en;
end
`else
wire [15:0] main_ram_data_cpu = main_ram_data;
wire [15:0] main_rom_data_cpu = main_rom_data;
wire        main_ram_ok_cpu   = main_ram_ok;
wire        main_rom_ok_cpu   = main_rom_ok;
wire [31:0] dipsw_cpu         = dipsw;
wire [12:0] volume_cpu        = volume;
wire [ 9:0] joystick1_cpu     = joystick1;
wire [ 9:0] joystick2_cpu     = joystick2;
wire [ 9:0] joystick3_cpu     = joystick3;
wire [ 9:0] joystick4_cpu     = joystick4;
wire [ 3:0] cab_1p_cpu        = cab_1p;
wire [ 3:0] coin_cpu          = coin;
wire [ 1:0] dial_x_cpu        = dial_x;
wire [ 1:0] dial_y_cpu        = dial_y;
wire [ 1:0] joymode_cpu       = joymode;
wire        service_cpu       = service;
wire        dip_test_cpu      = dip_test;
wire        dip_pause_cpu     = dip_pause;
wire        skip_en_cpu       = skip_en;
`endif

wire [ 1:0] dsn;
wire        cen16, cen16b, cen12, cen8, cen10b;
wire        cpu_cen, cpu_cenb;
wire        turbo, skip_en, video_flip;
reg         rst_game;

`include "turbo.vh"
assign skip_en  = status[7];
assign snd_vu   = 0;
assign snd_peak = 0;

`ifndef JTFRAME_MEMGEN
assign ba1_din=0, ba2_din=0, ba3_din=0,
       ba1_dsn=3, ba2_dsn=3, ba3_dsn=3;
`endif
/* verilator tracing_off */
// CPU clock enable signals come from 48MHz domain
jtframe_cen48 u_cen48(
    .clk        ( clk48         ),
    .cen16      (               ),
    .cen16b     (               ),
    .cen12      ( cen12         ),
    .cen8       ( cen8          ),
    .cen6       (               ),
    .cen4       (               ),
    .cen4_12    (               ),
    .cen3       (               ),
    .cen3q      (               ),
    .cen1p5     (               ),
    // 180 shifted signals
    .cen12b     (               ),
    .cen6b      (               ),
    .cen3b      (               ),
    .cen3qb     (               ),
    .cen1p5b    (               )
);

assign clk_gfx = clk;
assign rst_gfx = rst;

always @(posedge clk) rst_game <= hold_rst | rst48;


localparam REGSIZE=24;

// Turbo speed disables DMA
wire busreq_cpu = busreq & ~turbo;
wire busack_cpu;

`ifndef NOMAIN
jtcps2_main u_main(
    .rst        ( rst_game          ),
    .clk_rom    ( clk               ),
    .clk        ( clk48             ),
    .cpu_cen    ( cpu_cen           ),
    // Timing
    .V          ( vdump             ),
    .LVBL       ( LVBL              ),
    .LHBL       ( LHBL              ),
    .skip_en    ( skip_en_cpu       ),
    // PPU
    .ppu1_cs    ( ppu1_cs           ),
    .ppu2_cs    ( ppu2_cs           ),
    .objcfg_cs  ( objcfg_cs         ),
    .ppu_rstn   ( ppu_rstn          ),
    .mmr_dout   ( mmr_dout          ),
    .raster     ( raster            ),
    //.raster     ( 1'b0            ),
    // Keys
    .prog_din   ( prog_data[7:0]    ),
    .key_we     ( key_we            ),
    // Sound
    .z80_rstn    ( z80_rstn         ),
    .main2qs_din ( main2qs_din      ),
    .main2qs_addr( main2qs_addr     ),
    .main2qs_cs  ( main2qs_cs       ),
    .main2qs_busakn( main_busakn    ),
    .main2qs_waitn( main_waitn      ),
    .UDSWn      ( dsn[1]            ),
    .LDSWn      ( dsn[0]            ),
    .volume     ( volume_cpu        ),
    // cabinet I/O
    // Cabinet input
    .cab_1p      ( cab_1p_cpu       ),
    .coin        ( coin_cpu         ),
    .joymode     ( joymode_cpu      ),
    .joystick1   ( joystick1_cpu    ),
    .joystick2   ( joystick2_cpu    ),
    .joystick3   ( joystick3_cpu    ),
    .joystick4   ( joystick4_cpu    ),
    .service     ( service_cpu      ),
    .tilt        ( 1'b1             ),
    .dipsw       ( dipsw_cpu        ),
    .dial_x      ( dial_x_cpu       ),
    .dial_y      ( dial_y_cpu       ),
    // BUS sharing
    .busreq      ( busreq_cpu       ),
    .busack      ( busack_cpu       ),
    .RnW         ( main_rnw         ),
    // RAM/VRAM access
    .addr        ( ram_addr         ),
    .cpu_dout    ( main_dout        ),
    .ram_cs      ( main_ram_cs      ),
    .vram_cs     ( main_vram_cs     ),
    .oram_cs     ( main_oram_cs     ),
    .obank       ( obank            ),
    .oram_base   ( oram_base        ),
    .ram_data    ( main_ram_data_cpu),
    .ram_ok      ( main_ram_ok_cpu  ),
    // ROM access
    .rom_cs      ( main_rom_cs      ),
    .rom_addr    ( main_rom_addr    ),
    .rom_data    ( main_rom_data_cpu),
    .rom_ok      ( main_rom_ok_cpu  ),
    // DIP switches
    .dip_pause   ( dip_pause_cpu    ),
    .dip_test    ( dip_test_cpu     ),
    // EEPROM
    .eeprom_sclk ( sclk             ),
    .eeprom_sdi  ( sdi              ),
    .eeprom_sdo  ( sdo              ),
    .eeprom_scs  ( scs              ),
    // Debug
    .debug_bus   ( debug_bus        ),
    .st_dout     ( debug_view       )
);

assign busack = busack_cpu | turbo;

`else
    assign ram_addr      = 0;
    assign main_ram_cs   = 0;
    assign main_vram_cs  = 0;
    assign main_rom_cs   = 0;
    assign oram_base     = 0;
    assign main_oram_cs  = 0;
    assign main_rom_addr = 0;
    assign main_dout     = 0;
    assign z80_rstn      = 1;
    assign dsn           = 2'b11;
    assign main_rnw      = 1;
    assign sclk          = 0;
    assign sdi           = 0;
    assign scs           = 0;
    assign obank         = 0;
    assign busack        = 1;
    assign ppu1_cs       = 0;
    assign ppu2_cs       = 0;
    assign objcfg_cs     = 0;
    assign ppu_rstn      = 1;
    assign cpu_dout      = 0;
`endif

reg rst_video, rst_sdram;

always @(negedge clk_gfx) begin
    rst_video <= rst_gfx;
end

always @(negedge clk) begin
    rst_sdram <= rst;
end

assign dip_flip = video_flip;

jtcps1_video #(REGSIZE) u_video(
    .rst            ( rst_video     ),
    .clk            ( clk_gfx       ),
    .clk_cpu        ( clk48         ),
    .pxl2_cen       ( pxl2_cen      ),
    .pxl_cen        ( pxl_cen       ),

    .hdump          ( hdump         ),
    .vdump          ( vdump         ),
    .vrender        ( vrender       ),
    .gfx_en         ( gfx_en        ),
    .debug_bus      ( debug_bus     ),
    .cpu_speed      ( cpu_speed     ),
    .charger        (               ),
    .kabuki_en      (               ),
    .raster         ( raster        ),

    // CPU interface
    .ppu_rstn       ( ppu_rstn      ),
    .ppu1_cs        ( ppu1_cs       ),
    .ppu2_cs        ( ppu2_cs       ),
    .addr           ( ram_addr[12:1]),
    .dsn            ( dsn           ),      // data select, active low
    .cpu_dout       ( main_dout     ),
    .mmr_dout       ( mmr_dout      ),
    // BUS sharing
    .busreq         ( busreq        ),
    .busack         ( busack        ),

    // Object RAM
    .obank          ( obank         ),
    .oram_addr      ( gfx_oram_addr ),
    .oram_ok        ( gfx_oram_ok   ),
    .oram_data      ( gfx_oram_data ),
    .oram_clr       ( gfx_oram_clr  ),
    .oram_cs        ( gfx_oram_cs   ),
    .objcfg_cs      ( objcfg_cs     ),

    // Video signal
    .HS             ( HS            ),
    .VS             ( VS            ),
    .LHBL           ( LHBL          ),
    .LVBL           ( LVBL          ),
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),
    .flip           ( video_flip    ),

    // CPS-B Registers
    .cfg_we         ( cfg_we        ),
    .cfg_data       ( prog_data[7:0]),

    // Extra inputs read through the C-Board
    .cab_1p   ( cab_1p  ),
    .coin     ( coin    ),
    .joystick1      ( 10'h3ff       ),
    .joystick2      ( 10'h3ff       ),
    .joystick3      ( 10'h3ff       ),
    .joystick4      ( 10'h3ff       ),

    // Video RAM interface
    .vram_dma_addr  ( vram_dma_addr ),
    .vram_dma_data  ( vram_dma_data ),
    .vram_dma_ok    ( vram_dma_ok   ),
    .vram_dma_cs    ( vram_dma_cs   ),
    .vram_dma_clr   ( vram_clr      ),
    .vram_rfsh_en   ( vram_rfsh_en  ),

    // GFX ROM interface
    .rom1_addr      ( rom1_addr     ),
    .rom1_half      ( rom1_half     ),
    .rom1_data      ( rom1_data     ),
    .rom1_cs        ( rom1_cs       ),
    .rom1_ok        ( rom1_ok       ),
    .rom0_addr      ( rom0_addr     ),
    .rom0_bank      ( rom0_bank     ),
    .rom0_half      ( rom0_half     ),
    .rom0_data      ( rom0_data     ),
    .rom0_cs        ( rom0_cs       ),
    .rom0_ok        ( rom0_ok       ),

    .star_bank      ( star_bank     ),
    .star0_addr     (               ),
    .star0_data     ( 0             ),
    .star0_cs       (               ),
    .star0_ok       ( 1'b1          ),

    .star1_addr     (               ),
    .star1_data     ( 0             ),
    .star1_cs       (               ),
    .star1_ok       ( 1'b1          ),

    // Watched signals
    .watch_vram_cs  ( main_vram_cs  ),
    .watch          (               )
);

// Sound CPU cannot be disabled as there is
// interaction between both CPUs at power up
reg qsnd_rst;

always @(posedge clk48, posedge rst) begin
    if( rst )
        qsnd_rst  <= 1;
    else
        qsnd_rst  <= ~z80_rstn;
end

wire vol_up   = ~(coin[0] | joystick1[3]);
wire vol_down = ~(coin[0] | joystick1[2]);

`ifndef NOMAIN
jtcps15_sound u_sound(
    .rst        ( qsnd_rst          ),
    .clk48      ( clk48             ),
    .clk96      ( clk               ),
    .cen8       ( cen8              ),
    .vol_up     ( vol_up            ),
    .vol_down   ( vol_down          ),
    .volume     ( volume            ),
    // Decode keys
    .kabuki_we  ( 1'b0              ),
    .kabuki_en  ( 1'b0              ),

    // Interface with main CPU
    .main_addr  ( main2qs_addr      ),
    .main_dout  ( main_dout[7:0]    ),
    .main_din   ( main2qs_din       ),
    .main_ldswn ( dsn[0]            ),
    .main_buse_n( ~main2qs_cs       ),
    .main_busakn( main_busakn       ),
    .main_waitn ( main_waitn        ),

    // ROM
    .rom_addr   ( snd_addr          ),
    .rom_cs     ( snd_cs            ),
    .rom_data   ( snd_data          ),
    .rom_ok     ( snd_ok            ),

    // QSound sample ROM
    .qsnd_addr  ( qsnd_addr         ), // max 8 MB.
    .qsnd_cs    ( qsnd_cs           ),
    .qsnd_data  ( qsnd_data         ),
    .qsnd_ok    ( qsnd_ok           ),

    // ROM programming interface
`ifdef JTFRAME_MEMGEN
    .prog_addr  ( cps_prog_addr[12:0] ),
`else
    .prog_addr  ( prog_addr[12:0]   ),
`endif
    .prog_data  ( prog_data[7:0]    ),
    .prog_we    ( prog_qsnd         ),

    // Sound output
    .left       ( snd_left          ),
    .right      ( snd_right         ),
    .sample     ( sample            )
);
`else
    assign snd_left  = 0;
    assign snd_right = 0;
    assign sample    = 0;
    assign snd_cs    = 0;
    assign snd_addr  = 0;
    assign qsnd_cs   = 0;
    assign qsnd_addr = 0;
`endif
/* verilator tracing_on */
`ifdef JTFRAME_MEMGEN
jtcps1_memgen #(.CPS(2), .REGSIZE(REGSIZE)) u_memgen (
    .rst            ( rst_sdram       ),
    .clk            ( clk             ),
    .hold_rst       ( hold_rst        ),

    .ioctl_rom      ( ioctl_rom       ),
    .ioctl_addr     ( ioctl_addr      ),
    .ioctl_dout     ( ioctl_dout      ),
    .ioctl_wr       ( ioctl_wr        ),
    .ioctl_ram      ( ioctl_ram       ),
    .ioctl_din      ( ioctl_din       ),

    .prog_data      ( prog_data       ),
    .prog_rdy       ( prog_rdy        ),
    .post_addr      ( cps_post_addr   ),
    .post_data      ( cps_post_data   ),
    .post_ba        ( cps_post_ba     ),
    .post_mask      ( cps_post_mask   ),
    .post_we        ( cps_post_we     ),
    .cps_prog_addr  ( cps_prog_addr   ),
    .cfg_we         ( cfg_we          ),
    .prog_qsnd      ( prog_qsnd       ),
    .kabuki_we      (                 ),
    .cps2_key_we    ( key_we          ),
    .cps2_joymode   ( joymode         ),

    .sclk           ( sclk            ),
    .sdi            ( sdi             ),
    .sdo            ( sdo             ),
    .scs            ( scs             ),
    .dump_flag      (                 ),

    .main_rom_cs    ( main_rom_cs     ),
    .main_rom_ok    ( main_rom_ok     ),
    .main_rom_addr  ( main_rom_addr   ),
    .main_rom_data  ( main_rom_data   ),

    .vram_dma_cs    ( vram_dma_cs     ),
    .vram_clr       ( vram_clr        ),
    .main_ram_cs    ( main_ram_cs     ),
    .main_vram_cs   ( main_vram_cs    ),
    .main_oram_cs   ( main_oram_cs    ),
    .obank          ( obank           ),
    .gfx_oram_addr  ( gfx_oram_addr   ),
    .gfx_oram_data  ( gfx_oram_data   ),
    .gfx_oram_ok    ( gfx_oram_ok     ),
    .gfx_oram_clr   ( gfx_oram_clr    ),
    .gfx_oram_cs    ( gfx_oram_cs     ),
    .dsn            ( dsn             ),
    .main_dout      ( main_dout       ),
    .main_rnw       ( main_rnw        ),
    .main_ram_ok    ( main_ram_ok     ),
    .vram_dma_ok    ( vram_dma_ok     ),
    .main_ram_addr  ( ram_addr        ),
    .vram_dma_addr  ( vram_dma_addr   ),
    .main_ram_data  ( main_ram_data   ),
    .vram_dma_data  ( vram_dma_data   ),

    .snd_cs         ( snd_cs          ),
    .pcm_cs         ( qsnd_cs         ),
    .snd_ok         ( snd_ok          ),
    .pcm_ok         ( qsnd_ok         ),
    .snd_addr       ( snd_addr        ),
    .pcm_addr       ( qsnd_addr       ),
    .snd_data       ( snd_data        ),
    .pcm_data       ( qsnd_data       ),

    .rom0_cs        ( rom0_cs         ),
    .rom1_cs        ( rom1_cs         ),
    .rom0_ok        ( rom0_ok         ),
    .rom1_ok        ( rom1_ok         ),
    .rom0_addr      ( rom0_addr       ),
    .rom0_bank      ( rom0_bank       ),
    .rom1_addr      ( rom1_addr       ),
    .rom0_half      ( rom0_half       ),
    .rom1_half      ( rom1_half       ),
    .rom0_data      ( rom0_data       ),
    .rom1_data      ( rom1_data       ),

    .workram_cs     ( workram_cs      ),
    .workram_addr   ( workram_addr    ),
    .workram_data   ( workram_data    ),
    .workram_ok     ( workram_ok      ),
    .workram_we     ( workram_we      ),
    .workram_din    ( workram_din     ),
    .workram_dsn    ( workram_dsn     ),
    .workram_offset ( workram_offset  ),

    .vramrom_cs     ( vramrom_cs      ),
    .vramrom_addr   ( vramrom_addr    ),
    .vramrom_data   ( vramrom_data    ),
    .vramrom_ok     ( vramrom_ok      ),
    .vramrom_clr    ( vramrom_clr     ),

    .oramrom_cs     ( oramrom_cs      ),
    .oramrom_addr   ( oramrom_addr    ),
    .oramrom_data   ( oramrom_data    ),
    .oramrom_ok     ( oramrom_ok      ),
    .oramrom_clr    ( oramrom_clr     ),

    .mainrom_cs     ( mainrom_cs      ),
    .mainrom_addr   ( mainrom_addr    ),
    .mainrom_data   ( mainrom_data    ),
    .mainrom_ok     ( mainrom_ok      ),

    .sndrom_cs      ( sndrom_cs       ),
    .sndrom_addr    ( sndrom_addr     ),
    .sndrom_data    ( sndrom_data     ),
    .sndrom_ok      ( sndrom_ok       ),

    .pcmrom_cs      ( pcmrom_cs       ),
    .pcmrom_addr    ( pcmrom_addr     ),
    .pcmrom_data    ( pcmrom_data     ),
    .pcmrom_ok      ( pcmrom_ok       ),

    .objlorom_cs    ( objlorom_cs     ),
    .objlorom_addr  ( objlorom_addr   ),
    .objlorom_data  ( objlorom_data   ),
    .objlorom_ok    ( objlorom_ok     ),

    .objrom_cs      ( objrom_cs       ),
    .objrom_addr    ( objrom_addr     ),
    .objrom_data    ( objrom_data     ),
    .objrom_ok      ( objrom_ok       ),

    .scrrom_cs      ( scrrom_cs       ),
    .scrrom_addr    ( scrrom_addr     ),
    .scrrom_data    ( scrrom_data     ),
    .scrrom_ok      ( scrrom_ok       )
);
`else
jtcps1_sdram #(.CPS(2), .REGSIZE(REGSIZE)) u_sdram (
    .rst         ( rst_sdram     ),
    .clk         ( clk           ),
    .clk_gfx     ( clk_gfx       ),
    .clk_cpu     ( clk48         ),
    .LVBL        ( LVBL          ),
    .hold_rst    ( hold_rst      ),

    .ioctl_rom   ( ioctl_rom     ),
    .dwnld_busy  ( dwnld_busy    ),
    .cfg_we      ( cfg_we        ),

    // ROM LOAD
    .ioctl_addr  ( ioctl_addr    ),
    .ioctl_dout  ( ioctl_dout    ),
    .ioctl_din   ( ioctl_din     ),
    .ioctl_wr    ( ioctl_wr      ),
    .ioctl_ram   ( ioctl_ram     ),
    .prog_addr   ( prog_addr     ),
    .prog_data   ( prog_data     ),
    .prog_mask   ( prog_mask     ),
    .prog_ba     ( prog_ba       ),
    .prog_we     ( prog_we       ),
    .prog_rd     ( prog_rd       ),
    .prog_rdy    ( prog_rdy      ),
    .prog_qsnd   ( prog_qsnd     ),
    .kabuki_we   (               ), // disabled for CPS2
    .cps2_key_we ( key_we        ),
    .cps2_joymode( joymode       ),
    // joystick type


    // EEPROM
    .sclk           ( sclk          ),
    .sdi            ( sdi           ),
    .sdo            ( sdo           ),
    .scs            ( scs           ),
    .dump_flag      (               ),

    // Main CPU
    .main_rom_cs    ( main_rom_cs   ),
    .main_rom_ok    ( main_rom_ok   ),
    .main_rom_addr  ( main_rom_addr ),
    .main_rom_data  ( main_rom_data ),

    // VRAM
    .vram_clr       ( vram_clr      ),
    .vram_dma_cs    ( vram_dma_cs   ),
    .main_ram_cs    ( main_ram_cs   ),
    .main_vram_cs   ( main_vram_cs  ),
    .main_oram_cs   ( main_oram_cs  ),
    .obank          ( obank         ),
    .oram_base      ( oram_base     ),
    .vram_rfsh_en   ( vram_rfsh_en  ),

    .dsn            ( dsn           ),
    .main_dout      ( main_dout     ),
    .main_rnw       ( main_rnw      ),

    .main_ram_ok    ( main_ram_ok   ),
    .vram_dma_ok    ( vram_dma_ok   ),

    .main_ram_addr  ( ram_addr      ),
    .vram_dma_addr  ( vram_dma_addr ),

    .main_ram_data  ( main_ram_data ),
    .vram_dma_data  ( vram_dma_data ),

    .gfx_oram_addr  ( gfx_oram_addr ),
    .gfx_oram_data  ( gfx_oram_data ),
    .gfx_oram_ok    ( gfx_oram_ok   ),
    .gfx_oram_clr   ( gfx_oram_clr  ),
    .gfx_oram_cs    ( gfx_oram_cs   ),

    // Sound CPU and PCM
    .snd_cs      ( snd_cs        ),
    .pcm_cs      ( qsnd_cs       ),

    .snd_ok      ( snd_ok        ),
    .pcm_ok      ( qsnd_ok       ),

    .snd_addr    ( snd_addr      ),
    .pcm_addr    ( qsnd_addr     ),

    .snd_data    ( snd_data      ),
    .pcm_data    ( qsnd_data     ),

    // Graphics
    .rom0_cs     ( rom0_cs       ),
    .rom1_cs     ( rom1_cs       ),

    .rom0_ok     ( rom0_ok       ),
    .rom1_ok     ( rom1_ok       ),

    .rom0_addr   ( rom0_addr     ),
    .rom0_bank   ( rom0_bank     ),
    .rom1_addr   ( rom1_addr     ),

    .rom0_half   ( rom0_half     ),
    .rom1_half   ( rom1_half     ),

    .rom0_data   ( rom0_data     ),
    .rom1_data   ( rom1_data     ),

    .star_bank   ( star_bank     ),
    .star0_addr  ( 13'd0         ),
    .star0_data  (               ),
    .star0_ok    (               ),
    .star0_cs    ( 1'b0          ),

    .star1_addr  ( 13'd0         ),
    .star1_data  (               ),
    .star1_ok    (               ),
    .star1_cs    ( 1'b0          ),

    // Bank 0: allows R/W
    .ba0_addr    ( ba0_addr      ),
    .ba1_addr    ( ba1_addr      ),
    .ba2_addr    ( ba2_addr      ),
    .ba3_addr    ( ba3_addr      ),
    .ba_rd       ( ba_rd         ),
    .ba_wr       ( ba_wr         ),
    .ba_ack      ( ba_ack        ),
    .ba_dst      ( ba_dst        ),
    .ba_dok      ( ba_dok        ),
    .ba_rdy      ( ba_rdy        ),
    .ba0_din     ( ba0_din       ),
    .ba0_dsn     ( ba0_dsn       ),

    .data_read   ( data_read     )
);
`endif

endmodule
