# Run from repo root: jg -no_gui formal/axi4lite_dut_fv_sva.tcl
clear -all
analyze -sv12 rtl/axi4lite_slave.sv formal/axi4lite_dut_fv_sva.sv
elaborate -top axi4lite_dut_fv_sva
clock aclk
reset -expression {!aresetn}
prove -all
report -summary
