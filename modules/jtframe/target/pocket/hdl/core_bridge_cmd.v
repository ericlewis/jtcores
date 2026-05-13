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

// APF host/target command handler.
//
// This intentionally follows the public openFPGA core_bridge_cmd state-machine
// shape while using an inferred data table so the public JTFRAME Pocket target
// does not depend on a private/generated IP block.

module core_bridge_cmd (
    input  wire            clk,
    output reg             reset_n,

    input  wire            bridge_endian_little,
    input  wire    [31:0]  bridge_addr,
    input  wire            bridge_rd,
    output reg     [31:0]  bridge_rd_data,
    input  wire            bridge_wr,
    input  wire    [31:0]  bridge_wr_data,

    input  wire            status_boot_done,
    input  wire            status_setup_done,
    input  wire            status_running,

    output reg             dataslot_requestread,
    output reg     [15:0]  dataslot_requestread_id,
    input  wire            dataslot_requestread_ack,
    input  wire            dataslot_requestread_ok,

    output reg             dataslot_requestwrite,
    output reg     [15:0]  dataslot_requestwrite_id,
    input  wire            dataslot_requestwrite_ack,
    input  wire            dataslot_requestwrite_ok,

    output reg             dataslot_allcomplete,

    input  wire            savestate_supported,
    input  wire    [31:0]  savestate_addr,
    input  wire    [31:0]  savestate_size,
    input  wire    [31:0]  savestate_maxloadsize,

    output reg             osnotify_inmenu,

    output reg             savestate_start,
    input  wire            savestate_start_ack,
    input  wire            savestate_start_busy,
    input  wire            savestate_start_ok,
    input  wire            savestate_start_err,

    output reg             savestate_load,
    input  wire            savestate_load_ack,
    input  wire            savestate_load_busy,
    input  wire            savestate_load_ok,
    input  wire            savestate_load_err,

    input  wire    [9:0]   datatable_addr,
    input  wire            datatable_wren,
    input  wire    [31:0]  datatable_data,
    output reg     [31:0]  datatable_q
);

localparam [31:0] BUILD_DATE_BCD  = 32'h20260423;
localparam [31:0] BUILD_TIME_BCD  = 32'h00000000;
localparam [31:0] BUILD_UNIQUE_ID = 32'h4A545043;

localparam [3:0] ST_IDLE      = 4'd0;
localparam [3:0] ST_PARSE     = 4'd1;
localparam [3:0] ST_DONE_OK   = 4'd13;
localparam [3:0] ST_DONE_CODE = 4'd14;
localparam [3:0] ST_DONE_ERR  = 4'd15;

localparam [3:0] TARG_ST_IDLE       = 4'd0;
localparam [3:0] TARG_ST_READYTORUN = 4'd1;
localparam [3:0] TARG_ST_WAITRESULT = 4'd15;

reg [31:0] bridge_wr_data_in;
reg [31:0] bridge_rd_data_out;

reg [31:0] host_0;
reg [31:0] host_4;
reg [31:0] host_8;
reg [31:0] host_20;
reg [31:0] host_24;
reg [31:0] host_28;
reg [31:0] host_2C;
reg [31:0] host_40;
reg [31:0] host_44;
reg [31:0] host_48;
reg [31:0] host_4C;

reg        host_cmd_start;
reg [15:0] host_cmd_startval;
reg [15:0] host_cmd;
reg [15:0] host_resultcode;
reg [3:0]  hstate;

reg [31:0] target_0;
reg [31:0] target_4;
reg [31:0] target_8;
reg [31:0] target_20;
reg [31:0] target_24;
reg [31:0] target_28;
reg [31:0] target_2C;
reg [31:0] target_40;
reg [31:0] target_44;
reg [31:0] target_48;
reg [31:0] target_4C;
reg [3:0]  tstate;

reg        status_setup_done_1;
reg        status_setup_done_queue;

reg [31:0] datatable [0:255];
integer i;

wire host_space      = bridge_addr[31:24] == 8'hF8 && bridge_addr[15:8] == 8'h00;
wire target_space    = bridge_addr[31:24] == 8'hF8 && bridge_addr[15:8] == 8'h10;
wire datatable_space = bridge_addr[31:24] == 8'hF8 && bridge_addr[15:12] == 4'h2;
wire buildinfo_space = bridge_addr[31:24] == 8'hF8 && bridge_addr[15:8] == 8'h23 && bridge_addr[7:4] == 4'h8;

function [31:0] swap32;
    input [31:0] value;
    begin
        swap32 = { value[7:0], value[15:8], value[23:16], value[31:24] };
    end
endfunction

always @(*) begin
    bridge_wr_data_in = bridge_endian_little ? swap32(bridge_wr_data) : bridge_wr_data;
    bridge_rd_data    = bridge_endian_little ? swap32(bridge_rd_data_out) : bridge_rd_data_out;
end

always @(posedge clk) begin
    if (datatable_wren) begin
        datatable[datatable_addr[7:0]] <= datatable_data;
    end
    datatable_q <= datatable[datatable_addr[7:0]];

    status_setup_done_1 <= status_setup_done;
    if (status_setup_done && !status_setup_done_1) begin
        status_setup_done_queue <= 1'b1;
    end

    if (bridge_wr) begin
        if (host_space) begin
            case (bridge_addr[7:0])
                8'h00: begin
                    host_0 <= bridge_wr_data_in;
                    if (bridge_wr_data_in[31:16] == 16'h434D) begin
                        host_cmd_startval <= bridge_wr_data_in[15:0];
                        host_cmd_start    <= 1'b1;
                    end
                end
                8'h20: host_20 <= bridge_wr_data_in;
                8'h24: host_24 <= bridge_wr_data_in;
                8'h28: host_28 <= bridge_wr_data_in;
                8'h2C: host_2C <= bridge_wr_data_in;
                default: begin
                end
            endcase
        end else if (target_space) begin
            case (bridge_addr[7:0])
                8'h00: target_0  <= bridge_wr_data_in;
                8'h04: target_4  <= bridge_wr_data_in;
                8'h08: target_8  <= bridge_wr_data_in;
                8'h40: target_40 <= bridge_wr_data_in;
                8'h44: target_44 <= bridge_wr_data_in;
                8'h48: target_48 <= bridge_wr_data_in;
                8'h4C: target_4C <= bridge_wr_data_in;
                default: begin
                end
            endcase
        end else if (datatable_space) begin
            datatable[bridge_addr[9:2]] <= bridge_wr_data_in;
        end
    end

    if (bridge_rd) begin
        bridge_rd_data_out <= 32'd0;
        if (host_space) begin
            case (bridge_addr[7:0])
                8'h00: bridge_rd_data_out <= host_0;
                8'h04: bridge_rd_data_out <= host_4;
                8'h08: bridge_rd_data_out <= host_8;
                8'h40: bridge_rd_data_out <= host_40;
                8'h44: bridge_rd_data_out <= host_44;
                8'h48: bridge_rd_data_out <= host_48;
                8'h4C: bridge_rd_data_out <= host_4C;
                default: begin
                end
            endcase
        end else if (target_space) begin
            case (bridge_addr[7:0])
                8'h00: bridge_rd_data_out <= target_0;
                8'h04: bridge_rd_data_out <= target_4;
                8'h08: bridge_rd_data_out <= target_8;
                8'h20: bridge_rd_data_out <= target_20;
                8'h24: bridge_rd_data_out <= target_24;
                8'h28: bridge_rd_data_out <= target_28;
                8'h2C: bridge_rd_data_out <= target_2C;
                default: begin
                end
            endcase
        end else if (buildinfo_space) begin
            case (bridge_addr[3:2])
                2'd0:    bridge_rd_data_out <= BUILD_DATE_BCD;
                2'd1:    bridge_rd_data_out <= BUILD_TIME_BCD;
                default: bridge_rd_data_out <= BUILD_UNIQUE_ID;
            endcase
        end else if (datatable_space) begin
            bridge_rd_data_out <= datatable[bridge_addr[9:2]];
        end
    end

    case (hstate)
        ST_IDLE: begin
            dataslot_requestread  <= 1'b0;
            dataslot_requestwrite <= 1'b0;
            savestate_start       <= 1'b0;
            savestate_load        <= 1'b0;
            dataslot_allcomplete  <= 1'b0;

            if (host_cmd_start) begin
                host_cmd_start <= 1'b0;
                host_cmd       <= host_cmd_startval;
                hstate         <= ST_PARSE;
            end
        end

        ST_PARSE: begin
            host_0 <= {16'h4255, host_cmd};

            case (host_cmd)
                16'h0000: begin
                    host_resultcode <= 16'd1;
                    if (status_boot_done) begin
                        host_resultcode <= 16'd2;
                        if (status_setup_done) begin
                            host_resultcode <= 16'd3;
                        end else if (status_running) begin
                            host_resultcode <= 16'd4;
                        end
                    end
                    hstate <= ST_DONE_CODE;
                end

                16'h0010: begin
                    reset_n <= 1'b0;
                    hstate  <= ST_DONE_OK;
                end

                16'h0011: begin
                    reset_n <= 1'b1;
                    hstate  <= ST_DONE_OK;
                end

                16'h0080: begin
                    dataslot_allcomplete    <= 1'b0;
                    dataslot_requestread    <= 1'b1;
                    dataslot_requestread_id <= host_20[15:0];
                    if (dataslot_requestread_ack) begin
                        host_resultcode <= dataslot_requestread_ok ? 16'd0 : 16'd2;
                        hstate <= ST_DONE_CODE;
                    end
                end

                16'h0082: begin
                    dataslot_allcomplete     <= 1'b0;
                    dataslot_requestwrite    <= 1'b1;
                    dataslot_requestwrite_id <= host_20[15:0];
                    if (dataslot_requestwrite_ack) begin
                        host_resultcode <= dataslot_requestwrite_ok ? 16'd0 : 16'd2;
                        hstate <= ST_DONE_CODE;
                    end
                end

                16'h008A: begin
                    dataslot_allcomplete     <= 1'b0;
                    dataslot_requestwrite    <= 1'b1;
                    dataslot_requestwrite_id <= host_20[15:0];
                    if (dataslot_requestwrite_ack) begin
                        host_resultcode <= dataslot_requestwrite_ok ? 16'd0 : 16'd2;
                        hstate <= ST_DONE_CODE;
                    end
                end

                16'h008F: begin
                    dataslot_allcomplete <= 1'b1;
                    hstate <= ST_DONE_OK;
                end

                16'h00A0: begin
                    host_40 <= {31'd0, savestate_supported};
                    host_44 <= savestate_addr;
                    host_48 <= savestate_size;
                    host_resultcode <= 16'd0;
                    if (savestate_start_busy) host_resultcode <= 16'd1;
                    if (savestate_start_ok)   host_resultcode <= 16'd2;
                    if (savestate_start_err)  host_resultcode <= 16'd3;
                    if (host_20[0]) begin
                        savestate_start <= 1'b1;
                        if (savestate_start_ack) hstate <= ST_DONE_CODE;
                    end else begin
                        hstate <= ST_DONE_CODE;
                    end
                end

                16'h00A4: begin
                    host_40 <= {31'd0, savestate_supported};
                    host_44 <= savestate_addr;
                    host_48 <= savestate_maxloadsize;
                    host_resultcode <= 16'd0;
                    if (savestate_load_busy) host_resultcode <= 16'd1;
                    if (savestate_load_ok)   host_resultcode <= 16'd2;
                    if (savestate_load_err)  host_resultcode <= 16'd3;
                    if (host_20[0]) begin
                        savestate_load <= 1'b1;
                        if (savestate_load_ack) hstate <= ST_DONE_CODE;
                    end else begin
                        hstate <= ST_DONE_CODE;
                    end
                end

                16'h00B0: begin
                    osnotify_inmenu <= host_20[0];
                    hstate <= ST_DONE_OK;
                end

                16'h00B1: begin
                    host_40 <= host_20;
                    hstate <= ST_DONE_OK;
                end

                16'h00B2,
                16'h00B8: begin
                    host_40 <= host_20;
                    hstate <= ST_DONE_OK;
                end

                default: begin
                    hstate <= ST_DONE_ERR;
                end
            endcase
        end

        ST_DONE_OK: begin
            host_0 <= 32'h4F4B0000;
            hstate <= ST_IDLE;
        end

        ST_DONE_CODE: begin
            host_0 <= {16'h4F4B, host_resultcode};
            hstate <= ST_IDLE;
        end

        ST_DONE_ERR: begin
            host_0 <= 32'h4F4BFFFF;
            hstate <= ST_IDLE;
        end

        default: begin
            hstate <= ST_IDLE;
        end
    endcase

    case (tstate)
        TARG_ST_IDLE: begin
            if (status_setup_done_queue) begin
                status_setup_done_queue <= 1'b0;
                tstate <= TARG_ST_READYTORUN;
            end
        end

        TARG_ST_READYTORUN: begin
            target_0 <= 32'h636D0140;
            tstate <= TARG_ST_WAITRESULT;
        end

        TARG_ST_WAITRESULT: begin
            if (target_0[31:16] == 16'h6F6B) begin
                target_0 <= 32'd0;
                tstate <= TARG_ST_IDLE;
            end
        end

        default: begin
            tstate <= TARG_ST_IDLE;
        end
    endcase
end

initial begin
    reset_n                  = 1'b0;
    bridge_rd_data_out       = 32'd0;
    host_0                   = 32'h4F4B0001;
    host_4                   = 32'h00000020;
    host_8                   = 32'h00000040;
    host_20                  = 32'd0;
    host_24                  = 32'd0;
    host_28                  = 32'd0;
    host_2C                  = 32'd0;
    host_40                  = 32'd0;
    host_44                  = 32'd0;
    host_48                  = 32'd0;
    host_4C                  = 32'd0;
    host_cmd_start           = 1'b0;
    host_cmd_startval        = 16'd0;
    host_cmd                 = 16'd0;
    host_resultcode          = 16'd0;
    hstate                   = ST_IDLE;
    target_0                 = 32'd0;
    target_4                 = 32'h00000020;
    target_8                 = 32'h00000040;
    target_20                = 32'd0;
    target_24                = 32'd0;
    target_28                = 32'd0;
    target_2C                = 32'd0;
    target_40                = 32'd0;
    target_44                = 32'd0;
    target_48                = 32'd0;
    target_4C                = 32'd0;
    tstate                   = TARG_ST_IDLE;
    status_setup_done_1      = 1'b0;
    status_setup_done_queue  = 1'b0;
    dataslot_requestread     = 1'b0;
    dataslot_requestread_id  = 16'd0;
    dataslot_requestwrite    = 1'b0;
    dataslot_requestwrite_id = 16'd0;
    dataslot_allcomplete     = 1'b0;
    savestate_start          = 1'b0;
    savestate_load           = 1'b0;
    osnotify_inmenu          = 1'b0;
    datatable_q              = 32'd0;
    for (i = 0; i < 256; i = i + 1) begin
        datatable[i] = 32'd0;
    end
end

endmodule
