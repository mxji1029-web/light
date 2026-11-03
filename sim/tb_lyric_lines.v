`timescale 1ns/1ps
// Checks every generated sentence window: the per-frame table scan must select
// the sentence whose [start, stop) contains the lyric position, including the
// 300 ms tail, the exact hand-off at the next sentence and the silent gaps.
module tb_lyric_lines;
localparam HEX="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_lines.hex";
reg clk=0,rst=1,vs=1;reg[23:0] position=0;
wire valid;wire[8:0] base;wire[4:0] count;
always #5 clk=~clk;
lyric_line_lookup #(.LINE_FILE(HEX)) dut(.clk(clk),.rst(rst),.vs(vs),.position(position),
 .line_valid(valid),.line_base(base),.line_count(count));
reg[63:0] rows[0:63];
task probe;input[23:0] t;input exp_valid;input[8:0] exp_base;input[4:0] exp_count;begin
 position=t;
 vs=0;repeat(4)@(negedge clk);vs=1;
 repeat(240)@(negedge clk);
 if(valid!==exp_valid || (exp_valid && (base!==exp_base || count!==exp_count)))
  $fatal(1,"window mismatch at %0d: valid=%b base=%0d count=%0d",t,valid,base,count);
end endtask
integer i,checked=0,expected_count=0;
always @(posedge clk) if(valid && (base+count>9'd511)) $fatal(1,"event address past the table");
initial begin
 $readmemh(HEX,rows);
 for(i=0;i<64;i=i+1) if(rows[i][39:16]!=0) expected_count=expected_count+1;
 repeat(4)@(negedge clk);rst=0;
 probe(24'd0,1'b0,9'd0,5'd0);
 for(i=0;i<64;i=i+1)begin
  if(rows[i][39:16]!=0)begin
   probe(rows[i][63:40],1'b1,rows[i][15:7],rows[i][4:0]);
   probe(rows[i][39:16]-24'd1,1'b1,rows[i][15:7],rows[i][4:0]);
   if(i<63 && rows[i+1][39:16]!=0 && rows[i+1][63:40]==rows[i][39:16])
    probe(rows[i][39:16],1'b1,rows[i+1][15:7],rows[i+1][4:0]);
   checked=checked+1;
  end
 end
 if(checked!=expected_count)$fatal(1,"expected %0d sentence windows, got %0d",expected_count,checked);
 $display("PASS lyric sentence table: %0d windows, start/tail/hand-off boundaries",checked);$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule