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

// JTFRAME-facing APF bridge adapter.
//
// core_bridge_cmd owns the public APF host/target command protocol. This
// adapter keeps the JTFRAME-specific concerns local: menu/config registers,
// data-slot classification, setup-done timing, and the legacy ioctl signals
// expected by jtframe_board.

module jtframe_pocket_bridge(
    input               clk,
    input               boot_done,
    input               bridge_endian_little,
    input      [31:0]   bridge_addr,
    input               bridge_rd,
    output reg [31:0]   bridge_rd_data,
    input               bridge_wr,
    input      [31:0]   bridge_wr_data,
    input      [ 7:0]   ioctl_din,

    output              rst_req,
    output reg [63:0]   status,
    output reg [31:0]   dipsw,
    output reg [31:0]   cheat,
    output reg [ 6:0]   core_mod,
    output reg [ 7:0]   game_vol,
    output reg [31:0]   timestamp,
    output reg          osnotify_inmenu,
    output reg          osnotify_docked,
    output reg [ 7:0]   display_mode_id,
    output reg          display_mode_grayscale,

    output              ioctl_rom,
    output              ioctl_ram,
    output              ioctl_cart,
    output              ioctl_cheat,
    output              ioctl_lock,
    output reg          ioctl_wr,
    output reg [26:0]   ioctl_addr,
    output reg [ 7:0]   ioctl_dout
);

localparam [31:0] CFG_BASE         = 32'h60000000;
localparam [31:0] CFG_STATUS_LO    = CFG_BASE + 32'h00;
localparam [31:0] CFG_STATUS_HI    = CFG_BASE + 32'h04;
localparam [31:0] CFG_COREMOD_VOL  = CFG_BASE + 32'h08;
localparam [31:0] CFG_CHEAT        = CFG_BASE + 32'h0C;
localparam [31:0] CFG_DEBUG        = CFG_BASE + 32'h10;
localparam [31:0] CFG_RTC_EPOCH    = CFG_BASE + 32'h14;
localparam [31:0] CFG_RTC_DATE     = CFG_BASE + 32'h18;
localparam [31:0] CFG_RTC_TIME     = CFG_BASE + 32'h1C;
localparam [31:0] CFG_DOCK_MENU    = CFG_BASE + 32'h20;
localparam [31:0] CFG_DISPLAY      = CFG_BASE + 32'h24;
localparam [31:0] CFG_DIPSW        = CFG_BASE + 32'h28;
localparam [31:0] CFG_INSTANCE_0   = 32'hF9000000;
localparam [31:0] CFG_INSTANCE_1   = 32'hF9000004;
localparam [31:0] CFG_INSTANCE_1_LEGACY = 32'hFA000000;
localparam [31:0] SLOT_SAVE_BASE   = 32'h20000000;

localparam [15:0] SLOT_GAME_ID     = 16'd0;
localparam [15:0] SLOT_ROM_ID      = 16'd1;
localparam [15:0] SLOT_SAVE_ID     = 16'd2;
localparam [15:0] SLOT_CART_ID     = 16'd4;
localparam [15:0] SLOT_CRT_ID      = 16'd18;

localparam [1:0] SLOT_KIND_NONE    = 2'd0;
localparam [1:0] SLOT_KIND_ROM     = 2'd1;
localparam [1:0] SLOT_KIND_CART    = 2'd2;
localparam [1:0] SLOT_KIND_SAVE    = 2'd3;

localparam [15:0] SETUP_DONE_DRAIN = 16'd4095;

wire [31:0] cmd_bridge_rd_data;
wire        cmd_reset_n;
wire        cmd_osnotify_inmenu;

wire        dataslot_requestread;
wire [15:0] dataslot_requestread_id;
wire        dataslot_requestwrite;
wire [15:0] dataslot_requestwrite_id;
wire        dataslot_allcomplete;

reg         setup_done = 1'b0;
reg [15:0]  setup_done_delay = 16'd0;
reg [1:0]   active_slot_kind = SLOT_KIND_NONE;
reg         slot_transfer_active = 1'b0;
reg [31:0]  host_param_20 = 32'd0;

reg [31:0]  rtc_date_bcd = 32'd0;
reg [31:0]  rtc_time_bcd = 32'd0;
reg [31:0]  bridge_wr_data_in;
reg [31:0]  cfg_rd_data_out;
reg [31:0]  save_rd_data_out = 32'd0;

reg         save_rd_active = 1'b0;
reg [2:0]   save_rd_state = 3'd0;
reg [31:0]  save_rd_word = 32'd0;
reg [26:0]  save_rd_base = 27'd0;

wire host_space = bridge_addr[31:24] == 8'hF8 && bridge_addr[15:8] == 8'h00;
wire cmd_space  = bridge_addr[31:24] == 8'hF8;
wire save_space = bridge_addr[31:28] == SLOT_SAVE_BASE[31:28];

assign rst_req = ~cmd_reset_n;

assign ioctl_rom   = slot_transfer_active && active_slot_kind == SLOT_KIND_ROM;
assign ioctl_cart  = slot_transfer_active && active_slot_kind == SLOT_KIND_CART;
assign ioctl_ram   = (slot_transfer_active && active_slot_kind == SLOT_KIND_SAVE) || save_rd_active;
assign ioctl_cheat = 1'b0;
assign ioctl_lock  = 1'b0;

function [31:0] swap32;
    input [31:0] value;
    begin
        swap32 = { value[7:0], value[15:8], value[23:16], value[31:24] };
    end
endfunction

function slot_defined;
    input [15:0] slot_id;
    begin
        case (slot_id)
            SLOT_GAME_ID,
            SLOT_ROM_ID,
            SLOT_SAVE_ID,
            SLOT_CART_ID,
            SLOT_CRT_ID:  slot_defined = 1'b1;
            default:      slot_defined = 1'b0;
        endcase
    end
endfunction

function [1:0] slot_kind_from_id;
    input [15:0] slot_id;
    begin
        case (slot_id)
            SLOT_ROM_ID:  slot_kind_from_id = SLOT_KIND_ROM;
            SLOT_CART_ID: slot_kind_from_id = SLOT_KIND_CART;
            SLOT_SAVE_ID: slot_kind_from_id = SLOT_KIND_SAVE;
            default:      slot_kind_from_id = SLOT_KIND_NONE;
        endcase
    end
endfunction

always @(*) begin
    bridge_wr_data_in = bridge_endian_little ? swap32(bridge_wr_data) : bridge_wr_data;

    case (bridge_addr)
        CFG_INSTANCE_0:  cfg_rd_data_out = {16'd0, game_vol, 1'b0, core_mod};
        CFG_INSTANCE_1,
        CFG_INSTANCE_1_LEGACY: cfg_rd_data_out = dipsw;
        CFG_STATUS_LO:   cfg_rd_data_out = status[31:0];
        CFG_STATUS_HI:   cfg_rd_data_out = status[63:32];
        CFG_COREMOD_VOL: cfg_rd_data_out = {16'd0, game_vol, 1'b0, core_mod};
        CFG_CHEAT:       cfg_rd_data_out = cheat;
        CFG_DEBUG:       cfg_rd_data_out = 32'd0;
        CFG_RTC_EPOCH:   cfg_rd_data_out = timestamp;
        CFG_RTC_DATE:    cfg_rd_data_out = rtc_date_bcd;
        CFG_RTC_TIME:    cfg_rd_data_out = rtc_time_bcd;
        CFG_DIPSW:       cfg_rd_data_out = dipsw;
        CFG_DOCK_MENU:   cfg_rd_data_out = {30'd0, osnotify_docked, osnotify_inmenu};
        CFG_DISPLAY:     cfg_rd_data_out = {16'd0, display_mode_id, 7'd0, display_mode_grayscale};
        default:         cfg_rd_data_out = 32'd0;
    endcase

    if (cmd_space) begin
        bridge_rd_data = cmd_bridge_rd_data;
    end else if (save_space) begin
        bridge_rd_data = bridge_endian_little ? swap32(save_rd_data_out) : save_rd_data_out;
    end else begin
        bridge_rd_data = bridge_endian_little ? swap32(cfg_rd_data_out) : cfg_rd_data_out;
    end
end

core_bridge_cmd u_cmd(
    .clk                       ( clk                         ),
    .reset_n                   ( cmd_reset_n                 ),
    .bridge_endian_little      ( bridge_endian_little        ),
    .bridge_addr               ( bridge_addr                 ),
    .bridge_rd                 ( bridge_rd                   ),
    .bridge_rd_data            ( cmd_bridge_rd_data          ),
    .bridge_wr                 ( bridge_wr                   ),
    .bridge_wr_data            ( bridge_wr_data              ),
    .status_boot_done          ( boot_done                   ),
    .status_setup_done         ( setup_done                  ),
    .status_running            ( cmd_reset_n                 ),
    .dataslot_requestread      ( dataslot_requestread        ),
    .dataslot_requestread_id   ( dataslot_requestread_id     ),
    .dataslot_requestread_ack  ( dataslot_requestread        ),
    .dataslot_requestread_ok   ( slot_defined(dataslot_requestread_id) ),
    .dataslot_requestwrite     ( dataslot_requestwrite       ),
    .dataslot_requestwrite_id  ( dataslot_requestwrite_id    ),
    .dataslot_requestwrite_ack ( dataslot_requestwrite       ),
    .dataslot_requestwrite_ok  ( slot_defined(dataslot_requestwrite_id) ),
    .dataslot_allcomplete      ( dataslot_allcomplete        ),
    .savestate_supported       ( 1'b0                        ),
    .savestate_addr            ( 32'd0                       ),
    .savestate_size            ( 32'd0                       ),
    .savestate_maxloadsize     ( 32'd0                       ),
    .osnotify_inmenu           ( cmd_osnotify_inmenu         ),
    .savestate_start           (                             ),
    .savestate_start_ack       ( 1'b1                        ),
    .savestate_start_busy      ( 1'b0                        ),
    .savestate_start_ok        ( 1'b0                        ),
    .savestate_start_err       ( 1'b1                        ),
    .savestate_load            (                             ),
    .savestate_load_ack        ( 1'b1                        ),
    .savestate_load_busy       ( 1'b0                        ),
    .savestate_load_ok         ( 1'b0                        ),
    .savestate_load_err        ( 1'b1                        ),
    .datatable_addr            ( 10'd0                       ),
    .datatable_wren            ( 1'b0                        ),
    .datatable_data            ( 32'd0                       ),
    .datatable_q               (                             )
);

always @(posedge clk) begin
    ioctl_wr   <= 1'b0;
    ioctl_dout <= 8'd0;

    if (!boot_done) begin
        setup_done           <= 1'b0;
        setup_done_delay     <= 16'd0;
        slot_transfer_active <= 1'b0;
        active_slot_kind     <= SLOT_KIND_NONE;
        save_rd_active       <= 1'b0;
        save_rd_state        <= 3'd0;
        ioctl_addr           <= 27'd0;
    end else begin
        if (setup_done_delay != 16'd0) begin
            setup_done_delay <= setup_done_delay - 16'd1;
            if (setup_done_delay == 16'd1) begin
                setup_done <= 1'b1;
            end
        end

        if (dataslot_requestwrite && slot_defined(dataslot_requestwrite_id)) begin
            setup_done           <= 1'b0;
            setup_done_delay     <= 16'd0;
            active_slot_kind     <= slot_kind_from_id(dataslot_requestwrite_id);
            slot_transfer_active <= slot_kind_from_id(dataslot_requestwrite_id) != SLOT_KIND_NONE;
        end

        if (dataslot_allcomplete) begin
            slot_transfer_active <= 1'b0;
            active_slot_kind     <= SLOT_KIND_NONE;
            setup_done_delay     <= SETUP_DONE_DRAIN;
        end

        if (save_rd_active) begin
            case (save_rd_state)
                3'd1: begin
                    save_rd_word[7:0] <= ioctl_din;
                    ioctl_addr <= save_rd_base + 27'd1;
                    save_rd_state <= 3'd2;
                end
                3'd2: begin
                    save_rd_word[15:8] <= ioctl_din;
                    ioctl_addr <= save_rd_base + 27'd2;
                    save_rd_state <= 3'd3;
                end
                3'd3: begin
                    save_rd_word[23:16] <= ioctl_din;
                    ioctl_addr <= save_rd_base + 27'd3;
                    save_rd_state <= 3'd4;
                end
                3'd4: begin
                    save_rd_word[31:24] <= ioctl_din;
                    save_rd_data_out <= {
                        ioctl_din,
                        save_rd_word[23:16],
                        save_rd_word[15:8],
                        save_rd_word[7:0]
                    };
                    save_rd_state  <= 3'd0;
                    save_rd_active <= 1'b0;
                end
                default: begin
                    save_rd_state  <= 3'd0;
                    save_rd_active <= 1'b0;
                end
            endcase
        end else if (bridge_rd && save_space) begin
            save_rd_active <= 1'b1;
            save_rd_state  <= 3'd1;
            save_rd_base   <= bridge_addr[26:0];
            ioctl_addr     <= bridge_addr[26:0];
        end
    end

    if (bridge_wr) begin
        if (host_space) begin
            case (bridge_addr[7:0])
                8'h20: host_param_20 <= bridge_wr_data_in;
                8'h00: begin
                    if (bridge_wr_data_in[31:16] == 16'h434D) begin
                        case (bridge_wr_data_in[15:0])
                            16'h00B0: osnotify_inmenu <= host_param_20[0];
                            16'h00B2: osnotify_docked <= host_param_20[0];
                            16'h00B8: begin
                                display_mode_grayscale <= host_param_20[0];
                                display_mode_id        <= host_param_20[15:8];
                            end
                            default: begin
                            end
                        endcase
                    end
                end
                default: begin
                end
            endcase
        end else begin
            case (bridge_addr)
                CFG_INSTANCE_0: begin
                    core_mod <= bridge_wr_data_in[6:0];
                    game_vol <= bridge_wr_data_in[15:8];
                end
                CFG_INSTANCE_1,
                CFG_INSTANCE_1_LEGACY: begin
                    dipsw <= bridge_wr_data_in;
                end
                CFG_STATUS_LO:   status[31:0]  <= bridge_wr_data_in;
                CFG_STATUS_HI:   status[63:32] <= bridge_wr_data_in;
                CFG_COREMOD_VOL: begin
                    core_mod  <= bridge_wr_data_in[6:0];
                    game_vol  <= bridge_wr_data_in[15:8];
                end
                CFG_CHEAT:       cheat         <= bridge_wr_data_in;
                CFG_RTC_EPOCH:   timestamp     <= bridge_wr_data_in;
                CFG_RTC_DATE:    rtc_date_bcd  <= bridge_wr_data_in;
                CFG_RTC_TIME:    rtc_time_bcd  <= bridge_wr_data_in;
                CFG_DIPSW:       dipsw         <= bridge_wr_data_in;
                CFG_DOCK_MENU: begin
                    osnotify_inmenu <= bridge_wr_data_in[0];
                    osnotify_docked <= bridge_wr_data_in[1];
                end
                CFG_DISPLAY: begin
                    display_mode_grayscale <= bridge_wr_data_in[0];
                    display_mode_id        <= bridge_wr_data_in[15:8];
                end
                default: begin
                end
            endcase
        end
    end

end

initial begin
    status                  = 64'd0;
    dipsw                   = 32'hFFFFFFFF;
    cheat                   = 32'd0;
    core_mod                = 7'd0;
    game_vol                = 8'h80;
    timestamp               = 32'd0;
    rtc_date_bcd            = 32'd0;
    rtc_time_bcd            = 32'd0;
    osnotify_inmenu         = 1'b0;
    osnotify_docked         = 1'b0;
    display_mode_id         = 8'd0;
    display_mode_grayscale  = 1'b0;
    setup_done              = 1'b0;
    setup_done_delay        = 16'd0;
    active_slot_kind        = SLOT_KIND_NONE;
    slot_transfer_active    = 1'b0;
    host_param_20           = 32'd0;
    ioctl_wr                = 1'b0;
    ioctl_addr              = 27'd0;
    ioctl_dout              = 8'd0;
end

endmodule
