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

module jtframe_pocket_sync #(
    parameter W = 1,
    parameter [W-1:0] RESET = {W{1'b0}}
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [W-1:0] din,
    output reg  [W-1:0] dout
);

    reg [W-1:0] meta;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            meta <= RESET;
            dout <= RESET;
        end else begin
            meta <= din;
            dout <= meta;
        end
    end

endmodule
