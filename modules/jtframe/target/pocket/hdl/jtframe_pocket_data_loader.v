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

// APF bridge write loader.
//
// Pocket bridge traffic arrives on clk_74a, but JTFRAME's download/programming
// path consumes ioctl writes on the game clock. Buffer slot writes through a
// tiny dual-clock FIFO so ROM bytes are not sampled across clock domains
// directly.

module jtframe_pocket_data_loader #(
    parameter [3:0] ADDRESS_MASK_UPPER_4 = 4'h0,
    parameter ADDRESS_SIZE = 27,
    parameter WRITE_MEM_CLOCK_DELAY = 12,
    parameter WRITE_MEM_EN_CYCLE_LENGTH = 1,
    parameter OUTPUT_WORD_SIZE = 1
) (
    input  wire                         clk_74a,
    input  wire                         clk_memory,
    input  wire                         bridge_wr,
    input  wire                         bridge_endian_little,
    input  wire [31:0]                  bridge_addr,
    input  wire [31:0]                  bridge_wr_data,
    input  wire                         write_ready,
    output reg                          write_en = 1'b0,
    output reg  [ADDRESS_SIZE-1:0]      write_addr = {ADDRESS_SIZE{1'b0}},
    output reg  [8*OUTPUT_WORD_SIZE-1:0] write_data = {(8*OUTPUT_WORD_SIZE){1'b0}}
);

`define JTFRAME_POCKET_MAX(x, y) ((x > y) ? x : y)

localparam WORD_SIZE = 8 * OUTPUT_WORD_SIZE;
localparam FIFO_SIZE = WORD_SIZE + 28;
localparam [27:0] OUTPUT_WORD_STEP = (OUTPUT_WORD_SIZE == 2) ? 28'd2 : 28'd1;

wire [FIFO_SIZE-1:0] fifo_out;
wire                 fifo_empty;

reg                  read_req = 1'b0;
reg                  write_req = 1'b0;
reg [31:0]           shift_data = 32'd0;
reg [27:0]           buff_bridge_addr = 28'd0;
reg                  prev_bridge_wr = 1'b0;
reg [2:0]            write_count = 3'd0;
reg [2:0]            write_state = 3'd0;
reg [5:0]            read_state = 6'd0;

wire [FIFO_SIZE-1:0] fifo_in = {shift_data[WORD_SIZE-1:0], buff_bridge_addr};

localparam WRITE_START = 3'd1;
localparam WRITE_REQ_SHIFT = 3'd2;

localparam READ_DELAY = 6'd1;
localparam READ_WRITE = 6'd2;
localparam READ_WRITE_EN_CYCLE_OFF = READ_WRITE + WRITE_MEM_EN_CYCLE_LENGTH;
localparam READ_WRITE_END_DEFAULT = WRITE_MEM_CLOCK_DELAY - 1;
localparam READ_WRITE_END =
    `JTFRAME_POCKET_MAX(READ_WRITE_END_DEFAULT, READ_WRITE_EN_CYCLE_OFF + 1);
localparam HAS_DELAY = READ_WRITE_END_DEFAULT > READ_WRITE_EN_CYCLE_OFF;

dcfifo dcfifo_component (
    .data    ( fifo_in    ),
    .rdclk   ( clk_memory ),
    .rdreq   ( read_req   ),
    .wrclk   ( clk_74a    ),
    .wrreq   ( write_req  ),
    .q       ( fifo_out   ),
    .rdempty ( fifo_empty )
);
defparam dcfifo_component.clocks_are_synchronized = "FALSE",
    dcfifo_component.intended_device_family = "Cyclone V",
    dcfifo_component.lpm_numwords = 32,
    dcfifo_component.lpm_showahead = "OFF",
    dcfifo_component.lpm_type = "dcfifo",
    dcfifo_component.lpm_width = FIFO_SIZE,
    dcfifo_component.lpm_widthu = 5,
    dcfifo_component.overflow_checking = "OFF",
    dcfifo_component.rdsync_delaypipe = 5,
    dcfifo_component.underflow_checking = "OFF",
    dcfifo_component.use_eab = "OFF",
    dcfifo_component.wrsync_delaypipe = 5;

always @(posedge clk_74a) begin
    prev_bridge_wr <= bridge_wr;

    if (~prev_bridge_wr && bridge_wr && bridge_addr[31:28] == ADDRESS_MASK_UPPER_4) begin
        write_state <= WRITE_REQ_SHIFT;
        write_req <= 1'b1;
        write_count <= 3'd0;
        shift_data <= bridge_endian_little ? bridge_wr_data : {
            bridge_wr_data[7:0], bridge_wr_data[15:8], bridge_wr_data[23:16], bridge_wr_data[31:24]
        };
        buff_bridge_addr <= bridge_addr[27:0];
    end

    case (write_state)
        WRITE_START: begin
            write_req <= 1'b1;
            write_state <= WRITE_REQ_SHIFT;
        end
        WRITE_REQ_SHIFT: begin
            write_req <= 1'b0;
            shift_data <= {8'h00, shift_data[31:WORD_SIZE]};
                buff_bridge_addr <= buff_bridge_addr + OUTPUT_WORD_STEP;
            write_count <= write_count + 3'd1;
            if (write_count == (4 / OUTPUT_WORD_SIZE) - 1) begin
                write_state <= 3'd0;
            end else begin
                write_state <= WRITE_START;
            end
        end
        default: begin
        end
    endcase
end

always @(posedge clk_memory) begin
    if (read_state != 0) begin
        read_state <= read_state + 6'd1;
    end else if (~fifo_empty && write_ready) begin
        read_state <= READ_DELAY;
        read_req <= 1'b1;
    end

    case (read_state)
        READ_DELAY: begin
            read_req <= 1'b0;
            write_en <= 1'b0;
        end
        READ_WRITE: begin
            write_en <= 1'b1;
            write_addr <= fifo_out[ADDRESS_SIZE-1:0];
            write_data <= fifo_out[WORD_SIZE+27:28];
            read_req <= 1'b0;
        end
        READ_WRITE_EN_CYCLE_OFF: begin
            write_en <= 1'b0;
            if (!HAS_DELAY) begin
                read_state <= 6'd0;
            end
        end
        READ_WRITE_END: begin
            read_state <= 6'd0;
        end
        default: begin
        end
    endcase
end

endmodule

`undef JTFRAME_POCKET_MAX
