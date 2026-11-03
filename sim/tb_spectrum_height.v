`timescale 1ns/1ps
module tb_spectrum_height;
wire hs_out,vs_out,de_out;wire[23:0] rgb_out;
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) dut(
 .clk(1'b0),.rst(1'b0),.hs(1'b1),.vs(1'b1),.de(1'b0),.rgb(24'd0),
 .audio_valid(1'b0),.audio_sample(16'sd0),.paused(1'b0),
 .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out));

// Frozen arithmetic from the working spectrum-bars release, before optimization.
function[5:0] release_height;
 input[31:0] value;integer e,h;reg[31:0] fraction;
 begin
  e=0;for(h=0;h<30;h=h+1)if(value[h])e=h;
  if(value<16)release_height=0;
  else begin
   fraction=value-(32'd1<<e);
   h=(e-4)*3+1+((fraction*3)>>e);
   release_height=h>39?6'd39:h;
  end
 end
endfunction

// Independent boundary oracle: the three levels in octave e start at
// ceil(2^e), ceil(4*2^e/3), and ceil(5*2^e/3), respectively.
function[5:0] boundary_height;
 input[31:0] value;integer e,q;reg[31:0] threshold;
 begin
  boundary_height=0;
  for(e=4;e<=16;e=e+1)begin
   for(q=0;q<3;q=q+1)begin
    threshold=((3+q)*(32'd1<<e)+2)/3;
    if(value>=threshold)boundary_height=(e-4)*3+q+1;
   end
  end
 end
endfunction

integer checked=0;
task check;
 input[31:0] value;reg[5:0] got,expected,independent;
 begin
  got=dut.height(value);expected=release_height(value);independent=boundary_height(value);
  if(got!==expected || got!==independent)
   $fatal(1,"height(%0d) got %0d release %0d boundary %0d",value,got,expected,independent);
  checked=checked+1;
 end
endtask

integer value,e,q;reg[31:0] threshold;
initial begin
 for(value=0;value<1048576;value=value+1)check(value);
 // Explicitly exercise both neighbors of every step, including saturation.
 for(e=4;e<=16;e=e+1)begin
  for(q=0;q<3;q=q+1)begin
   threshold=((3+q)*(32'd1<<e)+2)/3;
   check(threshold-1);check(threshold);check(threshold+1);
  end
 end
 // The 29-bit absolute components sum to at most 805306366 before >>4,
 // so every magnitude consumed by height is <=50331647 (less than 2^26).
 // All values above the final threshold are saturated; cover every remaining
 // exponent and its endpoints without relying on the one-million-value sweep.
 for(e=20;e<=25;e=e+1)begin
  check((32'd1<<e)-1);check(32'd1<<e);check((32'd1<<(e+1))-1);
 end
 check(32'd50331647);
 $display("PASS spectrum height: %0d values match frozen release and independent boundary oracle; all 39 steps, saturation and 26-bit domain endpoints",checked);
 $finish;
end
endmodule
