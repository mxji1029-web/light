// 1024-point real-input FFT, natural-order bins 1..512, normalized by 1/N.
// Periodic Hann and Q15 twiddles include exact +1 (signed17 value32768).
// All reductions round nearest, ties away from zero. Saturation and capture
// ownership failures set sticky overrun; no arithmetic overflow wraps silently.
// Two spectrum_complex_ram banks, each built from two BRAM32K primitives.
// The combinational constant cases below intentionally contain no clocked ROM.
module spectrum_fft1024 (
    input wire clk,
    input wire rst,
    input wire sample_valid,
    input wire signed [15:0] sample_data,
    input wire paused,
    output reg block_ready,
    output reg [31:0] bin_power,
    output reg [8:0] bin_index,
    output reg bin_valid,
    output reg overrun
);
    localparam S_IDLE=4'd0, S_READ=4'd1, S_LATCH=4'd2,
               S_MUL=4'd3, S_ROTATE=4'd4, S_BFLY=4'd5, S_WRITE=4'd6,
               S_OUT_READ=4'd7, S_OUT_MUL=4'd8, S_OUT_EMIT=4'd9;

    function [9:0] reverse10;
        input [9:0] value;
        integer i;
        begin for (i=0;i<10;i=i+1) reverse10[i]=value[9-i]; end
    endfunction
    function signed [34:0] round_q15;
        input signed [34:0] value;
        begin
            if (value < 0) round_q15=-(((-value)+35'sd16384) >>> 15);
            else round_q15=(value+35'sd16384) >>> 15;
        end
    endfunction
    function signed [34:0] round_half;
        input signed [34:0] value;
        begin
            if (value < 0) round_half=-(((-value)+35'sd1) >>> 1);
            else round_half=(value+35'sd1) >>> 1;
        end
    endfunction
    function [15:0] saturate16;
        input signed [34:0] value;
        begin
            if (value > 35'sd32767) saturate16=16'h7fff;
            else if (value < -35'sd32768) saturate16=16'h8000;
            else saturate16=value[15:0];
        end
    endfunction
    function [16:0] hann_q15;
        input [9:0] address;
        reg [9:0] folded;
        begin
            folded=(address<=10'd512) ? address : (11'd1024-{1'b0,address});
            case (folded)
                10'd0: hann_q15=17'd0;
                10'd1: hann_q15=17'd0;
                10'd2: hann_q15=17'd1;
                10'd3: hann_q15=17'd3;
                10'd4: hann_q15=17'd5;
                10'd5: hann_q15=17'd8;
                10'd6: hann_q15=17'd11;
                10'd7: hann_q15=17'd15;
                10'd8: hann_q15=17'd20;
                10'd9: hann_q15=17'd25;
                10'd10: hann_q15=17'd31;
                10'd11: hann_q15=17'd37;
                10'd12: hann_q15=17'd44;
                10'd13: hann_q15=17'd52;
                10'd14: hann_q15=17'd60;
                10'd15: hann_q15=17'd69;
                10'd16: hann_q15=17'd79;
                10'd17: hann_q15=17'd89;
                10'd18: hann_q15=17'd100;
                10'd19: hann_q15=17'd111;
                10'd20: hann_q15=17'd123;
                10'd21: hann_q15=17'd136;
                10'd22: hann_q15=17'd149;
                10'd23: hann_q15=17'd163;
                10'd24: hann_q15=17'd177;
                10'd25: hann_q15=17'd192;
                10'd26: hann_q15=17'd208;
                10'd27: hann_q15=17'd224;
                10'd28: hann_q15=17'd241;
                10'd29: hann_q15=17'd259;
                10'd30: hann_q15=17'd277;
                10'd31: hann_q15=17'd296;
                10'd32: hann_q15=17'd315;
                10'd33: hann_q15=17'd335;
                10'd34: hann_q15=17'd355;
                10'd35: hann_q15=17'd376;
                10'd36: hann_q15=17'd398;
                10'd37: hann_q15=17'd420;
                10'd38: hann_q15=17'd443;
                10'd39: hann_q15=17'd467;
                10'd40: hann_q15=17'd491;
                10'd41: hann_q15=17'd516;
                10'd42: hann_q15=17'd541;
                10'd43: hann_q15=17'd567;
                10'd44: hann_q15=17'd593;
                10'd45: hann_q15=17'd621;
                10'd46: hann_q15=17'd648;
                10'd47: hann_q15=17'd677;
                10'd48: hann_q15=17'd705;
                10'd49: hann_q15=17'd735;
                10'd50: hann_q15=17'd765;
                10'd51: hann_q15=17'd796;
                10'd52: hann_q15=17'd827;
                10'd53: hann_q15=17'd859;
                10'd54: hann_q15=17'd891;
                10'd55: hann_q15=17'd924;
                10'd56: hann_q15=17'd958;
                10'd57: hann_q15=17'd992;
                10'd58: hann_q15=17'd1027;
                10'd59: hann_q15=17'd1062;
                10'd60: hann_q15=17'd1098;
                10'd61: hann_q15=17'd1134;
                10'd62: hann_q15=17'd1171;
                10'd63: hann_q15=17'd1209;
                10'd64: hann_q15=17'd1247;
                10'd65: hann_q15=17'd1286;
                10'd66: hann_q15=17'd1325;
                10'd67: hann_q15=17'd1365;
                10'd68: hann_q15=17'd1406;
                10'd69: hann_q15=17'd1447;
                10'd70: hann_q15=17'd1488;
                10'd71: hann_q15=17'd1530;
                10'd72: hann_q15=17'd1573;
                10'd73: hann_q15=17'd1616;
                10'd74: hann_q15=17'd1660;
                10'd75: hann_q15=17'd1704;
                10'd76: hann_q15=17'd1749;
                10'd77: hann_q15=17'd1795;
                10'd78: hann_q15=17'd1841;
                10'd79: hann_q15=17'd1887;
                10'd80: hann_q15=17'd1935;
                10'd81: hann_q15=17'd1982;
                10'd82: hann_q15=17'd2030;
                10'd83: hann_q15=17'd2079;
                10'd84: hann_q15=17'd2128;
                10'd85: hann_q15=17'd2178;
                10'd86: hann_q15=17'd2229;
                10'd87: hann_q15=17'd2280;
                10'd88: hann_q15=17'd2331;
                10'd89: hann_q15=17'd2383;
                10'd90: hann_q15=17'd2435;
                10'd91: hann_q15=17'd2488;
                10'd92: hann_q15=17'd2542;
                10'd93: hann_q15=17'd2596;
                10'd94: hann_q15=17'd2651;
                10'd95: hann_q15=17'd2706;
                10'd96: hann_q15=17'd2761;
                10'd97: hann_q15=17'd2817;
                10'd98: hann_q15=17'd2874;
                10'd99: hann_q15=17'd2931;
                10'd100: hann_q15=17'd2989;
                10'd101: hann_q15=17'd3047;
                10'd102: hann_q15=17'd3105;
                10'd103: hann_q15=17'd3165;
                10'd104: hann_q15=17'd3224;
                10'd105: hann_q15=17'd3284;
                10'd106: hann_q15=17'd3345;
                10'd107: hann_q15=17'd3406;
                10'd108: hann_q15=17'd3468;
                10'd109: hann_q15=17'd3530;
                10'd110: hann_q15=17'd3592;
                10'd111: hann_q15=17'd3655;
                10'd112: hann_q15=17'd3719;
                10'd113: hann_q15=17'd3783;
                10'd114: hann_q15=17'd3847;
                10'd115: hann_q15=17'd3912;
                10'd116: hann_q15=17'd3978;
                10'd117: hann_q15=17'd4044;
                10'd118: hann_q15=17'd4110;
                10'd119: hann_q15=17'd4177;
                10'd120: hann_q15=17'd4244;
                10'd121: hann_q15=17'd4312;
                10'd122: hann_q15=17'd4380;
                10'd123: hann_q15=17'd4449;
                10'd124: hann_q15=17'd4518;
                10'd125: hann_q15=17'd4587;
                10'd126: hann_q15=17'd4657;
                10'd127: hann_q15=17'd4728;
                10'd128: hann_q15=17'd4799;
                10'd129: hann_q15=17'd4870;
                10'd130: hann_q15=17'd4942;
                10'd131: hann_q15=17'd5014;
                10'd132: hann_q15=17'd5087;
                10'd133: hann_q15=17'd5160;
                10'd134: hann_q15=17'd5233;
                10'd135: hann_q15=17'd5307;
                10'd136: hann_q15=17'd5381;
                10'd137: hann_q15=17'd5456;
                10'd138: hann_q15=17'd5531;
                10'd139: hann_q15=17'd5606;
                10'd140: hann_q15=17'd5682;
                10'd141: hann_q15=17'd5759;
                10'd142: hann_q15=17'd5835;
                10'd143: hann_q15=17'd5913;
                10'd144: hann_q15=17'd5990;
                10'd145: hann_q15=17'd6068;
                10'd146: hann_q15=17'd6146;
                10'd147: hann_q15=17'd6225;
                10'd148: hann_q15=17'd6304;
                10'd149: hann_q15=17'd6383;
                10'd150: hann_q15=17'd6463;
                10'd151: hann_q15=17'd6543;
                10'd152: hann_q15=17'd6624;
                10'd153: hann_q15=17'd6705;
                10'd154: hann_q15=17'd6786;
                10'd155: hann_q15=17'd6868;
                10'd156: hann_q15=17'd6950;
                10'd157: hann_q15=17'd7032;
                10'd158: hann_q15=17'd7115;
                10'd159: hann_q15=17'd7198;
                10'd160: hann_q15=17'd7282;
                10'd161: hann_q15=17'd7365;
                10'd162: hann_q15=17'd7449;
                10'd163: hann_q15=17'd7534;
                10'd164: hann_q15=17'd7619;
                10'd165: hann_q15=17'd7704;
                10'd166: hann_q15=17'd7789;
                10'd167: hann_q15=17'd7875;
                10'd168: hann_q15=17'd7961;
                10'd169: hann_q15=17'd8047;
                10'd170: hann_q15=17'd8134;
                10'd171: hann_q15=17'd8221;
                10'd172: hann_q15=17'd8308;
                10'd173: hann_q15=17'd8396;
                10'd174: hann_q15=17'd8484;
                10'd175: hann_q15=17'd8572;
                10'd176: hann_q15=17'd8661;
                10'd177: hann_q15=17'd8749;
                10'd178: hann_q15=17'd8839;
                10'd179: hann_q15=17'd8928;
                10'd180: hann_q15=17'd9018;
                10'd181: hann_q15=17'd9108;
                10'd182: hann_q15=17'd9198;
                10'd183: hann_q15=17'd9288;
                10'd184: hann_q15=17'd9379;
                10'd185: hann_q15=17'd9470;
                10'd186: hann_q15=17'd9561;
                10'd187: hann_q15=17'd9653;
                10'd188: hann_q15=17'd9745;
                10'd189: hann_q15=17'd9837;
                10'd190: hann_q15=17'd9929;
                10'd191: hann_q15=17'd10021;
                10'd192: hann_q15=17'd10114;
                10'd193: hann_q15=17'd10207;
                10'd194: hann_q15=17'd10300;
                10'd195: hann_q15=17'd10394;
                10'd196: hann_q15=17'd10487;
                10'd197: hann_q15=17'd10581;
                10'd198: hann_q15=17'd10676;
                10'd199: hann_q15=17'd10770;
                10'd200: hann_q15=17'd10864;
                10'd201: hann_q15=17'd10959;
                10'd202: hann_q15=17'd11054;
                10'd203: hann_q15=17'd11149;
                10'd204: hann_q15=17'd11245;
                10'd205: hann_q15=17'd11340;
                10'd206: hann_q15=17'd11436;
                10'd207: hann_q15=17'd11532;
                10'd208: hann_q15=17'd11628;
                10'd209: hann_q15=17'd11724;
                10'd210: hann_q15=17'd11821;
                10'd211: hann_q15=17'd11917;
                10'd212: hann_q15=17'd12014;
                10'd213: hann_q15=17'd12111;
                10'd214: hann_q15=17'd12208;
                10'd215: hann_q15=17'd12306;
                10'd216: hann_q15=17'd12403;
                10'd217: hann_q15=17'd12501;
                10'd218: hann_q15=17'd12598;
                10'd219: hann_q15=17'd12696;
                10'd220: hann_q15=17'd12794;
                10'd221: hann_q15=17'd12892;
                10'd222: hann_q15=17'd12991;
                10'd223: hann_q15=17'd13089;
                10'd224: hann_q15=17'd13188;
                10'd225: hann_q15=17'd13286;
                10'd226: hann_q15=17'd13385;
                10'd227: hann_q15=17'd13484;
                10'd228: hann_q15=17'd13583;
                10'd229: hann_q15=17'd13682;
                10'd230: hann_q15=17'd13781;
                10'd231: hann_q15=17'd13881;
                10'd232: hann_q15=17'd13980;
                10'd233: hann_q15=17'd14079;
                10'd234: hann_q15=17'd14179;
                10'd235: hann_q15=17'd14279;
                10'd236: hann_q15=17'd14378;
                10'd237: hann_q15=17'd14478;
                10'd238: hann_q15=17'd14578;
                10'd239: hann_q15=17'd14678;
                10'd240: hann_q15=17'd14778;
                10'd241: hann_q15=17'd14878;
                10'd242: hann_q15=17'd14978;
                10'd243: hann_q15=17'd15078;
                10'd244: hann_q15=17'd15179;
                10'd245: hann_q15=17'd15279;
                10'd246: hann_q15=17'd15379;
                10'd247: hann_q15=17'd15480;
                10'd248: hann_q15=17'd15580;
                10'd249: hann_q15=17'd15680;
                10'd250: hann_q15=17'd15781;
                10'd251: hann_q15=17'd15881;
                10'd252: hann_q15=17'd15982;
                10'd253: hann_q15=17'd16082;
                10'd254: hann_q15=17'd16183;
                10'd255: hann_q15=17'd16283;
                10'd256: hann_q15=17'd16384;
                10'd257: hann_q15=17'd16485;
                10'd258: hann_q15=17'd16585;
                10'd259: hann_q15=17'd16686;
                10'd260: hann_q15=17'd16786;
                10'd261: hann_q15=17'd16887;
                10'd262: hann_q15=17'd16987;
                10'd263: hann_q15=17'd17088;
                10'd264: hann_q15=17'd17188;
                10'd265: hann_q15=17'd17288;
                10'd266: hann_q15=17'd17389;
                10'd267: hann_q15=17'd17489;
                10'd268: hann_q15=17'd17589;
                10'd269: hann_q15=17'd17690;
                10'd270: hann_q15=17'd17790;
                10'd271: hann_q15=17'd17890;
                10'd272: hann_q15=17'd17990;
                10'd273: hann_q15=17'd18090;
                10'd274: hann_q15=17'd18190;
                10'd275: hann_q15=17'd18290;
                10'd276: hann_q15=17'd18390;
                10'd277: hann_q15=17'd18489;
                10'd278: hann_q15=17'd18589;
                10'd279: hann_q15=17'd18689;
                10'd280: hann_q15=17'd18788;
                10'd281: hann_q15=17'd18887;
                10'd282: hann_q15=17'd18987;
                10'd283: hann_q15=17'd19086;
                10'd284: hann_q15=17'd19185;
                10'd285: hann_q15=17'd19284;
                10'd286: hann_q15=17'd19383;
                10'd287: hann_q15=17'd19482;
                10'd288: hann_q15=17'd19580;
                10'd289: hann_q15=17'd19679;
                10'd290: hann_q15=17'd19777;
                10'd291: hann_q15=17'd19876;
                10'd292: hann_q15=17'd19974;
                10'd293: hann_q15=17'd20072;
                10'd294: hann_q15=17'd20170;
                10'd295: hann_q15=17'd20267;
                10'd296: hann_q15=17'd20365;
                10'd297: hann_q15=17'd20462;
                10'd298: hann_q15=17'd20560;
                10'd299: hann_q15=17'd20657;
                10'd300: hann_q15=17'd20754;
                10'd301: hann_q15=17'd20851;
                10'd302: hann_q15=17'd20947;
                10'd303: hann_q15=17'd21044;
                10'd304: hann_q15=17'd21140;
                10'd305: hann_q15=17'd21236;
                10'd306: hann_q15=17'd21332;
                10'd307: hann_q15=17'd21428;
                10'd308: hann_q15=17'd21523;
                10'd309: hann_q15=17'd21619;
                10'd310: hann_q15=17'd21714;
                10'd311: hann_q15=17'd21809;
                10'd312: hann_q15=17'd21904;
                10'd313: hann_q15=17'd21998;
                10'd314: hann_q15=17'd22092;
                10'd315: hann_q15=17'd22187;
                10'd316: hann_q15=17'd22281;
                10'd317: hann_q15=17'd22374;
                10'd318: hann_q15=17'd22468;
                10'd319: hann_q15=17'd22561;
                10'd320: hann_q15=17'd22654;
                10'd321: hann_q15=17'd22747;
                10'd322: hann_q15=17'd22839;
                10'd323: hann_q15=17'd22931;
                10'd324: hann_q15=17'd23023;
                10'd325: hann_q15=17'd23115;
                10'd326: hann_q15=17'd23207;
                10'd327: hann_q15=17'd23298;
                10'd328: hann_q15=17'd23389;
                10'd329: hann_q15=17'd23480;
                10'd330: hann_q15=17'd23570;
                10'd331: hann_q15=17'd23660;
                10'd332: hann_q15=17'd23750;
                10'd333: hann_q15=17'd23840;
                10'd334: hann_q15=17'd23929;
                10'd335: hann_q15=17'd24019;
                10'd336: hann_q15=17'd24107;
                10'd337: hann_q15=17'd24196;
                10'd338: hann_q15=17'd24284;
                10'd339: hann_q15=17'd24372;
                10'd340: hann_q15=17'd24460;
                10'd341: hann_q15=17'd24547;
                10'd342: hann_q15=17'd24634;
                10'd343: hann_q15=17'd24721;
                10'd344: hann_q15=17'd24807;
                10'd345: hann_q15=17'd24893;
                10'd346: hann_q15=17'd24979;
                10'd347: hann_q15=17'd25064;
                10'd348: hann_q15=17'd25149;
                10'd349: hann_q15=17'd25234;
                10'd350: hann_q15=17'd25319;
                10'd351: hann_q15=17'd25403;
                10'd352: hann_q15=17'd25486;
                10'd353: hann_q15=17'd25570;
                10'd354: hann_q15=17'd25653;
                10'd355: hann_q15=17'd25736;
                10'd356: hann_q15=17'd25818;
                10'd357: hann_q15=17'd25900;
                10'd358: hann_q15=17'd25982;
                10'd359: hann_q15=17'd26063;
                10'd360: hann_q15=17'd26144;
                10'd361: hann_q15=17'd26225;
                10'd362: hann_q15=17'd26305;
                10'd363: hann_q15=17'd26385;
                10'd364: hann_q15=17'd26464;
                10'd365: hann_q15=17'd26543;
                10'd366: hann_q15=17'd26622;
                10'd367: hann_q15=17'd26700;
                10'd368: hann_q15=17'd26778;
                10'd369: hann_q15=17'd26855;
                10'd370: hann_q15=17'd26933;
                10'd371: hann_q15=17'd27009;
                10'd372: hann_q15=17'd27086;
                10'd373: hann_q15=17'd27162;
                10'd374: hann_q15=17'd27237;
                10'd375: hann_q15=17'd27312;
                10'd376: hann_q15=17'd27387;
                10'd377: hann_q15=17'd27461;
                10'd378: hann_q15=17'd27535;
                10'd379: hann_q15=17'd27608;
                10'd380: hann_q15=17'd27681;
                10'd381: hann_q15=17'd27754;
                10'd382: hann_q15=17'd27826;
                10'd383: hann_q15=17'd27898;
                10'd384: hann_q15=17'd27969;
                10'd385: hann_q15=17'd28040;
                10'd386: hann_q15=17'd28111;
                10'd387: hann_q15=17'd28181;
                10'd388: hann_q15=17'd28250;
                10'd389: hann_q15=17'd28319;
                10'd390: hann_q15=17'd28388;
                10'd391: hann_q15=17'd28456;
                10'd392: hann_q15=17'd28524;
                10'd393: hann_q15=17'd28591;
                10'd394: hann_q15=17'd28658;
                10'd395: hann_q15=17'd28724;
                10'd396: hann_q15=17'd28790;
                10'd397: hann_q15=17'd28856;
                10'd398: hann_q15=17'd28921;
                10'd399: hann_q15=17'd28985;
                10'd400: hann_q15=17'd29049;
                10'd401: hann_q15=17'd29113;
                10'd402: hann_q15=17'd29176;
                10'd403: hann_q15=17'd29238;
                10'd404: hann_q15=17'd29300;
                10'd405: hann_q15=17'd29362;
                10'd406: hann_q15=17'd29423;
                10'd407: hann_q15=17'd29484;
                10'd408: hann_q15=17'd29544;
                10'd409: hann_q15=17'd29603;
                10'd410: hann_q15=17'd29663;
                10'd411: hann_q15=17'd29721;
                10'd412: hann_q15=17'd29779;
                10'd413: hann_q15=17'd29837;
                10'd414: hann_q15=17'd29894;
                10'd415: hann_q15=17'd29951;
                10'd416: hann_q15=17'd30007;
                10'd417: hann_q15=17'd30062;
                10'd418: hann_q15=17'd30117;
                10'd419: hann_q15=17'd30172;
                10'd420: hann_q15=17'd30226;
                10'd421: hann_q15=17'd30280;
                10'd422: hann_q15=17'd30333;
                10'd423: hann_q15=17'd30385;
                10'd424: hann_q15=17'd30437;
                10'd425: hann_q15=17'd30488;
                10'd426: hann_q15=17'd30539;
                10'd427: hann_q15=17'd30590;
                10'd428: hann_q15=17'd30640;
                10'd429: hann_q15=17'd30689;
                10'd430: hann_q15=17'd30738;
                10'd431: hann_q15=17'd30786;
                10'd432: hann_q15=17'd30833;
                10'd433: hann_q15=17'd30881;
                10'd434: hann_q15=17'd30927;
                10'd435: hann_q15=17'd30973;
                10'd436: hann_q15=17'd31019;
                10'd437: hann_q15=17'd31064;
                10'd438: hann_q15=17'd31108;
                10'd439: hann_q15=17'd31152;
                10'd440: hann_q15=17'd31195;
                10'd441: hann_q15=17'd31238;
                10'd442: hann_q15=17'd31280;
                10'd443: hann_q15=17'd31321;
                10'd444: hann_q15=17'd31362;
                10'd445: hann_q15=17'd31403;
                10'd446: hann_q15=17'd31443;
                10'd447: hann_q15=17'd31482;
                10'd448: hann_q15=17'd31521;
                10'd449: hann_q15=17'd31559;
                10'd450: hann_q15=17'd31597;
                10'd451: hann_q15=17'd31634;
                10'd452: hann_q15=17'd31670;
                10'd453: hann_q15=17'd31706;
                10'd454: hann_q15=17'd31741;
                10'd455: hann_q15=17'd31776;
                10'd456: hann_q15=17'd31810;
                10'd457: hann_q15=17'd31844;
                10'd458: hann_q15=17'd31877;
                10'd459: hann_q15=17'd31909;
                10'd460: hann_q15=17'd31941;
                10'd461: hann_q15=17'd31972;
                10'd462: hann_q15=17'd32003;
                10'd463: hann_q15=17'd32033;
                10'd464: hann_q15=17'd32063;
                10'd465: hann_q15=17'd32091;
                10'd466: hann_q15=17'd32120;
                10'd467: hann_q15=17'd32147;
                10'd468: hann_q15=17'd32175;
                10'd469: hann_q15=17'd32201;
                10'd470: hann_q15=17'd32227;
                10'd471: hann_q15=17'd32252;
                10'd472: hann_q15=17'd32277;
                10'd473: hann_q15=17'd32301;
                10'd474: hann_q15=17'd32325;
                10'd475: hann_q15=17'd32348;
                10'd476: hann_q15=17'd32370;
                10'd477: hann_q15=17'd32392;
                10'd478: hann_q15=17'd32413;
                10'd479: hann_q15=17'd32433;
                10'd480: hann_q15=17'd32453;
                10'd481: hann_q15=17'd32472;
                10'd482: hann_q15=17'd32491;
                10'd483: hann_q15=17'd32509;
                10'd484: hann_q15=17'd32527;
                10'd485: hann_q15=17'd32544;
                10'd486: hann_q15=17'd32560;
                10'd487: hann_q15=17'd32576;
                10'd488: hann_q15=17'd32591;
                10'd489: hann_q15=17'd32605;
                10'd490: hann_q15=17'd32619;
                10'd491: hann_q15=17'd32632;
                10'd492: hann_q15=17'd32645;
                10'd493: hann_q15=17'd32657;
                10'd494: hann_q15=17'd32668;
                10'd495: hann_q15=17'd32679;
                10'd496: hann_q15=17'd32689;
                10'd497: hann_q15=17'd32699;
                10'd498: hann_q15=17'd32708;
                10'd499: hann_q15=17'd32716;
                10'd500: hann_q15=17'd32724;
                10'd501: hann_q15=17'd32731;
                10'd502: hann_q15=17'd32737;
                10'd503: hann_q15=17'd32743;
                10'd504: hann_q15=17'd32748;
                10'd505: hann_q15=17'd32753;
                10'd506: hann_q15=17'd32757;
                10'd507: hann_q15=17'd32760;
                10'd508: hann_q15=17'd32763;
                10'd509: hann_q15=17'd32765;
                10'd510: hann_q15=17'd32767;
                10'd511: hann_q15=17'd32768;
                10'd512: hann_q15=17'd32768;
                default: hann_q15=17'd0;
            endcase
        end
    endfunction
    function [16:0] sine_q15;
        input [8:0] angle;
        begin
            case(angle)
                9'd0: sine_q15=17'd0;
                9'd1: sine_q15=17'd201;
                9'd2: sine_q15=17'd402;
                9'd3: sine_q15=17'd603;
                9'd4: sine_q15=17'd804;
                9'd5: sine_q15=17'd1005;
                9'd6: sine_q15=17'd1206;
                9'd7: sine_q15=17'd1407;
                9'd8: sine_q15=17'd1608;
                9'd9: sine_q15=17'd1809;
                9'd10: sine_q15=17'd2009;
                9'd11: sine_q15=17'd2210;
                9'd12: sine_q15=17'd2411;
                9'd13: sine_q15=17'd2611;
                9'd14: sine_q15=17'd2811;
                9'd15: sine_q15=17'd3012;
                9'd16: sine_q15=17'd3212;
                9'd17: sine_q15=17'd3412;
                9'd18: sine_q15=17'd3612;
                9'd19: sine_q15=17'd3812;
                9'd20: sine_q15=17'd4011;
                9'd21: sine_q15=17'd4211;
                9'd22: sine_q15=17'd4410;
                9'd23: sine_q15=17'd4609;
                9'd24: sine_q15=17'd4808;
                9'd25: sine_q15=17'd5007;
                9'd26: sine_q15=17'd5205;
                9'd27: sine_q15=17'd5404;
                9'd28: sine_q15=17'd5602;
                9'd29: sine_q15=17'd5800;
                9'd30: sine_q15=17'd5998;
                9'd31: sine_q15=17'd6195;
                9'd32: sine_q15=17'd6393;
                9'd33: sine_q15=17'd6590;
                9'd34: sine_q15=17'd6787;
                9'd35: sine_q15=17'd6983;
                9'd36: sine_q15=17'd7180;
                9'd37: sine_q15=17'd7376;
                9'd38: sine_q15=17'd7571;
                9'd39: sine_q15=17'd7767;
                9'd40: sine_q15=17'd7962;
                9'd41: sine_q15=17'd8157;
                9'd42: sine_q15=17'd8351;
                9'd43: sine_q15=17'd8546;
                9'd44: sine_q15=17'd8740;
                9'd45: sine_q15=17'd8933;
                9'd46: sine_q15=17'd9127;
                9'd47: sine_q15=17'd9319;
                9'd48: sine_q15=17'd9512;
                9'd49: sine_q15=17'd9704;
                9'd50: sine_q15=17'd9896;
                9'd51: sine_q15=17'd10088;
                9'd52: sine_q15=17'd10279;
                9'd53: sine_q15=17'd10469;
                9'd54: sine_q15=17'd10660;
                9'd55: sine_q15=17'd10850;
                9'd56: sine_q15=17'd11039;
                9'd57: sine_q15=17'd11228;
                9'd58: sine_q15=17'd11417;
                9'd59: sine_q15=17'd11605;
                9'd60: sine_q15=17'd11793;
                9'd61: sine_q15=17'd11980;
                9'd62: sine_q15=17'd12167;
                9'd63: sine_q15=17'd12354;
                9'd64: sine_q15=17'd12540;
                9'd65: sine_q15=17'd12725;
                9'd66: sine_q15=17'd12910;
                9'd67: sine_q15=17'd13095;
                9'd68: sine_q15=17'd13279;
                9'd69: sine_q15=17'd13463;
                9'd70: sine_q15=17'd13646;
                9'd71: sine_q15=17'd13828;
                9'd72: sine_q15=17'd14010;
                9'd73: sine_q15=17'd14192;
                9'd74: sine_q15=17'd14373;
                9'd75: sine_q15=17'd14553;
                9'd76: sine_q15=17'd14733;
                9'd77: sine_q15=17'd14912;
                9'd78: sine_q15=17'd15091;
                9'd79: sine_q15=17'd15269;
                9'd80: sine_q15=17'd15447;
                9'd81: sine_q15=17'd15624;
                9'd82: sine_q15=17'd15800;
                9'd83: sine_q15=17'd15976;
                9'd84: sine_q15=17'd16151;
                9'd85: sine_q15=17'd16326;
                9'd86: sine_q15=17'd16500;
                9'd87: sine_q15=17'd16673;
                9'd88: sine_q15=17'd16846;
                9'd89: sine_q15=17'd17018;
                9'd90: sine_q15=17'd17190;
                9'd91: sine_q15=17'd17361;
                9'd92: sine_q15=17'd17531;
                9'd93: sine_q15=17'd17700;
                9'd94: sine_q15=17'd17869;
                9'd95: sine_q15=17'd18037;
                9'd96: sine_q15=17'd18205;
                9'd97: sine_q15=17'd18372;
                9'd98: sine_q15=17'd18538;
                9'd99: sine_q15=17'd18703;
                9'd100: sine_q15=17'd18868;
                9'd101: sine_q15=17'd19032;
                9'd102: sine_q15=17'd19195;
                9'd103: sine_q15=17'd19358;
                9'd104: sine_q15=17'd19520;
                9'd105: sine_q15=17'd19681;
                9'd106: sine_q15=17'd19841;
                9'd107: sine_q15=17'd20001;
                9'd108: sine_q15=17'd20160;
                9'd109: sine_q15=17'd20318;
                9'd110: sine_q15=17'd20475;
                9'd111: sine_q15=17'd20632;
                9'd112: sine_q15=17'd20788;
                9'd113: sine_q15=17'd20943;
                9'd114: sine_q15=17'd21097;
                9'd115: sine_q15=17'd21251;
                9'd116: sine_q15=17'd21403;
                9'd117: sine_q15=17'd21555;
                9'd118: sine_q15=17'd21706;
                9'd119: sine_q15=17'd21856;
                9'd120: sine_q15=17'd22006;
                9'd121: sine_q15=17'd22154;
                9'd122: sine_q15=17'd22302;
                9'd123: sine_q15=17'd22449;
                9'd124: sine_q15=17'd22595;
                9'd125: sine_q15=17'd22740;
                9'd126: sine_q15=17'd22884;
                9'd127: sine_q15=17'd23028;
                9'd128: sine_q15=17'd23170;
                9'd129: sine_q15=17'd23312;
                9'd130: sine_q15=17'd23453;
                9'd131: sine_q15=17'd23593;
                9'd132: sine_q15=17'd23732;
                9'd133: sine_q15=17'd23870;
                9'd134: sine_q15=17'd24008;
                9'd135: sine_q15=17'd24144;
                9'd136: sine_q15=17'd24279;
                9'd137: sine_q15=17'd24414;
                9'd138: sine_q15=17'd24548;
                9'd139: sine_q15=17'd24680;
                9'd140: sine_q15=17'd24812;
                9'd141: sine_q15=17'd24943;
                9'd142: sine_q15=17'd25073;
                9'd143: sine_q15=17'd25202;
                9'd144: sine_q15=17'd25330;
                9'd145: sine_q15=17'd25457;
                9'd146: sine_q15=17'd25583;
                9'd147: sine_q15=17'd25708;
                9'd148: sine_q15=17'd25833;
                9'd149: sine_q15=17'd25956;
                9'd150: sine_q15=17'd26078;
                9'd151: sine_q15=17'd26199;
                9'd152: sine_q15=17'd26320;
                9'd153: sine_q15=17'd26439;
                9'd154: sine_q15=17'd26557;
                9'd155: sine_q15=17'd26674;
                9'd156: sine_q15=17'd26791;
                9'd157: sine_q15=17'd26906;
                9'd158: sine_q15=17'd27020;
                9'd159: sine_q15=17'd27133;
                9'd160: sine_q15=17'd27246;
                9'd161: sine_q15=17'd27357;
                9'd162: sine_q15=17'd27467;
                9'd163: sine_q15=17'd27576;
                9'd164: sine_q15=17'd27684;
                9'd165: sine_q15=17'd27791;
                9'd166: sine_q15=17'd27897;
                9'd167: sine_q15=17'd28002;
                9'd168: sine_q15=17'd28106;
                9'd169: sine_q15=17'd28209;
                9'd170: sine_q15=17'd28311;
                9'd171: sine_q15=17'd28411;
                9'd172: sine_q15=17'd28511;
                9'd173: sine_q15=17'd28610;
                9'd174: sine_q15=17'd28707;
                9'd175: sine_q15=17'd28803;
                9'd176: sine_q15=17'd28899;
                9'd177: sine_q15=17'd28993;
                9'd178: sine_q15=17'd29086;
                9'd179: sine_q15=17'd29178;
                9'd180: sine_q15=17'd29269;
                9'd181: sine_q15=17'd29359;
                9'd182: sine_q15=17'd29448;
                9'd183: sine_q15=17'd29535;
                9'd184: sine_q15=17'd29622;
                9'd185: sine_q15=17'd29707;
                9'd186: sine_q15=17'd29792;
                9'd187: sine_q15=17'd29875;
                9'd188: sine_q15=17'd29957;
                9'd189: sine_q15=17'd30038;
                9'd190: sine_q15=17'd30118;
                9'd191: sine_q15=17'd30196;
                9'd192: sine_q15=17'd30274;
                9'd193: sine_q15=17'd30350;
                9'd194: sine_q15=17'd30425;
                9'd195: sine_q15=17'd30499;
                9'd196: sine_q15=17'd30572;
                9'd197: sine_q15=17'd30644;
                9'd198: sine_q15=17'd30715;
                9'd199: sine_q15=17'd30784;
                9'd200: sine_q15=17'd30853;
                9'd201: sine_q15=17'd30920;
                9'd202: sine_q15=17'd30986;
                9'd203: sine_q15=17'd31050;
                9'd204: sine_q15=17'd31114;
                9'd205: sine_q15=17'd31177;
                9'd206: sine_q15=17'd31238;
                9'd207: sine_q15=17'd31298;
                9'd208: sine_q15=17'd31357;
                9'd209: sine_q15=17'd31415;
                9'd210: sine_q15=17'd31471;
                9'd211: sine_q15=17'd31527;
                9'd212: sine_q15=17'd31581;
                9'd213: sine_q15=17'd31634;
                9'd214: sine_q15=17'd31686;
                9'd215: sine_q15=17'd31737;
                9'd216: sine_q15=17'd31786;
                9'd217: sine_q15=17'd31834;
                9'd218: sine_q15=17'd31881;
                9'd219: sine_q15=17'd31927;
                9'd220: sine_q15=17'd31972;
                9'd221: sine_q15=17'd32015;
                9'd222: sine_q15=17'd32058;
                9'd223: sine_q15=17'd32099;
                9'd224: sine_q15=17'd32138;
                9'd225: sine_q15=17'd32177;
                9'd226: sine_q15=17'd32214;
                9'd227: sine_q15=17'd32251;
                9'd228: sine_q15=17'd32286;
                9'd229: sine_q15=17'd32319;
                9'd230: sine_q15=17'd32352;
                9'd231: sine_q15=17'd32383;
                9'd232: sine_q15=17'd32413;
                9'd233: sine_q15=17'd32442;
                9'd234: sine_q15=17'd32470;
                9'd235: sine_q15=17'd32496;
                9'd236: sine_q15=17'd32522;
                9'd237: sine_q15=17'd32546;
                9'd238: sine_q15=17'd32568;
                9'd239: sine_q15=17'd32590;
                9'd240: sine_q15=17'd32610;
                9'd241: sine_q15=17'd32629;
                9'd242: sine_q15=17'd32647;
                9'd243: sine_q15=17'd32664;
                9'd244: sine_q15=17'd32679;
                9'd245: sine_q15=17'd32693;
                9'd246: sine_q15=17'd32706;
                9'd247: sine_q15=17'd32718;
                9'd248: sine_q15=17'd32729;
                9'd249: sine_q15=17'd32738;
                9'd250: sine_q15=17'd32746;
                9'd251: sine_q15=17'd32753;
                9'd252: sine_q15=17'd32758;
                9'd253: sine_q15=17'd32762;
                9'd254: sine_q15=17'd32766;
                9'd255: sine_q15=17'd32767;
                9'd256: sine_q15=17'd32768;
                default: sine_q15=17'd0;
            endcase
        end
    endfunction
    function signed [16:0] cosine_q15;
        input [8:0] angle;
        begin
            if (angle<=9'd256) cosine_q15=$signed(sine_q15(9'd256-angle));
            else cosine_q15=-$signed(sine_q15(angle-9'd256));
        end
    endfunction
    function signed [16:0] neg_sine_q15;
        input [8:0] angle;
        begin
            if (angle<=9'd256) neg_sine_q15=-$signed(sine_q15(angle));
            else neg_sine_q15=-$signed(sine_q15(10'd512-{1'b0,angle}));
        end
    endfunction

    reg [3:0] state;
    reg capture_bank, work_bank;
    reg [1:0] bank_ready;
    reg [9:0] capture_count;
    reg capture_we, capture_write_bank;
    reg [9:0] capture_address;
    reg [31:0] capture_word;
    reg capture_finished, finished_bank;
    wire signed [16:0] window_coefficient=$signed(hann_q15(capture_count));
    wire signed [32:0] window_product=sample_data*window_coefficient;
    wire signed [34:0] window_value=round_q15({{2{window_product[32]}},window_product});

    reg [3:0] stage;
    reg [9:0] half_span, group_base, offset;
    wire [9:0] fft_a_address=group_base+offset;
    wire [9:0] fft_b_address=group_base+offset+half_span;
    wire [8:0] twiddle_angle=offset << (4'd9-stage);
    reg signed [15:0] ar,ai,br,bi;
    reg signed [16:0] wr,wi;
    reg signed [32:0] product_rr,product_ii,product_ri,product_ir;
    wire signed [34:0] rotation_real={{2{product_rr[32]}},product_rr}-{{2{product_ii[32]}},product_ii};
    wire signed [34:0] rotation_imag={{2{product_ri[32]}},product_ri}+{{2{product_ir[32]}},product_ir};
    reg signed [18:0] rotated_real,rotated_imag;
    wire signed [34:0] ar_wide={{19{ar[15]}},ar};
    wire signed [34:0] ai_wide={{19{ai[15]}},ai};
    wire signed [34:0] tr_wide={{16{rotated_real[18]}},rotated_real};
    wire signed [34:0] ti_wide={{16{rotated_imag[18]}},rotated_imag};
    wire signed [34:0] result_ar=round_half(ar_wide+tr_wide);
    wire signed [34:0] result_ai=round_half(ai_wide+ti_wide);
    wire signed [34:0] result_br=round_half(ar_wide-tr_wide);
    wire signed [34:0] result_bi=round_half(ai_wide-ti_wide);
    wire arithmetic_clip=(result_ar>35'sd32767)||(result_ar< -35'sd32768)||
                         (result_ai>35'sd32767)||(result_ai< -35'sd32768)||
                         (result_br>35'sd32767)||(result_br< -35'sd32768)||
                         (result_bi>35'sd32767)||(result_bi< -35'sd32768);
    reg [31:0] butterfly_a,butterfly_b;
    reg [8:0] output_index;
    reg [31:0] power_re,power_im;
    reg [9:0] ram0_a_address,ram0_b_address,ram1_a_address,ram1_b_address;
    reg ram0_a_we,ram0_b_we,ram1_a_we,ram1_b_we;
    reg [31:0] ram0_a_data,ram0_b_data,ram1_a_data,ram1_b_data;
    wire [31:0] ram0_a_q,ram0_b_q,ram1_a_q,ram1_b_q;
    wire [31:0] work_a_q=work_bank ? ram1_a_q : ram0_a_q;
    wire [31:0] work_b_q=work_bank ? ram1_b_q : ram0_b_q;
    wire signed [15:0] output_real=$signed(work_a_q[15:0]);
    wire signed [15:0] output_imag=$signed(work_a_q[31:16]);
    wire output_phase=(state>=S_OUT_READ);
    wire [9:0] work_a_address=output_phase ? ({1'b0,output_index}+10'd1) : fft_a_address;
    wire [9:0] work_b_address=output_phase ? 10'd0 : fft_b_address;

    spectrum_complex_ram bank0(clk,ram0_a_address,ram0_b_address,ram0_a_we,ram0_b_we,
                               ram0_a_data,ram0_b_data,ram0_a_q,ram0_b_q);
    spectrum_complex_ram bank1(clk,ram1_a_address,ram1_b_address,ram1_a_we,ram1_b_we,
                               ram1_a_data,ram1_b_data,ram1_a_q,ram1_b_q);
    always @* begin
        ram0_a_address=capture_address;ram0_b_address=~capture_address;
        ram1_a_address=capture_address;ram1_b_address=~capture_address;
        ram0_a_we=capture_we && !capture_write_bank;
        ram1_a_we=capture_we && capture_write_bank;
        ram0_b_we=1'b0;ram1_b_we=1'b0;
        ram0_a_data=capture_word;ram1_a_data=capture_word;
        ram0_b_data=32'd0;ram1_b_data=32'd0;
        if(state!=S_IDLE)begin
            if(work_bank)begin
                ram1_a_address=work_a_address;ram1_b_address=work_b_address;
                ram1_a_we=(state==S_WRITE);ram1_b_we=(state==S_WRITE);
                ram1_a_data=butterfly_a;ram1_b_data=butterfly_b;
            end else begin
                ram0_a_address=work_a_address;ram0_b_address=work_b_address;
                ram0_a_we=(state==S_WRITE);ram0_b_we=(state==S_WRITE);
                ram0_a_data=butterfly_a;ram0_b_data=butterfly_b;
            end
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            state<=S_IDLE;capture_bank<=0;work_bank<=0;bank_ready<=0;capture_count<=0;
            capture_we<=0;capture_write_bank<=0;capture_address<=0;capture_word<=0;
            capture_finished<=0;finished_bank<=0;stage<=0;half_span<=1;group_base<=0;offset<=0;
            ar<=0;ai<=0;br<=0;bi<=0;wr<=0;wi<=0;
            product_rr<=0;product_ii<=0;product_ri<=0;product_ir<=0;
            rotated_real<=0;rotated_imag<=0;butterfly_a<=0;butterfly_b<=0;
            output_index<=0;power_re<=0;power_im<=0;
            block_ready<=0;bin_power<=0;bin_index<=0;bin_valid<=0;overrun<=0;
        end else begin
            capture_we<=0;capture_finished<=0;block_ready<=0;bin_valid<=0;
            // The pending final write occurs at this edge; the bank can be scheduled next edge.
            if(capture_finished) bank_ready[finished_bank]<=1'b1;
            if(sample_valid && !paused)begin
                if(bank_ready[capture_bank] || ((state!=S_IDLE)&&(capture_bank==work_bank)))
                    overrun<=1'b1;
                else begin
                    capture_we<=1'b1;capture_write_bank<=capture_bank;
                    capture_address<=reverse10(capture_count);
                    capture_word<={16'd0,saturate16(window_value)};
                    if(window_value>35'sd32767 || window_value< -35'sd32768) overrun<=1'b1;
                    if(capture_count==10'd1023)begin
                        capture_count<=0;capture_bank<=~capture_bank;
                        capture_finished<=1'b1;finished_bank<=capture_bank;
                    end else capture_count<=capture_count+10'd1;
                end
            end
            case(state)
                S_IDLE:begin
                    if(bank_ready!=0)begin
                        work_bank<=bank_ready[0] ? 1'b0 : 1'b1;
                        if(bank_ready[0])bank_ready[0]<=1'b0;else bank_ready[1]<=1'b0;
                        stage<=0;half_span<=1;group_base<=0;offset<=0;state<=S_READ;
                    end
                end
                S_READ: state<=S_LATCH;
                S_LATCH:begin
                    ar<=$signed(work_a_q[15:0]);ai<=$signed(work_a_q[31:16]);
                    br<=$signed(work_b_q[15:0]);bi<=$signed(work_b_q[31:16]);
                    wr<=cosine_q15(twiddle_angle);wi<=neg_sine_q15(twiddle_angle);
                    state<=S_MUL;
                end
                S_MUL:begin
                    product_rr<=br*wr;product_ii<=bi*wi;
                    product_ri<=br*wi;product_ir<=bi*wr;state<=S_ROTATE;
                end
                S_ROTATE:begin
                    rotated_real<=round_q15(rotation_real);rotated_imag<=round_q15(rotation_imag);
                    state<=S_BFLY;
                end
                S_BFLY:begin
                    butterfly_a<={saturate16(result_ai),saturate16(result_ar)};
                    butterfly_b<={saturate16(result_bi),saturate16(result_br)};
                    if(arithmetic_clip)overrun<=1'b1;
                    state<=S_WRITE;
                end
                S_WRITE:begin
                    if(offset==half_span-10'd1)begin
                        offset<=0;
                        if({1'b0,group_base}+({1'b0,half_span}<<1)==11'd1024)begin
                            group_base<=0;
                            if(stage==4'd9)begin output_index<=0;state<=S_OUT_READ;end
                            else begin stage<=stage+4'd1;half_span<=half_span<<1;state<=S_READ;end
                        end else begin group_base<=group_base+(half_span<<1);state<=S_READ;end
                    end else begin offset<=offset+10'd1;state<=S_READ;end
                end
                S_OUT_READ:state<=S_OUT_MUL;
                S_OUT_MUL:begin power_re<=output_real*output_real;power_im<=output_imag*output_imag;state<=S_OUT_EMIT;end
                S_OUT_EMIT:begin
                    bin_power<=power_re+power_im;bin_index<=output_index;bin_valid<=1'b1;
                    if(output_index==9'd511)begin block_ready<=1'b1;state<=S_IDLE;end
                    else begin output_index<=output_index+9'd1;state<=S_OUT_READ;end
                end
                default:state<=S_IDLE;
            endcase
        end
    end
endmodule
