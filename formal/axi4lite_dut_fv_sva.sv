// JasperGold SVA harness for the real axi4lite_slave (MEM_WORDS reduced to 4).
// Same checks as formal/axi4lite_dut_fv.sv (Yosys), written as concurrent SVA.
// Reset is applied by the Jasper script:  reset -expression {!aresetn}
// All inputs are free primary inputs (master side is unconstrained except
// for the VALID/payload persistence assumptions below).
module axi4lite_dut_fv_sva (
  input        aclk,
  input        aresetn,
  input [31:0] awaddr, wdata, araddr,
  input [3:0]  wstrb,
  input        awvalid, wvalid, bready, arvalid, rready
);
  wire        awready, wready, bvalid, arready, rvalid;
  wire [1:0]  bresp, rresp;
  wire [31:0] rdata;

  // Reduced memory depth keeps proofs inexpensive; RTL is unchanged.
  axi4lite_slave #(.MEM_WORDS(4)) dut (.*);

  // Transaction credits: accepted requests minus delivered responses.
  logic [5:0] aw_credit, w_credit, r_credit;
  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      aw_credit <= '0; w_credit <= '0; r_credit <= '0;
    end else begin
      aw_credit <= aw_credit + (awvalid && awready) - (bvalid && bready);
      w_credit  <= w_credit  + (wvalid  && wready ) - (bvalid && bready);
      r_credit  <= r_credit  + (arvalid && arready) - (rvalid && rready);
    end
  end

  default clocking cb @(posedge aclk); endclocking
  default disable iff (!aresetn);

  // ---------------- Assumptions: legal master behaviour ----------------
  // VALID and payload persist until READY. READY may stall indefinitely.
  m_aw_valid_hold: assume property ($past(aresetn) && $past(awvalid && !awready) |-> awvalid);
  m_aw_addr_hold:  assume property ($past(aresetn) && $past(awvalid && !awready) |-> awaddr == $past(awaddr));
  m_w_valid_hold:  assume property ($past(aresetn) && $past(wvalid && !wready)   |-> wvalid);
  m_w_data_hold:   assume property ($past(aresetn) && $past(wvalid && !wready)   |-> wdata == $past(wdata));
  m_w_strb_hold:   assume property ($past(aresetn) && $past(wvalid && !wready)   |-> wstrb == $past(wstrb));
  m_ar_valid_hold: assume property ($past(aresetn) && $past(arvalid && !arready) |-> arvalid);
  m_ar_addr_hold:  assume property ($past(aresetn) && $past(arvalid && !arready) |-> araddr == $past(araddr));

  // ---------------- Assertions: slave behaviour ----------------
  // Responses only for accepted requests, legal codes (OKAY=00, DECERR=11).
  a_b_aw_credit:  assert property (bvalid |-> aw_credit > 0);
  a_b_w_credit:   assert property (bvalid |-> w_credit  > 0);
  a_bresp_legal:  assert property (bvalid |-> (bresp == 2'b00 || bresp == 2'b11));
  a_r_credit:     assert property (rvalid |-> r_credit  > 0);
  a_rresp_legal:  assert property (rvalid |-> (rresp == 2'b00 || rresp == 2'b11));

  // B/R channel stability while the master stalls READY.
  a_b_valid_hold: assert property ($past(aresetn) && $past(bvalid && !bready) |-> bvalid);
  a_b_resp_hold:  assert property ($past(aresetn) && $past(bvalid && !bready) |-> bresp == $past(bresp));
  a_r_valid_hold: assert property ($past(aresetn) && $past(rvalid && !rready) |-> rvalid);
  a_r_data_hold:  assert property ($past(aresetn) && $past(rvalid && !rready) |-> rdata == $past(rdata));
  a_r_resp_hold:  assert property ($past(aresetn) && $past(rvalid && !rready) |-> rresp == $past(rresp));

  // ---------------- Covers: assumptions must not over-constrain ----------------
  c_b_okay:     cover property (bvalid && bready && bresp == 2'b00);
  c_b_decerr:   cover property (bvalid && bready && bresp == 2'b11);
  c_b_stall:    cover property (bvalid && !bready ##1 bvalid && !bready ##1 bvalid && bready);
  c_r_stall:    cover property (rvalid && !rready ##1 rvalid && !rready ##1 rvalid && rready);
  c_r_decerr:   cover property (rvalid && rready && rresp == 2'b11);
endmodule
