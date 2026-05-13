set s18_vdp_cells [get_keepers -nowarn {*|jts18_vdp:u_vdp|ym7101:u_vdp|*}]
if {[get_collection_size $s18_vdp_cells] > 0} {
    set_multicycle_path -from $s18_vdp_cells -setup 2
    set_multicycle_path -from $s18_vdp_cells -hold 1
}

foreach s18_vdp_node {
    *|jts18_vdp:u_vdp|clk2
    *|jts18_vdp:u_vdp|rst_n
    *|jts18_vdp:u_vdp|edclk_l
} {
    set s18_vdp_nodes [get_keepers -nowarn $s18_vdp_node]
    if {[get_collection_size $s18_vdp_nodes] > 0} {
        set_multicycle_path -from $s18_vdp_nodes -setup 2
        set_multicycle_path -from $s18_vdp_nodes -hold 1
    }
}

unset s18_vdp_cells
unset s18_vdp_node
unset s18_vdp_nodes
