/*
  Package for the bn128 curve https://github.com/ethereum/py_ecc/blob/master/py_ecc/bn128/bn128_curve.py

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

package bn128_pkg;

  /////////////////////////// Parameters ///////////////////////////
  localparam DAT_BITS = 256;
  localparam [DAT_BITS-1:0] P = 256'd21888242871839275222246405745257275088696311157297823662689037894645226208583;
  localparam WINDOW_BITS = 4;
  localparam WINDOW_ENT = (1 << WINDOW_BITS) - 1;

  // Parameters used during Montgomery multiplication
  localparam [255:0] MONT_MASK = 256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  localparam [255:0] MONT_FACTOR = 256'hf57a22b791888c6bd8afcbd01833da809ede7d651eca6ac987d20782e4866389;
  localparam int MONT_REDUCE_BITS = 256;
  localparam [250:0] MONT_RECIP_SQ = 251'h6d89f71cab8351f47ab1eff0a417ff6b5e71911d44501fbf32cfc5b538afa89; // Required for conversion into Montgomery form


  /////////////////////////// Typedefs ///////////////////////////
  typedef logic [DAT_BITS-1:0] fe_t;
  typedef fe_t [1:0] fe2_t;

  // Jacobian coordinates for Fp and Fp2 elements
  typedef struct packed {
    fe_t z;
    fe_t y;
    fe_t x;
  } jb_point_t;

  typedef struct packed {
    fe2_t z;
    fe2_t y;
    fe2_t x;
  } fp2_jb_point_t;

  // Affine points for Fp and Fp2 elements
  typedef struct packed {
    fe_t y;
    fe_t x;
  } af_point_t;

  typedef struct packed {
    fe2_t y;
    fe2_t x;
  } fp2_af_point_t;

  // Generator points
  fe_t G1X = 256'd1;
  fe_t G1Y = 256'h2;

  af_point_t G1_AF = '{x:G1X, y:G1Y};
  jb_point_t G1_JB = '{x:G1X, y:G1Y, z:256'd1};

  fe2_t G2X = {'d10857046999023057135944570762232829481370756359578518086990519993285655852781, 'd11559732032986387107991004021392285783925812861821192530917403151452391805634};
  fe2_t G2Y = {'d8495653923123431417604973247489272438418190587263600148770280649306958101930, 'd4082367875863433681332203403145435568316851327593401208105741076214120093531};
  fe2_t FE2_ONE = {256'd0, 256'd1};

  fp2_af_point_t G2_AF = '{x:G2X, y:G2Y};
  fp2_jb_point_t G2_JB = '{x:G2X, y:G2Y, z:FE2_ONE};


  /////////////////////////// Functions ///////////////////////////
  // Basic arithmetic functions for fe_t and fe2_t
  function fe_t fe_add(fe_t a, b);
    logic [$bits(fe_t):0] a_, b_;
    a_ = a;
    b_ = b;
    fe_add = a_ + b_ >= P ? a_ + b_ - P : a_ + b_;
  endfunction

  function fe2_t fe2_add(fe2_t a, b);
    fe2_add[0] = fe_add(a[0], b[0]);
    fe2_add[1] = fe_add(a[1] ,b[1]);
  endfunction

  function fe_t fe_sub(fe_t a, b);
    logic [$bits(fe_t):0] a_, b_;
    a_ = a;
    b_ = b;
    fe_sub = b_ > a_ ? a_- b_ + P : a_ - b_;
  endfunction

  function fe2_t fe2_sub(fe2_t a, b);
    fe2_sub[0] = fe_sub(a[0], b[0]);
    fe2_sub[1] = fe_sub(a[1], b[1]);
  endfunction

  function fe_t fe_mul(fe_t a, b);
    logic [$bits(fe_t)*2:0] m_;
    m_ = a * b;
    fe_mul = m_ % P;
  endfunction

  function fe2_t fe2_mul(fe2_t a, b);
    fe2_mul[0] = fe_sub(fe_mul(a[0], b[0]), fe_mul(a[1], b[1]));
    fe2_mul[1] = fe_add(fe_mul(a[0], b[1]), fe_mul(a[1], b[0]));
  endfunction

   // Inversion using extended euclidean algorithm
  function fe_t fe_inv(fe_t a, b = 1);
     fe_t u, v;
     logic [$bits(fe_t):0] x1, x2;

     u = a; v = P;
     x1 = b; x2 = 0;
     while (u != 1 && v != 1) begin
       while (u % 2 == 0) begin
         u = u / 2;
         if (x1 % 2 == 0)
           x1 = x1 / 2;
         else
           x1 = (x1 + P) / 2;
       end
       while (v % 2 == 0) begin
         v = v / 2;
         if (x2 % 2 == 0)
           x2 = x2 / 2;
         else
           x2 = (x2 + P) / 2;
       end
       if (u >= v) begin
         u = u - v;
         x1 = fe_sub(x1, x2);
       end else begin
         v = v - u;
         x2 = fe_sub(x2, x1);
       end
     end
     if (u == 1)
       return x1;
     else
       return x2;
  endfunction

  function fe2_t fe2_inv(fe2_t a);
    fe_t factor, t0, t1;
    t0 = fe_mul(a[0], a[0]);
    t1 = fe_mul(a[1], a[1]);
    factor = fe_inv(fe_add(t0, t1));
    fe2_inv[0]= fe_mul(a[0], factor);
    fe2_inv[1] = fe_mul(fe_sub(P, a[1]), factor);
  endfunction

  // Function for point doubling
  function jb_point_t dbl_jb_point(input jb_point_t p);
    fe_t I_X, I_Y, I_Z, A, B, C, D, X, Y, Z;
    if (p.z == 0) return p;
    I_X = p.x;
    I_Y = p.y;
    I_Z = p.z;
    A = fe_mul(I_Y, I_Y);
    B = fe_mul(fe_mul(4, I_X), A);
    C = fe_mul(fe_mul(8, A), A);
    D = fe_mul(fe_mul(3, I_X), I_X);
    X = fe_mul(D, D);
    X = fe_sub(X, fe_mul(2, B));
    Y = fe_mul(D, fe_sub(B, X));
    Y = fe_sub(Y, C);
    Z = fe_mul(fe_mul(2, I_Y), I_Z);
    dbl_jb_point.x = X;
    dbl_jb_point.y = Y;
    dbl_jb_point.z = Z;
    return dbl_jb_point;
  endfunction

  // Function for point addition
  function jb_point_t add_jb_point(jb_point_t p1, p2);
    fe_t A, U1, U2, S1, S2, H, H3, R;
    if (p1.z == 0) return p2;
    if (p2.z == 0) return p1;
    if (p1.y == p2.y && p1.x == p2.x) return (dbl_jb_point(p1));
    U1 = fe_mul(p1.x, p2.z);
    U1 = fe_mul(U1, p2.z);
    U2 = fe_mul(p2.x, p1.z);
    U2 = fe_mul(U2, p1.z);
    S1 = fe_mul(p1.y, p2.z);
    S1 = fe_mul(fe_mul(S1, p2.z), p2.z);
    S2 = fe_mul(p2.y, p1.z);
    S2 = fe_mul(fe_mul(S2, p1.z), p1.z);
    H = fe_sub(U2, U1);
    R = fe_sub(S2, S1);
    H3 = fe_mul(fe_mul(H, H), H);
    A = fe_mul(fe_mul(fe_mul(2, U1), H), H);
    add_jb_point.z = fe_mul(fe_mul(H, p1.z), p2.z);
    add_jb_point.x = fe_mul(R, R);
    add_jb_point.x = fe_sub(add_jb_point.x, H3);
    add_jb_point.x = fe_sub(add_jb_point.x, A);
    A = fe_mul(fe_mul(U1, H), H);
    A = fe_sub(A, add_jb_point.x);
    A = fe_mul(A, R);
    add_jb_point.y = fe_mul(S1, H3);
    add_jb_point.y = fe_sub(A, add_jb_point.y);
  endfunction

  // Function for point multiplication
  function jb_point_t point_mult(input logic [DAT_BITS-1:0] c, jb_point_t p);
    jb_point_t result, addend;
    result = 0;
    addend = p;
    while (c > 0) begin
      if (c[0]) begin
        result = add_jb_point(result, addend);
      end
      addend = dbl_jb_point(addend);
      c = c >> 1;
    end
    return result;
  endfunction

  // Function for G1 multiexp, takes an array of scalars and points
  function jb_point_t multiexp(input logic [DAT_BITS-1:0] s [], jb_point_t p []);
    jb_point_t res;
    res = 0;
    for (int i = 0; i < s.size(); i++) begin
      res = add_jb_point(point_mult(s[i], p[i]), res);
    end
    return res;
  endfunction

  // Function for G1 multiexp, using batched doubling
  function jb_point_t multiexp_batch(input logic [DAT_BITS-1:0] s [], jb_point_t p []);
    jb_point_t res;
    res = 0;
    for (int i = DAT_BITS-1; i >= 0; i--) begin
      res = dbl_jb_point(res);
      for (int j = 0; j < s.size(); j++) begin
        if (s[j][i] == 1) begin
          res = add_jb_point(p[j], res);
        end
      end
    end
    return res;
  endfunction

  // Function for G1 multiexp, using batch doubles and window method
  function jb_point_t multiexp_window(input logic [DAT_BITS-1:0] s [], jb_point_t p []);
    // First do pre-computation
    jb_point_t p_prec [];
    jb_point_t res;
    int j, i, p_val;
    i = 0;
    j = 0;
    p_val = 0;
    p_prec = new[WINDOW_ENT*s.size()];

    // Pre computation stage
    for (i = 0; i < p.size(); i++) begin
      p_prec[(WINDOW_ENT*i)] = p[i];
      for (j = 2; j <= WINDOW_ENT; j++) begin
        p_prec[(WINDOW_ENT*i)+(j-1)] = add_jb_point(p_prec[(WINDOW_ENT*i)+(j-2)], p_prec[WINDOW_ENT*i]);
      end
    end

    j = DAT_BITS-1;
    res = 0;

    while (j >= 0) begin
      i = 0;
      while (i < WINDOW_BITS) begin
        res = dbl_jb_point(res);
        i++;
        if (i > j) break;
      end

      for (int i = 0; i < s.size(); i++) begin
        // Get value to use for window
        p_val = 0;
        for (int k = 0; k < WINDOW_BITS; k++) begin
          if (j-k < 0) break;
          p_val += s[i][j-k] << (WINDOW_BITS-k-1);
        end
        if (p_val > 0)
          res = add_jb_point(res, p_prec[(i*WINDOW_ENT) + p_val-1]);
      end
      j = j - WINDOW_BITS;
    end
    return res;
  endfunction

  // Montgomery multiplication in fe
  function fe_t fe_mul_mont(fe_t a, b);
    logic [$bits(fe_t)*2:0] m_, tmp;
    m_ = a * b;
    tmp = (m_ & MONT_MASK) * MONT_FACTOR;
    tmp = tmp & MONT_MASK;
    tmp = tmp * P;
    tmp = tmp + m_;
    fe_mul_mont = tmp >> MONT_REDUCE_BITS;
  endfunction

  function fe_t fe_to_mont(fe_t a);
    fe_to_mont = fe_mul_mont(a, MONT_RECIP_SQ);
  endfunction

  function fe_t fe_from_mont(fe_t a);
    fe_from_mont = fe_mul_mont(a, 256'd1);
  endfunction

  // Functions for converting to affine, and printing
  function af_point_t to_affine(jb_point_t p);
    fe_t z_;
    z_ = fe_mul(p.z, p.z);
    to_affine.x = fe_mul(p.x, fe_inv(z_));
    z_ = fe_mul(z_, p.z);
    to_affine.y = fe_mul(p.y, fe_inv(z_));
  endfunction

  task print_jb_point(jb_point_t p);
    $display("x:0x%h", p.x);
    $display("y:0x%h", p.y);
    $display("z:0x%h", p.z);
  endtask

  task print_fp2_jb_point(fp2_jb_point_t p);
    $display("x:(c1:0x%h, c0:0x%h)", p.x[1], p.x[0]);
    $display("y:(c1:0x%h, c0:0x%h)", p.y[1], p.y[0]);
    $display("z:(c1:0x%h, c0:0x%h)", p.z[1], p.z[0]);
  endtask

  task print_af_point(af_point_t p);
    $display("x:(0x%h)", p.x);
    $display("y:(0x%h)", p.y);
  endtask

  task print_fp2_af_point(fp2_af_point_t p);
    $display("x:(c1:0x%h, c0:0x%h)", p.x[1], p.x[0]);
    $display("y:(c1:0x%h, c0:0x%h)", p.y[1], p.y[0]);
  endtask

endpackage