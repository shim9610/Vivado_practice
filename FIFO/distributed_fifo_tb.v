`timescale 1ns / 1ps

module distributed_fifo_tb;

    parameter DATA_WIDTH = 16;
    parameter BUFFER_SIZE = 32;
    parameter CLK_PERIOD = 10.0;
    parameter MAX_SAMPLES = 4096;

    // =========================================================================
    // DUT interface
    // =========================================================================
    reg  clk, reset;
    wire [DATA_WIDTH-1:0] data_in;
    reg  valid_s;
    wire ready_s;
    wire [DATA_WIDTH-1:0] data_out;
    wire valid_m;
    reg  ready_m;

    // =========================================================================
    // Test data source
    // =========================================================================
    reg [DATA_WIDTH-1:0] test_data [0:MAX_SAMPLES-1];

    // =========================================================================
    // Phase control (driven ONLY by initial block)
    // =========================================================================
    reg        phase_active;
    reg        drain_active;
    reg        capture_en;
    reg [15:0] target_send;
    reg [1:0]  bp_in_mode;   // 0=full, 1=75%, 2=67%, 3=50%
    reg [1:0]  bp_out_mode;  // 0=full, 1=75%, 2=67%, 3=blocked

    // =========================================================================
    // Send FSM state
    // =========================================================================
    reg [15:0] send_idx;
    reg        send_done_r;

    // =========================================================================
    // Input throttle
    // =========================================================================
    reg send_throttle;

    // =========================================================================
    // Verification
    // =========================================================================
    reg [DATA_WIDTH-1:0] sent_queue [0:MAX_SAMPLES-1];
    reg [DATA_WIDTH-1:0] recv_queue [0:MAX_SAMPLES-1];
    integer sq_head, rq_head;
    integer total_errors;

    // =========================================================================
    // Handshake wires
    // =========================================================================
    wire s_hsk = valid_s & ready_s;
    wire m_hsk = valid_m & ready_m;

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT
    // =========================================================================
    distributed_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_SIZE(BUFFER_SIZE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .valid_s(valid_s),
        .ready_s(ready_s),
        .data_out(data_out),
        .valid_m(valid_m),
        .ready_m(ready_m)
    );

    // =========================================================================
    // Combinational data_in
    // =========================================================================
    assign data_in = test_data[send_idx];

    // =========================================================================
    // Input throttle FSM (sole driver of: send_throttle)
    // =========================================================================
    always @(posedge clk) begin
        case (bp_in_mode)
            0: send_throttle <= 0;
            1: send_throttle <= ($urandom % 4 == 0);    // 25% stall
            2: send_throttle <= ($urandom % 3 == 0);    // 33% stall
            3: send_throttle <= ($urandom % 2 == 0);    // 50% stall
            default: send_throttle <= 0;
        endcase
    end

    // =========================================================================
    // Send FSM (sole driver of: send_idx, valid_s, send_done_r)
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            send_idx    <= 0;
            valid_s     <= 0;
            send_done_r <= 0;
        end else if (phase_active && !send_done_r) begin
            valid_s <= !send_throttle;
            if (s_hsk) begin
                if (send_idx >= target_send - 1) begin
                    send_done_r <= 1;
                    valid_s     <= 0;
                end else begin
                    send_idx <= send_idx + 1;
                end
            end
        end else begin
            valid_s <= 0;
        end
    end

    // =========================================================================
    // Backpressure FSM (sole driver of: ready_m)
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            ready_m <= 0;
        end else if (drain_active) begin
            ready_m <= 1;
        end else if (phase_active) begin
            case (bp_out_mode)
                0: ready_m <= 1;
                1: ready_m <= ($urandom % 4 != 0);    // 75% ready
                2: ready_m <= ($urandom % 3 != 0);    // 67% ready
                3: ready_m <= 0;                      // fully blocked
                default: ready_m <= 1;
            endcase
        end else begin
            ready_m <= 0;
        end
    end

    // =========================================================================
    // Sent data capture (sole driver of: sq_head, sent_queue)
    // =========================================================================
    always @(posedge clk) begin
        if (capture_en && s_hsk) begin
            sent_queue[sq_head] = data_in;
            sq_head = sq_head + 1;
        end
    end

    // =========================================================================
    // Recv data capture (sole driver of: rq_head, recv_queue)
    // =========================================================================
    always @(posedge clk) begin
        if (capture_en && m_hsk) begin
            recv_queue[rq_head] = data_out;
            rq_head = rq_head + 1;
        end
    end

    // =========================================================================
    // Tasks (ONLY set initial-block-owned control regs)
    // =========================================================================

    task do_reset;
        begin
            capture_en   = 0;
            phase_active = 0;
            drain_active = 0;
            bp_in_mode   = 0;
            bp_out_mode  = 0;
            reset = 1;
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            @(posedge clk);
            @(posedge clk);
            sq_head = 0;
            rq_head = 0;
        end
    endtask

    task fill_test_data;
        input integer count;
        input integer pattern;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                case (pattern)
                    0: test_data[i] = i[DATA_WIDTH-1:0];
                    1: test_data[i] = {DATA_WIDTH{1'b1}};
                    2: test_data[i] = {DATA_WIDTH{1'b0}};
                    3: test_data[i] = (i % 2) ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};
                    4: test_data[i] = (1 << (i % DATA_WIDTH));
                    5: test_data[i] = $urandom;
                    default: test_data[i] = i[DATA_WIDTH-1:0];
                endcase
            end
        end
    endtask

    task run_phase;
        integer idle;
        begin
            capture_en   = 1;
            phase_active = 1;

            wait(send_done_r);
            @(posedge clk);
            phase_active = 0;

            drain_active = 1;
            idle = 0;
            while (idle < 20) begin
                @(posedge clk);
                if (!valid_m) idle = idle + 1;
                else idle = 0;
            end
            drain_active = 0;
            @(posedge clk);
        end
    endtask

    task verify;
        input integer expected;
        integer i, errs, sent_n, recv_n;
        begin
            #1;
            sent_n = sq_head;
            recv_n = rq_head;
            errs = 0;

            if (sent_n !== expected)
                $display("  [WARN] Expected send=%0d, actual=%0d", expected, sent_n);
            if (sent_n !== recv_n) begin
                $display("  [FAIL] Count mismatch: sent=%0d recv=%0d", sent_n, recv_n);
                errs = errs + 1;
            end

            for (i = 0; i < recv_n && i < sent_n; i = i + 1) begin
                if (sent_queue[i] !== recv_queue[i]) begin
                    errs = errs + 1;
                    if (errs <= 10)
                        $display("  [FAIL] [%0d] sent=0x%04h recv=0x%04h",
                                 i, sent_queue[i], recv_queue[i]);
                end
            end
            if (errs > 10)
                $display("  ... and %0d more errors", errs - 10);

            if (errs == 0)
                $display("  [PASS] %0d/%0d OK", recv_n, expected);
            else
                $display("  [FAIL] %0d errors in %0d samples", errs, recv_n);

            total_errors = total_errors + errs;
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        total_errors = 0;
        capture_en   = 0;
        phase_active = 0;
        drain_active = 0;
        sq_head = 0;
        rq_head = 0;
        target_send = 0;
        bp_in_mode  = 0;
        bp_out_mode = 0;

        $display("");
        $display("========================================");
        $display("  Distributed FIFO Testbench (FSM)");
        $display("  DATA_WIDTH=%0d  BUFFER_SIZE=%0d", DATA_WIDTH, BUFFER_SIZE);
        $display("========================================");

        // =============================================
        // Phase 1: Sequential, no backpressure
        // =============================================
        $display("\n[Phase 1] Sequential, no backpressure");
        do_reset();
        fill_test_data(200, 0);
        target_send = 200;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(200);

        // =============================================
        // Phase 2: All-ones + all-zeros
        // =============================================
        $display("\n[Phase 2] All-ones + all-zeros");
        do_reset();
        fill_test_data(50, 1);
        begin : fill_p2
            integer k;
            for (k = 50; k < 100; k = k + 1)
                test_data[k] = {DATA_WIDTH{1'b0}};
        end
        target_send = 100;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(100);

        // =============================================
        // Phase 3: Alternating 0xFFFF / 0x0000
        // =============================================
        $display("\n[Phase 3] Alternating 0xFFFF/0x0000");
        do_reset();
        fill_test_data(100, 3);
        target_send = 100;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(100);

        // =============================================
        // Phase 4: Walking-one
        // =============================================
        $display("\n[Phase 4] Walking-one");
        do_reset();
        fill_test_data(DATA_WIDTH * 4, 4);
        target_send = DATA_WIDTH * 4;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(DATA_WIDTH * 4);

        // =============================================
        // Phase 5: Input backpressure only (75%)
        // =============================================
        $display("\n[Phase 5] Sequential + input backpressure (75%%)");
        do_reset();
        fill_test_data(300, 0);
        target_send = 300;
        bp_in_mode  = 1;
        bp_out_mode = 0;
        run_phase();
        verify(300);

        // =============================================
        // Phase 6: Output backpressure only (75%)
        // =============================================
        $display("\n[Phase 6] Sequential + output backpressure (75%%)");
        do_reset();
        fill_test_data(300, 0);
        target_send = 300;
        bp_in_mode  = 0;
        bp_out_mode = 1;
        run_phase();
        verify(300);

        // =============================================
        // Phase 7: Bidirectional backpressure (67%)
        // =============================================
        $display("\n[Phase 7] Bidirectional backpressure (67%%)");
        do_reset();
        fill_test_data(300, 5);
        target_send = 300;
        bp_in_mode  = 2;
        bp_out_mode = 2;
        run_phase();
        verify(300);

        // =============================================
        // Phase 8: Buffer full → drain
        // =============================================
        $display("\n[Phase 8] Buffer full stress");
        do_reset();
        fill_test_data(BUFFER_SIZE - 1, 0);
        target_send = BUFFER_SIZE - 1;
        bp_in_mode  = 0;
        bp_out_mode = 3; // output blocked
        capture_en  = 1;
        phase_active = 1;

        wait(send_done_r);
        @(posedge clk);
        phase_active = 0;
        #(CLK_PERIOD * 5);

        drain_active = 1;
        begin : drain_p8
            integer idle;
            idle = 0;
            while (idle < 20) begin
                @(posedge clk);
                if (!valid_m) idle = idle + 1;
                else idle = 0;
            end
        end
        drain_active = 0;
        @(posedge clk);
        verify(BUFFER_SIZE - 1);

        // =============================================
        // Phase 9: Single word
        // =============================================
        $display("\n[Phase 9] Single word");
        do_reset();
        test_data[0] = 16'hBEEF;
        target_send = 1;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(1);

        // =============================================
        // Phase 10: Edge values
        // =============================================
        $display("\n[Phase 10] Edge values");
        do_reset();
        test_data[0] = 16'h0000;
        test_data[1] = 16'hFFFF;
        test_data[2] = 16'h8000;
        test_data[3] = 16'h7FFF;
        test_data[4] = 16'h5555;
        test_data[5] = 16'hAAAA;
        target_send = 6;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(6);

        // =============================================
        // Phase 11: Heavy backpressure both sides (50%)
        // =============================================
        $display("\n[Phase 11] Heavy bidirectional backpressure (50%%)");
        do_reset();
        fill_test_data(200, 5);
        target_send = 200;
        bp_in_mode  = 3;
        bp_out_mode = 2;
        run_phase();
        verify(200);

        // =============================================
        // Phase 12: Reset mid-transfer
        // =============================================
        $display("\n[Phase 12] Reset mid-transfer");
        do_reset();
        fill_test_data(100, 0);
        target_send = 100;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        capture_en  = 1;
        phase_active = 1;

        wait(sq_head >= 10);
        @(posedge clk);

        capture_en   = 0;
        phase_active = 0;
        drain_active = 0;
        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        @(posedge clk);

        if (!valid_m)
            $display("  [PASS] FIFO empty after reset");
        else
            $display("  [FAIL] FIFO still valid after reset!");

        sq_head = 0;
        rq_head = 0;
        fill_test_data(50, 5);
        target_send = 50;
        bp_in_mode  = 0;
        bp_out_mode = 0;
        run_phase();
        verify(50);

        // =============================================
        // Summary
        // =============================================
        $display("\n========================================");
        if (total_errors == 0)
            $display("  ALL PHASES PASSED");
        else
            $display("  TOTAL ERRORS: %0d", total_errors);
        $display("========================================\n");
        $finish;
    end

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 1000000);
        $display("\n[TIMEOUT] sq_head=%0d rq_head=%0d send_idx=%0d", sq_head, rq_head, send_idx);
        $finish;
    end

endmodule