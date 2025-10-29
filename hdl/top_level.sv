`timescale 1ns / 1ps
`default_nettype none

module top_level
    (
        input wire          clk_100mhz,
        output logic [15:0] led,
        input wire   [15:0] sw,
        input wire   [3:0]  btn,
        output logic [2:0]  rgb0,
        output logic [2:0]  rgb1,
        input wire          midi_pmod,
        output logic        spkl,
        output logic        spkr,
       
        // UART
        input wire          uart_rxd,
        output logic        uart_txd,

        // Seven segment
        output logic [3:0]  ss0_an,  //anode control for upper four digits of seven-seg display
        output logic [3:0]  ss1_an,  //anode control for lower four digits of seven-seg display
        output logic [6:0]  ss0_c,   //cathode controls for the segments of upper four digits
        output logic [6:0]  ss1_c,   //cathode controls for the segments of lower four digits
        
        // // HDMI port
        // output logic [2:0]  hdmi_tx_p,  //hdmi output signals (positives) (blue, green, red)
        // output logic [2:0]  hdmi_tx_n,  //hdmi output signals (negatives) (blue, green, red)
        // output logic        hdmi_clk_p, hdmi_clk_n,  //differential hdmi clock

        // SDRAM (DDR3) ports
        inout wire   [15:0] ddr3_dq,       //data input/output
        inout wire   [1:0]  ddr3_dqs_n,    //data input/output differential strobe (negative)
        inout wire   [1:0]  ddr3_dqs_p,    //data input/output differential strobe (positive)
        output wire  [13:0] ddr3_addr,     //address
        output wire  [2:0]  ddr3_ba,       //bank address
        output wire         ddr3_ras_n,    //row active strobe
        output wire         ddr3_cas_n,    //column active strobe
        output wire         ddr3_we_n,     //write enable
        output wire         ddr3_reset_n,  //reset (active low!!!)
        output wire         ddr3_clk_p,    //general differential clock (p)
        output wire         ddr3_clk_n,    //general differential clock (n)
        output wire         ddr3_clke,     //clock enable
        output wire  [1:0]  ddr3_dm,       //data mask
        output wire         ddr3_odt       //on-die termination (helps impedance match)
    );

    localparam INSTRUMENT_COUNT = 3;
    localparam [6:0] MIDI_KEYS [0:INSTRUMENT_COUNT-1] = {
        7'd36,  // bd
        7'd38,  // sd
        //7'd48,  // t1
        //7'd45,  // t2
        //7'd43,  // t3
        7'd46   // hh_opened
        //7'd42,  // hh_closed
        //7'd44,  // hh_pedal
        //7'd49,  // cc
        //7'd51   // rc
    };

    logic clk_dram_ctrl;
    logic clk_ddr3;
    logic clk_ddr3_90;
    logic clk_ddr3_ref;
    logic clk;
    logic clk_locked;

    logic rst_buf [1:0];
    logic rst;
    assign rst = rst_buf[0] | ~clk_locked;
   
    logic rst_dram_ctrl_buf [1:0];
    logic rst_dram_ctrl;
    assign rst_dram_ctrl = rst_dram_ctrl_buf[0] | ~clk_locked;

    logic uart_rxd_buf [1:0];
    logic uart_din;
    assign uart_din = uart_rxd_buf[0];

    logic midi_din_buf [1:0];
    logic midi_din;
    assign midi_din = midi_din_buf[0];

    logic sample_load_complete;
    logic sample_load_complete_buf [1:0];
    logic sample_load_complete_sync;
    assign sample_load_complete_sync = sample_load_complete_buf[0];
    logic sample_load_triggered;
    logic sample_load_complete_trigger;

    logic [2:0] instr_debug_btn_buf [1:0];
    logic [2:0] instr_debug_btn;
    assign instr_debug_btn = instr_debug_btn_buf[0];
    logic [2:0] instr_trig_debug;

    assign led[3] = sample_load_complete_sync;
    assign led[15:4] = 0;
    assign rgb0 = 0;
    assign rgb1 = 0;
    assign uart_txd = 0;

    // Synchronization
    always_ff @ (posedge clk) begin
        rst_buf <= {btn[0], rst_buf[1]};

        if (rst) begin
            for (int i = 0; i < 2; i++) begin
                uart_rxd_buf[i] <= 0;
                midi_din_buf[i] <= 0;
                sample_load_complete_buf[i] <= 0;
                instr_debug_btn_buf[i] <= 0;
            end
            sample_load_complete_trigger <= 0;
            sample_load_triggered <= 0;
        end else begin
            uart_rxd_buf <= {uart_rxd, uart_rxd_buf[1]};
            midi_din_buf <= {midi_pmod, midi_din_buf[1]};

            // sample_load_complete CDC
            sample_load_complete_buf <= {sample_load_complete, sample_load_complete_buf[1]};

            instr_debug_btn_buf <= {btn[3:1], instr_debug_btn_buf[1]};

            if (sample_load_complete_sync && !sample_load_triggered) begin
                sample_load_complete_trigger <= 1;
                sample_load_triggered <= 1;
            end
            if (sample_load_complete_trigger) begin
                sample_load_complete_trigger <= 0;
            end
        end
    end
    always_ff @ (posedge clk_dram_ctrl) begin
        rst_dram_ctrl_buf <= {btn[0], rst_dram_ctrl_buf[1]};
    end

    genvar i;
    generate
        for (i=0; i<3; i++) begin
            debouncer_trig db_instr_trig (
                .clk(clk),
                .rst(rst),
                .dirty(instr_debug_btn[i]),
                .clean(instr_trig_debug[i])
            );
        end
    endgenerate

    clk_wiz clk_wiz_i (
        .clk_controller(clk_dram_ctrl),
        .clk_ddr3(clk_ddr3),
        .clk_ddr3_90(clk_ddr3_90),
        .clk_ddr3_ref(clk_ddr3_ref),
        .clk_passthrough(clk),
        .reset(btn[0]),
        .locked(clk_locked),
        .clk_in1(clk_100mhz)
    );

    logic [23:0]  addr_starts [INSTRUMENT_COUNT:0];

    logic [127:0] write_axis_data;
    logic         write_axis_tlast;
    logic         write_axis_valid;
    logic         write_axis_ready;

    dram_writer #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) dwr (
        .clk(clk),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst),
        .uart_din(uart_din),

        .addr_starts(addr_starts),
        
        .fifo_receiver_axis_tvalid(write_axis_valid),
        .fifo_receiver_axis_tready(write_axis_ready),
        .fifo_receiver_axis_tdata(write_axis_data),
        .fifo_receiver_axis_tlast(write_axis_tlast)
    );

    logic [23:0]  read_addr_axis_data;
    logic         read_addr_axis_tlast;
    logic         read_addr_axis_valid;
    logic         read_addr_axis_ready;

    dram_read_requester #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT),
        .MIDI_KEYS(MIDI_KEYS)
    ) drd_req (
        .clk(clk),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst),
        .midi_din(midi_din),

        .sample_load_complete_trigger(sample_load_complete_trigger),
        .addr_starts(addr_starts),
        
        .fifo_receiver_axis_tvalid(read_addr_axis_valid),
        .fifo_receiver_axis_tready(read_addr_axis_ready),
        .fifo_receiver_axis_tdata(read_addr_axis_data),
        .fifo_receiver_axis_tlast(read_addr_axis_tlast),

        .instr_trig_debug(instr_trig_debug)
    );

    logic [15:0]  sample_raw;
    logic         sample_raw_valid;

    logic         read_data_axis_valid;
    logic         read_data_axis_ready;
    logic [151:0] read_data_axis_data;

    dram_reader #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) drd (
        .clk(clk),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst),
        .rst_dram_ctrl(rst_dram_ctrl),

        .addr_starts(addr_starts),
        .sample(sample_raw),
        .sample_valid(sample_raw_valid),

        .fifo_sender_axis_tvalid(read_data_axis_valid),
        .fifo_sender_axis_tready(read_data_axis_ready),
        .fifo_sender_axis_tdata(read_data_axis_data)
    );

    logic [23:0]  response_addr;

    logic [23:0]  memrequest_addr;
    logic         memrequest_en;
    logic [127:0] memrequest_write_data;
    logic         memrequest_write_enable;
    logic [127:0] memrequest_resp_data;
    logic         memrequest_complete;
    logic         memrequest_busy;

    assign read_data_axis_data = {response_addr, memrequest_resp_data};

    traffic_generator tg (
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst_dram_ctrl(rst_dram_ctrl),

        .sample_load_complete(sample_load_complete),
        .response_addr(response_addr),

        .memrequest_addr(memrequest_addr),
        .memrequest_en(memrequest_en),
        .memrequest_write_data(memrequest_write_data),
        .memrequest_write_enable(memrequest_write_enable),
        .memrequest_resp_data(memrequest_resp_data),
        .memrequest_complete(memrequest_complete),
        .memrequest_busy(memrequest_busy),

        .write_axis_data(write_axis_data),
        .write_axis_tlast(write_axis_tlast),
        .write_axis_valid(write_axis_valid),
        .write_axis_ready(write_axis_ready),

        .read_addr_axis_data(read_addr_axis_data),
        .read_addr_axis_tlast(read_addr_axis_tlast),
        .read_addr_axis_valid(read_addr_axis_valid),
        .read_addr_axis_ready(read_addr_axis_ready),

        .read_data_axis_valid(read_data_axis_valid),
        .read_data_axis_ready(read_data_axis_ready)
    );

    ddr3_top #(
        .CONTROLLER_CLK_PERIOD(12_000), //ps, clock period of the controller interface
        .DDR3_CLK_PERIOD(3_000), //ps, clock period of the DDR3 RAM device (must be 1/4 of the CONTROLLER_CLK_PERIOD)
        .ROW_BITS(14), //width of row address
        .COL_BITS(10), //width of column address
        .BA_BITS(3), //width of bank address
        .BYTE_LANES(2), //number of DDR3 modules to be controlled
        .AUX_WIDTH(16), //width of aux line (must be >= 4)
        .WB2_ADDR_BITS(32), //width of 2nd wishbone address bus
        .WB2_DATA_BITS(32), //width of 2nd wishbone data bus
        .MICRON_SIM(0), //enable faster simulation for micron ddr3 model (shorten POWER_ON_RESET_HIGH and INITIAL_CKE_LOW)
        .ODELAY_SUPPORTED(0), //set to 1 when ODELAYE2 is supported
        .SECOND_WISHBONE(0), //set to 1 if 2nd wishbone is needed
        .ECC_ENABLE(0), // set to 1 or 2 to add ECC (1 = Side-band ECC per burst, 2 = Side-band ECC per 8 bursts , 3 = Inline ECC )
        .WB_ERROR(0) // set to 1 to support Wishbone error (asserts at ECC double bit error)
    ) ddr3_top (
        // Clock and reset
        .i_controller_clk(clk_dram_ctrl),
        .i_ddr3_clk(clk_ddr3),
        .i_ref_clk(clk_ddr3_ref),
        .i_ddr3_clk_90(clk_ddr3_90),
        .i_rst_n(!rst_dram_ctrl),

        // Inputs
        .i_wb_cyc(1), //bus cycle active (1 = normal operation, 0 = all ongoing transaction are to be cancelled)
        .i_wb_stb(memrequest_en), //request a transfer
        .i_wb_we(memrequest_write_enable), //write-enable (1 = write, 0 = read)
        .i_wb_addr(memrequest_addr), //burst-addressable {row,bank,col}
        .i_wb_data(memrequest_write_data), //write data, for a 4:1 controller data width is 8 times the number of pins on the device
        .i_wb_sel(16'hffff), //byte strobe for write (1 = write the byte)
        .i_aux(memrequest_write_enable), //for AXI-interface compatibility (given upon strobe)

        // Outputs
        .o_wb_stall(memrequest_busy), //1 = busy, cannot accept requests
        .o_wb_ack(memrequest_complete), //1 = read/write request has completed
        .o_wb_err(), //1 = Error due to ECC double bit error (fixed to 0 if WB_ERROR = 0)
        .o_wb_data(memrequest_resp_data), //read data, for a 4:1 controller data width is 8 times the number of pins on the device
        .o_aux(),

        // DDR3 I/O interface
        .o_ddr3_clk_p(ddr3_clk_p),
        .o_ddr3_clk_n(ddr3_clk_n),
        .o_ddr3_reset_n(ddr3_reset_n),
        .o_ddr3_cke(ddr3_clke), // CKE
        .o_ddr3_cs_n(), // chip select signal (controls rank 1 only) tied to 0 on this board by default.
        .o_ddr3_ras_n(ddr3_ras_n), // RAS#
        .o_ddr3_cas_n(ddr3_cas_n), // CAS#
        .o_ddr3_we_n(ddr3_we_n), // WE#
        .o_ddr3_addr(ddr3_addr),
        .o_ddr3_ba_addr(ddr3_ba),
        .io_ddr3_dq(ddr3_dq),
        .io_ddr3_dqs(ddr3_dqs_p),
        .io_ddr3_dqs_n(ddr3_dqs_n),
        .o_ddr3_dm(ddr3_dm),
        .o_ddr3_odt(ddr3_odt), // on-die termination
        .o_debug1()
    );

    logic [15:0] sample_upsampled;

    upsampler upsampler_i (
        .clk(clk),
        .rst(rst),
        .sample_in(sample_raw),
        .sample_in_valid(sample_raw_valid),
        .sample_out(sample_upsampled)
    );

    logic dac_out;
    assign spkl = dac_out;
    assign spkr = dac_out;

    dlt_sig_dac_2nd_order dlt_sig (
        .clk(clk),
        .rst(rst),
        .current_sample(sample_upsampled),
        .audio_out(dac_out)
    );

    logic [23:0]  memrequest_complete_counter;
    logic [15:0]  read_data_valid_counter;
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            memrequest_complete_counter <= 0;
            read_data_valid_counter <= 0;
        end else begin
            if (memrequest_complete) begin
                memrequest_complete_counter <= memrequest_complete_counter + 1;
            end
            if (read_data_axis_valid) begin
                read_data_valid_counter <= read_data_valid_counter + 1;
            end
        end
    end

    // logic [6:0] ss_c;
    // assign ss0_c = ss_c;
    // assign ss1_c = ss_c;
    // seven_segment_controller ssc (
    //     .clk(clk),
    //     .rst(rst),
    //     .val({8'b0, dwr.sample_loader_i.total_sample_counter}),
    //     .cat(ss_c),
    //     .an({ss0_an, ss1_an})
    // );

    logic [6:0] ss_c;
    assign ss0_c = ss_c;
    assign ss1_c = ss_c;
    seven_segment_controller ssc (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .val({read_data_valid_counter, memrequest_complete_counter[15:0]}),
        .cat(ss_c),
        .an({ss0_an, ss1_an})
    );
    // seven_segment_controller ssc (
    //     .clk(clk),
    //     .rst(rst),
    //     .val({16'b0, sample_raw}),
    //     .cat(ss_c),
    //     .an({ss0_an, ss1_an})
    // );

    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            led[0] <= 0;
        end else begin
            if (write_axis_tlast) begin
                led[0] <= 1;
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            led[1] <= 0;
            led[2] <= 0;
        end else begin
            if (dwr.stacker_chunk_axis_tlast) begin
                led[1] <= 1;
            end
            if (dwr.sample_axis_tlast) begin
                led[2] <= 1;
            end
        end
    end
endmodule
`default_nettype wire
