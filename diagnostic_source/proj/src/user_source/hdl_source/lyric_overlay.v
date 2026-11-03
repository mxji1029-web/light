// Two synchronous ROM reads; pixel and sync paths have the same two-clock delay.
//
// The glyph table is a block RAM (four 8-bit slices so TD maps every slice to
// 8192x1 banks; a 32-bit array makes TD use 1024x9 banks and silently drop the
// uninitialised parity lane). The syllable table is plain generated logic
// instead of an array: TD merged it with the glyph banks and lost 671 bits when
// it was a memory, and a case table cannot be re-packed.
module lyric_overlay #(
 parameter SUBTITLE_QUALITY=1,
 parameter FONT0="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_font0.hex",
 parameter FONT1="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_font1.hex",
 parameter FONT2="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_font2.hex",
 parameter FONT3="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_font3.hex",
 parameter LINE_FILE="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_lines.hex"
)(input clk,input rst,input hs,input vs,input de,input[23:0] rgb,
 input[23:0] position,input[7:0] level,
 output hs_out,output vs_out,output de_out,output[23:0] rgb_out);
// 256 glyph slots x 32 rows for the whole song.
reg[7:0] font0[0:8191],font1[0:8191],font2[0:8191],font3[0:8191];
initial begin
 $readmemh(FONT0,font0);$readmemh(FONT1,font1);
 $readmemh(FONT2,font2);$readmemh(FONT3,font3);
end
wire line_valid;wire[8:0] line_base;wire[4:0] line_count;
lyric_line_lookup #(.LINE_FILE(LINE_FILE),.ATOMIC_FRAME(SUBTITLE_QUALITY)) u_lines(
 .clk(clk),.rst(rst),.vs(vs),.position(position),
 .line_valid(line_valid),.line_base(line_base),.line_count(line_count));
reg[9:0] x_count,y_count;reg de_d;
wire[9:0] pixel_x=de_d?x_count:10'd0;
wire[9:0] left_edge=10'd320-{line_count,4'b0000};
wire in_line=line_valid && pixel_x>=left_edge && pixel_x<left_edge+{line_count,5'b00000};
wire[9:0] relative_x=pixel_x-left_edge;
wire[8:0] event_addr=line_base+relative_x[9:5];
// {glyph[7:0], start[23:0], end[23:0]}
reg[55:0] event_word_c;
always @* begin
// BEGIN GENERATED lyric_events
 event_word_c=56'd0;
 case(event_addr)
  9'd0: event_word_c=56'h6700bb80013ec0;
  9'd1: event_word_c=56'hbc01518001d4c0;
  9'd2: event_word_c=56'h5d01e780026ac0;
  9'd3: event_word_c=56'hc003a980045240;
  9'd4: event_word_c=56'hd8046500050dc0;
  9'd5: event_word_c=56'h6714ed101506c0;
  9'd6: event_word_c=56'h561506c0155190;
  9'd7: event_word_c=56'ha21551901575c0;
  9'd8: event_word_c=56'h8d1575c0159420;
  9'd9: event_word_c=56'hc415942015d110;
  9'd10: event_word_c=56'h1715d11015f4b0;
  9'd11: event_word_c=56'hd115f4b0162030;
  9'd12: event_word_c=56'h9e162030163230;
  9'd13: event_word_c=56'hb51632301696b0;
  9'd14: event_word_c=56'h811696b016e900;
  9'd15: event_word_c=56'h9316eae0170520;
  9'd16: event_word_c=56'h1d170520173340;
  9'd17: event_word_c=56'h521733401760d0;
  9'd18: event_word_c=56'hb01760d0178590;
  9'd19: event_word_c=56'h9017859017dea0;
  9'd20: event_word_c=56'h5817dea0182460;
  9'd21: event_word_c=56'haf182460184fb0;
  9'd22: event_word_c=56'hc7184fb0187a40;
  9'd23: event_word_c=56'h20187a4018a080;
  9'd24: event_word_c=56'hcd18a08018c0c0;
  9'd25: event_word_c=56'hd518c0c0191df0;
  9'd26: event_word_c=56'h9c191df0196bf0;
  9'd27: event_word_c=56'ha1196bf0199680;
  9'd28: event_word_c=56'h2519968019b810;
  9'd29: event_word_c=56'h0019b81019ddf0;
  9'd30: event_word_c=56'h4019ddf01a0b80;
  9'd31: event_word_c=56'h1c1a0b801a4d80;
  9'd32: event_word_c=56'h3b1a4d801aa7b0;
  9'd33: event_word_c=56'h041adf301af9a0;
  9'd34: event_word_c=56'ha41af9a01b28e0;
  9'd35: event_word_c=56'h4e1b28e01b45c0;
  9'd36: event_word_c=56'h7a1b45c01b9d80;
  9'd37: event_word_c=56'h041b9d801bd9e0;
  9'd38: event_word_c=56'h7a1bd9e01c3650;
  9'd39: event_word_c=56'hca1c36501c7100;
  9'd40: event_word_c=56'hd01c71001d34f0;
  9'd41: event_word_c=56'h671eedf01f0cb0;
  9'd42: event_word_c=56'ha11f0cb01f5cf0;
  9'd43: event_word_c=56'h251f5cf01f80f0;
  9'd44: event_word_c=56'h201f80f01faa30;
  9'd45: event_word_c=56'h061faa301fcf20;
  9'd46: event_word_c=56'h101fcf201ffad0;
  9'd47: event_word_c=56'haa1ffad0202620;
  9'd48: event_word_c=56'h3c202620204a20;
  9'd49: event_word_c=56'h00204a20209220;
  9'd50: event_word_c=56'hc120922020efb0;
  9'd51: event_word_c=56'h1220f4f0211b60;
  9'd52: event_word_c=56'h13211b60214140;
  9'd53: event_word_c=56'h71214140216900;
  9'd54: event_word_c=56'ha2216900218bb0;
  9'd55: event_word_c=56'h26218bb021de60;
  9'd56: event_word_c=56'h2221de60222900;
  9'd57: event_word_c=56'h722229002252d0;
  9'd58: event_word_c=56'hbf2252d0228300;
  9'd59: event_word_c=56'h6722830022a670;
  9'd60: event_word_c=56'h9e22a67022bcc0;
  9'd61: event_word_c=56'hb522bcc0232140;
  9'd62: event_word_c=56'h81232140236700;
  9'd63: event_word_c=56'h73236700238fe0;
  9'd64: event_word_c=56'h70238fe023b8f0;
  9'd65: event_word_c=56'h6723b8f023f0d0;
  9'd66: event_word_c=56'h9e23f0d0241d10;
  9'd67: event_word_c=56'hb4241d10246540;
  9'd68: event_word_c=56'hb624654024b760;
  9'd69: event_word_c=56'h8f2506b0252b70;
  9'd70: event_word_c=56'h7d252b70254b50;
  9'd71: event_word_c=56'h80254b5025a490;
  9'd72: event_word_c=56'h1425a49025e2d0;
  9'd73: event_word_c=56'hc825e2d0263f40;
  9'd74: event_word_c=56'h39263f402675d0;
  9'd75: event_word_c=56'h282675d0279900;
  9'd76: event_word_c=56'h9f28f800292170;
  9'd77: event_word_c=56'h25292170296c70;
  9'd78: event_word_c=56'h67296c7029b920;
  9'd79: event_word_c=56'h3329b9202a07b0;
  9'd80: event_word_c=56'hba2a07b02a6930;
  9'd81: event_word_c=56'h002a69302ab970;
  9'd82: event_word_c=56'h062ab9702af570;
  9'd83: event_word_c=56'h422af5702b5750;
  9'd84: event_word_c=56'hdb2b57502c4f30;
  9'd85: event_word_c=56'h672cc2202cdbd0;
  9'd86: event_word_c=56'ha42cdbd02d39c0;
  9'd87: event_word_c=56'h4e2d39c02d75c0;
  9'd88: event_word_c=56'h7a2d75c02de0a0;
  9'd89: event_word_c=56'h182de0a02ec770;
  9'd90: event_word_c=56'h2f2f17b02f3e20;
  9'd91: event_word_c=56'h182f3e202f5a40;
  9'd92: event_word_c=56'h612f5a402fa630;
  9'd93: event_word_c=56'hbc2fa630300240;
  9'd94: event_word_c=56'h5d3002403055b0;
  9'd95: event_word_c=56'h673055b031c770;
  9'd96: event_word_c=56'h67331290332880;
  9'd97: event_word_c=56'h56332880337f80;
  9'd98: event_word_c=56'h82337f8033ced0;
  9'd99: event_word_c=56'h0a33ced0341e20;
  9'd100: event_word_c=56'h2d341e203467a0;
  9'd101: event_word_c=56'h9d3467a034c7d0;
  9'd102: event_word_c=56'h9e34c7d03503d0;
  9'd103: event_word_c=56'h923503d0355aa0;
  9'd104: event_word_c=56'h65355aa0365730;
  9'd105: event_word_c=56'h2f36a2f036c6f0;
  9'd106: event_word_c=56'h6736c6f036edf0;
  9'd107: event_word_c=56'h6136edf0374b20;
  9'd108: event_word_c=56'h08374b20378ff0;
  9'd109: event_word_c=56'h34378ff037e1e0;
  9'd110: event_word_c=56'ha337e1e03882f0;
  9'd111: event_word_c=56'h183882f038dd50;
  9'd112: event_word_c=56'h91392040394b90;
  9'd113: event_word_c=56'h4e394b903961e0;
  9'd114: event_word_c=56'h483961e039bdf0;
  9'd115: event_word_c=56'h5e39bdf039ea90;
  9'd116: event_word_c=56'ha239ea903a4e50;
  9'd117: event_word_c=56'ha03a4e503aae20;
  9'd118: event_word_c=56'hcc3aae203c3480;
  9'd119: event_word_c=56'h673d17c03d35f0;
  9'd120: event_word_c=56'hbc3d35f03d7ee0;
  9'd121: event_word_c=56'h5d3d7ee03dd5e0;
  9'd122: event_word_c=56'hca3dd5e03e0220;
  9'd123: event_word_c=56'hd03e02203e1d50;
  9'd124: event_word_c=56'h7a3e1d503e53e0;
  9'd125: event_word_c=56'h9a3e53e03e6df0;
  9'd126: event_word_c=56'h863e6df03ecc10;
  9'd127: event_word_c=56'h833ecc103f0c60;
  9'd128: event_word_c=56'h323f18c03f4980;
  9'd129: event_word_c=56'hda3f49803f6c60;
  9'd130: event_word_c=56'h7d3f6c603f8e20;
  9'd131: event_word_c=56'h063f8e203faaa0;
  9'd132: event_word_c=56'h553faaa0401010;
  9'd133: event_word_c=56'h3e401010404c40;
  9'd134: event_word_c=56'h55404c404087b0;
  9'd135: event_word_c=56'h3e4087b040aa60;
  9'd136: event_word_c=56'h0240aa6040d970;
  9'd137: event_word_c=56'h9e40d97040fa70;
  9'd138: event_word_c=56'h8440fa70413f40;
  9'd139: event_word_c=56'h86413f40419f40;
  9'd140: event_word_c=56'h8c419f4041c520;
  9'd141: event_word_c=56'h5b41c52041eaa0;
  9'd142: event_word_c=56'ha741eaa0421140;
  9'd143: event_word_c=56'h47421140424080;
  9'd144: event_word_c=56'h254240804292a0;
  9'd145: event_word_c=56'h824292a042e6d0;
  9'd146: event_word_c=56'h674332f0435480;
  9'd147: event_word_c=56'h134354804382d0;
  9'd148: event_word_c=56'h6d4382d043c680;
  9'd149: event_word_c=56'h8443c680441c30;
  9'd150: event_word_c=56'hb7441c30444300;
  9'd151: event_word_c=56'h944443004471b0;
  9'd152: event_word_c=56'h2c4471b044c370;
  9'd153: event_word_c=56'hb644c370456780;
  9'd154: event_word_c=56'h67472350473a60;
  9'd155: event_word_c=56'hbc473a60478dd0;
  9'd156: event_word_c=56'h5d478dd047dc90;
  9'd157: event_word_c=56'hd747dc90480a50;
  9'd158: event_word_c=56'h0a480a50482f40;
  9'd159: event_word_c=56'h7e482f404859a0;
  9'd160: event_word_c=56'h294859a0488ac0;
  9'd161: event_word_c=56'h67488ac048d470;
  9'd162: event_word_c=56'hc948d470491b50;
  9'd163: event_word_c=56'h1a491f704954b0;
  9'd164: event_word_c=56'hc74954b0497a30;
  9'd165: event_word_c=56'h18497a3049a280;
  9'd166: event_word_c=56'h9e49a28049b9c0;
  9'd167: event_word_c=56'h2b49b9c04a0730;
  9'd168: event_word_c=56'h994a07304a6910;
  9'd169: event_word_c=56'h184a69104a8b60;
  9'd170: event_word_c=56'h634a8b604aaff0;
  9'd171: event_word_c=56'h384aaff04adab0;
  9'd172: event_word_c=56'h894adab04b0a50;
  9'd173: event_word_c=56'hc24b0a504b5370;
  9'd174: event_word_c=56'h3c4b53704bac80;
  9'd175: event_word_c=56'h674bac804bcbd0;
  9'd176: event_word_c=56'h9e4bcbd04bfcc0;
  9'd177: event_word_c=56'h544bfcc04c1eb0;
  9'd178: event_word_c=56'hb24c1eb04c42e0;
  9'd179: event_word_c=56'h324c42e04c99e0;
  9'd180: event_word_c=56'hda4c99e04cf020;
  9'd181: event_word_c=56'h2e4d37004d4c60;
  9'd182: event_word_c=56'h7a4d4c604d8ce0;
  9'd183: event_word_c=56'h074d8ce04dd990;
  9'd184: event_word_c=56'h0a4dd9904e0780;
  9'd185: event_word_c=56'hce4e07804e28e0;
  9'd186: event_word_c=56'h204e28e04e5700;
  9'd187: event_word_c=56'h064e57004e7a40;
  9'd188: event_word_c=56'hd34e7a404ec180;
  9'd189: event_word_c=56'hd24ec1804f7100;
  9'd190: event_word_c=56'h675130305146b0;
  9'd191: event_word_c=56'hbc5146b05199f0;
  9'd192: event_word_c=56'h5d5199f051f0c0;
  9'd193: event_word_c=56'h6751f0c05215b0;
  9'd194: event_word_c=56'h135215b05235f0;
  9'd195: event_word_c=56'h7b5235f0525d80;
  9'd196: event_word_c=56'h7a525d805290e0;
  9'd197: event_word_c=56'h645290e052e180;
  9'd198: event_word_c=56'h1052e180532c50;
  9'd199: event_word_c=56'h325334c0535c80;
  9'd200: event_word_c=56'h82535c80538140;
  9'd201: event_word_c=56'h6953814053aab0;
  9'd202: event_word_c=56'h0b53aab053d8a0;
  9'd203: event_word_c=56'h9753d8a05417d0;
  9'd204: event_word_c=56'h2a5417d05473e0;
  9'd205: event_word_c=56'h185473e0548eb0;
  9'd206: event_word_c=56'h02548eb054bfd0;
  9'd207: event_word_c=56'h6954bfd054e520;
  9'd208: event_word_c=56'h3d54e520551820;
  9'd209: event_word_c=56'h32551820555f00;
  9'd210: event_word_c=56'h51555f0055ae80;
  9'd211: event_word_c=56'h1f55ae8055d880;
  9'd212: event_word_c=56'h0955d8805608e0;
  9'd213: event_word_c=56'h8f5608e0562800;
  9'd214: event_word_c=56'h7d562800565a10;
  9'd215: event_word_c=56'h39565a1056a900;
  9'd216: event_word_c=56'h8256a90056fd60;
  9'd217: event_word_c=56'h9f574410576ff0;
  9'd218: event_word_c=56'h25576ff0578c40;
  9'd219: event_word_c=56'h74578c4057e7f0;
  9'd220: event_word_c=56'h0457e7f0583590;
  9'd221: event_word_c=56'h25583590588780;
  9'd222: event_word_c=56'h1858878058b7e0;
  9'd223: event_word_c=56'h9e58b7e058f230;
  9'd224: event_word_c=56'h1958f230597c00;
  9'd225: event_word_c=56'h675b3dd05b61d0;
  9'd226: event_word_c=56'h135b61d05ba0d0;
  9'd227: event_word_c=56'h635ba0d05bf6b0;
  9'd228: event_word_c=56'hca5bf6b05c1db0;
  9'd229: event_word_c=56'h875c1db05c4930;
  9'd230: event_word_c=56'hd15c49305c6ca0;
  9'd231: event_word_c=56'h445c6ca05c9550;
  9'd232: event_word_c=56'h235c95505cee90;
  9'd233: event_word_c=56'ha65cee905d3660;
  9'd234: event_word_c=56'h275d37205d6300;
  9'd235: event_word_c=56'hb95d63005d8eb0;
  9'd236: event_word_c=56'hd15d8eb05dae30;
  9'd237: event_word_c=56'h765dae305ddf80;
  9'd238: event_word_c=56'h595ddf805e2060;
  9'd239: event_word_c=56'h4c5e20605e7040;
  9'd240: event_word_c=56'ha05e70405e9bc0;
  9'd241: event_word_c=56'h0e5e9bc05ec950;
  9'd242: event_word_c=56'hcb5ec9505efce0;
  9'd243: event_word_c=56'h245efce05f2620;
  9'd244: event_word_c=56'h505f26205f6220;
  9'd245: event_word_c=56'h775f62205fb110;
  9'd246: event_word_c=56'hbe5fb1105fe590;
  9'd247: event_word_c=56'ha25fe590601170;
  9'd248: event_word_c=56'h82601170602e50;
  9'd249: event_word_c=56'h05602e50605e50;
  9'd250: event_word_c=56'h1f605e5060a9b0;
  9'd251: event_word_c=56'hba60a9b0610590;
  9'd252: event_word_c=56'h1f614fd0617100;
  9'd253: event_word_c=56'h88617100618f00;
  9'd254: event_word_c=56'h48618f0061eed0;
  9'd255: event_word_c=56'h5e61eed0624240;
  9'd256: event_word_c=56'ha2624240627ed0;
  9'd257: event_word_c=56'ha0627ed062e020;
  9'd258: event_word_c=56'hb162e020647a90;
  9'd259: event_word_c=56'h35651cc0656a60;
  9'd260: event_word_c=56'h35656a60659370;
  9'd261: event_word_c=56'h3565937065c6a0;
  9'd262: event_word_c=56'h3565c6a0669990;
  9'd263: event_word_c=56'h5f66a8c066ff60;
  9'd264: event_word_c=56'h8266ff60674d60;
  9'd265: event_word_c=56'h6e674d60679e30;
  9'd266: event_word_c=56'h6e679e30688170;
  9'd267: event_word_c=56'h5f693000697f20;
  9'd268: event_word_c=56'h82697f2069d140;
  9'd269: event_word_c=56'h6e69d1406a2300;
  9'd270: event_word_c=56'h6e6a23006aafa0;
  9'd271: event_word_c=56'h676aafa06b5710;
  9'd272: event_word_c=56'h356f24006f7590;
  9'd273: event_word_c=56'h356f75906f9f00;
  9'd274: event_word_c=56'h356f9f006fd260;
  9'd275: event_word_c=56'h356fd26070ac40;
  9'd276: event_word_c=56'h5f70b8407108b0;
  9'd277: event_word_c=56'h827108b07159b0;
  9'd278: event_word_c=56'h6e7159b071a7e0;
  9'd279: event_word_c=56'h6e71a7e0729420;
  9'd280: event_word_c=56'h5f733770738a20;
  9'd281: event_word_c=56'h82738a2073da90;
  9'd282: event_word_c=56'h6e73da90742a40;
  9'd283: event_word_c=56'h6e742a4074cdc0;
  9'd284: event_word_c=56'h6774cdc0751ec0;
  9'd285: event_word_c=56'h3c8d68408d97b0;
  9'd286: event_word_c=56'hc38d97b08dcd80;
  9'd287: event_word_c=56'h028dcd808e3cb0;
  9'd288: event_word_c=56'h678e3cb08e5c90;
  9'd289: event_word_c=56'hcc8e5c908e8540;
  9'd290: event_word_c=56'h258e85408eadf0;
  9'd291: event_word_c=56'h0a8eadf08ed670;
  9'd292: event_word_c=56'h008ed6708f24a0;
  9'd293: event_word_c=56'h168f24a08f7cc0;
  9'd294: event_word_c=56'h758f7cc08f98e0;
  9'd295: event_word_c=56'h288f98e08fc4c0;
  9'd296: event_word_c=56'h468fc4c08fedd0;
  9'd297: event_word_c=56'h578fedd09016b0;
  9'd298: event_word_c=56'h9e9016b0906330;
  9'd299: event_word_c=56'h1090633090b220;
  9'd300: event_word_c=56'h4990be2090d860;
  9'd301: event_word_c=56'h7a90d860910440;
  9'd302: event_word_c=56'h4b910440912630;
  9'd303: event_word_c=56'h8b9126309150f0;
  9'd304: event_word_c=56'h579150f0919f50;
  9'd305: event_word_c=56'hc6919f5091f500;
  9'd306: event_word_c=56'h6b91f500921b40;
  9'd307: event_word_c=56'ha2921b40924570;
  9'd308: event_word_c=56'hc7924570926ca0;
  9'd309: event_word_c=56'hb3926ca09299d0;
  9'd310: event_word_c=56'hdc9299d092f2b0;
  9'd311: event_word_c=56'h5392f2b0934200;
  9'd312: event_word_c=56'hd9938f7093aef0;
  9'd313: event_word_c=56'h2193aef093e370;
  9'd314: event_word_c=56'h3693e3709434d0;
  9'd315: event_word_c=56'h189434d0948390;
  9'd316: event_word_c=56'h0094839094ce00;
  9'd317: event_word_c=56'h8794ce0094fb60;
  9'd318: event_word_c=56'h9e94fb60954360;
  9'd319: event_word_c=56'hac95436096af80;
  9'd320: event_word_c=56'h49977b20979d10;
  9'd321: event_word_c=56'h36979d1097efc0;
  9'd322: event_word_c=56'h6797efc0983970;
  9'd323: event_word_c=56'hbd9839709866a0;
  9'd324: event_word_c=56'h0a9866a0989d60;
  9'd325: event_word_c=56'h5c989d6098bf50;
  9'd326: event_word_c=56'h4698bf5098e9b0;
  9'd327: event_word_c=56'h1e98e9b09937b0;
  9'd328: event_word_c=56'h0d9937b0998c40;
  9'd329: event_word_c=56'h18998c4099ae60;
  9'd330: event_word_c=56'h6699ae6099d440;
  9'd331: event_word_c=56'hd499d4409a00b0;
  9'd332: event_word_c=56'h9e9a00b09a2a50;
  9'd333: event_word_c=56'h759a2a509a60e0;
  9'd334: event_word_c=56'h0c9a60e09ab1e0;
  9'd335: event_word_c=56'h3c9ab6609ae060;
  9'd336: event_word_c=56'h799ae0609b08e0;
  9'd337: event_word_c=56'ha89b08e09b34f0;
  9'd338: event_word_c=56'h2d9b34f09b6100;
  9'd339: event_word_c=56'h009b61009bb1a0;
  9'd340: event_word_c=56'hab9bb1a09bf2b0;
  9'd341: event_word_c=56'h629bf2b09c1b00;
  9'd342: event_word_c=56'h609c1b009c4c80;
  9'd343: event_word_c=56'h119c4c809c74d0;
  9'd344: event_word_c=56'h7f9c74d09ca3b0;
  9'd345: event_word_c=56'h1b9ca3b09cf1b0;
  9'd346: event_word_c=56'h8a9cf1b09d50f0;
  9'd347: event_word_c=56'h4b9d9a109dbc60;
  9'd348: event_word_c=56'h309dbc609debd0;
  9'd349: event_word_c=56'h419debd09e3c40;
  9'd350: event_word_c=56'ha59e3c409e7540;
  9'd351: event_word_c=56'h029e75409ed960;
  9'd352: event_word_c=56'h9e9ed9609f0390;
  9'd353: event_word_c=56'h319f03909f5100;
  9'd354: event_word_c=56'h4d9f5100a09350;
  9'd355: event_word_c=56'h04a184a0a1ac30;
  9'd356: event_word_c=56'hb9a1ac30a1f280;
  9'd357: event_word_c=56'h37a1f280a24f20;
  9'd358: event_word_c=56'h67a24f20a26f30;
  9'd359: event_word_c=56'h7ca26f30a29570;
  9'd360: event_word_c=56'h0fa29570a2c780;
  9'd361: event_word_c=56'h98a2c780a2f0f0;
  9'd362: event_word_c=56'h9ea2f0f0a34280;
  9'd363: event_word_c=56'h10a34280a38a80;
  9'd364: event_word_c=56'h67a394a0a3b2a0;
  9'd365: event_word_c=56'h7ca3b2a0a3e210;
  9'd366: event_word_c=56'h4aa3e210a40910;
  9'd367: event_word_c=56'h9ea40910a43400;
  9'd368: event_word_c=56'h9ba43400a48290;
  9'd369: event_word_c=56'h15a48290a4c1f0;
  9'd370: event_word_c=56'h78a4c1f0a4edd0;
  9'd371: event_word_c=56'ha8a4edd0a51230;
  9'd372: event_word_c=56'h7aa51230a54a70;
  9'd373: event_word_c=56'h06a54a70a57380;
  9'd374: event_word_c=56'h3aa57380a5b280;
  9'd375: event_word_c=56'h3ba5b280a60a70;
  9'd376: event_word_c=56'h9fa60a70a62d50;
  9'd377: event_word_c=56'hb5a62d50a65f30;
  9'd378: event_word_c=56'h68a65f30a67b80;
  9'd379: event_word_c=56'h7aa67b80a6adc0;
  9'd380: event_word_c=56'hc5a6adc0a703a0;
  9'd381: event_word_c=56'h5aa703a0a75950;
  9'd382: event_word_c=56'h67a7a870a7cf70;
  9'd383: event_word_c=56'h13a7cf70a7ee30;
  9'd384: event_word_c=56'h7ca7ee30a84320;
  9'd385: event_word_c=56'haea84320a89480;
  9'd386: event_word_c=56'hcfa89480a8e6a0;
  9'd387: event_word_c=56'h14a8e6a0a8fd50;
  9'd388: event_word_c=56'ha0a8fd50a95ae0;
  9'd389: event_word_c=56'hbaa95ae0aa2980;
  9'd390: event_word_c=56'h3cab8b50abb010;
  9'd391: event_word_c=56'h3fabb010ac00e0;
  9'd392: event_word_c=56'h8eac00e0ac52a0;
  9'd393: event_word_c=56'h9eac52a0ac7bb0;
  9'd394: event_word_c=56'h85ac7bb0aca970;
  9'd395: event_word_c=56'h06aca970acd3a0;
  9'd396: event_word_c=56'h6facd3a0acef30;
  9'd397: event_word_c=56'hbbacef30ad3fa0;
  9'd398: event_word_c=56'h43ad3fa0ad8e90;
  9'd399: event_word_c=56'h3cad9250adb710;
  9'd400: event_word_c=56'h45adb710ade1d0;
  9'd401: event_word_c=56'hd6ade1d0ae06c0;
  9'd402: event_word_c=56'hb8ae06c0ae2be0;
  9'd403: event_word_c=56'h03ae2be0ae7920;
  9'd404: event_word_c=56'h78ae7920aed290;
  9'd405: event_word_c=56'h3caed290aefa20;
  9'd406: event_word_c=56'h01aefa20af2660;
  9'd407: event_word_c=56'h4faf2660af4f40;
  9'd408: event_word_c=56'h96af4f40af7970;
  9'd409: event_word_c=56'h95af7970afca70;
  9'd410: event_word_c=56'h9eafca70b01e40;
  9'd411: event_word_c=56'h85b01e40b045a0;
  9'd412: event_word_c=56'h00b045a0b05dd0;
  9'd413: event_word_c=56'h6ab05dd0b08d70;
  9'd414: event_word_c=56'ha9b08d70b0b2c0;
  9'd415: event_word_c=56'hadb0b2c0b110b0;
  9'd416: event_word_c=56'hd0b110b0b16120;
  9'd417: event_word_c=56'h10b1b160b1da10;
  9'd418: event_word_c=56'h13b1da10b1ee20;
  9'd419: event_word_c=56'h48b1ee20b24c10;
  9'd420: event_word_c=56'h5eb24c10b29bc0;
  9'd421: event_word_c=56'ha2b29bc0b2da60;
  9'd422: event_word_c=56'ha0b2da60b33d00;
  9'd423: event_word_c=56'hb1b33d00b4d110;
  9'd424: event_word_c=56'h35b5c3e0b703f0;
  9'd425: event_word_c=56'h5fb703f0b756d0;
  9'd426: event_word_c=56'h82b756d0b7a9b0;
  9'd427: event_word_c=56'h6eb7a9b0b7f8a0;
  9'd428: event_word_c=56'h6eb7f8a0b8e9c0;
  9'd429: event_word_c=56'h5fb988f0b9da50;
  9'd430: event_word_c=56'h82b9da50ba2b80;
  9'd431: event_word_c=56'h6eba2b80ba7ce0;
  9'd432: event_word_c=56'h6eba7ce0bb2750;
  9'd433: event_word_c=56'h67bb2750bbae50;
  9'd434: event_word_c=56'h35bfcf10c11280;
  9'd435: event_word_c=56'h5fc11280c16170;
  9'd436: event_word_c=56'h82c16170c1b060;
  9'd437: event_word_c=56'h6ec1b060c20550;
  9'd438: event_word_c=56'h6ec20550c2f6a0;
  9'd439: event_word_c=56'h5fc395d0c3e550;
  9'd440: event_word_c=56'h82c3e550c43530;
  9'd441: event_word_c=56'h6ec43530c486f0;
  9'd442: event_word_c=56'h6ec486f0c528c0;
  9'd443: event_word_c=56'h67c528c0c5ce50;
  9'd444: event_word_c=56'h67c5eec0c60ed0;
  9'd445: event_word_c=56'haec60ed0c661b0;
  9'd446: event_word_c=56'h0dc661b0c68be0;
  9'd447: event_word_c=56'h6cc68be0c70590;
  9'd448: event_word_c=56'h25c70590c73f50;
  9'd449: event_word_c=56'h18c73f50c8c3d0;
  9'd450: event_word_c=56'h35ddf4c0df3fb0;
  9'd451: event_word_c=56'h5fdf3fb0df8ab0;
  9'd452: event_word_c=56'h82df8ab0dfdd90;
  9'd453: event_word_c=56'h6edfdd90e02b90;
  9'd454: event_word_c=56'h6ee02b90e13090;
  9'd455: event_word_c=56'h5fe1bd90e213d0;
  9'd456: event_word_c=56'h82e213d0e25b10;
  9'd457: event_word_c=56'h6ee25b10e2b0c0;
  9'd458: event_word_c=56'h6ee2b0c0e34d50;
  9'd459: event_word_c=56'h67e34d50e3de10;
  9'd460: event_word_c=56'h67e41620e43a20;
  9'd461: event_word_c=56'haee43a20e48c10;
  9'd462: event_word_c=56'h0de48c10e4b940;
  9'd463: event_word_c=56'h6ce4b940e53350;
  9'd464: event_word_c=56'h25e53350e563e0;
  9'd465: event_word_c=56'h18e563e0e7a5f0;
  default: event_word_c=56'd0;
 endcase
// END GENERATED lyric_events
end
reg[55:0] event_word;reg[23:0] rgb0,rgb1;reg[2:0] sync0,sync1;
reg[9:0] y0;reg[4:0] col0,col1;reg eligible0,ink1,active1;
reg[9:0] x0,x1,y1;
reg[31:0] font_row;
wire started=position>=event_word[47:24];
wire active_word=started && position<event_word[23:0];
wire[23:0] age=position-event_word[47:24];
reg signed[10:0] bounce;
always @* begin
 bounce=0;
 if(started && age<24'd17408)begin
  // 512-sample steps avoid the old 7..14-pixel frame jumps. A lighter
  // overshoot reduces LCD motion trails; glyphs are still rendered once.
  case(age[14:9])
  0:bounce=18;1:bounce=16;2:bounce=14;3:bounce=12;4:bounce=10;
  5:bounce=8;6:bounce=6;7:bounce=4;8:bounce=3;9:bounce=2;
  10:bounce=1;11:bounce=0;12:bounce=-1;13:bounce=-2;
  14:bounce=-3;15,16,17:bounce=-4;18,19:bounce=-3;
  20,21:bounce=-2;22,23:bounce=-1;
  default:bounce=0;
  endcase
  // Scale the lift with volume, tapering the addition to zero as it settles.
  if(bounce<0)bounce=bounce-(((-bounce)*$signed({1'b0,level[7:6]}))>>>2);
 end
end
wire signed[10:0] row_signed=$signed({1'b0,y0})-11'sd388-bounce;
wire row_valid=row_signed>=0 && row_signed<32;
// glyph index is the high byte of the event word, so 256 glyph slots are addressed.
wire[12:0] font_addr={event_word[55:48],row_signed[4:0]};
// Bottom gradient: two hard steps (x1/2 then x1/4) made the lower third of the
// photo look banded and crushed on a bright picture. The factor now falls
// linearly from 255 to 140 between lines 320 and 440, so the caption still sits
// on a darker area but the photo keeps its detail and no band edge is visible.
reg[9:0] shade_row;
always @* begin
 if(y_count<=10'd320) shade_row=10'd0;
  else if(y_count>=(SUBTITLE_QUALITY ? 10'd435 : 10'd440)) shade_row=10'd115;
 else shade_row=y_count-10'd320;
end
wire[7:0] shade_k=8'd255-shade_row[7:0];
wire[16:0] shade_r=rgb[23:16]*shade_k;
wire[16:0] shade_g=rgb[15:8]*shade_k;
wire[16:0] shade_b=rgb[7:0]*shade_k;
// k=255 must be a bit-exact pass-through, otherwise every photo pixel loses 1 LSB.
wire[23:0] shaded=(shade_k==8'd255) ? rgb : {shade_r[15:8],shade_g[15:8],shade_b[15:8]};
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x_count<=0;y_count<=0;de_d<=0;rgb0<=0;rgb1<=0;sync0<=0;sync1<=0;
  y0<=0;col0<=0;col1<=0;eligible0<=0;ink1<=0;active1<=0;
  x0<=0;x1<=0;y1<=0;
 end else begin
  de_d<=de;
  if(!vs)begin x_count<=0;y_count<=0;end
  else if(de) x_count<=pixel_x+10'd1;
  else if(de_d)begin x_count<=0;y_count<=y_count+10'd1;end
  rgb0<=shaded;rgb1<=rgb0;sync0<={hs,vs,de};sync1<=sync0;
  y0<=y_count;col0<=relative_x[4:0];
  x0<=pixel_x;x1<=x0;y1<=y0;
  eligible0<=in_line && de;col1<=col0;
  ink1<=eligible0 && started && row_valid;active1<=active_word;
 end
end
// Glyph ROM has a synchronous read without reset, allowing block-RAM inference.
// The syllable word comes from the generated case table and is registered here
// so both paths keep the same one-clock latency.
always @(posedge clk) begin
 font_row<={font3[font_addr],font2[font_addr],font1[font_addr],font0[font_addr]};
 event_word<=event_word_c;
end
assign {hs_out,vs_out,de_out}=sync1;
wire glyph_ink=ink1 && font_row[31-col1];
generate if(SUBTITLE_QUALITY)begin : readability
 // Flip-flop shift history, not another glyph ROM or inferred RAM. Only active
 // pixels advance it. After each edge history[640] belongs to (x-1,y-1) of
 // the CURRENT rendered frame; blanking consumes no history locations.
 reg[640:0] ink_history;
 always @(posedge clk or posedge rst)begin
  if(rst)ink_history<=641'd0;
  else if(sync1[0])ink_history<={ink_history[639:0],glyph_ink};
 end
 // No VS clear is needed: y=0 masks stale history until the current first
 // row has filled the delay. Avoid641 replicated VS gates in the shift chain.
 // x=0 must not wrap to the previous line's final column. y=0 never reads a
 // previous frame. The foreground has absolute priority over its dark cast.
 wire cast_ink=sync1[0] && (x1!=0) && (y1!=0) && ink_history[640];
 wire[7:0] cast_r={2'b00,rgb1[23:18]}+8'd33;
 wire[7:0] cast_g={2'b00,rgb1[15:10]}+8'd27;
 wire[7:0] cast_b={2'b00,rgb1[7:2]}+8'd20;
 assign rgb_out=glyph_ink ? (active1?24'hf5c784:24'hf6ecd4) :
                cast_ink ? {cast_r,cast_g,cast_b} : rgb1;
end else begin : legacy_readability
 assign rgb_out=glyph_ink ? (active1?24'hf5c784:24'hf6ecd4):rgb1;
end endgenerate
endmodule
