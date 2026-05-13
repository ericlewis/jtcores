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

// Raw APF shell for the Pocket target.
//
// This follows the APF split used by reference Pocket cores:
// - io_bridge_peripheral: SPI bridge -> logical bridge bus
// - io_pad_controller:    1-wire pad -> logical controller buses
// - JTFRAME core wrapper: logical bridge/pad -> JTFRAME game core
//
// The shell still needs board-specific timing validation on real hardware.

`ifdef JTFRAME_COLORW
    `define JTFRAME_POCKET_COLORW `JTFRAME_COLORW
`else
    `define JTFRAME_POCKET_COLORW 4
`endif

`ifdef JTFRAME_WIDTH
    `define JTFRAME_POCKET_VIDEO_WIDTH `JTFRAME_WIDTH
`else
    `define JTFRAME_POCKET_VIDEO_WIDTH 320
`endif

`ifdef JTFRAME_HEIGHT
    `define JTFRAME_POCKET_VIDEO_HEIGHT `JTFRAME_HEIGHT
`else
    `define JTFRAME_POCKET_VIDEO_HEIGHT 240
`endif

module pocket_top (
    input   wire            clk_74a,
    input   wire            clk_74b,

    inout   wire    [7:0]   cart_tran_bank2,
    output  wire            cart_tran_bank2_dir,
    inout   wire    [7:0]   cart_tran_bank3,
    output  wire            cart_tran_bank3_dir,
    inout   wire    [7:0]   cart_tran_bank1,
    output  wire            cart_tran_bank1_dir,
    inout   wire    [7:4]   cart_tran_bank0,
    output  wire            cart_tran_bank0_dir,
    inout   wire            cart_tran_pin30,
    output  wire            cart_tran_pin30_dir,
    output  wire            cart_pin30_pwroff_reset,
    inout   wire            cart_tran_pin31,
    output  wire            cart_tran_pin31_dir,

    input   wire            port_ir_rx,
    output  wire            port_ir_tx,
    output  wire            port_ir_rx_disable,

    inout   wire            port_tran_si,
    output  wire            port_tran_si_dir,
    inout   wire            port_tran_so,
    output  wire            port_tran_so_dir,
    inout   wire            port_tran_sck,
    output  wire            port_tran_sck_dir,
    inout   wire            port_tran_sd,
    output  wire            port_tran_sd_dir,

    inout   wire    [11:0]  scal_vid,
    inout   wire            scal_clk,
    inout   wire            scal_de,
    inout   wire            scal_skip,
    inout   wire            scal_vs,
    inout   wire            scal_hs,

    output  wire            scal_audmclk,
    input   wire            scal_audadc,
    output  wire            scal_auddac,
    output  wire            scal_audlrck,

    inout   wire            bridge_spimosi,
    inout   wire            bridge_spimiso,
    inout   wire            bridge_spiclk,
    input   wire            bridge_spiss,
    inout   wire            bridge_1wire,

    output  wire    [21:16] cram0_a,
    inout   wire    [15:0]  cram0_dq,
    input   wire            cram0_wait,
    output  wire            cram0_clk,
    output  wire            cram0_adv_n,
    output  wire            cram0_cre,
    output  wire            cram0_ce0_n,
    output  wire            cram0_ce1_n,
    output  wire            cram0_oe_n,
    output  wire            cram0_we_n,
    output  wire            cram0_ub_n,
    output  wire            cram0_lb_n,

    output  wire    [21:16] cram1_a,
    inout   wire    [15:0]  cram1_dq,
    input   wire            cram1_wait,
    output  wire            cram1_clk,
    output  wire            cram1_adv_n,
    output  wire            cram1_cre,
    output  wire            cram1_ce0_n,
    output  wire            cram1_ce1_n,
    output  wire            cram1_oe_n,
    output  wire            cram1_we_n,
    output  wire            cram1_ub_n,
    output  wire            cram1_lb_n,

    output  wire    [12:0]  dram_a,
    output  wire    [1:0]   dram_ba,
    inout   wire    [15:0]  dram_dq,
    output  wire    [1:0]   dram_dqm,
    output  wire            dram_clk,
    output  wire            dram_cke,
    output  wire            dram_ras_n,
    output  wire            dram_cas_n,
    output  wire            dram_we_n,

    output  wire    [16:0]  sram_a,
    inout   wire    [15:0]  sram_dq,
    output  wire            sram_oe_n,
    output  wire            sram_we_n,
    output  wire            sram_ub_n,
    output  wire            sram_lb_n,

    input   wire            vblank,

    output  wire            dbg_tx,
    input   wire            dbg_rx,

    output  wire            user1,
    input   wire            user2,

    inout   wire            bist,
    output  wire            vpll_feed,

    inout   wire            aux_sda,
    output  wire            aux_scl
);

    localparam COLORW = `JTFRAME_POCKET_COLORW;
    localparam [15:0] VIDEO_WIDTH = `JTFRAME_POCKET_VIDEO_WIDTH;
    localparam [15:0] VIDEO_HEIGHT = `JTFRAME_POCKET_VIDEO_HEIGHT;
    reg [24:0] poweron_cnt = 25'd0;
    reg        core_reset_n = 1'b0;

    always @(posedge clk_74a) begin
        poweron_cnt <= poweron_cnt + 25'd1;
        if (poweron_cnt[15]) begin
            core_reset_n <= 1'b1;
        end
    end

    assign bist = 1'bZ;

    // Unused physical interfaces remain in a benign state until JTFRAME grows
    // platform support for them.
    assign port_ir_tx             = 1'b0;
    assign port_ir_rx_disable     = 1'b1;
    assign cart_tran_bank3        = 8'hZZ;
    assign cart_tran_bank3_dir    = 1'b0;
    assign cart_tran_bank2        = 8'hZZ;
    assign cart_tran_bank2_dir    = 1'b0;
    assign cart_tran_bank1        = 8'hZZ;
    assign cart_tran_bank1_dir    = 1'b0;
    assign cart_tran_bank0        = 4'hF;
    assign cart_tran_bank0_dir    = 1'b1;
    assign cart_tran_pin30        = 1'b0;
    assign cart_tran_pin30_dir    = 1'bZ;
    assign cart_pin30_pwroff_reset = 1'b0;
    assign cart_tran_pin31        = 1'bZ;
    assign cart_tran_pin31_dir    = 1'b0;

    assign port_tran_so           = 1'bZ;
    assign port_tran_so_dir       = 1'b0;
    assign port_tran_si           = 1'bZ;
    assign port_tran_si_dir       = 1'b0;
    assign port_tran_sck          = 1'bZ;
    assign port_tran_sck_dir      = 1'b0;
    assign port_tran_sd           = 1'bZ;
    assign port_tran_sd_dir       = 1'b0;

    assign cram0_a                = 'h0;
    assign cram0_dq               = {16{1'bZ}};
    assign cram0_clk              = 1'b0;
    assign cram0_adv_n            = 1'b1;
    assign cram0_cre              = 1'b0;
    assign cram0_ce0_n            = 1'b1;
    assign cram0_ce1_n            = 1'b1;
    assign cram0_oe_n             = 1'b1;
    assign cram0_we_n             = 1'b1;
    assign cram0_ub_n             = 1'b1;
    assign cram0_lb_n             = 1'b1;

    assign cram1_a                = 'h0;
    assign cram1_dq               = {16{1'bZ}};
    assign cram1_clk              = 1'b0;
    assign cram1_adv_n            = 1'b1;
    assign cram1_cre              = 1'b0;
    assign cram1_ce0_n            = 1'b1;
    assign cram1_ce1_n            = 1'b1;
    assign cram1_oe_n             = 1'b1;
    assign cram1_we_n             = 1'b1;
    assign cram1_ub_n             = 1'b1;
    assign cram1_lb_n             = 1'b1;

    assign sram_a                 = 'h0;
    assign sram_dq                = {16{1'bZ}};
    assign sram_oe_n              = 1'b1;
    assign sram_we_n              = 1'b1;
    assign sram_ub_n              = 1'b1;
    assign sram_lb_n              = 1'b1;

    assign dbg_tx                 = 1'bZ;
    assign user1                  = 1'bZ;
    assign aux_sda                = 1'bZ;
    assign aux_scl                = 1'bZ;
    assign vpll_feed              = 1'bZ;

    wire    [31:0]  cont1_key;
    wire    [31:0]  cont2_key;
    wire    [31:0]  cont3_key;
    wire    [31:0]  cont4_key;
    wire    [31:0]  cont1_joy;
    wire    [31:0]  cont2_joy;
    wire    [31:0]  cont3_joy;
    wire    [31:0]  cont4_joy;
    wire    [15:0]  cont1_trig;
    wire    [15:0]  cont2_trig;
    wire    [15:0]  cont3_trig;
    wire    [15:0]  cont4_trig;

    io_pad_controller u_pad(
        .clk            ( clk_74a         ),
        .reset_n        ( core_reset_n    ),
        .pad_1wire      ( bridge_1wire    ),
        .cont1_key      ( cont1_key       ),
        .cont2_key      ( cont2_key       ),
        .cont3_key      ( cont3_key       ),
        .cont4_key      ( cont4_key       ),
        .cont1_joy      ( cont1_joy       ),
        .cont2_joy      ( cont2_joy       ),
        .cont3_joy      ( cont3_joy       ),
        .cont4_joy      ( cont4_joy       ),
        .cont1_trig     ( cont1_trig      ),
        .cont2_trig     ( cont2_trig      ),
        .cont3_trig     ( cont3_trig      ),
        .cont4_trig     ( cont4_trig      ),
        .rx_timed_out   (                 )
    );

    wire            bridge_endian_little;
    wire    [31:0]  bridge_addr;
    wire            bridge_rd;
    wire    [31:0]  bridge_rd_data;
    wire            bridge_wr;
    wire    [31:0]  bridge_wr_data;

    io_bridge_peripheral u_bridge_phy(
        .clk            ( clk_74a                ),
        .reset_n        ( core_reset_n           ),
        .endian_little  ( bridge_endian_little   ),
        .pmp_addr       ( bridge_addr            ),
        .pmp_addr_valid (                        ),
        .pmp_rd         ( bridge_rd              ),
        .pmp_rd_data    ( bridge_rd_data         ),
        .pmp_wr         ( bridge_wr              ),
        .pmp_wr_data    ( bridge_wr_data         ),
        .phy_spimosi    ( bridge_spimosi         ),
        .phy_spimiso    ( bridge_spimiso         ),
        .phy_spiclk     ( bridge_spiclk          ),
        .phy_spiss      ( bridge_spiss           )
    );

    assign bridge_endian_little = 1'b0;

    wire    [12:0]  sdram_a_int;
    wire    [1:0]   sdram_ba_int;
    wire    [15:0]  sdram_dq_int;
    wire            sdram_dqml_int;
    wire            sdram_dqmh_int;
    wire            sdram_nwe_int;
    wire            sdram_ncas_int;
    wire            sdram_nras_int;
    wire            sdram_ncs_unused;
    wire            sdram_cke_int;

    wire    [COLORW-1:0]  core_r;
    wire    [COLORW-1:0]  core_g;
    wire    [COLORW-1:0]  core_b;
    wire            core_hs;
    wire            core_vs;
    wire            core_lhbl;
    wire            core_lvbl;
    wire            core_pxl_cen;
    wire            core_video_clk;
    wire            core_video_clk_90;
    wire            core_audio_clk;
    wire signed [15:0] core_audio_l;
    wire signed [15:0] core_audio_r;
    wire            core_led;
    wire    [23:0]  core_debug_rgb;
    wire    [ 7:0]  core_debug_flags;

    jtframe_pocket #(
        .COLORW      ( COLORW       ),
        .VIDEO_WIDTH ( VIDEO_WIDTH  ),
        .VIDEO_HEIGHT( VIDEO_HEIGHT )
    ) u_core(
        .clk_74a            ( clk_74a                ),
        .clk_74b            ( clk_74b                ),
        .reset_n            ( core_reset_n           ),
        .bridge_endian_little( bridge_endian_little  ),
        .bridge_addr        ( bridge_addr            ),
        .bridge_wr_data     ( bridge_wr_data         ),
        .bridge_wr          ( bridge_wr              ),
        .bridge_rd          ( bridge_rd              ),
        .bridge_rd_data     ( bridge_rd_data         ),
        .cont1_key          ( cont1_key              ),
        .cont2_key          ( cont2_key              ),
        .cont3_key          ( cont3_key              ),
        .cont4_key          ( cont4_key              ),
        .cont1_joy          ( cont1_joy              ),
        .cont2_joy          ( cont2_joy              ),
        .cont3_joy          ( cont3_joy              ),
        .cont4_joy          ( cont4_joy              ),
        .cont1_trig         ( cont1_trig             ),
        .cont2_trig         ( cont2_trig             ),
        .cont3_trig         ( cont3_trig             ),
        .cont4_trig         ( cont4_trig             ),
        .SDRAM_DQ           ( dram_dq                ),
        .SDRAM_A            ( sdram_a_int            ),
        .SDRAM_BA           ( sdram_ba_int           ),
        .SDRAM_DQML         ( sdram_dqml_int         ),
        .SDRAM_DQMH         ( sdram_dqmh_int         ),
        .SDRAM_nWE          ( sdram_nwe_int          ),
        .SDRAM_nCAS         ( sdram_ncas_int         ),
        .SDRAM_nRAS         ( sdram_nras_int         ),
        .SDRAM_nCS          ( sdram_ncs_unused       ),
        .SDRAM_CLK          ( dram_clk               ),
        .SDRAM_CKE          ( sdram_cke_int          ),
        .video_r            ( core_r                 ),
        .video_g            ( core_g                 ),
        .video_b            ( core_b                 ),
        .video_hs           ( core_hs                ),
        .video_vs           ( core_vs                ),
        .video_lhbl         ( core_lhbl              ),
        .video_lvbl         ( core_lvbl              ),
        .video_pxl_cen      ( core_pxl_cen           ),
        .video_rgb_clock    ( core_video_clk         ),
        .video_rgb_clock_90 ( core_video_clk_90      ),
        .audio_clk          ( core_audio_clk         ),
        .audio_l            ( core_audio_l           ),
        .audio_r            ( core_audio_r           ),
        .led                ( core_led               ),
        .pocket_debug_rgb   ( core_debug_rgb         ),
        .pocket_debug_flags ( core_debug_flags       )
    );

    assign dram_a     = sdram_a_int;
    assign dram_ba    = sdram_ba_int;
    assign dram_dqm   = {sdram_dqmh_int, sdram_dqml_int};
    assign dram_cke   = sdram_cke_int;
    assign dram_ras_n = sdram_nras_int;
    assign dram_cas_n = sdram_ncas_int;
    assign dram_we_n  = sdram_nwe_int;

    function [7:0] expand8;
        input [COLORW-1:0] in;
        begin
            expand8 = 8'd0;
            case (COLORW)
                1: expand8 = {8{in[0]}};
                2: expand8 = {4{in[1:0]}};
                3: expand8 = {in, in, in[2:1]};
                4: expand8 = {in, in};
                5: expand8 = {in, in[4:2]};
                6: expand8 = {in, in[5:4]};
                7: expand8 = {in, in[6]};
                default: begin
                    if (COLORW >= 8)
                        expand8 = in[COLORW-1 -: 8];
                    else
                        expand8 = {in, {(8-COLORW){1'b0}}};
                end
            endcase
        end
    endfunction

    function [23:0] debug_bar_color;
        input [2:0] index;
        input       enabled;
        begin
            if (enabled) begin
                case (index)
                    3'd0:    debug_bar_color = 24'hFF0000;
                    3'd1:    debug_bar_color = 24'h00FF00;
                    3'd2:    debug_bar_color = 24'h0000FF;
                    3'd3:    debug_bar_color = 24'hFFFF00;
                    3'd4:    debug_bar_color = 24'h00FFFF;
                    3'd5:    debug_bar_color = 24'hFF00FF;
                    3'd6:    debug_bar_color = 24'hFFFFFF;
                    default: debug_bar_color = 24'hFF8000;
                endcase
            end else begin
                case (index)
                    3'd0:    debug_bar_color = 24'h200000;
                    3'd1:    debug_bar_color = 24'h002000;
                    3'd2:    debug_bar_color = 24'h000020;
                    3'd3:    debug_bar_color = 24'h202000;
                    3'd4:    debug_bar_color = 24'h002020;
                    3'd5:    debug_bar_color = 24'h200020;
                    3'd6:    debug_bar_color = 24'h202020;
                    default: debug_bar_color = 24'h201000;
                endcase
            end
        end
    endfunction

    wire [23:0] video_rgb_raw = { expand8(core_r), expand8(core_g), expand8(core_b) };
    reg  [23:0] video_rgb = 24'd0;
    reg         video_de = 1'b0;
    reg         video_hs = 1'b0;
    reg         video_vs = 1'b0;
    wire        video_skip = 1'b0;
    wire        video_rgb_clock    = core_video_clk;
    wire        video_rgb_clock_90 = core_video_clk_90;
    wire [11:0] scal_ddio_vid;
    wire [11:0] scal_ddio_ctrl;
    reg         hs_prev = 1'b0;
    reg         vs_prev = 1'b0;
    reg         lhbl_crop_prev = 1'b0;
    reg [15:0]  video_crop_x = 16'd0;
    reg [15:0]  video_crop_y = 16'd0;
    wire        core_de_raw = core_lhbl & core_lvbl;
    wire        core_de_cropped = core_de_raw &&
                                  video_crop_x < VIDEO_WIDTH &&
                                  video_crop_y < VIDEO_HEIGHT;

    always @(posedge video_rgb_clock) begin
        if (core_pxl_cen) begin
            if (!core_lvbl) begin
                video_crop_x <= 16'd0;
                video_crop_y <= 16'd0;
                lhbl_crop_prev <= 1'b0;
            end else begin
                if (core_lhbl) begin
                    video_crop_x <= video_crop_x + 16'd1;
                end else begin
                    video_crop_x <= 16'd0;
                end

                if (lhbl_crop_prev && !core_lhbl) begin
                    video_crop_y <= video_crop_y + 16'd1;
                end
                lhbl_crop_prev <= core_lhbl;
            end
        end
    end

`ifdef JTFRAME_POCKET_TEST_PATTERN
    reg [9:0] pattern_h = 10'd0;
    reg [8:0] pattern_v = 9'd0;

    always @(posedge video_rgb_clock) begin
        if (pattern_h == 10'd383) begin
            pattern_h <= 10'd0;
            pattern_v <= (pattern_v == 9'd261) ? 9'd0 : pattern_v + 9'd1;
        end else begin
            pattern_h <= pattern_h + 10'd1;
        end

        video_de <= pattern_h < 10'd256 && pattern_v < 9'd240;
        video_hs <= pattern_h == 10'd280;
        video_vs <= pattern_h == 10'd0 && pattern_v == 9'd244;

        if (pattern_h < 10'd256 && pattern_v < 9'd240) begin
            case (pattern_h[7:5])
                3'd0:    video_rgb <= 24'hFF0000;
                3'd1:    video_rgb <= 24'h00FF00;
                3'd2:    video_rgb <= 24'h0000FF;
                3'd3:    video_rgb <= 24'hFFFF00;
                3'd4:    video_rgb <= 24'h00FFFF;
                3'd5:    video_rgb <= 24'hFF00FF;
                3'd6:    video_rgb <= 24'hFFFFFF;
                default: video_rgb <= 24'h404040;
            endcase
        end else begin
            video_rgb <= 24'h000000;
        end
    end
`elsif JTFRAME_POCKET_CORE_TIMING_PATTERN
    // Keep the JTFRAME core's pixel clock, blanking, and syncs, but replace RGB.
    // If this shows bars, the game is producing video timing and the issue is
    // black pixel data. If it stays black, the core is not producing timing.
    always @(posedge video_rgb_clock) begin
        video_de <= core_de_cropped;
        video_rgb <= core_de_cropped ? {
            {8{core_pxl_cen}},
            {8{core_led}},
            {8{core_hs ^ core_vs}}
        } : 24'h0;
        video_hs <= ~hs_prev & core_hs;
        video_vs <= ~vs_prev & core_vs;
        hs_prev <= core_hs;
        vs_prev <= core_vs;
    end
`elsif JTFRAME_POCKET_CORE_STATE_PATTERN
    // State diagnostic under real JTFRAME timing:
    // red=game reset released, green=download complete, blue=raw RGB nonzero.
    always @(posedge video_rgb_clock) begin
        video_de <= core_de_cropped;
        video_rgb <= core_de_cropped ? core_debug_rgb : 24'h0;
        video_hs <= ~hs_prev & core_hs;
        video_vs <= ~vs_prev & core_vs;
        hs_prev <= core_hs;
        vs_prev <= core_vs;
    end
`elsif JTFRAME_POCKET_CORE_BARS_PATTERN
    // Eight real-timing status bars, left to right:
    // reset released, download complete, ROM bridge writes seen,
    // SDRAM programmer writes seen, programmer acks seen, game SDRAM reads seen,
    // game SDRAM ready seen, raw RGB ever nonzero.
    reg [8:0] state_h = 9'd0;
    wire [2:0] state_bar = state_h[7:5];

    always @(posedge video_rgb_clock) begin
        video_de <= core_de_cropped;
        if (core_de_cropped) begin
            video_rgb <= debug_bar_color(state_bar, core_debug_flags[state_bar]);
            state_h <= state_h + 9'd1;
        end else begin
            video_rgb <= 24'h0;
            state_h <= 9'd0;
        end
        video_hs <= ~hs_prev & core_hs;
        video_vs <= ~vs_prev & core_vs;
        hs_prev <= core_hs;
        vs_prev <= core_vs;
    end
`else
    // APF wants RGB forced to black outside DE, and hsync/vsync as single-cycle
    // pulses rather than the full-width blanking-domain syncs used internally.
    always @(posedge video_rgb_clock) begin
        video_de <= core_de_cropped;
        video_rgb <= core_de_cropped ? video_rgb_raw : 24'h0;
        video_hs <= ~hs_prev & core_hs;
        video_vs <= ~vs_prev & core_vs;
        hs_prev <= core_hs;
        vs_prev <= core_vs;
    end
`endif

    mf_ddio_bidir_12 u_scal_vid(
        .datain_h    ( video_rgb[23:12] ),
        .datain_l    ( video_rgb[11:0]  ),
        .inclock     ( 1'b0             ),
        .oe          ( 1'b1             ),
        .outclock    ( video_rgb_clock  ),
        .dataout_h   (                  ),
        .dataout_l   (                  ),
        .padio       ( scal_ddio_vid    )
    );

    assign scal_vid = scal_ddio_vid;

    mf_ddio_bidir_12 u_scal_ctrl(
        .datain_h    ( { 8'd0, video_vs, video_hs, video_de, video_skip } ),
        .datain_l    ( { 8'd0, video_vs, video_hs, video_de, video_skip } ),
        .inclock     ( 1'b0                                             ),
        .oe          ( 1'b1                                             ),
        .outclock    ( video_rgb_clock                                  ),
        .dataout_h   (                                                  ),
        .dataout_l   (                                                  ),
        .padio       ( scal_ddio_ctrl                                   )
    );

    assign scal_vs   = scal_ddio_ctrl[3];
    assign scal_hs   = scal_ddio_ctrl[2];
    assign scal_de   = scal_ddio_ctrl[1];
    assign scal_skip = scal_ddio_ctrl[0];

    pin_ddio_clk u_scal_clk(
        .datain_h    ( 1'b1               ),
        .datain_l    ( 1'b0               ),
        .outclock    ( video_rgb_clock_90 ),
        .dataout     ( scal_clk           )
    );

    wire audio_lrck;
    wire audio_dac;
    wire audio_mclk;

    jtframe_pocket_sound_i2s u_sound_i2s(
        .clk_74a    ( clk_74a        ),
        .clk_audio  ( core_audio_clk ),
        .reset      ( ~core_reset_n  ),
        .audio_l    ( core_audio_l   ),
        .audio_r    ( core_audio_r   ),
        .audio_mclk ( audio_mclk     ),
        .audio_lrck ( audio_lrck     ),
        .audio_dac  ( audio_dac      )
    );

    assign scal_audmclk = audio_mclk;
    assign scal_auddac  = audio_dac;
    assign scal_audlrck = audio_lrck;

endmodule

`undef JTFRAME_POCKET_COLORW
