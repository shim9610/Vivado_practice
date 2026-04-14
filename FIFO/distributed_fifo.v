// BRAM입니다 이름이랑 다름 ㅠㅠ

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
    
    (* ram_style = "block", ram_extract = "yes" *) 
    reg [DATA_WIDTH-1:0] data_buffer[BUFFER_SIZE-1:0];
  

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
    reg valid_m_r;
    reg [DATA_WIDTH-1:0] data_out_r,data_out_r1;
    reg [DATA_WIDTH-1:0] data_out_r0 [1:0];
    reg write_flag;
    reg read_flag;
    reg [1:0] data_num;
    reg is_write;

    wire handshake = (valid_m_r & ready_m);
    wire write_condition = is_write && (data_num < 2);
    wire read_condition = (handshake | ~valid_m_r) && (data_num != 0);
    wire available_flag =   write_condition && is_write;
    always @(posedge clk or posedge reset) begin
        if (reset == 1) begin
            valid_m_r   <=  0;
            write_flag  <=  0;
            read_flag   <=  0;
            r_pointer   <=  0;
            data_out_r0[0] <=  0;
            data_out_r0[1] <=  0;
            data_num    <=  0;
            is_write        <=  0;
        end else begin
            if (valid && & (data_num < 2)) begin  // 데이터 슬롯이 2개 미만일 때만 r_pointer를 이동시키고 데이터를 읽어옴
                r_pointer       <=  rp_pointer;
                data_out_r1   <=  data_buffer[r_pointer];
                is_write    <=  1;
            end else begin
                is_write    <=  available_flag ^ is_write; // 데이터 슬롯이 꽉 찬경우 XOR 연산으로 is_write를 토글하여 뒷단의 버퍼에서 data_out_r1을 소비했는지 여부에따라 is_write 토글
            end

            if (write_condition) begin // 쓰기조건 만족시 data_out_r0에 데이터 쓰기 write_flag 스위칭으로 2칸을 사용
                data_out_r0[write_flag]   <=  data_out_r1;
                write_flag      <=  ~write_flag;
            end 

            if (read_condition) begin // 읽기조건 만족시 data_out_r0에서 데이터 꺼내기 read_flag 스위칭으로 2칸을 사용
                data_out_r  <=  data_out_r0[read_flag];
                read_flag   <=  ~read_flag;
            end


            if (handshake | ~valid_m_r) begin // 핸드쉐이크 발생하거나 valid_m_r이 0인 경우 valid_m_r 업데이트
                valid_m_r   <=  (data_num != 0);
            end

            data_num    <=   (data_num + (write_condition && is_write)) - read_condition; // 해당 클럭에서 발생한 이벤트 기반으로 data_num 계산
        end
    end산
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////output port assign/////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    assign data_out = data_out_r;
    assign ready_s  = ready_s_r;
    assign valid_m  = valid_m_r;
endmodule