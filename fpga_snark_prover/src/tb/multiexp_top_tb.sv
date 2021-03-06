/*
  Testbench for the multiexp core.

  Copyright (C) 2019  Benjamin Devlin

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
`timescale 1ps/1ps

module multiexp_top_tb ();
import bn128_pkg::*;
import common_pkg::*;

localparam CLK_PERIOD = 100;

localparam NUM_IN = 16;
localparam NUM_CORES = 8;
localparam NUM_ARITH = 1;

localparam DAT_BITS = $bits(fe_t);

logic clk, rst;

localparam DAT_IN0 = $bits(fe_t) + $bits(jb_point_t);

if_axi_stream #(.DAT_BYTS(($bits(fe_t)+7)/8), .CTL_BITS(8)) i_pnt_scl_if (clk);
if_axi_stream #(.DAT_BYTS(($bits(fe_t)+7)/8), .CTL_BITS(8)) o_pnt_if (clk);

jb_point_t in_p [];
fe_t in_s [];
logic [$clog2(DAT_BITS)-1:0] cnt;
logic [63:0] num_in;

initial begin
  rst = 0;
  repeat(2) #(20*CLK_PERIOD) rst = ~rst;
end

initial begin
  clk = 0;
  forever #(CLK_PERIOD/2) clk = ~clk;
end

multiexp_fp2_top #(
  .FP_TYPE            ( jb_point_t ),
  .FE_TYPE            ( fe_t       ),
  .FP2_TYPE           ( jb_point_t ),
  .FE2_TYPE           ( fe_t       ),      
  .P                  ( P          ),
  .NUM_CORES          ( NUM_CORES ),
  .NUM_ARITH          ( NUM_ARITH ),
  .REDUCE_BITS        ( MONT_REDUCE_BITS ),
  .FACTOR             ( MONT_FACTOR      ),
  .MASK               ( MONT_MASK        ),
  .CONST_3            ( CONST_3    ),
  .CONST_4            ( CONST_4    ),
  .CONST_8            ( CONST_8    )
)
multiexp_top (
  .i_clk ( clk ),
  .i_rst ( rst ),
  .i_pnt_scl_if ( i_pnt_scl_if ),
  .i_num_in ( num_in ),
  .o_pnt_if ( o_pnt_if )
);



task test0();
begin
  integer signed get_len, start_time, finish_time;
  logic [common_pkg::MAX_SIM_BYTS*8-1:0] get_dat;
  
  jb_point_t out;
  af_point_t expected;
  
  jb_point_t int_res [NUM_CORES];
  
  cnt = DAT_BITS-1;

  in_p = new[NUM_IN];
  in_s = new[NUM_IN];
  num_in = NUM_IN;

  $display("Running test0...");

  for (int i = 0; i < NUM_IN; i++) begin
    in_p[i] = point_mult(random_vector((DAT_BITS+7)/8) % P, jb_to_mont(G1_JB));
    $display("Input point #%d", i);
    print_jb_point(in_p[i]);
    in_s[i] = random_vector((DAT_BITS+7)/8) % P;
    $display("Key 0x%x", in_s[i]);
  end

  expected = to_affine(jb_from_mont(multiexp_batch(in_s, in_p)), 0);

  start_time = $time;
  fork
    for(int j = 0; j < DAT_BITS; j++) begin
      for (int i = 0; i < NUM_IN; i++) i_pnt_scl_if.put_stream({in_p[i], in_s[i]}, (DAT_IN0+7)/8, 0);
      cnt--;
    end
    begin
      o_pnt_if.get_stream(get_dat, get_len, 0);
    end
  join
  finish_time = $time;
  out = get_dat;
  
  $display("Expected:");
  print_af_point(expected);
  
  $display("test0 finished in %d clock cycles", (finish_time-start_time)/CLK_PERIOD);
  
  assert(to_affine(jb_from_mont(out), 0) == expected) else begin
    $display("Was:      0x%0x", to_affine(jb_from_mont(out)), 0);
    $fatal(1, "ERROR: Output did not match");
  end

  $display("test0 PASSED");
  in_p.delete();
  in_s.delete();
end
endtask;

initial begin

  i_pnt_scl_if.reset_source();
  o_pnt_if.rdy = 0;

  #(100*CLK_PERIOD);

  test0();

  #1us $finish();
end
endmodule