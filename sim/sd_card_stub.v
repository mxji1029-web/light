`timescale 1ns/1ps
// Simulation stand-in for sd_card_top: same port names, serves sectors from a
// synthetic card so the catalog scan, BMP loading and PCM streaming can be
// exercised without hardware. Compiled only for testbenches that define
// TB_FAKE_SD.
module sd_card_stub(
  input        clk,
  input        rst,
  output       SD_nCS,
  output       SD_DCLK,
  output       SD_MOSI,
  input        SD_MISO,
  output       sd_init_done,
  input        sd_sec_read,
  input  [31:0] sd_sec_read_addr,
  output [7:0] sd_sec_read_data,
  output       sd_sec_read_data_valid,
  output       sd_sec_read_end,
  input        sd_sec_write,
  input  [31:0] sd_sec_write_addr,
  input  [7:0] sd_sec_write_data,
  output       sd_sec_write_data_req,
  output       sd_sec_write_end
);
localparam BMP_LEN = 921654;
localparam CAT_SEC = 2;
localparam AUD_SEC = 88000;

assign SD_nCS = 1'b0;
assign SD_DCLK = 1'b0;
assign SD_MOSI = 1'b0;
assign sd_init_done = 1'b1;
assign sd_sec_write_data_req = 1'b0;
assign sd_sec_write_end = 1'b0;

function [7:0] card_byte;
 input [31:0] sec;
 input integer off;
 integer i;
 reg [31:0] sum;
 begin
  card_byte = 8'h5a;
  if (sec==0) card_byte = 8'h00;
  else if (sec==CAT_SEC) begin
   if (off==0) card_byte="A"; else if (off==1) card_byte="L";
   else if (off==2) card_byte="Y"; else if (off==3) card_byte="1";
   else if (off<8)  card_byte=(off==4)?8'd12:8'h00;
   else if (off<12) card_byte=(off==8)?8'hC0:(off==9)?8'h57:(off==10)?8'h01:8'h00; // 88000 = 0x0157C0
   else if (off<16) begin
    sum = 12 + AUD_SEC;
    for (i=0;i<12;i=i+1) sum = sum + 100 + 100*i;
    card_byte = (off==12) ? sum[7:0] : (off==13) ? sum[15:8] : (off==14) ? sum[23:16] : sum[31:24];
   end
   else if (off<16+48) begin
    i = (off-16)%4;
    card_byte = (100+100*((off-16)/4)) >> (8*i);   // little endian LBA
   end
  end
  else if (sec>=100 && sec%100==0 && sec<100+1200 && off<54) begin
   case (off)
    0: card_byte="B"; 1: card_byte="M";
    2: card_byte=BMP_LEN[7:0]; 3: card_byte=BMP_LEN[15:8];
    4: card_byte=BMP_LEN[23:16]; 5: card_byte=BMP_LEN[31:24];
    10: card_byte=8'd54;
    14: card_byte=8'd40;
    18: card_byte=8'h80; 19: card_byte=8'h02;
    22: card_byte=8'hE0; 23: card_byte=8'h01;
    26: card_byte=8'd1;
    28: card_byte=8'd24;
    default: card_byte=8'h00;
   endcase
  end
  else if (sec==AUD_SEC) begin
   if (off==0) card_byte="A"; else if (off==1) card_byte="P";
   else if (off==2) card_byte="C"; else if (off==3) card_byte="M";
   else if (off<8) card_byte=(off==4)?8'h80:(off==5)?8'hBB:8'h00;
   else if (off<12) card_byte=(off==8)?8'h50:(off==9)?8'hC3:(off==10)?8'h00:8'h00;
   else if (off<16) card_byte=(off==12)?8'h01:8'h00;
  end
 end
endfunction

localparam S_IDLE=2'd0, S_SERVE=2'd1, S_GAP=2'd2;
reg [1:0]  st;
reg [9:0]  cnt;
reg        busy;
reg [31:0] cur;
reg [7:0]  dv;
reg        vld, endf;

assign sd_sec_read_data = dv;
assign sd_sec_read_data_valid = vld;
assign sd_sec_read_end = endf;

// One idle clock (S_GAP) after every sector, so the client's address register
// has settled before the next sector is latched.
always @(posedge clk or posedge rst) begin
 if (rst) begin st<=S_IDLE; busy<=1'b0; cnt<=10'd0; cur<=32'd0; dv<=8'd0; vld<=1'b0; endf<=1'b0; end
 else case (st)
  S_IDLE: begin
   vld <= 1'b0;
   endf <= 1'b0;
   if (sd_sec_read) begin
    cur <= sd_sec_read_addr;
    cnt <= 10'd0;
    busy <= 1'b1;
    vld <= 1'b1;
    dv <= card_byte(sd_sec_read_addr, 0);
    st <= S_SERVE;
   end
  end
  S_SERVE: begin
   if (cnt == 10'd511) begin
    vld <= 1'b0;
    endf <= 1'b1;
    st <= S_GAP;
   end else begin
    cnt <= cnt + 10'd1;
    vld <= 1'b1;
    dv  <= card_byte(cur, cnt + 1);
   end
  end
  default: begin
   endf <= 1'b0;
   busy <= 1'b0;
   st <= S_IDLE;
  end
 endcase
end
endmodule
