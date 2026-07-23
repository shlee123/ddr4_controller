// SPDX-License-Identifier: MIT
// M34 controller/PHY boundary with per-byte training and pin isolation.
`timescale 1ns/1ps

module ddr4_phy_wrapper #(
  parameter integer DQ_W = 16,
  parameter integer DM_W = DQ_W/8,
  parameter integer TAP_W = 5,
  parameter integer MIN_EYE_TAPS = 3
)(
  input  wire                    clk,
  input  wire                    rst_n,
  input  wire                    controller_init_done,
  input  wire [DM_W-1:0]         lane_sample_ok,
  output reg                     phy_init_done,
  output reg                     phy_init_fail,
  output reg                     training_busy,
  output reg  [1:0]              training_phase,
  output reg  [DM_W*TAP_W-1:0]   write_level_tap,
  output reg  [DM_W*TAP_W-1:0]   read_level_tap,

  input  wire [DQ_W-1:0]         ctl_dq_out,
  input  wire                    ctl_dq_oe,
  input  wire [DM_W-1:0]         ctl_dqs_t_out,
  input  wire [DM_W-1:0]         ctl_dqs_c_out,
  input  wire                    ctl_dqs_oe,
  input  wire [DM_W-1:0]         ctl_dm_n_out,
  input  wire                    ctl_dm_oe,
  output wire [DQ_W-1:0]         ctl_dq_in,

  inout  wire [DQ_W-1:0]         ddr_dq,
  inout  wire [DM_W-1:0]         ddr_dqs_t,
  inout  wire [DM_W-1:0]         ddr_dqs_c,
  inout  wire [DM_W-1:0]         ddr_dm_n
);
  localparam [1:0] PH_WRITE = 2'd0, PH_READ = 2'd1, PH_DONE = 2'd2, PH_FAIL = 2'd3;
  localparam integer MAX_TAP = (1 << TAP_W) - 1;

  reg [TAP_W-1:0] tap;
  reg [DM_W-1:0] first_valid_seen;
  reg [TAP_W-1:0] first_valid [0:DM_W-1];
  reg [TAP_W-1:0] last_valid [0:DM_W-1];
  integer lane;
  integer width;
  reg stage_bad;

  assign ddr_dq    = (phy_init_done && ctl_dq_oe)  ? ctl_dq_out    : {DQ_W{1'bz}};
  assign ddr_dqs_t = (phy_init_done && ctl_dqs_oe) ? ctl_dqs_t_out : {DM_W{1'bz}};
  assign ddr_dqs_c = (phy_init_done && ctl_dqs_oe) ? ctl_dqs_c_out : {DM_W{1'bz}};
  assign ddr_dm_n  = (phy_init_done && ctl_dm_oe)  ? ctl_dm_n_out  : {DM_W{1'bz}};
  assign ctl_dq_in = ddr_dq;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phy_init_done   <= 1'b0;
      phy_init_fail   <= 1'b0;
      training_busy   <= 1'b0;
      training_phase  <= PH_WRITE;
      tap             <= {TAP_W{1'b0}};
      first_valid_seen <= {DM_W{1'b0}};
      write_level_tap <= {(DM_W*TAP_W){1'b0}};
      read_level_tap  <= {(DM_W*TAP_W){1'b0}};
      for (lane = 0; lane < DM_W; lane = lane + 1) begin
        first_valid[lane] <= {TAP_W{1'b0}};
        last_valid[lane]  <= {TAP_W{1'b0}};
      end
    end else if (!controller_init_done) begin
      phy_init_done   <= 1'b0;
      phy_init_fail   <= 1'b0;
      training_busy   <= 1'b0;
      training_phase  <= PH_WRITE;
      tap             <= {TAP_W{1'b0}};
      first_valid_seen <= {DM_W{1'b0}};
    end else if (!phy_init_done && !phy_init_fail) begin
      training_busy <= 1'b1;
      for (lane = 0; lane < DM_W; lane = lane + 1) begin
        if (lane_sample_ok[lane]) begin
          if (!first_valid_seen[lane]) begin
            first_valid[lane] <= tap;
            first_valid_seen[lane] <= 1'b1;
          end
          last_valid[lane] <= tap;
        end
      end

      if (tap == MAX_TAP[TAP_W-1:0]) begin
        stage_bad = 1'b0;
        for (lane = 0; lane < DM_W; lane = lane + 1) begin
          width = last_valid[lane] - first_valid[lane] + 1;
          if (!first_valid_seen[lane] || (width < MIN_EYE_TAPS)) begin
            stage_bad = 1'b1;
          end else if (training_phase == PH_WRITE) begin
            write_level_tap[lane*TAP_W +: TAP_W] <=
              first_valid[lane] + ((last_valid[lane] - first_valid[lane]) >> 1);
          end else begin
            read_level_tap[lane*TAP_W +: TAP_W] <=
              first_valid[lane] + ((last_valid[lane] - first_valid[lane]) >> 1);
          end
        end

        if (!stage_bad) begin
          if (training_phase == PH_WRITE) begin
            training_phase   <= PH_READ;
            tap              <= {TAP_W{1'b0}};
            first_valid_seen <= {DM_W{1'b0}};
          end else begin
            training_phase <= PH_DONE;
            training_busy  <= 1'b0;
            phy_init_done  <= 1'b1;
          end
        end else begin
          training_phase <= PH_FAIL;
          training_busy  <= 1'b0;
          phy_init_fail  <= 1'b1;
        end
      end else begin
        tap <= tap + {{(TAP_W-1){1'b0}},1'b1};
      end
    end
  end
endmodule
