`timescale 1ns / 1ps
`default_nettype none
module top_level
    (
        input  wire         clk_100mhz,
        output logic [15:0] led,
        input  wire  [15:0] sw,
        input  wire   [4:0] btn,
        output logic        spk,
        output logic        aud_sd_n,
       
        // UART
        input  wire         uart_rxd,
        output logic        uart_txd,

        // Seven segment
        output logic  [7:0] ss_a,
        output logic  [6:0] ss_c,

        // SDRAM (DDR2) ports
        inout  wire [15:0] ddr2_dq,
        inout  wire  [1:0] ddr2_dqs_n,
        inout  wire  [1:0] ddr2_dqs_p,
        output wire [12:0] ddr2_addr,
        output wire  [2:0] ddr2_ba,
        output wire        ddr2_ras_n,
        output wire        ddr2_cas_n,
        output wire        ddr2_we_n,
        output wire  [0:0] ddr2_ck_p,
        output wire  [0:0] ddr2_ck_n,
        output wire  [0:0] ddr2_cke,
        output wire  [0:0] ddr2_odt,
        output wire  [0:0] ddr2_cs_n,
        output wire  [1:0] ddr2_dm
    );

    localparam INSTRUMENT_COUNT = 10;

    // First three elements are also mapped to btn[4:1]
    localparam [6:0] MIDI_KEYS [0:INSTRUMENT_COUNT-1] = {
        7'd36,  // bd
        7'd38,  // sd
        7'd48,  // t1
        7'd45,  // t2
        7'd43,  // t3
        7'd46,  // hh_opened
        7'd42,  // hh_closed
        7'd44,  // hh_pedal
        7'd49,  // cc
        7'd51   // rc
    };

    // TODO: add MIDI pin
    logic  midi_pin;
    assign midi_pin = 1'b0;

    assign aud_sd_n = 1'b1;  // Active low shutdown signal for audio output

    logic  clk;
    assign clk = clk_100mhz;
    
    // MIG output
    logic  clk_dram_ctrl;  // 150 MHz
    logic  rst_dram_ctrl;

    // cw_dram
    logic  clk_dram_ref;   // 200 MHz
    logic  cw_dram_locked;

    logic  cw_dram_locked_dram_ref_buf [1:0];
    logic  cw_dram_locked_dram_ref;
    assign cw_dram_locked_dram_ref = cw_dram_locked_dram_ref_buf[0];

    logic  init_calib_complete_dram_ctrl;
    logic  init_calib_complete_buf [1:0];
    logic  init_calib_complete;
    assign init_calib_complete = init_calib_complete_buf[0];

    logic  rst_buf [1:0];
    logic  rst;
    assign rst = rst_buf[0] | ~cw_dram_locked | ~init_calib_complete;   

    logic  rst_dram_ref_buf [1:0];
    logic  rst_dram_ref;
    assign rst_dram_ref = rst_dram_ref_buf[0] | ~cw_dram_locked_dram_ref;

    logic  uart_rxd_buf [1:0];
    logic  uart_din;
    assign uart_din = uart_rxd_buf[0];

    logic  midi_din_buf [1:0];
    logic  midi_din;
    assign midi_din = midi_din_buf[0];

    logic  sample_load_complete_dram_ctrl;
    logic  sample_load_complete_buf [1:0];
    logic  sample_load_complete;
    assign sample_load_complete = sample_load_complete_buf[0];

    logic  [INSTRUMENT_COUNT-1:0] instr_debug_btn_buf [1:0];
    logic  [INSTRUMENT_COUNT-1:0] instr_debug_btn;
    assign instr_debug_btn = instr_debug_btn_buf[0];
    logic  [INSTRUMENT_COUNT-1:0] instr_trig_debug;

    logic [23:0] addr_offsets [INSTRUMENT_COUNT:0];
    logic        addr_offsets_valid;


    logic [2:0] output_src;
    logic [2:0] crush_src;
    logic [2:0] distortion_src;
    logic [2:0] filter_src;
    logic [2:0] reverb_src;
    logic [2:0] delay_src;

    logic [9:0] volume;
    logic [9:0] pitch;
    logic [9:0] delay_wet;
    logic [9:0] delay_rate;
    logic [9:0] delay_feedback;
    logic [9:0] reverb_wet;
    logic [9:0] reverb_size;
    logic [9:0] reverb_feedback;
    logic [9:0] filter_quality;
    logic [9:0] filter_cutoff;
    logic [9:0] distortion_drive;
    logic [9:0] crush_pressure;
    logic       delay_rate_fast;

    uart_param_controller uart_ctrl (
        .clk(clk),
        .rst(rst),

        .en(sample_load_complete & addr_offsets_valid),
        .uart_din(uart_din),

        .output_src(output_src),
        .crush_src(crush_src),
        .distortion_src(distortion_src),
        .filter_src(filter_src),
        .reverb_src(reverb_src),
        .delay_src(delay_src),
        
        .volume(volume),
        .pitch(pitch),
        .delay_wet(delay_wet),
        .delay_rate(delay_rate),
        .delay_feedback(delay_feedback),
        .reverb_wet(reverb_wet),
        .reverb_size(reverb_size),
        .reverb_feedback(reverb_feedback),
        .filter_quality(filter_quality),
        .filter_cutoff(filter_cutoff),
        .distortion_drive(distortion_drive),
        .crush_pressure(crush_pressure),
        .delay_rate_fast(delay_rate_fast)
    );


    logic [13:0] sample_period;
    pitch_to_sample_period p2sp (
        .clk(clk),
        .rst(rst),
        .pitch(pitch),
        .sample_period(sample_period)
    );


    // Synchronization
    always_ff @ (posedge clk) begin
        rst_buf <= {btn[0], rst_buf[1]};
        init_calib_complete_buf <= {init_calib_complete_dram_ctrl, init_calib_complete_buf[1]};

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
            // From 75 MHz to 100 MHz
            sample_load_complete_buf <= {sample_load_complete_dram_ctrl, sample_load_complete_buf[1]};

            instr_debug_btn_buf <= {btn[4:1], instr_debug_btn_buf[1]};
        end
    end
    always_ff @ (posedge clk_dram_ref) begin
        rst_dram_ref_buf <= {btn[0], rst_dram_ref_buf[1]};
        cw_dram_locked_dram_ref_buf <= {
            cw_dram_locked,
            cw_dram_locked_dram_ref_buf[1]
        };
    end


    // Instrument trigger buttons
    genvar i;
    generate
        for (i=0; i<4; i++) begin
            debouncer_trig db_instr_trig (
                .clk(clk),
                .rst(rst),
                .dirty(instr_debug_btn[i]),
                .clean(instr_trig_debug[i])
            );
        end
    endgenerate
    always_comb begin
        for (int i=4; i<INSTRUMENT_COUNT; i++) begin
            instr_trig_debug[i] = 1'b0;
        end
    end


    // Generate 200 MHz DRAM controller system clock
    cw_dram cw_dram_i (
        .clk_dram_ref(clk_dram_ref),
        .reset(btn[0]),
        .locked(cw_dram_locked),
        .clk_in1(clk)
    );


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
        
        .addr_offsets(addr_offsets),
        .addr_offsets_valid(addr_offsets_valid),
    
        .fifo_receiver_axis_tvalid(write_axis_valid),
        .fifo_receiver_axis_tready(write_axis_ready),
        .fifo_receiver_axis_tdata(write_axis_data),
        .fifo_receiver_axis_tlast(write_axis_tlast)
    );

    logic [39:0]  read_addr_axis_data;
    logic         read_addr_axis_tlast;
    logic         read_addr_axis_valid;
    logic         read_addr_axis_ready;

    logic [ 6:0]  velocity_map [INSTRUMENT_COUNT-1:0];

    logic [6:0] midi_key;
    logic [6:0] midi_vel;
    logic       midi_msg_valid;

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

        .velocity(velocity_map),

        .instr_trig_debug(instr_trig_debug),

        .midi_key(midi_key),
        .midi_vel(midi_vel),
        .midi_dout_valid(midi_msg_valid)
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
        .velocity(velocity_map),

        .instrument_samples(current_instrument_samples),
        .sample(sample_raw),
        .sample_valid(sample_raw_valid),

        .fifo_sender_axis_tvalid(read_data_audio_axis_valid),
        .fifo_sender_axis_tready(read_data_audio_axis_ready),
        .fifo_sender_axis_tdata(read_data_audio_axis_data),

        .sample_period(sample_period_dram_out)
    );

    logic [23:0]  memrequest_addr;
    logic         memrequest_en;
    logic [127:0] memrequest_write_data;
    logic         memrequest_write_enable;
    logic         memrequest_write_ready;
    logic [127:0] memrequest_read_data;
    logic         memrequest_read_valid;

    logic         memrequest_ready;
    logic         memrequest_busy;
    assign        memrequest_busy = ~memrequest_ready;

    traffic_generator tg (
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst_dram_ctrl(rst_dram_ctrl),

        .sample_load_complete(sample_load_complete_dram_ctrl),

        .memrequest_addr(memrequest_addr),
        .memrequest_en(memrequest_en),
        .memrequest_write_data(memrequest_write_data),
        .memrequest_write_enable(memrequest_write_enable),
        .memrequest_write_ready(memrequest_write_ready),
        .memrequest_read_data(memrequest_read_data),
        .memrequest_read_valid(memrequest_read_valid),
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
        .read_data_audio_axis_data(read_data_audio_axis_data)
    );

    mig_nexys4ddr mig_nexys4ddr_i (
        // Memory interface ports
        .ddr2_addr           (ddr2_addr),
        .ddr2_ba             (ddr2_ba),
        .ddr2_cas_n          (ddr2_cas_n),
        .ddr2_ck_n           (ddr2_ck_n),
        .ddr2_ck_p           (ddr2_ck_p),
        .ddr2_cke            (ddr2_cke),
        .ddr2_ras_n          (ddr2_ras_n),
        .ddr2_we_n           (ddr2_we_n),
        .ddr2_dq             (ddr2_dq),
        .ddr2_dqs_n          (ddr2_dqs_n),
        .ddr2_dqs_p          (ddr2_dqs_p),
        .ddr2_odt            (ddr2_odt),
        .ddr2_cs_n           (ddr2_cs_n),
        .ddr2_dm             (ddr2_dm),

        // Application interface ports
        .app_addr            ({memrequest_addr, 3'b0}),
        .app_cmd             ({2'b0, ~memrequest_write_enable}),
        .app_en              (memrequest_en),
        .app_rdy             (memrequest_ready),
        .app_wdf_data        (memrequest_write_data),
        .app_wdf_end         (memrequest_write_enable),
        .app_wdf_wren        (memrequest_write_enable),
        .app_wdf_rdy         (memrequest_write_ready),
        .app_wdf_mask        (16'b0),
        .app_rd_data         (memrequest_read_data),
        .app_rd_data_valid   (memrequest_read_valid),
        .app_rd_data_end     (),
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),

        .ui_clk              (clk_dram_ctrl),
        .ui_clk_sync_rst     (rst_dram_ctrl),

        .sys_clk_i           (clk_dram_ref),
        .sys_rst             (~rst_dram_ref),
        
        .init_calib_complete (init_calib_complete_dram_ctrl)
    );


    audio_processor aud_pcr (
        .clk(clk),
        .rst(rst),

        .volume_on_clk(volume),
        .delay_wet_on_clk(delay_wet),
        .delay_rate_on_clk(delay_rate),
        .delay_feedback_on_clk(delay_feedback),
        .reverb_wet_on_clk(reverb_wet),
        .reverb_size_on_clk(reverb_size),
        .reverb_feedback_on_clk(reverb_feedback),
        .filter_quality_on_clk(filter_quality),
        .filter_cutoff_on_clk(filter_cutoff),
        .distortion_drive_on_clk(distortion_drive),
        .crush_pressure_on_clk(crush_pressure),

        .output_src_on_clk(output_src),
        .crush_src_on_clk(crush_src),
        .distortion_src_on_clk(distortion_src),
        .filter_src_on_clk(filter_src),
        .reverb_src_on_clk(reverb_src),
        .delay_src_on_clk(delay_src),

        .delay_rate_fast_on_clk(delay_rate_fast),

        .sample_period_dram_out(sample_period_dram_out),

        .sample_from_dram(sample_raw),
        .valid_from_dram(sample_raw_valid),

        .spkl(spk),
        .spkr()
    );


    // Debug

    logic [23:0]  memrequest_complete_counter;
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            memrequest_complete_counter <= 0;
        end else begin
            if (memrequest_write_enable && memrequest_ready && memrequest_write_ready) begin
                memrequest_complete_counter <= memrequest_complete_counter + 1;
            end
        end
    end

    logic [31:0] ss_val;
    assign ss_val = {
        dwr.sample_loader_i.instrument_counter,
        4'b0,
        memrequest_complete_counter
    };

    seven_segment_controller ssc (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .val(ss_val),
        .cat(ss_c),
        .an(ss_a)
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
    assign led[1] = sample_load_complete;
    assign led[2] = addr_offsets_valid;
    assign led[3] = init_calib_complete;
    assign led[4] = init_calib_complete_dram_ctrl;
    assign led[5] = ~rst_dram_ref;
    assign led[6] = ~rst_dram_ctrl;
    assign led[7] = cw_dram_locked;
    assign led[15:8] = 0;
    assign uart_txd = 0;
endmodule
`default_nettype wire
