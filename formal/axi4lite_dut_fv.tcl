# Run from repo root: jg -no_gui formal/axi4lite_dut_fv.tcl
clear -all
analyze -sv12 rtl/axi4lite_slave.sv formal/axi4lite_dut_fv.sv
elaborate -top axi4lite_dut_fv      ;# MEM_WORDS=4 is set inside the harness
clock aclk
reset -expression {!aresetn}
prove -all
report -summary
