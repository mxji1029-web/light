`timescale 1ns/1ps
module tb_pcm_sd_reader;
  parameter integer SAMPLE_COUNT=3;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1,start=0,valid=0,sec_end=0;
  reg [7:0] data=0;
  wire req,we,found,playing;
  wire [31:0] addr,word;
  pcm_sd_reader dut(.clk(clk),.rst(rst),.start(start),.scan_start(32'd7),
    .req(req),.addr(addr),.data_valid(valid),.sec_end(sec_end),.data(data),
    .fifo_data(word),.fifo_we(we),.room_ok(1'b1),.found(found),.playing(playing));
  function [15:0] sample;
    input integer n;
    begin
      case(n)
        0:sample=16'h8000;1:sample=16'h04d2;2:sample=16'hffff;
        default:sample=n*37-16000;
      endcase
    end
  endfunction
  function [7:0] card_byte;
    input integer i;
    reg [15:0] s;
    begin
      case(i)
        0:card_byte="A";1:card_byte="P";2:card_byte="C";3:card_byte="M";
        4:card_byte=8'h80;5:card_byte=8'hbb;6:card_byte=0;7:card_byte=0;
        8:card_byte=SAMPLE_COUNT;9:card_byte=SAMPLE_COUNT>>8;
        10:card_byte=SAMPLE_COUNT>>16;11:card_byte=SAMPLE_COUNT>>24;
        12:card_byte=1;13:card_byte=0;14:card_byte=0;15:card_byte=0;
        default:begin
          s=sample((i-16)/2);
          card_byte=i<16+SAMPLE_COUNT*2 ? ((i%2) ? s[15:8] : s[7:0]) : 8'h5a;
        end
      endcase
    end
  endfunction
  integer b,reads=0,words=0,position;
  reg [31:0] expected;
  initial forever begin
    @(posedge req);
    reads=reads+1;
    if(addr<7 || addr>7+(15+SAMPLE_COUNT*2)/512)
      $fatal(1,"reader ran past audio file: %d",addr);
    repeat(2) @(negedge clk);
    for(b=0;b<512;b=b+1) begin
      valid=1; data=card_byte((addr-7)*512+b); @(negedge clk);
    end
    valid=0; sec_end=1; @(negedge clk); sec_end=0;
  end
  always @(negedge clk) if(!rst && we) begin
    position=(words%((SAMPLE_COUNT+1)/2))*2;
    expected={position+1<SAMPLE_COUNT ? sample(position+1) : 16'd0,sample(position)};
    if(word!==expected) $fatal(1,"PCM mismatch word %d: %h expected %h",words,word,expected);
    words=words+1;
    if(words==3*((SAMPLE_COUNT+1)/2)) begin
      $display("PASS: %0d samples, PCM order, exact EOF, padding, three loops",SAMPLE_COUNT);
      $finish;
    end
  end
  initial begin
    repeat(4) @(negedge clk);rst=0;start=1;
    @(negedge clk);start=0;
  end
  initial begin #1000000; $fatal(1,"timeout"); end
endmodule
