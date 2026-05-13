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

module jtframe_pocket_clocks(
    input  wire clk_74a,
    input  wire game_rst,

    output wire clk_sys,
    output wire clk_rom,
    output wire clk_pico,
    output wire clk24,
    output wire clk48,
    output wire clk96,
    output wire sdram_clk,
    output wire pll_locked,
    output wire rst24,
    output wire rst48,
    output wire rst96,
    output wire video_rgb_clock,
    output wire video_rgb_clock_90
);

`ifdef SIMULATION
    assign clk48 = clk_74a;
    assign clk24 = clk_74a;
    assign clk96 = clk_74a;
    assign video_rgb_clock = clk_74a;
    assign video_rgb_clock_90 = clk_74a;
    assign pll_locked = 1'b1;
`else
    jtframe_pocket_pll u_pll(
        .refclk         ( clk_74a             ),
        .rst            ( 1'b0                ),
        .outclk_48      ( clk48               ),
        .outclk_24      ( clk24               ),
        .outclk_96      ( clk96               ),
        .outclk_pix     ( video_rgb_clock     ),
        .outclk_pix_90  ( video_rgb_clock_90  ),
        .locked         ( pll_locked          )
    );
`endif

`ifdef JTFRAME_SDRAM96
    assign clk_rom = clk96;
`else
    assign clk_rom = clk48;
`endif
    // SDRAM command/data signals are generated in clk_rom; keep the pin clock
    // in the same domain, especially for JTFRAME_SDRAM96 cores.
    assign sdram_clk = clk_rom;
    assign clk_sys  = clk_rom;
    assign clk_pico = clk48;

    jtframe_rst_sync u_reset96(
        .rst      ( game_rst ),
        .clk      ( clk96    ),
        .rst_sync ( rst96    )
    );

    jtframe_rst_sync u_reset48(
        .rst      ( game_rst ),
        .clk      ( clk48    ),
        .rst_sync ( rst48    )
    );

    jtframe_rst_sync u_reset24(
        .rst      ( game_rst ),
        .clk      ( clk24    ),
        .rst_sync ( rst24    )
    );

endmodule
