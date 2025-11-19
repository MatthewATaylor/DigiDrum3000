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
        input  wire         midi_pin,
        output logic        spkl,
        output logic        spkr,
       
        // UART
        input wire          uart_rxd,
        output logic        uart_txd,

        // SPI ADC
        output logic        copi,
        output logic        dclk,
        output logic        cs0,
        output logic        cs1,
        input wire          cipo,

        // Patch pins
        inout wire          dry_pin,
        inout wire          crush_pin,
        inout wire          distortion_pin,
        inout wire          filter_pin,
        inout wire          reverb_pin,
        inout wire          delay_pin,

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
    assign led[15:4] = 0;
    assign rgb0 = 0;
    assign rgb1 = 0;
    assign uart_txd = 0;

    logic [23:0]  addr_offsets [INSTRUMENT_COUNT:0];
    logic         addr_offsets_valid;
    logic         addr_offsets_valid_pixel;


    logic [9:0] volume[2:0];
    logic [9:0] pitch [2:0];
    logic [9:0] delay_wet[2:0];
    logic [9:0] delay_rate[2:0];
    logic [9:0] delay_feedback[2:0];
    logic [9:0] reverb_wet[2:0];
    logic [9:0] reverb_size[2:0];
    logic [9:0] reverb_feedback[2:0];
    logic [9:0] filter_quality[2:0];
    logic [9:0] filter_cutoff[2:0];
    logic [9:0] distortion_drive[2:0];
    logic [9:0] crush_pressure[2:0];

    logic [13:0] sample_period;
    pitch_to_sample_period p2sp (
        .clk(clk),
        .rst(rst),
        .pitch(sw[5] ? pitch[0] : sw[15:6]),
        .sample_period(sample_period)
    );


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
            midi_din_buf <= {midi_pin, midi_din_buf[1]};

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

    // rst_video causes video_sig_gen to be disabled during sample loading.
    // Do this in order to start up video in a well defined state.
    // Put rst_video through a register to delay one cycle.
    //  (aligns with reset signal for dram_writer stacker)
    logic rst_video;
    assign rst_video = ~sample_load_complete_pixel | ~addr_offsets_valid_pixel;
    logic rst_video_buf;
    always_ff @ (posedge clk_pixel) begin
        if (rst_pixel) begin
            rst_video_buf <= 1;
        end else begin
            rst_video_buf <= rst_video;
        end
    end

    video_sig_gen video_sig_gen_i (
        .pixel_clk(clk_pixel),
        .rst(rst_pixel | rst_video_buf),

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
        .addr_offsets_valid_pixel(addr_offsets_valid_pixel),
    
        .pixel_valid(active_draw_hdmi),
        .pixel_data(pixel_to_write),
        .pixel_last(pixel_last),

        .fifo_receiver_axis_tvalid(write_axis_valid),
        .fifo_receiver_axis_tready(write_axis_ready),
        .fifo_receiver_axis_tdata(write_axis_data),
        .fifo_receiver_axis_tlast(write_axis_tlast)
    );

    logic [39:0]  read_addr_axis_data;
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

        .sample_period(sample_period),
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
    logic [167:0] read_data_audio_axis_data;

    logic [15:0]  current_instrument_samples [INSTRUMENT_COUNT-1:0];
    logic [13:0]  sample_period_dram_out;

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
        .instrument_samples(current_instrument_samples),

        .fifo_sender_axis_tvalid(read_data_audio_axis_valid),
        .fifo_sender_axis_tready(read_data_audio_axis_ready),
        .fifo_sender_axis_tdata(read_data_audio_axis_data),

        .sample_period(sample_period_dram_out)
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

    logic [15:0] resample;
    logic        resample_valid;
    resampler resampler_i (
        .clk(clk),
        .rst(rst),
        .sample_period_in(sample_period_dram_out),
        .sample_period_farrow_out(14'd568),
        .sample_in(sample_raw),
        .sample_in_valid(sample_raw_valid),
        .sample_out(resample),
        .sample_out_valid(resample_valid)
    );

    logic [15:0] delay_out;
    logic        delay_out_valid;
    audio_delay delay (
        .clk(clk),
        .rst(rst),
        .pot_wet(10'b0),
        .pot_rate(delay_rate[0]),
        .pot_feedback(10'b0),
        .sample_in(resample),
        .sample_in_valid(resample_valid),
        .sample_out(delay_out),
        .sample_out_valid(delay_out_valid)
    );

    logic [15:0] sample_upsampled;
    upsampler upsampler_i (
        .clk(clk),
        .rst(rst),
        .sample_in(delay_out),
        .sample_in_valid(delay_out_valid),
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

    logic [23:0] pixel_to_display_24;
    logic active_draw_to_hdmi;
    logic v_sync_to_hdmi;
    logic h_sync_to_hdmi;

    video_processor #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) vid_pcr (
        .clk_100MHz(clk),
        .clk_pixel(clk_pixel),
        .rst(rst),

        //.instrument_samples(current_instrument_samples),
        .midi_key(instr_trig_debug[0] ? 7'd36 : instr_trig_debug[1] ? 7'd38 : 7'd46),
        .midi_valid(|instr_trig_debug),
        .midi_velocity(7'h7F),
        .volume_on_clk(volume[0]),
        .pitch_on_clk(pitch[0]),
        .delay_wet_on_clk(delay_wet[0]),
        .delay_rate_on_clk(delay_rate[0]),
        .delay_feedback_on_clk(delay_feedback[0]),
        .reverb_wet_on_clk(reverb_wet[0]),
        .reverb_size_on_clk(reverb_size[0]),
        .reverb_feedback_on_clk(reverb_feedback[0]),
        .filter_quality_on_clk(filter_quality[0]),
        .filter_cutoff_on_clk(filter_cutoff[0]),
        .distortion_drive_on_clk(distortion_drive[0]),
        .crush_pressure_on_clk(crush_pressure[0]),

        .output_src_on_clk(output_src[0]),
        .crush_src_on_clk(crush_src[0]),
        .distortion_src_on_clk(distortion_src[0]),
        .filter_src_on_clk(filter_src[0]),
        .reverb_src_on_clk(reverb_src[0]),
        .delay_src_on_clk(delay_src[0]),

        .pixel_to_hdmi(pixel_to_display_24),
        .active_draw_to_hdmi(active_draw_to_hdmi),
        .v_sync_to_hdmi(v_sync_to_hdmi),
        .h_sync_to_hdmi(h_sync_to_hdmi)
      );

    logic [9:0] tmds_10b    [0:2];
    logic       tmds_signal [2:0];
 
    tmds_encoder tmds_red (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .video_data(pixel_to_display_24[23:16]),
        .control(2'b0),
        .video_enable(active_draw_to_hdmi),
        .tmds(tmds_10b[2])
    );
    tmds_encoder tmds_green (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .video_data(pixel_to_display_24[15:8]),
        .control(2'b0),
        .video_enable(active_draw_to_hdmi),
        .tmds(tmds_10b[1])
    );
    tmds_encoder tmds_blue (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .video_data(pixel_to_display_24[7:0]),
        .control({v_sync_to_hdmi, h_sync_to_hdmi}),
        .video_enable(active_draw_to_hdmi),
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

    logic [2:0] output_src[2:0];
    logic [2:0] crush_src[2:0];
    logic [2:0] distortion_src[2:0];
    logic [2:0] filter_src[2:0];
    logic [2:0] reverb_src[2:0];
    logic [2:0] delay_src[2:0];

    pcb_interface pcb (
        .clk(clk),
        .rst(rst),

        .dry_pin(dry_pin),
        .delay_pin(delay_pin),
        .reverb_pin(reverb_pin),
        .filter_pin(filter_pin),
        .distortion_pin(distortion_pin),
        .crush_pin(crush_pin),

        .output_src(output_src[0]),
        .crush_src(crush_src[0]),
        .distortion_src(distortion_src[0]),
        .filter_src(filter_src[0]),
        .reverb_src(reverb_src[0]),
        .delay_src(delay_src[0]),

        .cipo(cipo),
        .copi(copi),
        .dclk(dclk),
        .cs0(cs0),
        .cs1(cs1),

        .volume(volume[0]),
        .pitch(pitch[0]),
        .delay_wet(delay_wet[0]),
        .delay_rate(delay_rate[0]),
        .delay_feedback(delay_feedback[0]),
        .reverb_wet(reverb_wet[0]),
        .reverb_size(reverb_size[0]),
        .reverb_feedback(reverb_feedback[0]),
        .filter_quality(filter_quality[0]),
        .filter_cutoff(filter_cutoff[0]),
        .distortion_drive(distortion_drive[0]),
        .crush_pressure(crush_pressure[0])
    );

    // clock boundry
    always_ff @(posedge clk_dram_ctrl) begin
        output_src[2] <= output_src[1];
        output_src[1] <= output_src[0];
        crush_src[2] <= crush_src[1];
        crush_src[1] <= crush_src[0];
        distortion_src[2] <= distortion_src[1];
        distortion_src[1] <= distortion_src[0];
        filter_src[2] <= filter_src[1];
        filter_src[1] <= filter_src[0];
        reverb_src[2] <= reverb_src[1];
        reverb_src[1] <= reverb_src[0];
        delay_src[2] <= delay_src[1];
        delay_src[1] <= delay_src[0];
        volume[2] <= volume[1];
        volume[1] <= volume[0];
        pitch[2] <= pitch[1];
        pitch[1] <= pitch[0];
        delay_wet[2] <= delay_wet[1];
        delay_wet[1] <= delay_wet[0];
        delay_rate[2] <= delay_rate[1];
        delay_rate[1] <= delay_rate[0];
        delay_feedback[2] <= delay_feedback[1];
        delay_feedback[1] <= delay_feedback[0];
        reverb_wet[2] <= reverb_wet[1];
        reverb_wet[1] <= reverb_wet[0];
        reverb_size[2] <= reverb_size[1];
        reverb_size[1] <= reverb_size[0];
        reverb_feedback[2] <= reverb_feedback[1];
        reverb_feedback[1] <= reverb_feedback[0];
        filter_quality[2] <= filter_quality[1];
        filter_quality[1] <= filter_quality[0];
        filter_cutoff[2] <= filter_cutoff[1];
        filter_cutoff[1] <= filter_cutoff[0];
        distortion_drive[2] <= distortion_drive[1];
        distortion_drive[1] <= distortion_drive[0];
        crush_pressure[2] <= crush_pressure[1];
        crush_pressure[1] <= crush_pressure[0];
    end

    logic [31:0] ss_val;
    always_comb begin
        case (sw[4:2])
            3'b001: ss_val = {6'h00, volume[2], 6'h00, pitch[2]};
            3'b010: ss_val = {6'h00, delay_wet[2], 6'h00, delay_rate[2]};
            3'b011: ss_val = {6'h00, delay_feedback[2], 6'h00, reverb_wet[2]};
            3'b100: ss_val = {6'h00, reverb_size[2], 6'h00, reverb_feedback[2]};
            3'b101: ss_val = {6'h00, filter_quality[2], 6'h00, filter_cutoff[2]};
            3'b110: ss_val = {6'h00, distortion_drive[2], 6'h00, crush_pressure[2]};
            3'b111: ss_val = {
                7'h0, delay_src[2],
                1'b0, reverb_src[2],
                1'b0, filter_src[2],
                1'b0, distortion_src[2],
                1'b0, crush_src[2],
                1'b0, output_src[2]
            };
            default: ss_val = {16'b0, memrequest_complete_counter[15:0]};
        endcase
    end

    logic [6:0] ss_c;
    assign ss0_c = ss_c;
    assign ss1_c = ss_c;
    seven_segment_controller ssc (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .val(ss_val),
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
    assign led[3] = tg.write_addr_last_valid;
endmodule
`default_nettype wire
