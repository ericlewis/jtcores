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

// JTFRAME keeps the historical clk24/clk48/clk96 names even when the actual
// MCLK family is not exactly 48 MHz. On Pocket we derive the complete game and
// scaler clock set from the same PLL so the pixel clock stays phase-related to
// the core clock.

`ifdef JTFRAME_PLL6144
    `define JTFRAME_POCKET_PLL_CLK48  "49.152000 MHz"
    `define JTFRAME_POCKET_PLL_CLK24  "24.576000 MHz"
    `define JTFRAME_POCKET_PLL_CLK96  "98.304000 MHz"
    `define JTFRAME_POCKET_PLL_PIX    "6.144000 MHz"
    `define JTFRAME_POCKET_PLL_PIX90  "40690 ps"
`elsif JTFRAME_PLL6293
    `define JTFRAME_POCKET_PLL_CLK48  "50.318176 MHz"
    `define JTFRAME_POCKET_PLL_CLK24  "25.159088 MHz"
    `define JTFRAME_POCKET_PLL_CLK96  "100.636352 MHz"
    `define JTFRAME_POCKET_PLL_PIX    "6.289772 MHz"
    `define JTFRAME_POCKET_PLL_PIX90  "39746 ps"
`elsif JTFRAME_PLL6671
    `define JTFRAME_POCKET_PLL_CLK48  "53.391632 MHz"
    `define JTFRAME_POCKET_PLL_CLK24  "26.695816 MHz"
    `define JTFRAME_POCKET_PLL_CLK96  "106.783264 MHz"
    `define JTFRAME_POCKET_PLL_PIX    "6.673954 MHz"
    `define JTFRAME_POCKET_PLL_PIX90  "37459 ps"
`else
    `define JTFRAME_POCKET_PLL_CLK48  "48.000000 MHz"
    `define JTFRAME_POCKET_PLL_CLK24  "24.000000 MHz"
    `define JTFRAME_POCKET_PLL_CLK96  "96.000000 MHz"
    `define JTFRAME_POCKET_PLL_PIX    "6.000000 MHz"
    `define JTFRAME_POCKET_PLL_PIX90  "41667 ps"
`endif

module jtframe_pocket_pll(
    input  wire refclk,
    input  wire rst,
    output wire outclk_48,
    output wire outclk_24,
    output wire outclk_96,
    output wire outclk_pix,
    output wire outclk_pix_90,
    output wire locked
);

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(5),
        .output_clock_frequency0(`JTFRAME_POCKET_PLL_CLK48),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1(`JTFRAME_POCKET_PLL_CLK24),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .output_clock_frequency2(`JTFRAME_POCKET_PLL_CLK96),
        .phase_shift2("0 ps"),
        .duty_cycle2(50),
        .output_clock_frequency3(`JTFRAME_POCKET_PLL_PIX),
        .phase_shift3("0 ps"),
        .duty_cycle3(50),
        .output_clock_frequency4(`JTFRAME_POCKET_PLL_PIX),
        .phase_shift4(`JTFRAME_POCKET_PLL_PIX90),
        .duty_cycle4(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      ( rst ),
        .outclk   ( { outclk_pix_90, outclk_pix, outclk_96, outclk_24, outclk_48 } ),
        .locked   ( locked ),
        .fboutclk ( ),
        .fbclk    ( 1'b0 ),
        .refclk   ( refclk )
    );

endmodule

`undef JTFRAME_POCKET_PLL_CLK48
`undef JTFRAME_POCKET_PLL_CLK24
`undef JTFRAME_POCKET_PLL_CLK96
`undef JTFRAME_POCKET_PLL_PIX
`undef JTFRAME_POCKET_PLL_PIX90
