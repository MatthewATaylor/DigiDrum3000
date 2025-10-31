`timescale 1ns / 1ps
`default_nettype none

module top_level
    (
        input  wire         clk_100mhz,
        output logic [15:0] led,
        input  wire  [15:0] sw,
        input  wire  [3:0]  btn,
        output logic [2:0]  rgb0,
        output logic [2:0]  rgb1,
        input  wire         midi_pmod,
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
        output logic [2:0]  hdmi_tx_p,  //hdmi output signals (positives) (blue, green, red)
        output logic [2:0]  hdmi_tx_n,  //hdmi output signals (negatives) (blue, green, red)
        output logic        hdmi_clk_p, hdmi_clk_n,  //differential hdmi clock

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

    logic clk;
    assign clk = clk_100mhz;

    // cw_dram
    logic clk_dram_ctrl;
    logic clk_ddr3;
    logic clk_ddr3_90;
    logic clk_ddr3_ref;
    logic cw_dram_locked;

    // cw_hdmi
    logic clk_pixel;
    logic clk_tmds;
    logic cw_hdmi_locked;

    logic clk_locked;
    assign clk_locked = cw_dram_locked & cw_hdmi_locked;

    logic rst_buf [1:0];
    logic rst;
    assign rst = rst_buf[0] | ~clk_locked;
   
    logic rst_dram_ctrl_buf [1:0];
    logic rst_dram_ctrl;
    assign rst_dram_ctrl = rst_dram_ctrl_buf[0] | ~clk_locked;

    logic rst_pixel_buf [1:0];
    logic rst_pixel;
    assign rst_pixel = rst_pixel_buf[0] | ~clk_locked;

    logic uart_rxd_buf [1:0];
    logic uart_din;
    assign uart_din = uart_rxd_buf[0];

    logic midi_din_buf [1:0];
    logic midi_din;
    assign midi_din = midi_din_buf[0];

    logic sample_load_complete_dram_ctrl;
    logic sample_load_complete_buf [1:0];
    logic sample_load_complete;
    assign sample_load_complete = sample_load_complete_buf[0];

    logic sample_load_complete_pixel_buf[1:0];
    logic sample_load_complete_pixel;
    assign sample_load_complete_pixel = sample_load_complete_buf[0];

    logic [2:0] instr_debug_btn_buf [1:0];
    logic [2:0] instr_debug_btn;
    assign instr_debug_btn = instr_debug_btn_buf[0];
    logic [2:0] instr_trig_debug;

    assign led[1] = sample_load_complete;
    assign led[15:3] = 0;
    assign rgb0 = 0;
    assign rgb1 = 0;
    assign uart_txd = 0;

    // Synchronization
    always_ff @ (posedge clk) begin
        rst_buf <= {btn[0], rst_buf[1]};

        if (rst) begin
            for (int i=0; i<2; i++) begin
                uart_rxd_buf[i] <= 0;
                midi_din_buf[i] <= 0;
                sample_load_complete_buf[i] <= 0;
                instr_debug_btn_buf[i] <= 0;
            end
        end else begin
            uart_rxd_buf <= {uart_rxd, uart_rxd_buf[1]};
            midi_din_buf <= {midi_pmod, midi_din_buf[1]};

            // sample_load_complete CDC
            // From 83.333 MHz to 100 MHz
            sample_load_complete_buf <= {sample_load_complete_dram_ctrl, sample_load_complete_buf[1]};

            instr_debug_btn_buf <= {btn[3:1], instr_debug_btn_buf[1]};
        end
    end
    always_ff @ (posedge clk_dram_ctrl) begin
        rst_dram_ctrl_buf <= {btn[0], rst_dram_ctrl_buf[1]};
    end
    always_ff @ (posedge clk_pixel) begin
        rst_pixel_buf <= {btn[0], rst_pixel_buf[1]};

        if (rst_pixel) begin
            for (int i=0; i<2; i++) begin
                sample_load_complete_pixel_buf[i] <= 0;
            end
        end else begin
             // sample_load_complete CDC
             // From 83.333 MHz to 74.25 MHz
            sample_load_complete_pixel_buf <= {sample_load_complete_dram_ctrl, sample_load_complete_pixel_buf[1]};
        end
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

    cw_dram cw_dram_i (
        .clk_controller(clk_dram_ctrl),
        .clk_ddr3(clk_ddr3),
        .clk_ddr3_90(clk_ddr3_90),
        .clk_ddr3_ref(clk_ddr3_ref),
        .reset(btn[0]),
        .locked(cw_dram_locked),
        .clk_in1(clk)
    );
    cw_hdmi cw_hdmi_i (
        .clk_pixel(clk_pixel),
        .clk_tmds(clk_tmds),
        .reset(btn[0]),
        .locked(cw_hdmi_locked),
        .sysclk(clk)
    );

    logic [10:0] h_count_hdmi;
    logic [9:0]  v_count_hdmi;
    logic        v_sync_hdmi;
    logic        h_sync_hdmi;
    logic        active_draw_hdmi;
    logic        new_frame_hdmi;
    logic [5:0]  frame_count_hdmi;

    logic pixel_last;
    assign pixel_last = (h_count_hdmi == 1279) && (v_count_hdmi == 719);

    video_sig_gen video_sig_gen_i (
        .pixel_clk(clk_pixel),
        .rst(rst_pixel),

        .h_count(h_count_hdmi),
        .v_count(v_count_hdmi),
        .v_sync(v_sync_hdmi),
        .h_sync(h_sync_hdmi),
        .active_draw(active_draw_hdmi),
        .new_frame(new_frame_hdmi),
        .frame_count(frame_count_hdmi)
    );

    logic [7:0]  pixel_to_write_r;
    logic [7:0]  pixel_to_write_g;
    logic [7:0]  pixel_to_write_b;

    logic [15:0] pixel_to_write;
    assign pixel_to_write = {
        pixel_to_write_r[7:3],
        pixel_to_write_g[7:2],
        pixel_to_write_b[7:3]
    };

    test_pattern_generator video_test (
        .pattern_select(sw[1:0]),
        .h_count(h_count_hdmi),
        .v_count(v_count_hdmi),
        .pixel_red(pixel_to_write_r),
        .pixel_green(pixel_to_write_g),
        .pixel_blue(pixel_to_write_b)
    );

    logic [23:0]  addr_offsets [INSTRUMENT_COUNT:0];
    logic         addr_offsets_valid;

    logic [127:0] write_axis_data;
    logic         write_axis_tlast;
    logic         write_axis_valid;
    logic         write_axis_ready;

    assign led[2] = addr_offsets_valid;

    dram_writer #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) dwr (
        .clk(clk),
        .clk_dram_ctrl(clk_dram_ctrl),
        .clk_pixel(clk_pixel),
        .rst(rst),
        .rst_pixel(rst_pixel),
        .uart_din(uart_din),
        
        .sample_load_complete(sample_load_complete_pixel),
        .addr_offsets(addr_offsets),
        .addr_offsets_valid(addr_offsets_valid),
    
        .pixel_valid(active_draw_hdmi),
        .pixel_data(pixel_to_write),
        .pixel_last(pixel_last),

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

        .sample_load_complete(sample_load_complete),
        .addr_offsets(addr_offsets),
        .addr_offsets_valid(addr_offsets_valid),
        
        .fifo_receiver_axis_tvalid(read_addr_axis_valid),
        .fifo_receiver_axis_tready(read_addr_axis_ready),
        .fifo_receiver_axis_tdata(read_addr_axis_data),
        .fifo_receiver_axis_tlast(read_addr_axis_tlast),

        .instr_trig_debug(instr_trig_debug)
    );

    logic [15:0]  sample_raw;
    logic         sample_raw_valid;

    logic         read_data_audio_axis_valid;
    logic         read_data_audio_axis_ready;
    logic [151:0] read_data_audio_axis_data;

    dram_reader_audio #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) drd_audio (
        .clk(clk),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst),
        .rst_dram_ctrl(rst_dram_ctrl),

        .addr_offsets(addr_offsets),
        .addr_offsets_valid(addr_offsets_valid),
        .sample(sample_raw),
        .sample_valid(sample_raw_valid),

        .fifo_sender_axis_tvalid(read_data_audio_axis_valid),
        .fifo_sender_axis_tready(read_data_audio_axis_ready),
        .fifo_sender_axis_tdata(read_data_audio_axis_data)
    );

    logic         read_data_video_axis_valid;
    logic         read_data_video_axis_ready;
    logic [127:0] read_data_video_axis_data;
    logic         read_data_video_axis_tlast;
    logic         read_data_video_axis_af;

    logic [15:0]  pixel_to_display;

    dram_reader_video drd_video (
        .clk_pixel(clk_pixel),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst_pixel(rst_pixel),
        .rst_dram_ctrl(rst_dram_ctrl),

        .h_count_hdmi(h_count_hdmi),
        .v_count_hdmi(v_count_hdmi),
        .active_draw_hdmi(active_draw_hdmi),

        .pixel(pixel_to_display),

        .fifo_sender_axis_tvalid(read_data_video_axis_valid),
        .fifo_sender_axis_tready(read_data_video_axis_ready),
        .fifo_sender_axis_tdata(read_data_video_axis_data),
        .fifo_sender_axis_tlast(read_data_video_axis_tlast),
        .fifo_sender_axis_af(read_data_video_axis_af)
    );

    logic [23:0]  memrequest_addr;
    logic         memrequest_en;
    logic [127:0] memrequest_write_data;
    logic         memrequest_write_enable;
    logic [127:0] memrequest_resp_data;
    logic         memrequest_complete;
    logic         memrequest_busy;

    traffic_generator tg (
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst_dram_ctrl(rst_dram_ctrl),

        .sample_load_complete(sample_load_complete_dram_ctrl),

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

        .read_data_audio_axis_valid(read_data_audio_axis_valid),
        .read_data_audio_axis_ready(read_data_audio_axis_ready),
        .read_data_audio_axis_data(read_data_audio_axis_data),

        .read_data_video_axis_valid(read_data_video_axis_valid),
        .read_data_video_axis_ready(read_data_video_axis_ready),
        .read_data_video_axis_data(read_data_video_axis_data),
        .read_data_video_axis_tlast(read_data_video_axis_tlast),
        .read_data_video_axis_af(read_data_video_axis_af)
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

    logic [9:0] tmds_10b    [0:2];
    logic       tmds_signal [2:0];
 
    tmds_encoder tmds_red (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .video_data({pixel_to_display[15:11], 3'b0}),
        .control(2'b0),
        .video_enable(active_draw_hdmi),
        .tmds(tmds_10b[2])
    );
    tmds_encoder tmds_green (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .video_data({pixel_to_display[10:5], 2'b0}),
        .control(2'b0),
        .video_enable(active_draw_hdmi),
        .tmds(tmds_10b[1])
    );
    tmds_encoder tmds_blue (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .video_data({pixel_to_display[4:0], 3'b0}),
        .control({v_sync_hdmi, h_sync_hdmi}),
        .video_enable(active_draw_hdmi),
        .tmds(tmds_10b[0])
    );
    
    tmds_serializer red_ser (
        .clk_pixel(clk_pixel),
        .clk_5x(clk_tmds),
        .rst(rst_pixel),
        .tmds_in(tmds_10b[2]),
        .tmds_out(tmds_signal[2])
    );
    tmds_serializer green_ser (
        .clk_pixel(clk_pixel),
        .clk_5x(clk_tmds),
        .rst(rst_pixel),
        .tmds_in(tmds_10b[1]),
        .tmds_out(tmds_signal[1])
    );
    tmds_serializer blue_ser (
        .clk_pixel(clk_pixel),
        .clk_5x(clk_tmds),
        .rst(rst_pixel),
        .tmds_in(tmds_10b[0]),
        .tmds_out(tmds_signal[0])
    );

    OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
    OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
    OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
    OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

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
            if (read_data_audio_axis_valid) begin
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

    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            led[0] <= 0;
        end else begin
            if (write_axis_tlast) begin
                led[0] <= 1;
            end
        end
    end
endmodule
// old testing code:

//module top_level (
//    input  wire         clk_100mhz,  //100 MHz onboard clock
//    input  wire  [15:0] sw,          //all 16 input slide switches
//    input  wire  [ 3:0] btn,         //all four momentary button switches
//    output logic [15:0] led,         //16 green output LEDs (located right above switches)
//    output logic [ 2:0] rgb0,        //RGB channels of RGB LED0
//    output logic [ 2:0] rgb1,        //RGB channels of RGB LED1
//    output logic        spkl,        // left line out port
//    output logic        spkr         // right line out port
//);
//
//  //shut up those rgb LEDs for now (active high):
//  assign rgb1 = 0;  //set to 0.
//  assign rgb0 = 0;  //set to 0.
//  assign led  = sw;
//
//  //have btnd control system reset
//  logic sys_rst;
//  assign sys_rst = btn[0];
//
//  logic spk_out;
//  assign spkl = spk_out;
//  assign spkr = spk_out;
//
//  logic        sin_wave;
//  logic        square_wave;
//  logic        impulse_approx;  // same as square at very high frequency
//
//  logic [ 3:0] wave_shift;
//  logic [31:0] wave_period;
//  logic [31:0] wave_frequency;
//  logic [31:0] square_count;
//  logic        square_state;
//
//  logic        divider_busy;
//  logic [31:0] divider_out;
//  logic        divider_out_valid;
//  divider my_divide (
//      .clk(clk_100mhz),
//      .rst(sys_rst),
//      .dividend(32'd50_000_000),
//      .divisor(wave_frequency),
//      .data_in_valid(!divider_busy),
//      .quotient(divider_out),
//      .remainder(),
//      .data_out_valid(divider_out_valid),
//      .busy(divider_busy)
//  );
//
//  always_ff @(posedge clk_100mhz) begin
//    wave_frequency <= {27'b0, 1'b1, sw[15:12]} << sw[11:8];
//    wave_shift <= 4'hF - sw[7:4];
//    wave_period <= divider_out_valid ? divider_out : wave_period;
//  end
//
//  counter wave_count (
//      .clk(clk_100mhz),
//      .rst(sys_rst),
//      .period(wave_period),
//      .count(square_count)
//  );
//
//  counter sampled_counter (
//      .clk(clk_100mhz),
//      .rst(sys_rst),
//      .period(2272),
//      .count(sample_cycle_count)
//  );
//
//  logic [15:0] sin_sample;
//  logic [15:0] sin_upsample;
//  logic [15:0] sample_out;
//  logic [31:0] sample_cycle_count;
//
//  always_ff @(posedge clk_100mhz) begin
//    sample_out <= sw[2] ? $signed(sw[0] ? sin_sample : sin_upsample) >>> wave_shift : 0;
//  end
//
//  sin_gen my_sin_gen (
//      .clk(clk_100mhz),
//      .rst(sys_rst),
//      // ideally 2^29 * 2pi * freq / cycles_per_sample
//      .delta_angle(wave_frequency << 16),
//      .get_next_sample(sample_cycle_count == 0),
//      .current_sample(sin_sample)
//  );
//
//  upsampler my_upsample (
//      .clk(clk_100mhz),
//      .rst(sys_rst),
//      .sample_in(sin_sample),
//      .sample_in_valid(sample_cycle_count == 2),
//      .sample_out(sin_upsample)
//  );
//
//  dlt_sig_dac_2nd_order ds_dac (
//      .clk(clk_100mhz),
//      .rst(sys_rst),
//      .current_sample(sample_out),
//      .audio_out(sin_wave)
//  );
//
//  always_ff @(posedge clk_100mhz) begin
//    square_state <= (square_count == 0) ^ square_state;
//
//    impulse_approx <= square_state && (square_count < 1000);
//    square_wave <= square_state;
//  end
//
//  always_comb begin
//    case (sw[1:0])
//      2'b00:   spk_out = sw[2] ? square_wave : 0;
//      2'b01:   spk_out = sw[2] ? impulse_approx : 0;
//      default: spk_out = sin_wave;
//    endcase
//  end
//
//endmodule  // top_level
`default_nettype wire
