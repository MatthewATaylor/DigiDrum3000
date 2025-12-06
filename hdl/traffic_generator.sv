`timescale 1ns / 1ps
`default_nettype none

module traffic_generator
    (
        input wire           clk_dram_ctrl,
        input wire           rst_dram_ctrl,

        output logic         sample_load_complete,

        // UberDDR3 control signals
        output logic [23:0]  memrequest_addr,
        output logic         memrequest_en,
        output logic [127:0] memrequest_write_data,
        output logic         memrequest_write_enable,
        input wire   [127:0] memrequest_resp_data,
        input wire           memrequest_complete,
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
        output logic [16+24+128-1:0] read_data_audio_axis_data,

        // Video read data AXIS FIFO output
        output logic         read_data_video_axis_valid,
        input wire           read_data_video_axis_ready,
        output logic [127:0] read_data_video_axis_data,
        output logic         read_data_video_axis_tlast,
        input wire           read_data_video_axis_af
    );

    localparam FRAME_BUFFER_DEPTH = 115200;

    // RST: Do not interface with DRAM
    // WR_AUDIO: Write audio data from write FIFO to DRAM
    //  (but hold this state until all audio samples are written)
    // WR_VIDEO: Write video data from write FIFO to DRAM
    // RD_AUDIO: Give DRAM read request using address in read_addr FIFO
    // RD_VIDEO: Give DRAM read request using an address counter
    enum {RST, WR_AUDIO, WR_VIDEO, RD_AUDIO, RD_VIDEO} state;

    assign write_axis_ready =
        !memrequest_busy && 
        ((state == WR_AUDIO) || (state == WR_VIDEO));
    
    // read_addr FIFO is only for audio
    assign read_addr_axis_ready = !memrequest_busy && (state == RD_AUDIO);

    // Audio read requests come through AXI FIFO
    // Create valid and ready signals for video read requests
    logic video_read_request_valid;
    assign video_read_request_valid = !read_data_video_axis_af && (state == RD_VIDEO);
    logic video_read_request_ready;
    assign video_read_request_ready = !memrequest_busy && (state == RD_VIDEO);

    // write_addr_last+1 is video addr offset
    logic [23:0] write_addr_last;
    logic        write_addr_last_valid;   

    // On startup, count up as audio samples are written to memory
    // After startup, use as counter for pixel addressing
    logic [23:0] write_address;
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            write_address <= 0;
        end else begin
            if (write_axis_valid & write_axis_ready) begin
                if (!write_addr_last_valid) begin
                    // We are loading audio samples
                    write_address <= write_address + 1;
                end else begin
                    if (write_axis_tlast || write_address == write_addr_last + FRAME_BUFFER_DEPTH) begin
                        // End of video frame
                        write_address <= write_addr_last + 1;
                    end else begin
                        write_address <= write_address + 1;
                    end
                end
            end
        end
    end

    logic [23:0] video_read_request_address;
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            video_read_request_address <= 0;
        end else begin
            if (write_addr_last_valid && video_read_request_address < write_addr_last + 1) begin
                // We can now set up at video addr offset
                video_read_request_address <= write_addr_last + 1;
            end else if (video_read_request_valid && video_read_request_ready) begin
                if (video_read_request_address == write_addr_last + FRAME_BUFFER_DEPTH) begin
                    video_read_request_address <= write_addr_last + 1;
                end else begin
                    video_read_request_address <= video_read_request_address + 1;
                end
            end
        end
    end


    logic [13:0] memrequest_sample_period;

    logic [23:0] response_addr;
    logic [13:0] response_sample_period;
    logic        response_wr_enable;
    
    command_fifo #(
        .DEPTH(64),
        .WIDTH(39)
    ) mcf (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .write(memrequest_en),
        .command_in(
            {
                memrequest_addr,
                memrequest_write_enable,
                memrequest_sample_period
            }
        ),
        .full(),
        
        .command_out(
            {
                response_addr,
                response_wr_enable,
                response_sample_period
            }
        ),
        .read(memrequest_complete),
        .empty()
    );


    logic response_is_video;
    assign response_is_video =
        (response_addr >= write_addr_last + 1) &&
        (response_addr <= write_addr_last + FRAME_BUFFER_DEPTH);

    // Set data/valid signals for read data FIFOs
    assign read_data_audio_axis_data = {
        2'b0,
        response_sample_period,
        response_addr,
        memrequest_resp_data
    };
    assign read_data_video_axis_data = memrequest_resp_data;
    assign read_data_audio_axis_valid =
        !response_wr_enable && memrequest_complete && !response_is_video;
    assign read_data_video_axis_valid =
        !response_wr_enable && memrequest_complete && response_is_video;

    assign read_data_video_axis_tlast =
        (response_addr == write_addr_last + FRAME_BUFFER_DEPTH);

    // Determine when memory is filled with audio samples
    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            sample_load_complete <= 0;
            write_addr_last <= 0;
            write_addr_last_valid <= 0;
        end else begin
            if (!sample_load_complete) begin
                if (!write_addr_last_valid) begin
                    if (write_axis_tlast) begin
                        write_addr_last <= write_address;
                        write_addr_last_valid <= 1;
                    end
                end else begin
                    if (response_addr == write_addr_last) begin
                        sample_load_complete <= 1;
                    end
                end
            end
        end
    end

    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl) begin
            state <= RST;
        end else begin
            if (sample_load_complete) begin
                // Just cycle between states.
                // 
                // dram_writer can send 1 chunk every 8 74.25 MHz cycles.
                // traffic_generator accesses write FIFO every 3 83.333 MHz
                //  cycles.
                // Therefore, the write FIFO should not overflow.
                // 
                // dram_read_requester sends 1 address even less frequently
                //  (audio sample rate)
                case (state)
                    RD_AUDIO: begin
                        state <= WR_VIDEO;
                    end
                    WR_VIDEO: begin
                        state <= RD_VIDEO;
                    end
                    RD_VIDEO: begin
                        state <= RD_AUDIO;
                    end
                    default: begin
                        state <= RD_AUDIO;
                    end
                endcase
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
            WR_AUDIO, WR_VIDEO: begin
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
            RD_VIDEO: begin
                memrequest_addr = video_read_request_address;
                memrequest_sample_period = 14'b0;
                memrequest_en = video_read_request_valid && !memrequest_busy;
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
        endcase // case (state)
    end // always_comb
endmodule

`default_nettype wire
