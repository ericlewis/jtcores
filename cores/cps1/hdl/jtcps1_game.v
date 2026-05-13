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
    Date: 28-1-2020 */

module jtcps1_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        clk_gfx, rst_gfx, hold_rst;
wire        snd_cs, adpcm_cs, main_ram_cs, main_vram_cs, main_rom_cs,
            rom0_cs, rom1_cs,
            vram_dma_cs;
wire [ 1:0] joymode;
wire [15:0] snd_addr;
wire [17:0] adpcm_addr;
wire [ 7:0] snd_data, adpcm_data;
wire [17:1] ram_addr;
wire [21:1] main_rom_addr;
wire [15:0] main_ram_data, main_rom_data, main_dout, mmr_dout;
wire        main_rom_ok, main_ram_ok;
wire        ppu1_cs, ppu2_cs, ppu_rstn;
wire [19:0] rom1_addr, rom0_addr;
wire [31:0] rom0_data, rom1_data;
// Video RAM interface
wire [17:1] vram_dma_addr;
wire [15:0] vram_dma_data;
wire        vram_dma_ok, rom0_ok, rom1_ok, snd_ok, adpcm_ok;
wire [15:0] cpu_dout;
wire        cpu_speed;
wire        star_bank, dump_flag;

wire        main_rnw, busreq, busack;
wire [ 7:0] snd_latch0, snd_latch1;
wire [ 7:0] dipsw_a, dipsw_b, dipsw_c;

wire [12:0] star0_addr, star1_addr;
wire [31:0] star0_data, star1_data;
wire        star0_ok,   star1_ok,
            star0_cs,   star1_cs;

wire        vram_clr, vram_rfsh_en;
wire [ 8:0] hdump;
wire [ 8:0] vdump, vrender;

wire        rom0_half, rom1_half;
wire        cfg_we;

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
reg [ 9:0] joystick1_cpu, joystick2_cpu;
reg [ 3:0] cab_1p_cpu, coin_cpu;
reg [ 7:0] dipsw_a_cpu, dipsw_b_cpu, dipsw_c_cpu;
reg [ 1:0] dial_x_cpu, dial_y_cpu, joymode_cpu;
reg        charger_cpu, service_cpu, dip_test_cpu, dip_pause_cpu;

always @(posedge clk48) begin
    joystick1_cpu     <= joystick1;
    joystick2_cpu     <= joystick2;
    cab_1p_cpu        <= cab_1p;
    coin_cpu          <= coin;
    dipsw_a_cpu       <= dipsw_a;
    dipsw_b_cpu       <= dipsw_b;
    dipsw_c_cpu       <= dipsw_c;
    dial_x_cpu        <= dial_x;
    dial_y_cpu        <= dial_y;
    joymode_cpu       <= joymode;
    charger_cpu       <= charger;
    service_cpu       <= service;
    dip_test_cpu      <= dip_test;
    dip_pause_cpu     <= dip_pause;
end
`else
wire [15:0] main_ram_data_cpu = main_ram_data;
wire [15:0] main_rom_data_cpu = main_rom_data;
wire        main_ram_ok_cpu   = main_ram_ok;
wire        main_rom_ok_cpu   = main_rom_ok;
wire [ 9:0] joystick1_cpu     = joystick1;
wire [ 9:0] joystick2_cpu     = joystick2;
wire [ 3:0] cab_1p_cpu        = cab_1p;
wire [ 3:0] coin_cpu          = coin;
wire [ 7:0] dipsw_a_cpu       = dipsw_a;
wire [ 7:0] dipsw_b_cpu       = dipsw_b;
wire [ 7:0] dipsw_c_cpu       = dipsw_c;
wire [ 1:0] dial_x_cpu        = dial_x;
wire [ 1:0] dial_y_cpu        = dial_y;
wire [ 1:0] joymode_cpu       = joymode;
wire        charger_cpu       = charger;
wire        service_cpu       = service;
wire        dip_test_cpu      = dip_test;
wire        dip_pause_cpu     = dip_pause;
`endif

assign { dipsw_c, dipsw_b, dipsw_a } = dipsw[23:0];

wire [15:0] fave;
wire [ 1:0] dsn;
wire        cen10b;
wire        cpu_cen, cpu_cenb;
wire        charger;
wire        turbo, video_flip, filter_old;
reg         rst_game;

`include "turbo.vh"
assign snd_vu       = 0;
assign filter_old   = dipsw[24];
assign debug_view   = debug_bus[0] ? fave[7:0] : fave[15:8];
    //{ 6'd0, dump_flag, filter_old };
`ifndef JTFRAME_MEMGEN
assign ba1_din=0, ba2_din=0, ba3_din=0,
       ba1_dsn=3, ba2_dsn=3, ba3_dsn=3;
`endif

assign clk_gfx  = clk;
assign rst_gfx  = rst;

always @(posedge clk) rst_game <= hold_rst | rst48;

localparam REGSIZE=24;

// Turbo speed disables DMA
wire busreq_cpu = busreq & ~turbo;
wire busack_cpu;
assign busack = busack_cpu | turbo;
/* verilator tracing_on */
`ifndef NOMAIN
jtcps1_main u_main(
    .rst        ( rst_game          ),
    .clk        ( clk48             ),
    .cen10      ( cpu_cen           ),
    .cen10b     ( cpu_cenb          ),
    .cpu_cen    (                   ),
    .turbo      ( turbo             ),
    .joymode    ( joymode_cpu       ),
    // Timing
    .V          ( vdump             ),
    .LVBL       ( LVBL              ),
    .LHBL       ( LHBL              ),
    // PPU
    .ppu1_cs    ( ppu1_cs           ),
    .ppu2_cs    ( ppu2_cs           ),
    .ppu_rstn   ( ppu_rstn          ),
    .mmr_dout   ( mmr_dout          ),
    // Sound
    .snd_latch0 ( snd_latch0        ),
    .snd_latch1 ( snd_latch1        ),
    .UDSWn      ( dsn[1]            ),
    .LDSWn      ( dsn[0]            ),
    // cabinet I/O
    // Cabinet input
    .charger     ( charger_cpu      ),
    .cab_1p      ( cab_1p_cpu[1:0]  ),
    .coin        ( coin_cpu[1:0]    ),
    .joystick1   ( joystick1_cpu    ),
    .joystick2   ( joystick2_cpu    ),
    .dial_x      ( dial_x_cpu       ),
    .dial_y      ( dial_y_cpu       ),
    .service     ( service_cpu      ),
    .tilt        ( 1'b1             ),
    // BUS sharing
    .busreq      ( busreq_cpu       ),
    .busack      ( busack_cpu       ),
    .RnW         ( main_rnw         ),
    // RAM/VRAM access
    .addr        ( ram_addr         ),
    .cpu_dout    ( main_dout        ),
    .ram_cs      ( main_ram_cs      ),
    .vram_cs     ( main_vram_cs     ),
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
    .dipsw_a     ( dipsw_a_cpu      ),
    .dipsw_b     ( dipsw_b_cpu      ),
    .dipsw_c     ( dipsw_c_cpu      ),
    .fave        ( fave             )
);
`else
assign ram_addr      = 0;
assign main_ram_cs   = 0;
assign main_vram_cs  = 0;
assign main_rom_cs   = 0;
assign main_rom_addr = 0;
assign main_dout     = 0;
assign dsn           = 2'b11;
assign main_rnw      = 1'b1;
assign busack_cpu    = 1;
assign ppu1_cs       = 0;
assign ppu2_cs       = 0;
assign ppu_rstn      = 1;
`endif

reg rst_video;

always @(posedge clk_gfx) begin
    rst_video <= rst_gfx;
end

assign dip_flip = video_flip;
/* verilator tracing_off */
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
    .cpu_speed      ( cpu_speed     ),
    .charger        ( charger       ),
    .kabuki_en      (               ),
    .raster         (               ),
    .watch          (               ),
    .watch_vram_cs  (               ),
    .star_bank      ( star_bank     ),

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

    // EEPROM
    .sclk           ( sclk          ),
    .sdi            ( sdi           ),
    .sdo            ( sdo           ),
    .scs            ( scs           ),

    // Extra inputs read through the C-Board
    .cab_1p   ( cab_1p  ),
    .coin     ( coin    ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .joystick3      ( joystick3     ),
    .joystick4      ( joystick4     ),

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
    .rom0_bank      (               ),
    .rom0_half      ( rom0_half     ),
    .rom0_data      ( rom0_data     ),
    .rom0_cs        ( rom0_cs       ),
    .rom0_ok        ( rom0_ok       ),

    .star0_addr     ( star0_addr    ),
    .star0_data     ( star0_data    ),
    .star0_ok       ( star0_ok      ),
    .star0_cs       ( star0_cs      ),

    .star1_addr     ( star1_addr    ),
    .star1_data     ( star1_data    ),
    .star1_ok       ( star1_ok      ),
    .star1_cs       ( star1_cs      ),
    .debug_bus      ( debug_bus     )
);

`ifndef NOSOUND
`ifdef FAKE_LATCH
integer snd_frame_cnt=0;
reg [7:0] fake_latch0 = 8'h0, fake_latch1 = 8'h0;
assign snd_latch1 = fake_latch1;
assign snd_latch0 = fake_latch0;
localparam FAKE0=20;
localparam FAKE1=1000;
always @(negedge LVBL) begin
    snd_frame_cnt <= snd_frame_cnt+1;
    case( snd_frame_cnt )
        /* ffight
        FAKE0: fake_latch <= 8'hf0;
        FAKE0+5+2: fake_latch <= 8'hf7;
        FAKE0+5+4: fake_latch <= 8'hf2;
        FAKE0+5+6: fake_latch <= 8'h55;
        default: fake_latch <= 8'hff;
        */
        // Nemo
        //FAKE0: fake_latch <= 8'h2;
        //FAKE0+1: fake_latch <= 8'h2;
        //FAKE0+2: fake_latch <= 8'h0;
        // KOD
        FAKE0: fake_latch0 <= 8'h6;
        // Magic Sword
        //FAKE0: fake_latch <= 8'h1e;
        //FAKE1: fake_latch <= 8'h0;
        //FAKE1+1: fake_latch <= 8'h4;
        //FAKE1+2: fake_latch <= 8'h0;
        // SF2, Chun Li
        // FAKE0: begin
        //     fake_latch1 <= 8'h00;
        //     fake_latch0 <= 8'hf0;
        // end

        // FAKE0+10: begin
        //     fake_latch1 <= 8'h00;
        //     fake_latch0 <= 8'hff;
        // end
        // FAKE0+11: begin
        //     fake_latch1 <= 8'h00;
        //     fake_latch0 <= 8'hf7;
        // end
        // FAKE0+12: begin
        //     fake_latch1 <= 8'h00;
        //     fake_latch0 <= 8'hff;
        // end
        // FAKE0+13: begin
        //     fake_latch1 <= 8'h00;
        //     fake_latch0 <= 8'h06;
        // end
        // FAKE0+14: begin
        //     fake_latch1 <= 8'h00;
        //     fake_latch0 <= 8'hff;
        // end

        //default: fake_latch <= 8'hff;
    endcase
end
`endif

reg [3:0] rst_snd;
always @(posedge clk) begin
    rst_snd <= { rst_snd[2:0], rst_game };
end
/* verilator tracing_off */
jtcps1_sound u_sound(
    .rst            ( rst_snd[3]    ),
    .clk            ( clk48         ),

    .filter_old     ( filter_old    ),
    .dip_fxlevel    ( dip_fxlevel   ),
    // Interface with main CPU
    .snd_latch0     ( snd_latch0    ),
    .snd_latch1     ( snd_latch1    ),

    // ROM
    .rom_addr       ( snd_addr      ),
    .rom_cs         ( snd_cs        ),
    .rom_data       ( snd_data      ),
    .rom_ok         ( snd_ok        ),

    // ADPCM ROM
    .adpcm_addr     ( adpcm_addr    ),
    .adpcm_cs       ( adpcm_cs      ),
    .adpcm_data     ( adpcm_data    ),
    .adpcm_ok       ( adpcm_ok      ),

    // Sound output
    .left           ( snd_left      ),
    .right          ( snd_right     ),
    .sample         ( sample        ),
    .peak           ( snd_peak      ),
    .debug_bus      ( debug_bus     )
);
`else
assign snd_addr   = 0;
assign snd_cs     = 0;
assign snd_left   = 0;
assign snd_right  = 0;
assign snd_peak   = 0;
assign adpcm_addr = 0;
assign adpcm_cs   = 0;
assign sample     = 0;
`endif

reg rst_sdram;
always @(posedge clk) rst_sdram <= rst;

`ifdef JTFRAME_MEMGEN
jtcps1_memgen #(.CPS(1), .REGSIZE(REGSIZE)) u_memgen (
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
    .cps_prog_addr  (                 ),
    .cfg_we         ( cfg_we          ),
    .prog_qsnd      (                 ),
    .kabuki_we      (                 ),
    .cps2_key_we    (                 ),
    .cps2_joymode   ( joymode         ),

    .sclk           ( sclk            ),
    .sdi            ( sdi             ),
    .sdo            ( sdo             ),
    .scs            ( scs             ),
    .dump_flag      ( dump_flag       ),

    .main_rom_cs    ( main_rom_cs     ),
    .main_rom_ok    ( main_rom_ok     ),
    .main_rom_addr  ( main_rom_addr   ),
    .main_rom_data  ( main_rom_data   ),

    .vram_dma_cs    ( vram_dma_cs     ),
    .vram_clr       ( vram_clr        ),
    .main_ram_cs    ( main_ram_cs     ),
    .main_vram_cs   ( main_vram_cs    ),
    .main_oram_cs   ( 1'b0            ),
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
    .pcm_cs         ( adpcm_cs        ),
    .snd_ok         ( snd_ok          ),
    .pcm_ok         ( adpcm_ok        ),
    .snd_addr       ( snd_addr        ),
    .pcm_addr       ( adpcm_addr      ),
    .snd_data       ( snd_data        ),
    .pcm_data       ( adpcm_data      ),

    .rom0_cs        ( rom0_cs         ),
    .rom1_cs        ( rom1_cs         ),
    .rom0_ok        ( rom0_ok         ),
    .rom1_ok        ( rom1_ok         ),
    .rom0_addr      ( rom0_addr       ),
    .rom0_bank      ( 2'd0            ),
    .rom1_addr      ( rom1_addr       ),
    .rom0_half      ( rom0_half       ),
    .rom1_half      ( rom1_half       ),
    .rom0_data      ( rom0_data       ),
    .rom1_data      ( rom1_data       ),

    .star_bank      ( star_bank       ),
    .star0_addr     ( star0_addr      ),
    .star0_data     ( star0_data      ),
    .star0_ok       ( star0_ok        ),
    .star0_cs       ( star0_cs        ),
    .star1_addr     ( star1_addr      ),
    .star1_data     ( star1_data      ),
    .star1_ok       ( star1_ok        ),
    .star1_cs       ( star1_cs        ),

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

    .objrom_cs      ( objrom_cs       ),
    .objrom_addr    ( objrom_addr     ),
    .objrom_data    ( objrom_data     ),
    .objrom_ok      ( objrom_ok       ),

    .scrrom_cs      ( scrrom_cs       ),
    .scrrom_addr    ( scrrom_addr     ),
    .scrrom_data    ( scrrom_data     ),
    .scrrom_ok      ( scrrom_ok       ),

    .star0rom_cs    ( star0rom_cs     ),
    .star0rom_addr  ( star0rom_addr   ),
    .star0rom_data  ( star0rom_data   ),
    .star0rom_ok    ( star0rom_ok     ),
    .star1rom_cs    ( star1rom_cs     ),
    .star1rom_addr  ( star1rom_addr   ),
    .star1rom_data  ( star1rom_data   ),
    .star1rom_ok    ( star1rom_ok     )
);
`else
wire nc0, nc1, nc2, nc3;
/* verilator tracing_on */
jtcps1_sdram #(.REGSIZE(REGSIZE)) u_sdram (
    .rst         ( rst_sdram     ),
    .clk         ( clk           ),
    .clk_gfx     ( clk_gfx       ),
    .clk_cpu     ( clk48         ),
    .LVBL        ( LVBL          ),
    .star_bank   ( star_bank     ),
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
    /*verilator lint_off width*/
    .prog_addr   ( prog_addr     ),
    /*verilator lint_on width*/
    .prog_data   ( prog_data     ),
    .prog_mask   ( prog_mask     ),
    .prog_ba     ( prog_ba       ),
    .prog_we     ( prog_we       ),
    .prog_rd     ( prog_rd       ),
    .prog_rdy    ( prog_rdy      ),
    // Unused QSound ports
    .prog_qsnd   (               ),
    .kabuki_we   (               ),
    // Unused CPS2 ports
    .cps2_key_we (               ),
    .cps2_joymode( joymode       ),
    .rom0_bank   (               ),

    // EEPROM
    .sclk           ( sclk          ),
    .sdi            ( sdi           ),
    .sdo            ( sdo           ),
    .scs            ( scs           ),

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
    .vram_rfsh_en   ( vram_rfsh_en  ),

    // Object RAM (CPS2)
    .main_oram_cs   ( 1'b0          ),

    .dsn            ( dsn           ),
    .main_dout      ( main_dout     ),
    .main_rnw       ( main_rnw      ),

    .main_ram_ok    ( main_ram_ok   ),
    .vram_dma_ok    ( vram_dma_ok   ),

    .main_ram_addr  ( ram_addr      ),
    .vram_dma_addr  ( vram_dma_addr ),

    .main_ram_data  ( main_ram_data ),
    .vram_dma_data  ( vram_dma_data ),

    // Sound CPU and PCM
    .snd_cs      ( snd_cs        ),
    .pcm_cs      ( adpcm_cs      ),

    .snd_ok      ( snd_ok        ),
    .pcm_ok      ( adpcm_ok      ),

    .snd_addr    ( snd_addr      ),
    .pcm_addr    ( adpcm_addr    ),

    .snd_data    ( snd_data      ),
    .pcm_data    ( adpcm_data    ),

    // Graphics
    .rom0_cs     ( rom0_cs       ),
    .rom1_cs     ( rom1_cs       ),

    .rom0_ok     ( rom0_ok       ),
    .rom1_ok     ( rom1_ok       ),

    .rom0_addr   ( rom0_addr     ),
    .rom1_addr   ( rom1_addr     ),

    .rom0_half   ( rom0_half     ),
    .rom1_half   ( rom1_half     ),

    .rom0_data   ( rom0_data     ),
    .rom1_data   ( rom1_data     ),

    .star0_addr  ( star0_addr    ),
    .star0_data  ( star0_data    ),
    .star0_ok    ( star0_ok      ),
    .star0_cs    ( star0_cs      ),

    .star1_addr  ( star1_addr    ),
    .star1_data  ( star1_data    ),
    .star1_ok    ( star1_ok      ),
    .star1_cs    ( star1_cs      ),

    // Bank 0: allows R/W
    /*verilator lint_off width*/
    .ba0_addr    ({nc0,ba0_addr} ),
    .ba1_addr    ({nc1,ba1_addr} ),
    .ba2_addr    ({nc2,ba2_addr} ),
    .ba3_addr    ({nc3,ba3_addr} ),
    /*verilator lint_on width*/
    .ba_rd       ( ba_rd         ),
    .ba_wr       ( ba_wr         ),
    .ba_ack      ( ba_ack        ),
    .ba_dst      ( ba_dst        ),
    .ba_dok      ( ba_dok        ),
    .ba_rdy      ( ba_rdy        ),
    .ba0_din     ( ba0_din       ),
    .ba0_dsn     ( ba0_dsn       ),

    .data_read   ( data_read     ),
    .dump_flag   ( dump_flag     )
);
`endif

endmodule
