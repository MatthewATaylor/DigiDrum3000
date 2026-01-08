`timescale 1ns / 1ps
`default_nettype none

module traffic_generator
    (
        input wire           clk_dram_ctrl,
        input wire           rst_dram_ctrl,

        output logic         sample_load_complete,

        // DRAM controller signals
        output logic [23:0]  memrequest_addr,
        output logic         memrequest_en,
        output logic [127:0] memrequest_write_data,
        output logic         memrequest_write_enable,
        input wire           memrequest_write_ready,
        input wire   [127:0] memrequest_read_data,
        input wire           memrequest_read_valid,
        input wire           memrequest_busy,
        
        // Write AXIS FIFO input
        input wire   [127:0] write_axis_data,
        input wire           write_axis_tlast,
        input wire           write_axis_valid,
        output logic         write_axis_ready,

        // Read address AXIS FIFO input
        input wire   [39:0]  read_addr_axis_data,
        input wire           read_addr_axis_tlast,
        input wire           read_addr_axis_valid,
        output logic         read_addr_axis_ready,

        // Audio read data AXIS FIFO output
        // tlast always low
        output logic                 read_data_audio_axis_valid,
        input wire                   read_data_audio_axis_ready,
        output logic [16+24+128-1:0] read_data_audio_axis_data
    );

    // RST: Do not interface with DRAM
    // WR_AUDIO: Write audio data from write FIFO to DRAM
    //  (but hold this state until all audio samples are written)
    // RD_AUDIO: Give DRAM read request using address in read_addr FIFO
    enum {RST, WR_AUDIO, RD_AUDIO} state;

    assign write_axis_ready =
        !memrequest_busy && memrequest_write_ready && (state == WR_AUDIO);
    
    // read_addr FIFO is only for audio
    assign read_addr_axis_ready =
        !memrequest_busy && (state == RD_AUDIO);


    // On startup, count up as audio samples are written to memory
    logic [23:0] write_address;
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            write_address <= 0;
        end else begin
            if (write_axis_valid & write_axis_ready) begin
                write_address <= write_address + 1;
            end
        end
    end


    logic [13:0] memrequest_sample_period;

    logic [23:0] response_addr;
    logic [13:0] response_sample_period;
    
    command_fifo #(
        .DEPTH(64),
        .WIDTH(38)
    ) mcf (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .write(
            memrequest_en &&
            !memrequest_write_enable &&
            !memrequest_busy
        ),
        .command_in(
            {
                memrequest_addr,
                memrequest_sample_period
            }
        ),
        .full(),
        
        .command_out(
            {
                response_addr,
                response_sample_period
            }
        ),
        .read(memrequest_read_valid),
        .empty()
    );

    // Set data/valid signals for read data FIFOs
    assign read_data_audio_axis_data = {
        2'b0,
        response_sample_period,
        response_addr,
        memrequest_read_data
    };
    assign read_data_audio_axis_valid = memrequest_read_valid;

    // Determine when memory is filled with audio samples
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            sample_load_complete <= 0;
        end else begin
            if (!sample_load_complete && write_axis_tlast) begin
                sample_load_complete <= 1;
            end
        end
    end

    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            state <= RST;
        end else begin
            if (sample_load_complete) begin
                // dram_writer can send 1 chunk every 8 100 MHz cycles.
                // traffic_generator accesses write FIFO every 75 MHz cycle.
                // Therefore, the write FIFO should not overflow.
                // 
                // dram_read_requester sends 1 address even less frequently
                //  (audio sample rate)
                state <= RD_AUDIO;
            end else begin
                state <= WR_AUDIO;
            end
        end
    end

    always_comb begin
        case (state)
            RST: begin
                memrequest_addr = 0;
                memrequest_sample_period = 14'b0;
                memrequest_en = 0;
                memrequest_write_data = 0;
                memrequest_write_enable = 0;
            end
            WR_AUDIO: begin
                memrequest_addr = write_address;
                memrequest_sample_period = 14'b0;
                memrequest_en = write_axis_valid && !memrequest_busy;
                memrequest_write_enable = write_axis_valid && !memrequest_busy;
                memrequest_write_data = write_axis_data;
            end
            RD_AUDIO: begin
                memrequest_addr = read_addr_axis_data[23:0];
                memrequest_sample_period = read_addr_axis_data[37:24];
                memrequest_en = read_addr_axis_valid && !memrequest_busy;
                memrequest_write_enable = 0;
                memrequest_write_data = 0;
            end
            default: begin
                memrequest_addr = 0;
                memrequest_sample_period = 14'b0;
                memrequest_en = 0;
                memrequest_write_data = 0;
                memrequest_write_enable = 0;
            end
        endcase
    end
endmodule

`default_nettype wire
