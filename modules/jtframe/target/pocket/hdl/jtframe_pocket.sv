/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.
*/

module jtframe_pocket #(
    parameter BUTTONS                = 2,
    parameter GAME_INPUTS_ACTIVE_LOW = 1'b1,
    parameter COLORW                 = 4,
    parameter VIDEO_WIDTH            = 320,
    parameter VIDEO_HEIGHT           = 240,
    parameter SDRAMW                 = 22
)(
    input               clk_74a,
    input               clk_74b,
    input               reset_n,

    input               bridge_endian_little,
    input      [31:0]   bridge_addr,
    input      [31:0]   bridge_wr_data,
    input               bridge_wr,
    input               bridge_rd,
    output     [31:0]   bridge_rd_data,

    input      [31:0]   cont1_key,
    input      [31:0]   cont2_key,
    input      [31:0]   cont3_key,
    input      [31:0]   cont4_key,
    input      [31:0]   cont1_joy,
    input      [31:0]   cont2_joy,
    input      [31:0]   cont3_joy,
    input      [31:0]   cont4_joy,
    input      [15:0]   cont1_trig,
    input      [15:0]   cont2_trig,
    input      [15:0]   cont3_trig,
    input      [15:0]   cont4_trig,

    inout      [15:0]   SDRAM_DQ,
    output     [12:0]   SDRAM_A,
    output     [ 1:0]   SDRAM_BA,
    output              SDRAM_DQML,
    output              SDRAM_DQMH,
    output              SDRAM_nWE,
    output              SDRAM_nCAS,
    output              SDRAM_nRAS,
    output              SDRAM_nCS,
    output              SDRAM_CLK,
    output              SDRAM_CKE,

    output     [COLORW-1:0] video_r,
    output     [COLORW-1:0] video_g,
    output     [COLORW-1:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_lhbl,
    output              video_lvbl,
    output              video_pxl_cen,
    output              video_rgb_clock,
    output              video_rgb_clock_90,
    output              audio_clk,
    output signed [15:0] audio_l,
    output signed [15:0] audio_r,
    output              led,
    output     [23:0]   pocket_debug_rgb,
    output     [ 7:0]   pocket_debug_flags
);

function automatic [15:0] map_pad_key;
    input [31:0] key;
    begin
        map_pad_key = 16'd0;
        // Ignore keyboard/mouse packed data for joystick translation.
        if (key[31:28] < 4'h4) begin
            map_pad_key[0]  = key[3];
            map_pad_key[1]  = key[2];
            map_pad_key[2]  = key[1];
            map_pad_key[3]  = key[0];
            map_pad_key[4]  = key[4];
            map_pad_key[5]  = key[5];
            map_pad_key[6]  = key[6];
            map_pad_key[7]  = key[7];
            map_pad_key[8]  = key[8];
            map_pad_key[9]  = key[9];
            map_pad_key[10] = key[10];
            map_pad_key[11] = key[11];
            map_pad_key[12] = key[12];
            map_pad_key[13] = key[13];
            map_pad_key[14] = key[14];
            map_pad_key[15] = key[15];
        end
    end
endfunction

function automatic [7:0] axis_u2s;
    input [7:0] axis;
    begin
        axis_u2s = axis - 8'd128;
    end
endfunction

function automatic [15:0] stick_u2s;
    input [15:0] stick;
    begin
        stick_u2s = stick == 16'd0 ? 16'd0 : { axis_u2s(stick[15:8]), axis_u2s(stick[7:0]) };
    end
endfunction

wire                pll_locked;
wire                clk_sys;
wire                clk_rom;
wire                clk_pico;
wire                clk24;
wire                clk48;
wire                clk96;

wire                rst;
wire                rst_n;
wire                game_rst;
wire                game_rst_n;
wire                sdram_init;
wire                rst_req;
wire                rst_req_raw;

assign audio_clk = clk_sys;

wire [31:0]         cont1_key_sys;
wire [31:0]         cont2_key_sys;
wire [31:0]         cont3_key_sys;
wire [31:0]         cont4_key_sys;
wire [31:0]         cont1_joy_sys;
wire [31:0]         cont2_joy_sys;
wire [31:0]         cont3_joy_sys;
wire [31:0]         cont4_joy_sys;
wire [15:0]         cont1_trig_sys;
wire [15:0]         cont2_trig_sys;
wire [15:0]         cont3_trig_sys;
wire [15:0]         cont4_trig_sys;

jtframe_pocket_sync #(.W(32)) u_sync_cont1_key(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont1_key     ),
    .dout   ( cont1_key_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont2_key(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont2_key     ),
    .dout   ( cont2_key_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont3_key(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont3_key     ),
    .dout   ( cont3_key_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont4_key(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont4_key     ),
    .dout   ( cont4_key_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont1_joy(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont1_joy     ),
    .dout   ( cont1_joy_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont2_joy(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont2_joy     ),
    .dout   ( cont2_joy_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont3_joy(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont3_joy     ),
    .dout   ( cont3_joy_sys )
);

jtframe_pocket_sync #(.W(32)) u_sync_cont4_joy(
    .clk    ( clk_sys       ),
    .rst    ( rst           ),
    .din    ( cont4_joy     ),
    .dout   ( cont4_joy_sys )
);

jtframe_pocket_sync #(.W(16)) u_sync_cont1_trig(
    .clk    ( clk_sys        ),
    .rst    ( rst            ),
    .din    ( cont1_trig     ),
    .dout   ( cont1_trig_sys )
);

jtframe_pocket_sync #(.W(16)) u_sync_cont2_trig(
    .clk    ( clk_sys        ),
    .rst    ( rst            ),
    .din    ( cont2_trig     ),
    .dout   ( cont2_trig_sys )
);

jtframe_pocket_sync #(.W(16)) u_sync_cont3_trig(
    .clk    ( clk_sys        ),
    .rst    ( rst            ),
    .din    ( cont3_trig     ),
    .dout   ( cont3_trig_sys )
);

jtframe_pocket_sync #(.W(16)) u_sync_cont4_trig(
    .clk    ( clk_sys        ),
    .rst    ( rst            ),
    .din    ( cont4_trig     ),
    .dout   ( cont4_trig_sys )
);

wire [15:0] joy1_key = map_pad_key(cont1_key_sys);
wire [15:0] joy2_key = map_pad_key(cont2_key_sys);
wire [15:0] joy3_key = map_pad_key(cont3_key_sys);
wire [15:0] joy4_key = map_pad_key(cont4_key_sys);

wire [ 3:0] board_start = { 3'd0, joy1_key[15] };
wire [ 3:0] board_coin  = { 3'd0, joy1_key[14] };

wire [15:0] joyana_l1 = stick_u2s(cont1_joy_sys[15:0]);
wire [15:0] joyana_l2 = stick_u2s(cont2_joy_sys[15:0]);
wire [15:0] joyana_l3 = stick_u2s(cont3_joy_sys[15:0]);
wire [15:0] joyana_l4 = stick_u2s(cont4_joy_sys[15:0]);
wire [15:0] joyana_r1 = stick_u2s(cont1_joy_sys[31:16]);
wire [15:0] joyana_r2 = stick_u2s(cont2_joy_sys[31:16]);
wire [15:0] joyana_r3 = stick_u2s(cont3_joy_sys[31:16]);
wire [15:0] joyana_r4 = stick_u2s(cont4_joy_sys[31:16]);

wire [63:0]         status;
wire [63:0]         status_raw;
wire [31:0]         dipsw;
wire [31:0]         dipsw_raw;
wire [31:0]         cheat;
wire [31:0]         cheat_raw;
wire [ 6:0]         core_mod;
wire [ 6:0]         core_mod_raw;
wire [ 7:0]         game_vol;
wire [ 7:0]         game_vol_raw;
wire [ 7:0]         debug_view;
wire                dwnld_busy;
wire [31:0]         timestamp;
wire [31:0]         timestamp_raw;
wire                osnotify_inmenu;
wire                osnotify_inmenu_raw;
wire                osnotify_docked;
wire                osnotify_docked_raw;
wire [ 7:0]         display_mode_id;
wire [ 7:0]         display_mode_id_raw;
wire                display_mode_grayscale;
wire                display_mode_grayscale_raw;

wire                ioctl_rom_raw;
wire                ioctl_ram_raw;
wire                ioctl_cart_raw;
wire                ioctl_cheat_raw;
wire                ioctl_lock_raw;
wire                ioctl_wr_raw;
wire [26:0]         ioctl_addr_raw;
wire [ 7:0]         ioctl_dout_raw;
wire                ioctl_rom_sync;
wire                ioctl_ram_sync;
wire                ioctl_cart_sync;
wire                ioctl_rom;
wire                ioctl_wr;
wire                ioctl_ram;
wire                ioctl_cart;
wire                ioctl_cheat;
wire                ioctl_lock;
wire [25:0]         ioctl_addr;
wire [ 7:0]         ioctl_dout;
wire [ 7:0]         ioctl_din;
wire [ 7:0]         ioctl_merged;

wire                ioctl_slot_wr_rom;
wire [26:0]         ioctl_slot_addr_rom;
wire [ 7:0]         ioctl_slot_dout_rom;
wire                ioctl_slot_wr_ram;
wire [26:0]         ioctl_slot_addr_ram;
wire [ 7:0]         ioctl_slot_dout_ram;
wire                ioctl_slot_wr = ioctl_slot_wr_rom | ioctl_slot_wr_ram;

wire [12:0]         hdmi_arx;
wire [12:0]         hdmi_ary;
wire [ 1:0]         rotate;
wire                rot_osdonly;
wire                dip_test;
wire                dip_pause;
wire                dip_flip;
wire [ 1:0]         dip_fxlevel;

wire [ 9:0]         game_joy1;
wire [ 9:0]         game_joy2;
wire [ 9:0]         game_joy3;
wire [ 9:0]         game_joy4;
wire [ 3:0]         game_coin;
wire [ 3:0]         game_start;
wire                game_service;
wire                game_tilt;
wire [15:0]         mouse_1p;
wire [15:0]         mouse_2p;
wire [ 1:0]         mouse_strobe;
wire [ 8:0]         gun_1p_x;
wire [ 8:0]         gun_1p_y;
wire [ 8:0]         gun_2p_x;
wire [ 8:0]         gun_2p_y;
wire [ 1:0]         dial_x;
wire [ 1:0]         dial_y;
wire [ 7:0]         paddle_1;
wire [ 7:0]         paddle_2;
wire [ 7:0]         paddle_3 = 8'd0;
wire [ 7:0]         paddle_4 = 8'd0;
wire [ 8:0]         spinner_1p = 9'd0;
wire [ 8:0]         spinner_2p = 9'd0;

wire [3*COLORW-1:0] base_rgb;
wire                base_lhbl;
wire                base_lvbl;
wire                base_hs;
wire                base_vs;

wire [COLORW-1:0]   red;
wire [COLORW-1:0]   green;
wire [COLORW-1:0]   blue;
wire                LHBL;
wire                LVBL;
wire                hs;
wire                vs;
wire                pxl_cen;
wire                pxl2_cen;
wire                rst24;
wire                rst48;
wire                rst96;
wire                field = 1'b0;

wire signed [15:0]  snd_left;
wire signed [15:0]  snd_right;
wire                sample;
wire [ 5:0]         snd_en;
wire [ 5:0]         snd_vu;
wire [ 7:0]         snd_vol;
wire                snd_peak;
wire [ 3:0]         gfx_en;
wire [ 7:0]         debug_bus;
wire [ 7:0]         st_addr;
wire [ 7:0]         st_dout;

wire [SDRAMW-1:0]   ba0_addr;
wire [SDRAMW-1:0]   ba1_addr;
wire [SDRAMW-1:0]   ba2_addr;
wire [SDRAMW-1:0]   ba3_addr;
wire [SDRAMW-1:0]   burst_addr;
wire [ 3:0]         ba_rd;
wire [ 3:0]         ba_wr;
wire [ 3:0]         ba_ack;
wire [ 3:0]         ba_rdy;
wire [ 3:0]         ba_dst;
wire [ 3:0]         ba_dok;
wire [ 1:0]         burst_ba;
wire                burst_rd;
wire                burst_wr;
wire                burst_ack;
wire                burst_dst;
wire                burst_dok;
wire                burst_rdy;
wire [15:0]         ba0_din;
wire [15:0]         ba1_din;
wire [15:0]         ba2_din;
wire [15:0]         ba3_din;
wire [15:0]         burst_din;
wire [ 1:0]         ba0_dsn;
wire [ 1:0]         ba1_dsn;
wire [ 1:0]         ba2_dsn;
wire [ 1:0]         ba3_dsn;
wire [15:0]         sdram_dout;

wire [SDRAMW-1:0]   prog_addr;
wire [15:0]         prog_data;
wire [ 1:0]         prog_mask;
wire [ 1:0]         prog_ba;
wire                prog_we;
wire                prog_rd;
wire                prog_dst;
wire                prog_dok;
wire                prog_rdy;
wire                prog_ack;

wire                game_rx = 1'b1;
wire                game_tx;

wire [ 7:0]         st_lpbuf;

jtframe_pocket_clocks u_clocks(
    .clk_74a             ( clk_74a             ),
    .game_rst            ( game_rst            ),
    .clk_sys             ( clk_sys             ),
    .clk_rom             ( clk_rom             ),
    .clk_pico            ( clk_pico            ),
    .clk24               ( clk24               ),
    .clk48               ( clk48               ),
    .clk96               ( clk96               ),
    .sdram_clk           ( SDRAM_CLK           ),
    .pll_locked          ( pll_locked          ),
    .rst24               ( rst24               ),
    .rst48               ( rst48               ),
    .rst96               ( rst96               ),
    .video_rgb_clock     ( video_rgb_clock     ),
    .video_rgb_clock_90  ( video_rgb_clock_90  )
);

jtframe_pocket_sync #(.W(1)) u_sync_rst_req(
    .clk    ( clk_sys    ),
    .rst    ( ~pll_locked),
    .din    ( rst_req_raw),
    .dout   ( rst_req    )
);

jtframe_pocket_sync #(.W(64)) u_sync_status(
    .clk    ( clk_sys    ),
    .rst    ( ~pll_locked),
    .din    ( status_raw ),
    .dout   ( status     )
);

jtframe_pocket_sync #(.W(32)) u_sync_dipsw(
    .clk    ( clk_sys    ),
    .rst    ( ~pll_locked),
    .din    ( dipsw_raw  ),
    .dout   ( dipsw      )
);

jtframe_pocket_sync #(.W(32)) u_sync_cheat(
    .clk    ( clk_sys    ),
    .rst    ( ~pll_locked),
    .din    ( cheat_raw  ),
    .dout   ( cheat      )
);

jtframe_pocket_sync #(.W(7)) u_sync_core_mod(
    .clk    ( clk_sys      ),
    .rst    ( ~pll_locked  ),
    .din    ( core_mod_raw ),
    .dout   ( core_mod     )
);

jtframe_pocket_sync #(.W(8)) u_sync_game_vol(
    .clk    ( clk_sys      ),
    .rst    ( ~pll_locked  ),
    .din    ( game_vol_raw ),
    .dout   ( game_vol     )
);

jtframe_pocket_sync #(.W(32)) u_sync_timestamp(
    .clk    ( clk_sys       ),
    .rst    ( ~pll_locked   ),
    .din    ( timestamp_raw ),
    .dout   ( timestamp     )
);

jtframe_pocket_sync #(.W(1)) u_sync_inmenu(
    .clk    ( clk_sys             ),
    .rst    ( ~pll_locked         ),
    .din    ( osnotify_inmenu_raw ),
    .dout   ( osnotify_inmenu     )
);

jtframe_pocket_sync #(.W(1)) u_sync_docked(
    .clk    ( clk_sys             ),
    .rst    ( ~pll_locked         ),
    .din    ( osnotify_docked_raw ),
    .dout   ( osnotify_docked     )
);

jtframe_pocket_sync #(.W(8)) u_sync_display_mode_id(
    .clk    ( clk_sys              ),
    .rst    ( ~pll_locked          ),
    .din    ( display_mode_id_raw  ),
    .dout   ( display_mode_id      )
);

jtframe_pocket_sync #(.W(1)) u_sync_display_gray(
    .clk    ( clk_sys                     ),
    .rst    ( ~pll_locked                 ),
    .din    ( display_mode_grayscale_raw  ),
    .dout   ( display_mode_grayscale      )
);

jtframe_pocket_bridge u_bridge(
    .clk                    ( clk_74a               ),
    .boot_done              ( pll_locked            ),
    .bridge_endian_little   ( bridge_endian_little  ),
    .bridge_addr            ( bridge_addr           ),
    .bridge_wr_data         ( bridge_wr_data        ),
    .bridge_wr              ( bridge_wr             ),
    .bridge_rd              ( bridge_rd             ),
    .bridge_rd_data         ( bridge_rd_data        ),
    .ioctl_din              ( ioctl_merged          ),
    .rst_req                ( rst_req_raw           ),
    .status                 ( status_raw            ),
    .dipsw                  ( dipsw_raw             ),
    .cheat                  ( cheat_raw             ),
    .core_mod               ( core_mod_raw          ),
    .game_vol               ( game_vol_raw          ),
    .timestamp              ( timestamp_raw         ),
    .osnotify_inmenu        ( osnotify_inmenu_raw   ),
    .osnotify_docked        ( osnotify_docked_raw   ),
    .display_mode_id        ( display_mode_id_raw   ),
    .display_mode_grayscale ( display_mode_grayscale_raw),
    .ioctl_rom              ( ioctl_rom_raw         ),
    .ioctl_ram              ( ioctl_ram_raw         ),
    .ioctl_cart             ( ioctl_cart_raw        ),
    .ioctl_cheat            ( ioctl_cheat_raw       ),
    .ioctl_lock             ( ioctl_lock_raw        ),
    .ioctl_wr               ( ioctl_wr_raw          ),
    .ioctl_addr             ( ioctl_addr_raw        ),
    .ioctl_dout             ( ioctl_dout_raw        )
);

jtframe_pocket_sync #(.W(1)) u_sync_ioctl_rom(
    .clk    ( clk_sys        ),
    .rst    ( ~pll_locked    ),
    .din    ( ioctl_rom_raw  ),
    .dout   ( ioctl_rom_sync )
);

jtframe_pocket_sync #(.W(1)) u_sync_ioctl_ram(
    .clk    ( clk_sys        ),
    .rst    ( ~pll_locked    ),
    .din    ( ioctl_ram_raw  ),
    .dout   ( ioctl_ram_sync )
);

jtframe_pocket_sync #(.W(1)) u_sync_ioctl_cart(
    .clk    ( clk_sys         ),
    .rst    ( ~pll_locked     ),
    .din    ( ioctl_cart_raw  ),
    .dout   ( ioctl_cart_sync )
);

jtframe_pocket_sync #(.W(1)) u_sync_ioctl_cheat(
    .clk    ( clk_sys          ),
    .rst    ( ~pll_locked      ),
    .din    ( ioctl_cheat_raw  ),
    .dout   ( ioctl_cheat      )
);

jtframe_pocket_sync #(.W(1)) u_sync_ioctl_lock(
    .clk    ( clk_sys         ),
    .rst    ( ~pll_locked     ),
    .din    ( ioctl_lock_raw  ),
    .dout   ( ioctl_lock      )
);

jtframe_pocket_data_loader #(
    .ADDRESS_MASK_UPPER_4    ( 4'h1 ),
    .ADDRESS_SIZE            ( 27   )
) u_slot_loader_rom (
    .clk_74a              ( clk_74a                ),
    .clk_memory           ( clk_sys                ),
    .bridge_wr            ( bridge_wr              ),
    .bridge_endian_little ( bridge_endian_little   ),
    .bridge_addr          ( bridge_addr            ),
    .bridge_wr_data       ( bridge_wr_data         ),
    .write_ready          ( ~prog_we               ),
    .write_en             ( ioctl_slot_wr_rom      ),
    .write_addr           ( ioctl_slot_addr_rom    ),
    .write_data           ( ioctl_slot_dout_rom    )
);

jtframe_pocket_data_loader #(
    .ADDRESS_MASK_UPPER_4    ( 4'h2 ),
    .ADDRESS_SIZE            ( 27   )
) u_slot_loader_ram (
    .clk_74a              ( clk_74a                ),
    .clk_memory           ( clk_sys                ),
    .bridge_wr            ( bridge_wr              ),
    .bridge_endian_little ( bridge_endian_little   ),
    .bridge_addr          ( bridge_addr            ),
    .bridge_wr_data       ( bridge_wr_data         ),
    .write_ready          ( 1'b1                   ),
    .write_en             ( ioctl_slot_wr_ram      ),
    .write_addr           ( ioctl_slot_addr_ram    ),
    .write_data           ( ioctl_slot_dout_ram    )
);

reg [11:0] ioctl_rom_drain = 12'd0;
reg [11:0] ioctl_ram_drain = 12'd0;
reg [11:0] ioctl_cart_drain = 12'd0;

wire ioctl_rom_req  = ioctl_rom_sync  | ioctl_slot_wr_rom;
wire ioctl_ram_req  = ioctl_ram_sync  | ioctl_slot_wr_ram;
wire ioctl_cart_req = ioctl_cart_sync;

always @(posedge clk_sys) begin
    if (!pll_locked) begin
        ioctl_rom_drain  <= 12'd0;
        ioctl_ram_drain  <= 12'd0;
        ioctl_cart_drain <= 12'd0;
    end else begin
        if (ioctl_rom_req)
            ioctl_rom_drain <= 12'hFFF;
        else if (ioctl_ram_req || ioctl_cart_req)
            ioctl_rom_drain <= 12'd0;
        else if (ioctl_rom_drain != 12'd0)
            ioctl_rom_drain <= ioctl_rom_drain - 12'd1;

        if (ioctl_ram_req)
            ioctl_ram_drain <= 12'hFFF;
        else if (ioctl_rom_req || ioctl_cart_req)
            ioctl_ram_drain <= 12'd0;
        else if (ioctl_ram_drain != 12'd0)
            ioctl_ram_drain <= ioctl_ram_drain - 12'd1;

        if (ioctl_cart_req)
            ioctl_cart_drain <= 12'hFFF;
        else if (ioctl_rom_req || ioctl_ram_req)
            ioctl_cart_drain <= 12'd0;
        else if (ioctl_cart_drain != 12'd0)
            ioctl_cart_drain <= ioctl_cart_drain - 12'd1;
    end
end

wire ioctl_ram_hold  = (ioctl_ram_drain  != 12'd0) & ~ioctl_rom_req & ~ioctl_cart_req;
wire ioctl_cart_hold = (ioctl_cart_drain != 12'd0) & ~ioctl_rom_req & ~ioctl_ram_req;
wire ioctl_rom_hold  = (ioctl_rom_drain  != 12'd0) & ~ioctl_ram_req & ~ioctl_cart_req;

wire ioctl_ram_active  = ioctl_ram_req  | ioctl_ram_hold;
wire ioctl_cart_active = ioctl_cart_req | ioctl_cart_hold;
wire ioctl_rom_active  = ioctl_rom_req  | ioctl_rom_hold;

assign ioctl_ram  = ioctl_ram_active;
assign ioctl_cart = ioctl_cart_active & ~ioctl_ram_active;
assign ioctl_rom  = ioctl_rom_active & ~ioctl_ram_active & ~ioctl_cart_active;
assign ioctl_wr   = ioctl_slot_wr ? 1'b1 : ioctl_wr_raw;
assign ioctl_addr = ioctl_slot_wr_rom ? ioctl_slot_addr_rom[25:0] :
                    ioctl_slot_wr_ram ? ioctl_slot_addr_ram[25:0] :
                    ioctl_addr_raw[25:0];
assign ioctl_dout = ioctl_slot_wr_rom ? ioctl_slot_dout_rom :
                    ioctl_slot_wr_ram ? ioctl_slot_dout_ram :
                    ioctl_dout_raw;

reg rom_write_seen = 1'b0;
reg prog_we_seen = 1'b0;
reg prog_ack_seen = 1'b0;
reg game_read_seen = 1'b0;
reg game_rdy_seen = 1'b0;
reg raw_rgb_seen = 1'b0;

always @(posedge clk_sys) begin
    if (!pll_locked) begin
        rom_write_seen <= 1'b0;
        prog_we_seen   <= 1'b0;
        prog_ack_seen  <= 1'b0;
        game_read_seen <= 1'b0;
        game_rdy_seen  <= 1'b0;
        raw_rgb_seen   <= 1'b0;
    end else begin
        if (ioctl_slot_wr_rom) rom_write_seen <= 1'b1;
        if (prog_we)           prog_we_seen   <= 1'b1;
        if (prog_ack)          prog_ack_seen  <= 1'b1;
        if (|ba_rd)            game_read_seen <= 1'b1;
        if (|ba_rdy)           game_rdy_seen  <= 1'b1;
        if (|{red, green, blue}) raw_rgb_seen <= 1'b1;
    end
end

jtframe_board #(
    .BUTTONS               ( BUTTONS                ),
    .GAME_INPUTS_ACTIVE_LOW( GAME_INPUTS_ACTIVE_LOW ),
    .COLORW                ( COLORW                 ),
    .VIDEO_WIDTH           ( VIDEO_WIDTH            ),
    .VIDEO_HEIGHT          ( VIDEO_HEIGHT           ),
    .SDRAMW                ( SDRAMW                 ),
    .MISTER                ( 0                      )
) u_board(
    .rst            ( rst            ),
    .rst_n          ( rst_n          ),
    .game_rst       ( game_rst       ),
    .game_rst_n     ( game_rst_n     ),
    .sdram_init     ( sdram_init     ),
    .rst_req        ( rst_req        ),
    .pll_locked     ( pll_locked     ),
    .clk_sys        ( clk_sys        ),
    .clk_rom        ( clk_rom        ),
    .clk_pico       ( clk_pico       ),
    .core_mod       ( core_mod       ),
    .vertical       (                ),
    .black_frame    (                ),
    .osd_shown      ( 1'b0           ),
    .led            ( led            ),
    .snd_lin        ( snd_left       ),
    .snd_rin        ( snd_right      ),
    .snd_lout       ( audio_l        ),
    .snd_rout       ( audio_r        ),
    .game_vol       ( game_vol       ),
    .snd_vol        ( snd_vol        ),
    .snd_sample     ( sample         ),
    .snd_peak       ( snd_peak       ),
    .snd_en         ( snd_en         ),
    .snd_vu         ( snd_vu         ),
    .ba0_addr       ( ba0_addr       ),
    .ba1_addr       ( ba1_addr       ),
    .ba2_addr       ( ba2_addr       ),
    .ba3_addr       ( ba3_addr       ),
`ifdef JTFRAME_SDRAM_CACHE
    .burst_addr     ( burst_addr     ),
    .burst_ba       ( burst_ba       ),
    .burst_rd       ( burst_rd       ),
    .burst_wr       ( burst_wr       ),
    .burst_ack      ( burst_ack      ),
    .burst_dst      ( burst_dst      ),
    .burst_dok      ( burst_dok      ),
    .burst_rdy      ( burst_rdy      ),
    .burst_din      ( burst_din      ),
`endif
    .ba_rd          ( ba_rd          ),
    .ba_wr          ( ba_wr          ),
    .ba_ack         ( ba_ack         ),
    .ba_rdy         ( ba_rdy         ),
    .ba_dst         ( ba_dst         ),
    .ba_dok         ( ba_dok         ),
    .ba0_din        ( ba0_din        ),
    .ba1_din        ( ba1_din        ),
    .ba2_din        ( ba2_din        ),
    .ba3_din        ( ba3_din        ),
    .ba0_dsn        ( ba0_dsn        ),
    .ba1_dsn        ( ba1_dsn        ),
    .ba2_dsn        ( ba2_dsn        ),
    .ba3_dsn        ( ba3_dsn        ),
    .sdram_dout     ( sdram_dout     ),
    .prog_addr      ( prog_addr      ),
    .prog_data      ( prog_data      ),
    .prog_dsn       ( prog_mask      ),
    .prog_ba        ( prog_ba        ),
    .prog_we        ( prog_we        ),
    .prog_rd        ( prog_rd        ),
    .prog_dok       ( prog_dok       ),
    .prog_rdy       ( prog_rdy       ),
    .prog_dst       ( prog_dst       ),
    .prog_ack       ( prog_ack       ),
    .ioctl_cart     ( ioctl_cart     ),
    .dwnld_busy     ( dwnld_busy     ),
    .ioctl_ram      ( ioctl_ram      ),
    .SDRAM_DQ       ( SDRAM_DQ       ),
    .SDRAM_A        ( SDRAM_A        ),
    .SDRAM_DQML     ( SDRAM_DQML     ),
    .SDRAM_DQMH     ( SDRAM_DQMH     ),
    .SDRAM_nWE      ( SDRAM_nWE      ),
    .SDRAM_nCAS     ( SDRAM_nCAS     ),
    .SDRAM_nRAS     ( SDRAM_nRAS     ),
    .SDRAM_nCS      ( SDRAM_nCS      ),
    .SDRAM_BA       ( SDRAM_BA       ),
    .SDRAM_CKE      ( SDRAM_CKE      ),
    .ps2_kbd_clk    ( 1'b1           ),
    .ps2_kbd_data   ( 1'b1           ),
    .uart_rx        ( 1'b1           ),
    .uart_tx        (                ),
    .board_joystick1( joy1_key       ),
    .board_joystick2( joy2_key       ),
    .board_joystick3( joy3_key       ),
    .board_joystick4( joy4_key       ),
    .board_start    ( board_start    ),
    .board_coin     ( board_coin     ),
    .joyana_l1      ( joyana_l1      ),
    .joyana_r1      ( joyana_r1      ),
    .joyana_l2      ( joyana_l2      ),
    .joyana_r2      ( joyana_r2      ),
    .game_joystick1 ( game_joy1      ),
    .game_joystick2 ( game_joy2      ),
    .game_joystick3 ( game_joy3      ),
    .game_joystick4 ( game_joy4      ),
    .game_coin      ( game_coin      ),
    .game_start     ( game_start     ),
    .game_service   ( game_service   ),
    .game_tilt      ( game_tilt      ),
    .bd_mouse_dx    ( cont4_key_sys[31:28] == 4'h5 ? { cont4_joy_sys[15], cont4_joy_sys[7:0] } : 9'd0 ),
    .bd_mouse_dy    ( cont4_key_sys[31:28] == 4'h5 ? { cont4_trig_sys[15], cont4_trig_sys[7:0] } : 9'd0 ),
    .mouse_1p       ( mouse_1p       ),
    .mouse_2p       ( mouse_2p       ),
    .mouse_strobe   ( mouse_strobe   ),
    .bd_mouse_f     ( cont4_key_sys[31:28] == 4'h5 ? cont4_joy_sys[23:16] : 8'd0 ),
    .bd_mouse_idx   ( 1'b0           ),
    .bd_mouse_st    ( cont4_key_sys[31:28] == 4'h5 ),
    .board_paddle_1 ( 8'd0           ),
    .board_paddle_2 ( 8'd0           ),
    .spinner_1      ( 9'd0           ),
    .spinner_2      ( 9'd0           ),
    .game_paddle_1  ( paddle_1       ),
    .game_paddle_2  ( paddle_2       ),
    .dial_x         ( dial_x         ),
    .dial_y         ( dial_y         ),
    .gun_1p_x       ( gun_1p_x       ),
    .gun_1p_y       ( gun_1p_y       ),
    .gun_2p_x       ( gun_2p_x       ),
    .gun_2p_y       ( gun_2p_y       ),
    .lightgun_en    (                ),
    .status         ( status         ),
    .dipsw          ( dipsw[23:0]    ),
    .hdmi_arx       ( hdmi_arx       ),
    .hdmi_ary       ( hdmi_ary       ),
    .rotate         ( rotate         ),
    .rot_osdonly    ( rot_osdonly    ),
    .dip_test       ( dip_test       ),
    .dip_pause      ( dip_pause      ),
    .dip_flip       ( dip_flip       ),
    .dip_fxlevel    ( dip_fxlevel    ),
    .ioctl_din      ( ioctl_din      ),
    .ioctl_merged   ( ioctl_merged   ),
    .osd_rotate     ( 2'd0           ),
    .game_r         ( red            ),
    .game_g         ( green          ),
    .game_b         ( blue           ),
    .LHBL           ( LHBL           ),
    .LVBL           ( LVBL           ),
    .hs             ( hs             ),
    .vs             ( vs             ),
    .pxl2_cen       ( pxl2_cen       ),
    .pxl_cen        ( pxl_cen        ),
    .base_rgb       ( base_rgb       ),
    .base_lhbl      ( base_lhbl      ),
    .base_lvbl      ( base_lvbl      ),
    .base_hs        ( base_hs        ),
    .base_vs        ( base_vs        ),
    .prog_cheat     ( ioctl_cheat    ),
    .prog_lock      ( ioctl_lock     ),
    .ioctl_wr       ( ioctl_wr       ),
    .ioctl_dout     ( ioctl_dout     ),
    .ioctl_addr     ( ioctl_addr[12:0] ),
    .cheat          ( cheat          ),
    .st_addr        ( st_addr        ),
    .st_dout        ( st_dout        ),
    .target_info    ( st_lpbuf       ),
    .timestamp      ( timestamp      ),
    .gfx_en         ( gfx_en         ),
    .debug_bus      ( debug_bus      ),
    .debug_view     ( debug_view     )
);

`ifdef JTFRAME_LF_BUFFER
    wire [ 7:0] game_vrender;
    wire [ 8:0] game_hdump;
    wire [ 8:0] ln_addr;
    wire [15:0] ln_data;
    wire        ln_done;
    wire        ln_we;
    wire        ln_hs;
    wire        ln_vs;
    wire        ln_lvbl;
    wire [15:0] ln_dout;
    wire [15:0] ln_pxl;
    wire [ 7:0] ln_v;

    reg pxl1_cen;
    always @(posedge clk_sys) pxl1_cen <= pxl2_cen & ~pxl_cen;

    jtframe_lfbuf_bram u_lf_buf(
        .rst        ( rst           ),
        .clk        ( clk_rom       ),
        .pxl_cen    ( pxl1_cen      ),
        .hs         ( hs            ),
        .vs         ( vs            ),
        .lvbl       ( LVBL          ),
        .lhbl       ( LHBL          ),
        .vrender    ( game_vrender  ),
        .hdump      ( game_hdump    ),
        .ln_addr    ( ln_addr       ),
        .ln_data    ( ln_data       ),
        .ln_done    ( ln_done       ),
        .ln_hs      ( ln_hs         ),
        .ln_dout    ( ln_dout       ),
        .ln_pxl     ( ln_pxl        ),
        .ln_v       ( ln_v          ),
        .ln_vs      ( ln_vs         ),
        .ln_lvbl    ( ln_lvbl       ),
        .ln_we      ( ln_we         ),
        .st_addr    ( st_addr       ),
        .st_dout    ( st_lpbuf      )
    );
`else
    assign st_lpbuf = 8'd0;
`endif

`include "jtframe_game_instance.v"

assign video_r    = base_rgb[3*COLORW-1 -: COLORW];
assign video_g    = base_rgb[2*COLORW-1 -: COLORW];
assign video_b    = base_rgb[COLORW-1:0];
assign video_hs   = base_hs;
assign video_vs   = base_vs;
assign video_lhbl = base_lhbl;
assign video_lvbl = base_lvbl;
assign video_pxl_cen = pxl_cen;
assign pocket_debug_rgb = {
    {8{game_rst_n}},
    {8{~dwnld_busy}},
    {8{|{red, green, blue}}}
};
assign pocket_debug_flags = {
    raw_rgb_seen,
    game_rdy_seen,
    game_read_seen,
    prog_ack_seen,
    prog_we_seen,
    rom_write_seen,
    ~dwnld_busy,
    game_rst_n
};

endmodule
