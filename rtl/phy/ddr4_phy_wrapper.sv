// SPDX-License-Identifier: MIT
// M34 controller/PHY boundary with DDR4 MRS-controlled per-byte training.
`timescale 1ns/1ps

module ddr4_phy_wrapper #(
  parameter integer DQ_W = 16,
  parameter integer DM_W = DQ_W/8,
  parameter integer TAP_W = 5,
  parameter integer MIN_EYE_TAPS = 3,
  parameter integer T_MOD_CK = 24
)(
  input  wire                    clk,
  input  wire                    rst_n,
  input  wire                    controller_init_done,
  input  wire [16:0]             mr1_normal,
  input  wire [16:0]             mr3_normal,
  input  wire [DM_W-1:0]         lane_sample_ok,
  output reg                     phy_init_done,
  output reg                     phy_init_fail,
  output reg                     training_busy,
  output reg  [2:0]              training_phase,
  output reg  [DM_W*TAP_W-1:0]   write_level_tap,
  output reg  [DM_W*TAP_W-1:0]   read_level_tap,
  output reg                     train_mrs_valid,
  output reg  [2:0]              train_mrs_index,
  output reg  [16:0]             train_mrs_value,

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
  localparam [2:0] PH_WL_ENABLE = 3'd0, PH_WRITE = 3'd1,
                   PH_WL_DISABLE = 3'd2, PH_MPR_ENABLE = 3'd3,
                   PH_READ = 3'd4, PH_MPR_DISABLE = 3'd5,
                   PH_DONE = 3'd6, PH_FAIL = 3'd7;
  localparam integer MAX_TAP = (1 << TAP_W) - 1;

  reg [TAP_W-1:0] tap;
  reg [15:0] wait_cnt;
  reg command_sent;
  reg [DM_W-1:0] first_valid_seen;
  reg [TAP_W-1:0] first_valid [0:DM_W-1];
  reg [TAP_W-1:0] last_valid [0:DM_W-1];
  integer lane;
  integer width;
  reg stage_bad;

  assign ddr_dq    = (phy_init_done && ctl_dq_oe)  ? ctl_dq_out     : {DQ_W{1'bz}};
  assign ddr_dqs_t = (phy_init_done && ctl_dqs_oe) ? ctl_dqs_t_out  : {DM_W{1'bz}};
  assign ddr_dqs_c = (phy_init_done && ctl_dqs_oe) ? ctl_dqs_c_out  : {DM_W{1'bz}};
  assign ddr_dm_n  = (phy_init_done && ctl_dm_oe)  ? ctl_dm_n_out   : {DM_W{1'bz}};
  assign ctl_dq_in = ddr_dq;

  task automatic start_mrs(input [2:0] index, input [16:0] value);
    begin
      train_mrs_valid <= 1'b1;
      train_mrs_index <= index;
      train_mrs_value <= value;
      command_sent    <= 1'b1;
      wait_cnt        <= T_MOD_CK;
    end
  endtask

  task automatic clear_eye;
    begin
      tap <= {TAP_W{1'b0}};
      first_valid_seen <= {DM_W{1'b0}};
      for (lane = 0; lane < DM_W; lane = lane + 1) begin
        first_valid[lane] <= {TAP_W{1'b0}};
        last_valid[lane]  <= {TAP_W{1'b0}};
      end
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phy_init_done <= 1'b0;
      phy_init_fail <= 1'b0;
      training_busy <= 1'b0;
      training_phase <= PH_WL_ENABLE;
      train_mrs_valid <= 1'b0;
      train_mrs_index <= 3'd0;
      train_mrs_value <= 17'd0;
      command_sent <= 1'b0;
      wait_cnt <= 16'd0;
      tap <= {TAP_W{1'b0}};
      first_valid_seen <= {DM_W{1'b0}};
      write_level_tap <= {(DM_W*TAP_W){1'b0}};
      read_level_tap <= {(DM_W*TAP_W){1'b0}};
      for (lane = 0; lane < DM_W; lane = lane + 1) begin
        first_valid[lane] <= {TAP_W{1'b0}};
        last_valid[lane]  <= {TAP_W{1'b0}};
      end
    end else if (!controller_init_done) begin
      phy_init_done <= 1'b0;
      phy_init_fail <= 1'b0;
      training_busy <= 1'b0;
      training_phase <= PH_WL_ENABLE;
      train_mrs_valid <= 1'b0;
      command_sent <= 1'b0;
      wait_cnt <= 16'd0;
      clear_eye();
    end else if (!phy_init_done && !phy_init_fail) begin
      training_busy <= 1'b1;
      train_mrs_valid <= 1'b0;
      if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;

      case (training_phase)
        PH_WL_ENABLE: begin
          if (!command_sent) start_mrs(3'd1, mr1_normal | 17'h00080);
          else if (wait_cnt == 0) begin
            command_sent <= 1'b0;
            training_phase <= PH_WRITE;
            clear_eye();
          end
        end

        PH_WRITE, PH_READ: begin
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
              if (!first_valid_seen[lane] || (width < MIN_EYE_TAPS))
                stage_bad = 1'b1;
              else if (training_phase == PH_WRITE)
                write_level_tap[lane*TAP_W +: TAP_W] <=
                  first_valid[lane] + ((last_valid[lane] - first_valid[lane]) >> 1);
              else
                read_level_tap[lane*TAP_W +: TAP_W] <=
                  first_valid[lane] + ((last_valid[lane] - first_valid[lane]) >> 1);
            end
            if (stage_bad) begin
              training_phase <= PH_FAIL;
              training_busy <= 1'b0;
              phy_init_fail <= 1'b1;
            end else if (training_phase == PH_WRITE) begin
              training_phase <= PH_WL_DISABLE;
              command_sent <= 1'b0;
            end else begin
              training_phase <= PH_MPR_DISABLE;
              command_sent <= 1'b0;
            end
          end else tap <= tap + {{(TAP_W-1){1'b0}},1'b1};
        end

        PH_WL_DISABLE: begin
          if (!command_sent) start_mrs(3'd1, mr1_normal & ~17'h00080);
          else if (wait_cnt == 0) begin
            command_sent <= 1'b0;
            training_phase <= PH_MPR_ENABLE;
          end
        end
        PH_MPR_ENABLE: begin
          if (!command_sent) start_mrs(3'd3, mr3_normal | 17'h00004);
          else if (wait_cnt == 0) begin
            command_sent <= 1'b0;
            training_phase <= PH_READ;
            clear_eye();
          end
        end
        PH_MPR_DISABLE: begin
          if (!command_sent) start_mrs(3'd3, mr3_normal & ~17'h00004);
          else if (wait_cnt == 0) begin
            training_phase <= PH_DONE;
            training_busy <= 1'b0;
            phy_init_done <= 1'b1;
          end
        end
        default: begin
          training_phase <= PH_FAIL;
          training_busy <= 1'b0;
          phy_init_fail <= 1'b1;
        end
      endcase
    end
  end
endmodule
