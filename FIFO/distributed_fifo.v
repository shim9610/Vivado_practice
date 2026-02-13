`timescale 1ns / 1ps
module distributed_fifo #(
    parameter DATA_WIDTH = 8,
    parameter BUFFER_SIZE = 32
    )
    (
    input clk,
    input reset,
    input [DATA_WIDTH-1:0] data_in,
    input valid_s,
    output ready_s,
	output [DATA_WIDTH-1:0] data_out,
    output valid_m,
    input ready_m
    );
    localparam BUFFER_POINTER_SIZE = (BUFFER_SIZE <= 0) ? 1 : $clog2(BUFFER_SIZE);
    
    reg [BUFFER_POINTER_SIZE-1:0] w_pointer,r_pointer;
    wire [BUFFER_POINTER_SIZE-1:0] rp_pointer = (r_pointer < BUFFER_SIZE-1) ? r_pointer + 1 : 0;
    wire [BUFFER_POINTER_SIZE-1:0] wp_pointer = (w_pointer < BUFFER_SIZE-1) ? w_pointer + 1 : 0;
    wire [BUFFER_POINTER_SIZE-1:0] wpp_pointer = (wp_pointer < BUFFER_SIZE-1) ? wp_pointer + 1 : 0;
    wire ready = (~(wp_pointer ==r_pointer) & ~(wpp_pointer ==r_pointer));
    wire valid = ~(r_pointer == w_pointer);
    
    (* ram_style = "distributed" *)
    reg [DATA_WIDTH-1:0] data_buffer[BUFFER_SIZE-1:0];
    wire [DATA_WIDTH-1:0] read_value = data_buffer[r_pointer];

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////Write Data from RingBuffer///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    reg ready_s_r;
    always @(posedge clk or posedge reset) begin
        if (reset == 1) begin
            w_pointer   <= 0;
            ready_s_r   <= 0;
        end else begin
            ready_s_r   <=  ready;
            if (ready_s_r & valid_s) begin
                w_pointer   <=   wp_pointer;
            end
        end 
    end
    always @(posedge clk) begin
        if (ready_s_r & valid_s) begin
            data_buffer[w_pointer] <= data_in;
        end
    end

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////Read Data from RingBuffer///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    wire handshake = (valid & ready_m);
    always @(posedge clk or posedge reset) begin
        if (reset == 1) begin
            r_pointer   <=  0;
        end else if (handshake) begin
            r_pointer   <=  rp_pointer;
        end
    end
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////output port assign/////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    assign data_out = read_value;
    assign ready_s  = ready_s_r;
    assign valid_m  = valid;
endmodule