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

module jtframe_pocket_sound_i2s #(
    parameter CHANNEL_WIDTH = 16
)(
    input  wire                         clk_74a,
    input  wire                         clk_audio,
    input  wire                         reset,

    input  wire signed [CHANNEL_WIDTH-1:0] audio_l,
    input  wire signed [CHANNEL_WIDTH-1:0] audio_r,

    output reg                          audio_mclk = 1'b0,
    output reg                          audio_lrck = 1'b0,
    output reg                          audio_dac  = 1'b0
);

    localparam [21:0] CLK74_DIV100          = 22'd742500;
    localparam [21:0] AUDIO_MCLK_X2_DIV100  = 22'd245760;

    reg [21:0] audio_mclk_acc = 22'd0;
    wire [22:0] audio_mclk_next = {1'b0, audio_mclk_acc} + {1'b0, AUDIO_MCLK_X2_DIV100};

    always @(posedge clk_74a or posedge reset) begin
        if (reset) begin
            audio_mclk_acc <= 22'd0;
            audio_mclk <= 1'b0;
        end else if (audio_mclk_next >= {1'b0, CLK74_DIV100}) begin
            audio_mclk_acc <= audio_mclk_next[21:0] - CLK74_DIV100;
            audio_mclk <= ~audio_mclk;
        end else begin
            audio_mclk_acc <= audio_mclk_next[21:0];
        end
    end

    reg [1:0] audio_mclk_divider = 2'd0;
    reg       audio_mclk_l       = 1'b0;
    wire      audio_sclk         = audio_mclk_divider[1];

    always @(posedge clk_74a or posedge reset) begin
        if (reset) begin
            audio_mclk_divider <= 2'd0;
            audio_mclk_l <= 1'b0;
        end else begin
            audio_mclk_l <= audio_mclk;
            if (audio_mclk & ~audio_mclk_l) begin
                audio_mclk_divider <= audio_mclk_divider + 2'd1;
            end
        end
    end

    reg              sample_req_74a     = 1'b0;
    reg              sample_ack_audio   = 1'b0;
    reg              sample_req_meta    = 1'b0;
    reg              sample_req_audio   = 1'b0;
    reg              sample_req_seen    = 1'b0;
    reg [31:0]       sample_audio       = 32'd0;

    always @(posedge clk_audio or posedge reset) begin
        if (reset) begin
            sample_req_meta <= 1'b0;
            sample_req_audio <= 1'b0;
            sample_req_seen <= 1'b0;
            sample_ack_audio <= 1'b0;
            sample_audio <= 32'd0;
        end else begin
            sample_req_meta <= sample_req_74a;
            sample_req_audio <= sample_req_meta;
            if (sample_req_audio != sample_req_seen) begin
                sample_req_seen <= sample_req_audio;
                sample_audio <= { audio_r, audio_l };
                sample_ack_audio <= ~sample_ack_audio;
            end
        end
    end

    reg              sample_ack_meta = 1'b0;
    reg              sample_ack_74a  = 1'b0;
    reg              sample_ack_seen = 1'b0;
    reg [31:0]       sample_74a      = 32'd0;
    reg [31:0]       sample_shift    = 32'd0;
    reg [ 4:0]       audio_lrck_cnt  = 5'd0;
    reg              audio_sclk_l    = 1'b0;

    always @(posedge clk_74a or posedge reset) begin
        if (reset) begin
            sample_req_74a <= 1'b0;
            sample_ack_meta <= 1'b0;
            sample_ack_74a <= 1'b0;
            sample_ack_seen <= 1'b0;
            sample_74a <= 32'd0;
            sample_shift <= 32'd0;
            audio_lrck_cnt <= 5'd0;
            audio_lrck <= 1'b0;
            audio_dac <= 1'b0;
            audio_sclk_l <= 1'b0;
        end else begin
            sample_ack_meta <= sample_ack_audio;
            sample_ack_74a <= sample_ack_meta;
            if (sample_ack_74a != sample_ack_seen) begin
                sample_ack_seen <= sample_ack_74a;
                sample_74a <= sample_audio;
            end

            if (audio_sclk_l & ~audio_sclk) begin
                audio_dac <= sample_shift[31];
                audio_lrck_cnt <= audio_lrck_cnt + 5'd1;

                if (audio_lrck_cnt == 5'd31) begin
                    audio_lrck <= ~audio_lrck;
                    if (!audio_lrck) begin
                        sample_shift <= sample_74a;
                        sample_req_74a <= ~sample_req_74a;
                    end
                end else if (audio_lrck_cnt < 5'd16) begin
                    sample_shift <= { sample_shift[30:0], 1'b0 };
                end
            end

            audio_sclk_l <= audio_sclk;
        end
    end

endmodule
