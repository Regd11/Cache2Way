`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:01:48 04/12/2012 
// Design Name: 
// Module Name:    ins_cache 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

/*
//	CACHE METRICS
//
//##Memory details: 256 Bytes#######################
//#													#
//#memory width:		64 bit				    	#
//#memory depth:		32 lines					#
//#memory address bus:	5 bit						#
//#													#
//##################################################
//
//##Address space:	256 Bytes######################
//#													#
//#word lenght: 	16 bit							#
//#line size: 		4 word (4*16bit = 64 bit line)	#
//#					(balance with memory throughput)#
//#cache storage:	64 Bytes						#
//#cache lines:	32 Bytes/4 word = 8 lines			#
//#													#
//##################################################
//
//##Address lenght: 8 bit (256 memory positions)################
//#																#
//#word address:	4 words per line -> 2 bit (b1:b0)			#
//#line address:	8 lines per set -> 3 bit (b4:b2)			#
//#tag lenght:		remaining bits + val bit -> 8-2-3+1 = 4 bit	#
//#																#
//##############################################################
*/

`define READY	0
`define WAIT	1

`define TAG_T	31
`define TAG_B	13

`define LINE_T	12
`define LINE_B	6

`define WORD_T	5
`define WORD_B  2

module ins_cache(
//PROCESSOR INTERFACE
    input clk,
    input rst,
    input rd_en,
    output rd_rdy,
    input [31:0] addr,
    output reg [31:0] inst,
	 
//MEMORY INTERFACE
	output[31:0] mem_addr,
	output mem_rd_en,
	input mem_rd_rdy,
	input[511:0] mem_data
    );

reg status;
 
reg[511:0] cache_set[127:0];    //cache_set with 128 lines, and 64bytes each line
reg[511:0] cache_set2[127:0];   //cache_set with 128 lines, and 64bytes each line
reg[20:0]  cache_tag[127:0];    //tag+valid+dirty bits for set 1
reg[20:0]  cache_tag2[127:0];   //tag+valid+dirty bits for set 2
reg        cache_lru[127:0];    //LRU bits


wire new_status;
 
wire[511:0]	new_cache_set;
wire[511:0]	new_cache_set2;
wire[20:0]	new_cache_tag;
wire[20:0]	new_cache_tag2;

wire cache_hit;
wire cache_hit_set;
wire cache_hit_set2;

wire[511:0] line_source;
wire[20:0] cache_tag_temp;
wire[20:0] cache_tag2_temp;

integer i;

//////ALIAS/////////
wire[6:0] line_addr;
assign line_addr = addr[`LINE_T:`LINE_B];

wire[3:0] word_addr;
assign word_addr = addr[`WORD_T:`WORD_B];
///////////////////


always @(posedge clk) begin
	if (rst) begin
		status <= `READY;
		for (i=0; i<128 ; i=i+1  ) begin
			cache_tag[i] <= 21'b0;
			cache_tag2[i] <= 21'b0;
			cache_lru[i] <= 1'b0;
		end
	end
	else begin
		status <= new_status;

		cache_set[line_addr] <= new_cache_set;
		cache_tag[line_addr] <= new_cache_tag;
		cache_set2[line_addr] <= new_cache_set2;
        cache_tag2[line_addr] <= new_cache_tag2;
	end           
end

//STATE MACHINE AND REGISTER ASSIGN//////////////////////////////////////////////////////////

assign cache_tag_temp = cache_tag[line_addr];
assign cache_tag2_temp = cache_tag2[line_addr];

assign cache_hit_set = ({1'b1,addr[`TAG_T:`TAG_B]} == cache_tag_temp[19:0])?	1'b1	:
          																		1'b0	;
      
assign cache_hit_set2 = ({1'b1,addr[`TAG_T:`TAG_B]} == cache_tag2_temp[19:0])?	1'b1	:
                                                                                1'b0    ;    																		
          																		  
assign cache_hit = cache_hit_set || cache_hit_set2;

assign new_status =	((status == `READY) && !rd_en )				?	`READY	:
					((status == `READY) && rd_en && cache_hit)	?	`READY	:
					((status == `READY) && rd_en && !cache_hit)	?	`WAIT	:
					((status == `WAIT) && !mem_rd_rdy )			?	`WAIT	:
					((status == `WAIT) && mem_rd_rdy )			?	`READY	:
																	status	;
																							
assign new_cache_set = ((status == `WAIT) && mem_rd_rdy && !cache_lru[line_addr] )	?	mem_data				:
																                        cache_set[line_addr]	;

assign new_cache_set2 = ((status == `WAIT) && mem_rd_rdy && cache_lru[line_addr] )	?	mem_data				:
																                        cache_set2[line_addr]	;

assign new_cache_tag = ((status == `WAIT) && mem_rd_rdy && !cache_lru[line_addr] )	?	{2'b01,addr[`TAG_T:`TAG_B]}	:
																                        cache_tag[line_addr]		;

assign new_cache_tag2 = ((status == `WAIT) && mem_rd_rdy && cache_lru[line_addr] )	?	{2'b01,addr[`TAG_T:`TAG_B]}	:
																                        cache_tag2[line_addr]		;
//OUTPUT ASSIGN//////////////////////////////////////////////////////////////////////////////
	//processor outputs
assign rd_rdy = (cache_hit && rd_en)						?	1'b1	:
				((status == `WAIT) && mem_rd_rdy && rd_en)	?	1'b1	:
																1'b0	;

assign line_source = ((status == `WAIT) && mem_rd_rdy && rd_en)	?	mem_data				:
					 (cache_hit_set)                            ?   cache_set[line_addr]	:
																	cache_set2[line_addr]	;
wire [31:0] inst_wire;
assign inst_wire =	(word_addr == 4'b0000)	?	line_source[31:0] 	:
					(word_addr == 4'b0001)	?	line_source[63:32] 	:
					(word_addr == 4'b0010)	?	line_source[95:64] 	:
					(word_addr == 4'b0011)	?	line_source[127:96] :
					(word_addr == 4'b0100)	?	line_source[159:128]:
                    (word_addr == 4'b0101)  ?   line_source[191:160]:
                    (word_addr == 4'b0110)  ?   line_source[223:192]:
                    (word_addr == 4'b0111)  ?   line_source[255:224]:
                    (word_addr == 4'b1000)	?	line_source[287:256]:
                    (word_addr == 4'b1001)  ?   line_source[319:288]:
                    (word_addr == 4'b1010)  ?   line_source[351:320]:
                    (word_addr == 4'b1011)  ?   line_source[383:352]:
                    (word_addr == 4'b1100)  ?   line_source[415:384]:
                    (word_addr == 4'b1101)  ?   line_source[447:416]:
                    (word_addr == 4'b1110)  ?   line_source[479:448]:
                                                line_source[511:480];

always@(posedge clk) begin
    
	inst <= inst_wire;
end

always@(posedge clk) begin

	if(cache_hit_set)
    begin
        cache_lru[line_addr] = 1'b1;
    end
    else if(cache_hit_set2)
    begin
        cache_lru[line_addr] = 1'b0;
    end
	else if  ((status == `WAIT) && mem_rd_rdy && !cache_lru[line_addr] )
	begin
	   cache_lru[line_addr] = 1'b1;
	end
	else if  ((status == `WAIT) && mem_rd_rdy && cache_lru[line_addr] )
	begin
	   cache_lru[line_addr] = 1'b0;
	end
	
end


	//memory outputs
assign mem_addr = {addr[`TAG_T:`LINE_B],6'b0};

assign mem_rd_en = ((status == `READY) && rd_en && !cache_hit)	?	1'b1	:
																	1'b0	;
	
endmodule
