module bmp_read #(parameter [31:0] CATALOG_MAGIC=32'h31424c41, parameter SCALE_QUALITY=1)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [6:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [6:0]            scan_found_total,
    output reg catalog_reset, catalog_valid,
    output reg [31:0] catalog_audio_sector,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output                      sd_sec_read,
    output [31:0]               sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output                      bmp_data_wr_en,
    output [23:0]               bmp_data
);

localparam ST_CAT_CHECK = 3'd5;
localparam ST_CAT_EMIT = 3'd6;
localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;

localparam ST_LOAD_CHECK=3'd7;
reg [2:0] state;
reg header_read;
reg [31:0] header_read_addr;
wire scaler_read,scaler_done;
wire [31:0] scaler_addr;
reg [10:0] length_rows;
reg [31:0] required_length;
// Declare header/handshake signals before their scaler connections (Verilog-2001).
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [31:0] load_sector_latched;
reg write_ack_sync;
reg [31:0] abs_height;
// Header fields settle hundreds of cycles before sector completion.
// Register the signed conversion separately from range/format decisions.
always @(posedge clk or posedge rst)
 if(rst)abs_height<=0;else abs_height<=height[31]?(~height+32'd1):height;
wire [11:0] source_stride=((width[10:0]<<1)+width[10:0]+12'd3)&12'hffc;
assign sd_sec_read=(state==ST_LOAD_DATA)?scaler_read:header_read;
assign sd_sec_read_addr=(state==ST_LOAD_DATA)?scaler_addr:header_read_addr;
generate if(SCALE_QUALITY)begin : quality_scaling
bmp_scale_quality scaler(
 .clk(clk),.rst(rst || !sd_init_done),.start(state==ST_LOAD_WAIT && write_ack_sync),
 .base_sector(load_sector_latched),.pixel_offset(pixel_offset),
 .source_width(width[10:0]),.source_height(abs_height[10:0]),.source_top_down(height[31]),
 .target_width(bmp_width),.target_height(bmp_height),.done(scaler_done),
 .sd_sec_read(scaler_read),.sd_sec_read_addr(scaler_addr),.sd_sec_read_data(sd_sec_read_data),
 .sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_end(sd_sec_read_end),
 .pixel_valid(bmp_data_wr_en),.pixel_data(bmp_data));
end else begin : nearest_scaling
bmp_scale_stream scaler(
 .clk(clk),.rst(rst || !sd_init_done),.start(state==ST_LOAD_WAIT && write_ack_sync),
 .base_sector(load_sector_latched),.pixel_offset(pixel_offset),
 .source_width(width[10:0]),.source_height(abs_height[10:0]),.source_top_down(height[31]),
 .target_width(bmp_width),.target_height(bmp_height),.done(scaler_done),
 .sd_sec_read(scaler_read),.sd_sec_read_addr(scaler_addr),.sd_sec_read_data(sd_sec_read_data),
 .sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_end(sd_sec_read_end),
 .pixel_valid(bmp_data_wr_en),.pixel_data(bmp_data));
end endgenerate
// The memory clock holds ACK until this domain withdraws write_req.
// Only the second stage may drive the request state machine.
reg write_ack_meta; /* fehdl keep="true" */
always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_ack_meta <= 1'b0;
        write_ack_sync <= 1'b0;
    end else begin
        write_ack_meta <= write_req_ack;
        write_ack_sync <= write_ack_meta;
    end
end

reg [9:0] rd_cnt;
reg [31:0] cat_word,cat_magic,cat_count,cat_audio,cat_checksum;

reg [6:0] cat_cursor;
reg [31:0] cat_sum;
reg cat_bad;
reg cat_more_q;
reg catalog_header_ok;
// The count/audio fields are complete by byte 11. Register the full-width
// range check before the sector-end scan decision (byte 511).
always @(posedge clk or posedge rst)
 if(rst)catalog_header_ok<=0;
 else catalog_header_ok<=cat_magic==CATALOG_MAGIC &&
     cat_count>=32'd1 && cat_count<=32'd64 && cat_audio!=0;
wire [5:0] cat_entry = (rd_cnt - 10'd16) >> 2;
always @(posedge clk or posedge rst) begin
 if(rst)begin cat_word<=0;cat_magic<=0;cat_count<=0;cat_audio<=0;cat_checksum<=0;end
 else if(state==ST_SCAN && sd_sec_read_data_valid)begin
  cat_word<={sd_sec_read_data,cat_word[31:8]};
  if(rd_cnt==3) cat_magic<={sd_sec_read_data,cat_word[31:8]};
  if(rd_cnt==7) cat_count<={sd_sec_read_data,cat_word[31:8]};
  if(rd_cnt==11)cat_audio<={sd_sec_read_data,cat_word[31:8]};
  if(rd_cnt==15)cat_checksum<={sd_sec_read_data,cat_word[31:8]};
 end
end

// The logical table is not cleared on reset, matching the old register array.
// A scan writes one full32bit entry every four valid bytes. The two16bit RAM
// ports perform this one logical operation together; written-cycle q is unused.
wire cat_store_we=!rst && state==ST_SCAN && sd_sec_read_data_valid &&
                  rd_cnt>=10'd19 && rd_cnt<=10'd271 && rd_cnt[1:0]==2'd3;
wire[31:0] cat_store_data={sd_sec_read_data,cat_word[31:8]};
wire[5:0] cat_read_index=(state==ST_CAT_CHECK || state==ST_CAT_EMIT) ?
                         cat_cursor[5:0]+6'd1 : 6'd0;
wire[31:0] cat_ram_q;
catalog_word_ram_raw catalog_addresses(
 .clk(clk),.write_en(cat_store_we),.write_index(cat_entry),
 .write_data(cat_store_data),.read_index(cat_read_index),.read_data(cat_ram_q));
reg[31:0] cat_entry0_cache;
reg cat_read0_pending;
always @(posedge clk)begin
 cat_read0_pending<=!cat_store_we && cat_read_index==0;
 if(cat_store_we && cat_entry==0)cat_entry0_cache<=cat_store_data;
 else if(cat_read0_pending)cat_entry0_cache<=cat_ram_q;
end
// A nonzero cursor consumes the prior clock's read-ahead. Entry0 may instead
// need the retained cache when sector-end coincided with writing another entry.
// Prefer a freshly completed read0, including a short/early-ended transaction.
wire[31:0] cat_current_word=(cat_cursor[5:0]==0 && !cat_read0_pending) ?
                           cat_entry0_cache : cat_ram_q;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [15:0] bit_count;
reg [31:0] compression;
reg [31:0] dib_size;
reg [15:0] planes;

reg [31:0] scan_sector;
wire header_match;
reg [31:0] file_sector_count;
reg [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;

assign ready = (state == ST_IDLE);
// Bounded positive dimensions keep all offset/stride arithmetic exact.
reg header_dimensions_ok,header_format_ok,header_payload_ok;
always @(posedge clk or posedge rst)begin
 if(rst)begin header_dimensions_ok<=0;header_format_ok<=0;header_payload_ok<=0;end
 else begin
  header_dimensions_ok<=(width>=1 && width<=1024) &&
   (abs_height>=1 && abs_height<=1024) && (bmp_width>=1 && bmp_width<=640) &&
   (bmp_height>=1 && bmp_height<=480);
  header_format_ok<=(header_0=="B" && header_1=="M") &&
   (dib_size==40 || dib_size==108 || dib_size==124) &&
   (planes==1 && bit_count==24 && compression==0);
  header_payload_ok<=(pixel_offset>=14+dib_size && pixel_offset<=65535) &&
   (file_len>=pixel_offset && file_len<=32'd3211264);
 end
end
assign header_match=header_dimensions_ok && header_format_ok && header_payload_ok;
// File length is complete at header byte 5; a sector ends after byte 511.
// These two pipeline stages settle long before SCAN consumes the look-ahead,
// splitting ceil(length/512), sector addition and scan-range comparison.
always @(posedge clk or posedge rst)begin
    if(rst)begin file_sector_count<=1;next_scan_sector_if_match<=0;end
    else begin
        file_sector_count<=(file_len==0)?32'd1:((file_len+32'd511)>>9);
        next_scan_sector_if_match<=scan_sector+file_sector_count;
    end
end
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_end)
            rd_cnt <= 10'd0;
        else if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size <= 0; planes<=0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_size[7:0] <= sd_sec_read_data;
            10'd15: dib_size[15:8] <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;
            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;
            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        length_rows<=0;required_length<=0;
        catalog_reset<=0;catalog_valid<=0;catalog_audio_sector<=0;cat_cursor<=0;cat_sum<=0;cat_bad<=0;cat_more_q<=0;
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        header_read       <= 1'b0;
        header_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 7'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else if (!sd_init_done) begin
        length_rows<=0;required_length<=0;
        catalog_reset<=0;catalog_valid<=0;catalog_audio_sector<=0;cat_cursor<=0;cat_sum<=0;cat_bad<=0;cat_more_q<=0;
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        header_read       <= 1'b0;
        header_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 7'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else begin
        catalog_reset <= 0;
        scan_found_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                header_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    catalog_valid<=0;catalog_audio_sector<=0;
                    scan_done        <= 1'b0;
                    scan_found_total <= 7'd0;
                    scan_sector      <= scan_start_sector;
                    header_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    header_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                header_read <= 1'b1;

                if (sd_sec_read_end) begin
                    header_read <= 1'b0;

                    if (catalog_header_ok)begin
                        cat_cursor<=0;cat_sum<=cat_count+cat_audio;cat_bad<=0;state<=ST_CAT_CHECK;
                        // Match a count byte7 update on this sector-end clock.
                        cat_more_q<=(sd_sec_read_data_valid && rd_cnt==10'd7) ?
                                    (|cat_word[14:8]) : (|cat_count[6:0]);
                    end else if (header_match) begin
                        // A full fallback table must not hide a later valid catalog.
                        if(scan_found_total<scan_target_count && scan_found_total<7'd64)begin
                            scan_found_valid  <= 1'b1;
                            scan_found_sector <= scan_sector;
                            scan_found_total  <= scan_found_total + 7'd1;
                        end
                        if (next_scan_sector_if_match > scan_max_sector) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            header_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            header_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            header_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_CAT_CHECK: begin
                header_read<=0;
                // The previous clock predicted cursor<count. While true the
                // next cursor cannot exceed count, so terminal equality works.
                if(cat_more_q)begin
                    cat_sum<=cat_sum+cat_current_word;
                    if(cat_current_word==0)cat_bad<=1;
                    cat_cursor<=cat_cursor+1'b1;
                    cat_more_q<=((cat_cursor+7'd1)!=cat_count[6:0]);
                end else begin
                    // Cursor is dead on rejection and is reset at the next CHECK.
                    // Clear at every terminal CHECK so checksum acceptance does not
                    // drive the cursor hold/reset control path.
                    cat_cursor<=0;
                    if(cat_sum==cat_checksum && !cat_bad)begin
                        catalog_reset<=1;catalog_valid<=1;catalog_audio_sector<=cat_audio;
                        scan_found_total<=0;state<=ST_CAT_EMIT;
                    end else if(scan_sector>=scan_max_sector)begin scan_done<=1;state<=ST_IDLE;end
                    else begin
                        scan_sector<=next_scan_sector_if_miss;header_read_addr<=next_scan_sector_if_miss;state<=ST_SCAN;
                    end
                end
            end
            ST_CAT_EMIT: begin
                header_read<=0;
                scan_found_valid<=1;scan_found_sector<=cat_current_word;
                scan_found_total<=scan_found_total+1'b1;cat_cursor<=cat_cursor+1'b1;
                if(cat_cursor+7'd1>=cat_count[6:0])begin scan_done<=1;state<=ST_IDLE;end
            end
            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                header_read <= 1'b1;

                if (sd_sec_read_end) begin
                    header_read <= 1'b0;
                    if (header_match) begin
                        length_rows<=abs_height[10:0];
                        required_length<=pixel_offset;
                        state<=ST_LOAD_CHECK;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_ack_sync) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_CHECK: begin
                // Multi-cycle extent validation avoids a variable multiplier/divider.
                header_read<=0;
                if(length_rows!=0)begin
                    required_length<=required_length+source_stride;
                    length_rows<=length_rows-1'b1;
                end else if(required_length<=file_len)begin
                    write_req<=1;
                    header_read_addr<=load_sector_latched;
                    state<=ST_LOAD_WAIT;
                end else state<=ST_IDLE;
            end
            ST_LOAD_DATA: begin
                state_code<=4'd4;
                header_read<=0;
                if(scaler_done)state<=ST_IDLE;
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                header_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule

// 64 x 32-bit catalog memory with one operation per rising clock edge.
// write_en=1: store write_data at write_index. read_data on a write edge is
// unspecified and must not be consumed; read_index is ignored on this edge.
// write_en=0: output the word at read_index after this edge (one-edge read).
// read_data remains stable between clock edges. There is no reset or run-time
// initialization; stored words survive caller resets. Data before a word's
// first write is unspecified and must not be consumed by the caller.
// This low-cost variant deliberately omits the default wrapper's write bypass.
module catalog_word_ram_raw (
    input wire clk,
    input wire write_en,
    input wire [5:0] write_index,
    input wire [31:0] write_data,
    input wire [5:0] read_index,
    output wire [31:0] read_data
);
    wire [5:0] operation_index = write_en ? write_index : read_index;
`ifdef __ICARUS__
    // Equivalent synchronous NORMAL/read-first memory model. The old word on
    // a write edge is an implementation detail, not part of the RAW contract.
    reg [31:0] words [0:63];
    reg [31:0] ram_read;
    assign read_data = ram_read;
    always @(posedge clk) begin
        ram_read <= words[operation_index];
        if (write_en)
            words[operation_index] <= write_data;
    end
`else
    EG_PHY_BRAM32K #(
        .MODE("DP16K"),
        .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL")
    ) words (
        .clka(clk), .clkb(clk),
        .addra({4'b0, operation_index, 1'b0}),
        .addrb({4'b0, operation_index, 1'b1}),
        .dia(write_data[15:0]), .dib(write_data[31:16]),
        .doa(read_data[15:0]), .dob(read_data[31:16]),
        .wea(write_en), .web(write_en), .csa(1'b1), .csb(1'b1),
        .rsta(1'b0), .rstb(1'b0), .ocea(1'b1), .oceb(1'b1),
        .bytea(1'b0), .byteb(1'b0), .bytewea(1'b0), .byteweb(1'b0)
    );
`endif
endmodule
