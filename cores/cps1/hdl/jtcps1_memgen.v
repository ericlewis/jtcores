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
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module jtcps1_memgen #( parameter
    CPS     = 1,
    REGSIZE = 24,
    Z80_AW  = CPS==1 ? 16 : 19,
    PCM_AW  = CPS==1 ? 18 : 23
)(
    input             rst,
    input             clk,
    output            hold_rst,

    input             ioctl_rom,
    input      [25:0] ioctl_addr,
    input      [ 7:0] ioctl_dout,
    input             ioctl_wr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,

    input      [ 7:0] prog_data,
    input             prog_rdy,
`ifdef JTFRAME_SDRAM_LARGE
    output reg [22:0] post_addr,
`else
    output reg [21:0] post_addr,
`endif
    output reg [ 7:0] post_data,
    output reg [ 1:0] post_ba,
    output reg [ 1:0] post_mask,
    output reg        post_we,
    output     [22:0] cps_prog_addr,
    output            cfg_we,
    output            prog_qsnd,
    output            kabuki_we,
    output            cps2_key_we,
    output     [ 1:0] cps2_joymode,

    input             sclk,
    input             sdi,
    output            sdo,
    input             scs,
    output            dump_flag,

    input             main_rom_cs,
    output            main_rom_ok,
    input      [20:0] main_rom_addr,
    output     [15:0] main_rom_data,

    input             vram_dma_cs,
    input             vram_clr,
    input             main_ram_cs,
    input             main_vram_cs,
    input             main_oram_cs,
`ifdef CPS2
    input             obank,
    input      [12:0] gfx_oram_addr,
    output     [15:0] gfx_oram_data,
    output            gfx_oram_ok,
    input             gfx_oram_clr,
    input             gfx_oram_cs,
`endif
    input      [ 1:0] dsn,
    input      [15:0] main_dout,
    input             main_rnw,
    output            main_ram_ok,
    output            vram_dma_ok,
    input      [17:1] main_ram_addr,
    input      [17:1] vram_dma_addr,
    output     [15:0] main_ram_data,
    output     [15:0] vram_dma_data,

    input             snd_cs,
    input             pcm_cs,
    output            snd_ok,
    output            pcm_ok,
    input  [Z80_AW-1:0] snd_addr,
    input  [PCM_AW-1:0] pcm_addr,
    output     [ 7:0] snd_data,
    output     [ 7:0] pcm_data,

    input             rom0_cs,
    input             rom1_cs,
    output reg        rom0_ok,
    output            rom1_ok,
    input      [19:0] rom0_addr,
    input      [ 1:0] rom0_bank,
    input      [19:0] rom1_addr,
    input             rom0_half,
    input             rom1_half,
    output reg [31:0] rom0_data,
    output     [31:0] rom1_data,

`ifdef CPS1
    input             star_bank,
    input      [12:0] star0_addr,
    output     [31:0] star0_data,
    output            star0_ok,
    input             star0_cs,
    input      [12:0] star1_addr,
    output     [31:0] star1_data,
    output            star1_ok,
    input             star1_cs,
`endif

    output            workram_cs,
    output     [20:1] workram_addr,
    input      [15:0] workram_data,
    input             workram_ok,
    output            workram_we,
    output     [15:0] workram_din,
    output     [ 1:0] workram_dsn,
    output     [22:0] workram_offset,

    output            vramrom_cs,
    output     [17:1] vramrom_addr,
    input      [15:0] vramrom_data,
    input             vramrom_ok,
    output            vramrom_clr,

`ifdef CPS2
    output            oramrom_cs,
    output     [13:1] oramrom_addr,
    input      [15:0] oramrom_data,
    input             oramrom_ok,
    output            oramrom_clr,
`endif

    output            mainrom_cs,
    output     [21:1] mainrom_addr,
    input      [15:0] mainrom_data,
    input             mainrom_ok,

    output            sndrom_cs,
    output [Z80_AW-1:0] sndrom_addr,
    input      [ 7:0] sndrom_data,
    input             sndrom_ok,

    output            pcmrom_cs,
    output [PCM_AW-1:0] pcmrom_addr,
    input      [ 7:0] pcmrom_data,
    input             pcmrom_ok,

`ifdef CPS2
    output            objlorom_cs,
    output     [23:2] objlorom_addr,
    input      [31:0] objlorom_data,
    input             objlorom_ok,
`endif

    output            objrom_cs,
    output     [23:2] objrom_addr,
    input      [31:0] objrom_data,
    input             objrom_ok,

    output            scrrom_cs,
    output     [22:2] scrrom_addr,
    input      [31:0] scrrom_data,
    input             scrrom_ok

`ifdef CPS1
    ,
    output            star0rom_cs,
    output     [22:2] star0rom_addr,
    input      [31:0] star0rom_data,
    input             star0rom_ok,
    output            star1rom_cs,
    output     [22:2] star1rom_addr,
    input      [31:0] star1rom_data,
    input             star1rom_ok
`endif
);

localparam [22:0] ZERO_OFFSET = 23'h0,
                  PCM_OFFSET  = ZERO_OFFSET,
                  VRAM_OFFSET = 23'h20_0000,
                  ORAM_OFFSET = 23'h28_0000,
                  WRAM_OFFSET = 23'h30_0000,
                  SND_OFFSET  = 23'h38_0000,
                  ROM_OFFSET  = ZERO_OFFSET;

`ifdef CPS2
localparam [22:0] SCR_OFFSET = 23'h00_0000;
`else
localparam [22:0] SCR_OFFSET = ZERO_OFFSET;
`endif

`ifdef CPS15
localparam EEPROM_AW=7, EEPROM_DW=8;
`else
localparam EEPROM_AW=6, EEPROM_DW=16;
`endif

wire [22:0] cps_prog_addr_w;
wire [15:0] cps_prog_data;
wire [ 1:0] cps_prog_mask, cps_prog_ba;
wire        cps_prog_we;
wire        dump_we;
reg  [20:1] main_addr_x;
reg  [25:0] prom_ioctl_addr;
reg  [ 7:0] prom_ioctl_dout;
reg         prom_ioctl_wr;
reg         prom_ioctl_ram;
reg         prom_ioctl_rom;
wire [21:0] gfx0_addr, gfx1_addr;
wire [ 1:0] objgfx_cs;
wire [22:0] cps2_gfx0;

assign hold_rst       = 1'b0;
assign dump_we        = ioctl_wr & ioctl_ram;
assign cps_prog_addr  = cps_prog_addr_w;

assign gfx0_addr = { rom0_addr, rom0_half, 1'b0 };
assign gfx1_addr = { rom1_addr, rom1_half, 1'b0 };

always @(*) begin
`ifdef JTFRAME_SDRAM_LARGE
    post_addr = cps_prog_addr_w;
`else
    post_addr = cps_prog_addr_w[21:0];
`endif
    post_data = cps_prog_data[7:0];
    post_ba   = cps_prog_ba;
    post_mask = cps_prog_mask;
    post_we   = cps_prog_we;
end

always @(posedge clk) begin
    prom_ioctl_addr <= ioctl_addr;
    prom_ioctl_dout <= ioctl_dout;
    prom_ioctl_wr   <= ioctl_wr;
    prom_ioctl_ram  <= ioctl_ram;
    prom_ioctl_rom  <= ioctl_rom;
end

jtcps1_prom_we #(
    .CPS        ( CPS        ),
    .REGSIZE    ( REGSIZE    ),
    .CPU_OFFSET ( ROM_OFFSET ),
    .PCM_OFFSET ( PCM_OFFSET ),
    .SND_OFFSET ( SND_OFFSET )
) u_prom_we(
    .clk            ( clk             ),
    .ioctl_rom      ( prom_ioctl_rom  ),
    .ioctl_addr     ( prom_ioctl_addr ),
    .ioctl_dout     ( prom_ioctl_dout ),
    .ioctl_wr       ( prom_ioctl_wr   ),
    .ioctl_ram      ( prom_ioctl_ram  ),
    .prog_addr      ( cps_prog_addr_w ),
    .prog_data      ( cps_prog_data   ),
    .prog_mask      ( cps_prog_mask   ),
    .prog_ba        ( cps_prog_ba     ),
    .prog_we        ( cps_prog_we     ),
    .prom_we        ( prog_qsnd       ),
    .prog_rdy       ( prog_rdy        ),
    .cfg_we         ( cfg_we          ),
    .dwnld_busy     (                 ),
    .kabuki_we      ( kabuki_we       ),
    .cps2_key_we    ( cps2_key_we     ),
    .joymode        ( cps2_joymode    )
);

always @(*) begin
    main_addr_x = { 3'd0, main_ram_addr[17:1] };
`ifdef CPS2
    if( main_oram_cs ) begin
        main_addr_x[17:14] = 4'd0;
        main_addr_x[13]    = main_ram_addr[15] ^ obank;
    end
`endif
end

assign workram_cs     = main_ram_cs | main_vram_cs | main_oram_cs;
assign workram_we     = !main_rnw;
assign workram_din    = main_dout;
assign workram_dsn    = dsn;
assign workram_addr   = main_addr_x;
assign workram_offset = main_oram_cs ? ORAM_OFFSET :
                       (main_ram_cs  ? WRAM_OFFSET : VRAM_OFFSET);
assign main_ram_ok    = workram_ok;
assign main_ram_data  = workram_data;

assign vramrom_cs     = vram_dma_cs;
assign vramrom_addr   = vram_dma_addr;
assign vramrom_clr    = vram_clr;
assign vram_dma_ok    = vramrom_ok;
assign vram_dma_data  = vramrom_data;

`ifdef CPS2
assign oramrom_cs     = gfx_oram_cs;
assign oramrom_addr   = gfx_oram_addr;
assign oramrom_clr    = gfx_oram_clr;
assign gfx_oram_ok    = oramrom_ok;
assign gfx_oram_data  = oramrom_data;
`endif

assign mainrom_cs     = main_rom_cs;
assign mainrom_addr   = main_rom_addr;
assign main_rom_ok    = mainrom_ok;
assign main_rom_data  = mainrom_data;

assign sndrom_cs      = snd_cs;
assign sndrom_addr    = snd_addr;
assign snd_ok         = sndrom_ok;
assign snd_data       = sndrom_data;

assign pcmrom_cs      = pcm_cs;
assign pcmrom_addr    = pcm_addr;
assign pcm_ok         = pcmrom_ok;
assign pcm_data       = pcmrom_data;

`ifdef CPS2
assign objgfx_cs      = {2{rom0_cs}} & { rom0_bank[0], ~rom0_bank[0] };
assign cps2_gfx0      = { rom0_bank[1], gfx0_addr };
assign objlorom_cs    = objgfx_cs[0];
assign objlorom_addr  = cps2_gfx0[22:1];

always @(*) begin
    rom0_ok   = rom0_bank[0] ? objrom_ok   : objlorom_ok;
    rom0_data = rom0_bank[0] ? objrom_data : objlorom_data;
end
`else
assign objgfx_cs      = 2'b10;
assign cps2_gfx0      = { 1'b0, gfx0_addr };

always @(*) begin
    rom0_ok   = objrom_ok;
    rom0_data = objrom_data;
end
`endif

assign objrom_cs      = objgfx_cs[1];
assign objrom_addr    = cps2_gfx0[22:1];
assign scrrom_cs      = rom1_cs;
assign scrrom_addr    = gfx1_addr[21:1];
assign rom1_ok        = scrrom_ok;
assign rom1_data      = scrrom_data;

`ifdef CPS1
wire [21:0] gfx_star0 = { 1'b0, star_bank, 5'd0, star0_addr, 2'b00 };
wire [21:0] gfx_star1 = { 1'b0, star_bank, 5'd0, star1_addr, 2'b10 };

assign star0rom_cs    = star0_cs;
assign star0rom_addr  = gfx_star0[21:1];
assign star0_ok       = star0rom_ok;
assign star0_data     = star0rom_data;

assign star1rom_cs    = star1_cs;
assign star1rom_addr  = gfx_star1[21:1];
assign star1_ok       = star1rom_ok;
assign star1_data     = star1rom_data;
`endif

jt9346_16b8b #(.DW(EEPROM_DW), .AW(EEPROM_AW)) u_eeprom(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .sclk       ( sclk      ),
    .sdi        ( sdi       ),
    .sdo        ( sdo       ),
    .scs        ( scs       ),
    .dump_clk   ( clk       ),
    .dump_addr  ( ioctl_addr[(EEPROM_DW==16?EEPROM_AW+1:EEPROM_AW):0] ),
    .dump_we    ( dump_we   ),
    .dump_din   ( ioctl_dout),
    .dump_dout  ( ioctl_din ),
    .dump_flag  ( dump_flag ),
    .dump_clr   ( ioctl_ram )
);

endmodule
