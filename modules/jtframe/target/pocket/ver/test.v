`timescale 1ns/1ps

module test;

`ifdef JTFRAME_COLORW
localparam COLORW = `JTFRAME_COLORW;
`else
localparam COLORW = 4;
`endif

reg clk_74a = 1'b0;
reg clk_74b = 1'b0;
reg reset_n = 1'b0;
wire [12:0] SDRAM_A;
wire [15:0] SDRAM_DQ;
wire [ 1:0] SDRAM_BA;
wire        SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS;
wire        SDRAM_nRAS, SDRAM_nCS, SDRAM_CLK, SDRAM_CKE;

wire [COLORW-1:0] video_r;
wire [COLORW-1:0] video_g;
wire [COLORW-1:0] video_b;
wire        video_hs;
wire        video_vs;
wire        video_lhbl;
wire        video_lvbl;
wire signed [15:0] audio_l;
wire signed [15:0] audio_r;
wire        led;

reg  [31:0] frame_cnt = 32'd0;

function [7:0] expand8;
    input [COLORW-1:0] in;
    begin
        expand8 = 8'd0;
        case (COLORW)
            1: expand8 = {8{in[0]}};
            2: expand8 = {4{in[1:0]}};
            3: expand8 = { in, in, in[2:1] };
            4: expand8 = { in, in };
            5: expand8 = { in, in[4:2] };
            6: expand8 = { in, in[5:4] };
            7: expand8 = { in, in[6] };
            default: expand8 = in[7:0];
        endcase
    end
endfunction

always #6.734 clk_74a = ~clk_74a;
always #6.734 clk_74b = ~clk_74b;

initial begin
    reset_n = 1'b0;
    #250 reset_n = 1'b1;
end

always @(negedge video_vs)
    frame_cnt <= frame_cnt + 32'd1;

pocket_dump u_dump(
    .VGA_VS     ( video_vs   ),
    .led        ( led        ),
    .frame_cnt  ( frame_cnt  )
);

video_dump u_video(
    .pxl_clk    ( clk_74a            ),
    .pxl_cen    ( 1'b1               ),
    .pxl_hb     ( ~video_lhbl        ),
    .pxl_vb     ( ~video_lvbl        ),
    .red        ( expand8(video_r)   ),
    .green      ( expand8(video_g)   ),
    .blue       ( expand8(video_b)   ),
    .frame_cnt  ( frame_cnt          )
);

mt48lc16m16a2 #(.filename("rom.bin")) pocket_sdram (
    .Dq         ( SDRAM_DQ      ),
    .Addr       ( SDRAM_A       ),
    .Ba         ( SDRAM_BA      ),
    .Clk        ( SDRAM_CLK     ),
    .Cke        ( SDRAM_CKE     ),
    .Cs_n       ( SDRAM_nCS     ),
    .Ras_n      ( SDRAM_nRAS    ),
    .Cas_n      ( SDRAM_nCAS    ),
    .We_n       ( SDRAM_nWE     ),
    .Dqm        ( { SDRAM_DQMH, SDRAM_DQML } ),
    .downloading( 1'b0          ),
    .VS         ( video_vs      ),
    .frame_cnt  ( frame_cnt     )
);

pocket_top UUT(
    .clk_74a        ( clk_74a        ),
    .clk_74b        ( clk_74b        ),
    .reset_n        ( reset_n        ),
    .bridge_endian_little( 1'b0           ),
    .bridge_addr    ( 32'd0          ),
    .bridge_wr_data ( 32'd0          ),
    .bridge_wr      ( 1'b0           ),
    .bridge_rd      ( 1'b0           ),
    .bridge_rd_data (                ),
    .cont1_key      ( 32'd0          ),
    .cont2_key      ( 32'd0          ),
    .cont3_key      ( 32'd0          ),
    .cont4_key      ( 32'd0          ),
    .cont1_joy      ( 32'd0          ),
    .cont2_joy      ( 32'd0          ),
    .cont3_joy      ( 32'd0          ),
    .cont4_joy      ( 32'd0          ),
    .cont1_trig     ( 16'd0          ),
    .cont2_trig     ( 16'd0          ),
    .cont3_trig     ( 16'd0          ),
    .cont4_trig     ( 16'd0          ),
    .SDRAM_A        ( SDRAM_A        ),
    .SDRAM_DQ       ( SDRAM_DQ       ),
    .SDRAM_BA       ( SDRAM_BA       ),
    .SDRAM_DQML     ( SDRAM_DQML     ),
    .SDRAM_DQMH     ( SDRAM_DQMH     ),
    .SDRAM_nWE      ( SDRAM_nWE      ),
    .SDRAM_nCAS     ( SDRAM_nCAS     ),
    .SDRAM_nRAS     ( SDRAM_nRAS     ),
    .SDRAM_nCS      ( SDRAM_nCS      ),
    .SDRAM_CLK      ( SDRAM_CLK      ),
    .SDRAM_CKE      ( SDRAM_CKE      ),
    .video_r        ( video_r        ),
    .video_g        ( video_g        ),
    .video_b        ( video_b        ),
    .video_hs       ( video_hs       ),
    .video_vs       ( video_vs       ),
    .video_lhbl     ( video_lhbl     ),
    .video_lvbl     ( video_lvbl     ),
    .video_pxl_cen  (                ),
    .audio_l        ( audio_l        ),
    .audio_r        ( audio_r        ),
    .led            ( led            )
);

endmodule
