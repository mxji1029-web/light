`timescale 1ns/1ps
module tb_catalog_scan #(parameter [31:0] MAGIC=32'h31424c41);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,valid=0,sec_end=0;
 reg [7:0] data=0;
 wire ready,done,found,req,cat_reset,cat_valid;
 wire [31:0] addr,found_addr,audio_addr;
 wire [6:0] count;
 integer num=12,bad_checksum=0,seen=0,reading=0,i,j;
 integer legacy_count=1;
 wire [31:0] scan_max=legacy_count*1801+1;
 reg [31:0] sum;
 reg [7:0] block[0:511];
 bmp_read #(.CATALOG_MAGIC(MAGIC)) dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(start),
 .scan_start_sector(0),.scan_max_sector(scan_max),.scan_target_count(7'd64),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_addr),.scan_found_total(count),
 .catalog_reset(cat_reset),.catalog_valid(cat_valid),.catalog_audio_sector(audio_addr),
 .load_start(1'b0),.load_sector(0),.sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req_ack(1'b0),.sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(sec_end));
 task word;input integer offset;input [31:0] value;begin
 block[offset]=value[7:0];block[offset+1]=value[15:8];block[offset+2]=value[23:16];block[offset+3]=value[31:24];end endtask
 always @(negedge clk) if(req && !reading) begin
   reading=1;
   for(i=0;i<512;i=i+1)block[i]=0;
   if(addr<legacy_count*1801 && addr%1801==0)begin // A legacy image before the catalog must be discarded after valid catalog.
     block[0]="B";block[1]="M";word(2,921654);word(10,54);word(14,40);word(18,640);word(22,480);block[26]=1;block[28]=24;
   end
   if(addr==legacy_count*1801)begin
     word(0,MAGIC);
     word(4,num);word(8,7);sum=num+7;
     for(i=0;i<num && i<64;i=i+1)begin word(16+4*i,1000000+(63-i)*1801);sum=sum+1000000+(63-i)*1801;end
     word(12,sum+bad_checksum);
   end
   for(i=0;i<512;i=i+1)begin valid=1;data=block[i];@(negedge clk);end
   valid=0;sec_end=1;@(negedge clk);sec_end=0;
   repeat(3)@(negedge clk);reading=0;
 end
 always @(posedge clk)begin
   #1;
   if(rst || cat_reset)seen=0;
   else if(found)begin
     if(cat_valid && found_addr!==1000000+(63-seen)*1801)$fatal(1,"catalog address order failed %0d %0d",seen,found_addr);
     seen=seen+1;
   end
 end
 task test;input integer n,corrupt;begin
   @(negedge clk);rst=1;num=n;bad_checksum=corrupt;
   repeat(6)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
   wait(done);repeat(6)@(negedge clk);
   if(n>=1 && n<=64 && !corrupt)begin
     if(count!==n || seen!=n || !cat_valid || audio_addr!==7)$fatal(1,"catalog count/audio failed n=%0d count=%0d seen=%0d",n,count,seen);
   end else if(count!==legacy_count || seen!=legacy_count || cat_valid)$fatal(1,"invalid catalog altered fallback");
 end endtask
 initial begin test(1,0);test(12,0);test(64,0);test(0,0);test(65,0);test(12,1);legacy_count=64;test(12,0);
 $display("PASS: catalog 1/12/64, ordered high LBAs, explicit earlier audio, invalid0/65/checksum fallback");$finish;end
 initial begin #2000000;$fatal(1,"catalog timeout");end
endmodule
