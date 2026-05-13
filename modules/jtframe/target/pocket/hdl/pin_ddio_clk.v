// megafunction wizard: %ALTDDIO_OUT%
// Lightweight copy of the single-bit DDR clock output cell used by
// working Pocket APF shells.

`timescale 1 ps / 1 ps
module pin_ddio_clk (
    input   [0:0] datain_h,
    input   [0:0] datain_l,
    input         outclock,
    output  [0:0] dataout
);

    wire [0:0] sub_wire0;
    assign dataout = sub_wire0[0:0];

    altddio_out ALTDDIO_OUT_component (
        .datain_h   ( datain_h   ),
        .datain_l   ( datain_l   ),
        .outclock   ( outclock   ),
        .dataout    ( sub_wire0  ),
        .aclr       ( 1'b0       ),
        .aset       ( 1'b0       ),
        .oe         ( 1'b1       ),
        .oe_out     (            ),
        .outclocken ( 1'b1       ),
        .sclr       ( 1'b0       ),
        .sset       ( 1'b0       )
    );

    defparam
        ALTDDIO_OUT_component.extend_oe_disable       = "OFF",
        ALTDDIO_OUT_component.intended_device_family  = "Cyclone V",
        ALTDDIO_OUT_component.invert_output           = "OFF",
        ALTDDIO_OUT_component.lpm_hint                = "UNUSED",
        ALTDDIO_OUT_component.lpm_type                = "altddio_out",
        ALTDDIO_OUT_component.oe_reg                  = "UNREGISTERED",
        ALTDDIO_OUT_component.power_up_high           = "OFF",
        ALTDDIO_OUT_component.width                   = 1;

endmodule
