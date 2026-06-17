// User interface:
// Buttons:
//   Center: reset
//   Up/Down/Left/Right: instrument trigger
// Switches:
//   sw[ 0]: slow/fast delay (if UART controller is off)
//   sw[ 1]: UART controller on/off
//   sw[ 2]: expression pedal controls on/off
//   sw[15]: Ethernet latency timer on/off

`timescale 1ns / 1ps
`default_nettype none
module top_level
    (
        input  wire         clk_100mhz,
        output logic [15:0] led,
        input  wire  [15:0] sw,
        input  wire   [4:0] btn,
        input  wire         midi_pin,
       
        // UART
        input  wire         uart_rxd,
        output logic        uart_txd,

        // Seven segment
        output logic  [7:0] ss_a,
        output logic  [6:0] ss_c,

        // Ethernet PHY
        output logic        eth_clk,
        output logic        eth_rst_n,
        output logic        eth_txen,
        output logic  [1:0] eth_txd,
        inout  wire   [2:0] eth_mode,

        // SDRAM (DDR2) ports
        inout  wire  [15:0] ddr2_dq,
        inout  wire   [1:0] ddr2_dqs_n,
        inout  wire   [1:0] ddr2_dqs_p,
        output wire  [12:0] ddr2_addr,
        output wire   [2:0] ddr2_ba,
        output wire         ddr2_ras_n,
        output wire         ddr2_cas_n,
        output wire         ddr2_we_n,
        output wire   [0:0] ddr2_ck_p,
        output wire   [0:0] ddr2_ck_n,
        output wire   [0:0] ddr2_cke,
        output wire   [0:0] ddr2_odt,
        output wire   [0:0] ddr2_cs_n,
        output wire   [1:0] ddr2_dm,

        // Patch pins
        inout wire          dry_pin,
        inout wire          crush_pin,
        inout wire          distortion_pin,
        inout wire          filter_pin,
        inout wire          reverb_pin,
        inout wire          delay_pin,

        // SPI ADC (pots)
        output logic        copi,
        output logic        dclk,
        output logic        cs0,
        output logic        cs1,
        input  wire         cipo,

        // SPI ADC (pedals)
        output logic        pedal_copi,
        output logic        pedal_dclk,
        output logic        pedal_cs,
        input  wire         pedal_cipo,

        // TDM DAC (audio out)
        output logic        dac_copi,
        output logic        dac_bclk,
        output logic        dac_fsync
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

    logic  btn_rst;
    assign btn_rst = btn[0];

    // MIG output
    logic  clk_dram_ctrl;  // 150 MHz
    logic  rst_dram_ctrl;

    // cw_dram_eth
    logic  clk_dram_ref;   // 200 MHz
    logic  clk_audio;      // 120 MHz
    logic  clks_locked;

    logic  clks_locked_dram_ref_buf [1:0];
    logic  clks_locked_dram_ref;
    assign clks_locked_dram_ref = clks_locked_dram_ref_buf[0];

    logic  clks_locked_eth_buf [1:0];
    logic  clks_locked_eth;
    assign clks_locked_eth = clks_locked_eth_buf[0];

    logic  clks_locked_audio_buf [1:0];
    logic  clks_locked_audio;
    assign clks_locked_audio = clks_locked_audio_buf[0];

    logic  init_calib_complete_dram_ctrl;

    logic  rst_buf [1:0];

    logic  rst_dram_ref_buf [1:0];
    logic  rst_dram_ref;
    assign rst_dram_ref = rst_dram_ref_buf[0] | ~clks_locked_dram_ref;

    logic  rst_eth_buf [1:0];
    assign eth_rst_n = ~rst_eth_buf[0] & clks_locked_eth;

    logic  rst_audio_buf [1:0];
    logic  rst_audio;
    assign rst_audio = rst_audio_buf[0] | ~clks_locked_audio;

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


    logic [16*8-1:0] square_wave_samples;
    logic            square_wave_samples_valid;

    square_wave #(
        .AMPLITUDE(10000),
        .FREQUENCY(50.0)
    ) square_wave_0 (
        .clk(clk_audio),
        .rst(rst_audio),
        .sample_out(square_wave_samples[16*1-1:16*0]),
        .sample_out_valid(square_wave_samples_valid)
    );

    genvar sqi;
    generate
        for (sqi=1; sqi<8; sqi++) begin
            square_wave #(
                .AMPLITUDE(10000),
                .FREQUENCY(50.0*(sqi+1))
            ) square_wave_i (
                .clk(clk_audio),
                .rst(rst_audio),
                .sample_out(square_wave_samples[16*(sqi+1)-1:16*sqi]),
                .sample_out_valid()
            );
        end
    endgenerate


    // From PCB interface
    logic [2:0] output_src_pcb;
    logic [2:0] crush_src_pcb;
    logic [2:0] distortion_src_pcb;
    logic [2:0] filter_src_pcb;
    logic [2:0] reverb_src_pcb;
    logic [2:0] delay_src_pcb;

    // From UART controller
    logic [2:0] output_src_uart;
    logic [2:0] crush_src_uart;
    logic [2:0] distortion_src_uart;
    logic [2:0] filter_src_uart;
    logic [2:0] reverb_src_uart;
    logic [2:0] delay_src_uart;

    logic [2:0] output_src;
    logic [2:0] crush_src;
    logic [2:0] distortion_src;
    logic [2:0] filter_src;
    logic [2:0] reverb_src;
    logic [2:0] delay_src;

    // From PCB interface
    logic [9:0] volume_pcb;
    logic [9:0] pitch_pcb;
    logic [9:0] delay_wet_pcb;
    logic [9:0] delay_rate_pcb;
    logic [9:0] delay_feedback_pcb;
    logic [9:0] reverb_wet_pcb;
    logic [9:0] reverb_size_pcb;
    logic [9:0] reverb_feedback_pcb;
    logic [9:0] filter_quality_pcb;
    logic [9:0] filter_cutoff_pcb;
    logic [9:0] distortion_drive_pcb;
    logic [9:0] crush_pressure_pcb;

    // From UART controller
    logic [9:0] volume_uart;
    logic [9:0] pitch_uart;
    logic [9:0] delay_wet_uart;
    logic [9:0] delay_rate_uart;
    logic [9:0] delay_feedback_uart;
    logic [9:0] reverb_wet_uart;
    logic [9:0] reverb_size_uart;
    logic [9:0] reverb_feedback_uart;
    logic [9:0] filter_quality_uart;
    logic [9:0] filter_cutoff_uart;
    logic [9:0] distortion_drive_uart;
    logic [9:0] crush_pressure_uart;
    logic       delay_rate_fast_uart;

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

    // From pedals
    logic [9:0] volume_pedal;
    logic [9:0] pitch_pedal;
    logic [9:0] delay_rate_pedal;
    logic [9:0] delay_feedback_pedal;

    uart_param_controller uart_ctrl (
        .clk(clk_audio),
        .rst(rst_audio),

        .en(sample_load_complete & addr_offsets_valid),
        .uart_din(uart_din),

        .output_src(output_src_uart),
        .crush_src(crush_src_uart),
        .distortion_src(distortion_src_uart),
        .filter_src(filter_src_uart),
        .reverb_src(reverb_src_uart),
        .delay_src(delay_src_uart),
        
        .volume(volume_uart),
        .pitch(pitch_uart),
        .delay_wet(delay_wet_uart),
        .delay_rate(delay_rate_uart),
        .delay_feedback(delay_feedback_uart),
        .reverb_wet(reverb_wet_uart),
        .reverb_size(reverb_size_uart),
        .reverb_feedback(reverb_feedback_uart),
        .filter_quality(filter_quality_uart),
        .filter_cutoff(filter_cutoff_uart),
        .distortion_drive(distortion_drive_uart),
        .crush_pressure(crush_pressure_uart),
        .delay_rate_fast(delay_rate_fast_uart)
    );


    logic [11:0] delay_rate_sum;
    logic [11:0] delay_feedback_sum;
    logic [11:0] pitch_sum;
    logic [11:0] volume_sum;

    logic [9:0] delay_rate_clipped;
    logic [9:0] delay_feedback_clipped;
    logic [9:0] pitch_clipped;
    logic [9:0] volume_clipped;

    always_ff @ (posedge clk_audio) begin
        if (rst_audio) begin
            delay_rate_sum <= 0;
            delay_feedback_sum <= 0;
            pitch_sum <= 0;
            volume_sum <= 0;
            delay_rate_clipped <= 0;
            delay_feedback_clipped <= 0;
            pitch_clipped <= 0;
            volume_clipped <= 0;
        end else begin
            delay_rate_sum <= {2'b00, delay_rate_pedal} + {2'b00, delay_rate_pcb} - 12'd512;
            if ($signed(delay_rate_sum) < 12'sd0) begin
                delay_rate_clipped <= 10'd0;
            end else if ($signed(delay_rate_sum) > 12'sd1023) begin
                delay_rate_clipped <= 10'd1023;
            end else begin
                delay_rate_clipped <= delay_rate_sum;
            end

            delay_feedback_sum <= {2'b00, delay_feedback_pedal} + {2'b00, delay_feedback_pcb} - 12'd512;
            if ($signed(delay_feedback_sum) < 12'sd0) begin
                delay_feedback_clipped <= 10'd0;
            end else if ($signed(delay_feedback_sum) > 12'sd1023) begin
                delay_feedback_clipped <= 10'd1023;
            end else begin
                delay_feedback_clipped <= delay_feedback_sum;
            end

            pitch_sum <= {2'b00, pitch_pedal} + {2'b00, pitch_pcb} - 12'd512;
            if ($signed(pitch_sum) < 12'sd0) begin
                pitch_clipped <= 10'd0;
            end else if ($signed(pitch_sum) > 12'sd1023) begin
                pitch_clipped <= 10'd1023;
            end else begin
                pitch_clipped <= pitch_sum;
            end

            volume_sum <= {2'b00, volume_pedal} + {2'b00, volume_pcb} - 12'd512;
            if ($signed(volume_sum) < 12'sd0) begin
                volume_clipped <= 10'd0;
            end else if ($signed(volume_sum) > 12'sd1023) begin
                volume_clipped <= 10'd1023;
            end else begin
                volume_clipped <= volume_sum;
            end
        end
    end

    always_comb begin
        if (sw[1]) begin
            volume = volume_uart;
            pitch = pitch_uart;
            delay_wet = delay_wet_uart;
            delay_rate = delay_rate_uart;
            delay_feedback = delay_feedback_uart;
            reverb_wet = reverb_wet_uart;
            reverb_size = reverb_size_uart;
            reverb_feedback = reverb_feedback_uart;
            filter_quality = filter_quality_uart;
            filter_cutoff = filter_cutoff_uart;
            distortion_drive = distortion_drive_uart;
            crush_pressure = crush_pressure_uart;
            delay_rate_fast = delay_rate_fast_uart;
        end else begin
            if (sw[2]) begin
                delay_rate = delay_rate_clipped;
                delay_feedback = delay_feedback_clipped;
                pitch = pitch_clipped;
                volume = volume_clipped;
            end else begin
                delay_rate = delay_rate_pcb;
                delay_feedback = delay_feedback_pcb;
                pitch = pitch_pcb;
                volume = volume_pcb;
            end
            delay_wet = delay_wet_pcb;
            reverb_wet = reverb_wet_pcb;
            reverb_size = reverb_size_pcb;
            reverb_feedback = reverb_feedback_pcb;
            filter_quality = filter_quality_pcb;
            filter_cutoff = filter_cutoff_pcb;
            distortion_drive = distortion_drive_pcb;
            crush_pressure = crush_pressure_pcb;
            delay_rate_fast = sw[0];
        end
    end


    logic [13:0] sample_period;
    pitch_to_sample_period p2sp (
        .clk(clk_audio),
        .rst(rst_audio),
        .pitch(pitch),
        .sample_period(sample_period)
    );


    // Synchronization
    always_ff @ (posedge clk_100mhz) begin
        rst_buf <= {btn_rst, rst_buf[1]};
    end
    always_ff @ (posedge clk_dram_ref, posedge btn_rst) begin
        if (btn_rst) begin
            rst_dram_ref_buf <= {1'b1, 1'b1};
        end else begin
            rst_dram_ref_buf <= {1'b0, rst_dram_ref_buf[1]};
            clks_locked_dram_ref_buf <= {
                clks_locked,
                clks_locked_dram_ref_buf[1]
            };
        end
    end
    always_ff @ (posedge eth_clk, posedge btn_rst) begin
        if (btn_rst) begin
            rst_eth_buf <= {1'b1, 1'b1};
        end else begin
            rst_eth_buf <= {1'b0, rst_eth_buf[1]};
            clks_locked_eth_buf <= {
                clks_locked,
                clks_locked_eth_buf[1]
            };
        end
    end
    always_ff @ (posedge clk_audio, posedge btn_rst) begin
        if (btn_rst) begin
            rst_audio_buf <= {1'b1, 1'b1};
        end else begin
            rst_audio_buf <= {1'b0, rst_audio_buf[1]};
            clks_locked_audio_buf <= {
                clks_locked,
                clks_locked_audio_buf[1]
            };
        end
    end
    always_ff @ (posedge clk_audio) begin
        if (rst_audio) begin
            for (int i=0; i<2; i++) begin
                uart_rxd_buf[i]             <= 1'b0;
                midi_din_buf[i]             <= 1'b0;
                sample_load_complete_buf[i] <= 1'b0;
                instr_debug_btn_buf[i]      <= 1'b0;
            end
        end else begin
            uart_rxd_buf             <= {uart_rxd, uart_rxd_buf[1]};
            midi_din_buf             <= {midi_pin, midi_din_buf[1]};
            sample_load_complete_buf <= {sample_load_complete_dram_ctrl, sample_load_complete_buf[1]};
            instr_debug_btn_buf      <= {btn[4:1], instr_debug_btn_buf[1]};
        end
    end


    // Instrument trigger buttons
    genvar i;
    generate
        for (i=0; i<4; i++) begin
            debouncer_trig db_instr_trig (
                .clk(clk_audio),
                .rst(rst_audio),
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


    cw_dram_eth cw_dram_eth_i (
        .clk_in(clk_100mhz),          // 100 MHz
        .reset(rst_buf[0]),
        .locked(clks_locked),
        .clk_dram_ref(clk_dram_ref),  // 200 MHz
        .eth_clk(eth_clk),            // 50  MHz
        .clk_audio(clk_audio)         // 120 MHz
    );


    logic [127:0] write_axis_data;
    logic         write_axis_tlast;
    logic         write_axis_valid;
    logic         write_axis_ready;

    dram_writer #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) dwr (
        .clk(clk_audio),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst_audio),
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
        .clk(clk_audio),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst_audio),
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
        .clk(clk_audio),
        .clk_dram_ctrl(clk_dram_ctrl),
        .rst(rst_audio),
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

    logic [15:0] instrument_samples_resampled [INSTRUMENT_COUNT-1:0];
    logic [15:0] sample_processed_l;
    logic [15:0] sample_processed_r;
    logic        sample_processed_valid;
    audio_processor #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) aud_pcr (
        .clk(clk_audio),
        .rst(rst_audio),

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

        .instrument_samples(current_instrument_samples),
        .sample_from_dram(sample_raw),
        .valid_from_dram(sample_raw_valid),

        .sample_out_l(sample_processed_l),
        .sample_out_r(sample_processed_r),
        .instrument_samples_out(instrument_samples_resampled),
        .sample_out_valid(),
        .sample_out_valid_base(sample_processed_valid)
    );


    pcb_interface pcb (
        .clk(clk_audio),
        .rst(rst_audio),

        .dry_pin(dry_pin),
        .delay_pin(delay_pin),
        .reverb_pin(reverb_pin),
        .filter_pin(filter_pin),
        .distortion_pin(distortion_pin),
        .crush_pin(crush_pin),

        .output_src(output_src),
        .crush_src(crush_src),
        .distortion_src(distortion_src),
        .filter_src(filter_src),
        .reverb_src(reverb_src),
        .delay_src(delay_src),

        .cipo(cipo),
        .copi(copi),
        .dclk(dclk),
        .cs0(cs0),
        .cs1(cs1),

        .volume(volume_pcb),
        .pitch(pitch_pcb),
        .delay_wet(delay_wet_pcb),
        .delay_rate(delay_rate_pcb),
        .delay_feedback(delay_feedback_pcb),
        .reverb_wet(reverb_wet_pcb),
        .reverb_size(reverb_size_pcb),
        .reverb_feedback(reverb_feedback_pcb),
        .filter_quality(filter_quality_pcb),
        .filter_cutoff(filter_cutoff_pcb),
        .distortion_drive(distortion_drive_pcb),
        .crush_pressure(crush_pressure_pcb)
    );


    logic [9:0] pedal_value;
    logic [1:0] pedal_index;
    logic       pedal_value_valid;
    pedal_controller pedal_con (
        .clk(clk_audio),
        .rst(rst_audio),

        .cipo(pedal_cipo),
        .copi(pedal_copi),
        .dclk(pedal_dclk),
        .cs(pedal_cs),
        
        .value(pedal_value),
        .pedal_index(pedal_index),
        .value_valid(pedal_value_valid)
    );
    always_ff @ (posedge clk_audio) begin
        if (rst_audio) begin
            volume_pedal <= 0;
            pitch_pedal <= 0;
            delay_rate_pedal <= 0;
            delay_feedback_pedal <= 0;
        end else begin
            if (pedal_value_valid) begin
                case (pedal_index)
                    2'b00: volume_pedal <= pedal_value;
                    2'b01: pitch_pedal <= pedal_value;
                    2'b10: delay_rate_pedal <= pedal_value;
                    2'b11: delay_feedback_pedal <= pedal_value <= 10'd823 ? pedal_value+10'd200 : 10'd1023;
                endcase
            end
        end
    end


    audio_eth_transmit audio_eth_transmit_i (
        .clk(clk_audio),
        .rst(rst_audio),
        .sample_in(
            {
                instrument_samples_resampled[9],
                instrument_samples_resampled[8],
                instrument_samples_resampled[7],
                instrument_samples_resampled[6],
                instrument_samples_resampled[5],
                instrument_samples_resampled[4],
                instrument_samples_resampled[3],
                instrument_samples_resampled[2],
                instrument_samples_resampled[1],
                instrument_samples_resampled[0],
                sample_processed_r,
                sample_processed_l
            }
        ),
        .sample_in_valid(sample_processed_valid),

        .eth_clk(eth_clk),
        .eth_rst_n(eth_rst_n),
        .eth_txen(eth_txen),
        .eth_txd(eth_txd),
        .eth_crsdv(eth_mode[2]),
        .eth_rxd(eth_mode[1:0]),

        .sw_latency_timer(sw[15])
    );

    dac_controller dac_controller_i (
        .clk(clk_audio),
        .rst(rst_audio),
        .sample_in_l(sample_processed_l),
        .sample_in_r(sample_processed_r),
        .sample_in_valid(sample_processed_valid),
        
        .dac_copi(dac_copi),
        .dac_bclk(dac_bclk),
        .dac_fsync(dac_fsync)
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
    always_comb begin
        //ss_val = {
        //    audio_eth_transmit_i.packet_rx_counter,
        //    audio_eth_transmit_i.sample_period_offset
        //};
        
        ss_val = audio_eth_transmit_i.eth_latency_counter;

        //if (sample_load_complete) begin
        //    ss_val = {
        //        //pedal_value[9:2],
        //        1'b0,
        //        drd_req.midi_proc.velocity,  // 7 bits
        //        4'b0,
        //        memrequest_complete_counter[19:0]
        //    };
        //end else begin
        //    ss_val = {
        //        dwr.sample_loader_i.instrument_counter, // 4 bits
        //        4'b0,
        //        memrequest_complete_counter  // 24 bits
        //    };
        //end
    end
    seven_segment_controller ssc (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .val(ss_val),
        .cat(ss_c),
        .an(ss_a)
    );


    //logic[31:0] ss_val;
    //always_ff @ (posedge clk) begin
    //    if (rst) begin
    //        ss_val <= 0;
    //    end else begin
    //        ss_val <= {
    //            6'b0,
    //            pitch_pedal,
    //            6'b0,
    //            volume_pedal
    //        };
    //    end
    //end
    //seven_segment_controller ssc (
    //    .clk(clk),
    //    .rst(rst),
    //    .val(ss_val),
    //    .cat(ss_c),
    //    .an(ss_a)
    //);


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
    assign led[3] = init_calib_complete_dram_ctrl;
    assign led[4] = ~rst_dram_ref;
    assign led[5] = ~rst_dram_ctrl;
    assign led[6] = clks_locked;
    assign led[7] = eth_rst_n;
    assign led[15:8] = 0;
    assign uart_txd = 0;
endmodule
`default_nettype wire
