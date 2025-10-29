`timescale 1ns / 1ps
`default_nettype none

module traffic_generator
    (
        input wire           clk_dram_ctrl,
        input wire           rst_dram_ctrl,

        output logic         sample_load_complete,
        output logic [23:0]  response_addr,

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
        input wire   [23:0]  read_addr_axis_data,
        input wire           read_addr_axis_tlast,
        input wire           read_addr_axis_valid,
        output logic         read_addr_axis_ready,

        // Read data AXIS FIFO output
        // tlast always low
        // data = {response_addr, memrequest_resp_data}
        output logic         read_data_axis_valid,
        input wire           read_data_axis_ready
    );

    enum {RST, WR_AUDIO, RD_AUDIO} state;

    assign write_axis_ready = !memrequest_busy && (state == WR_AUDIO);
    assign read_addr_axis_ready = !memrequest_busy && (state == RD_AUDIO);

    logic [23:0] write_address;

    always_ff @ (posedge clk_dram_ctrl) begin
        if (rst_dram_ctrl | (write_axis_valid & write_axis_ready & write_axis_tlast)) begin
            write_address <= 0;
        end else begin
            if (write_axis_valid & write_axis_ready) begin
                write_address <= write_address + 1;
            end
        end
    end

    logic response_wr_enable;

    command_fifo #(
        .DEPTH(64),
        .WIDTH(25)
    ) mcf (
        .clk(clk_dram_ctrl),
        .rst(rst_dram_ctrl),
        .write(memrequest_en),
        .command_in({memrequest_addr, memrequest_write_enable}),
        .full(),
        
        .command_out({response_addr, response_wr_enable}),
        .read(memrequest_complete),
        .empty()
    );

    assign read_data_axis_valid = ~response_wr_enable & memrequest_complete;

    logic [23:0] write_addr_last;
    logic        write_addr_last_valid;

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
                state <= RD_AUDIO;
            end else begin
                state <= WR_AUDIO;
            end
        end
    end

    always_comb begin
        case(state)
            RST: begin
                memrequest_addr = 0;
                memrequest_en = 0;
                memrequest_write_data = 0;
                memrequest_write_enable = 0;
            end
            WR_AUDIO: begin
                memrequest_addr = write_address;
                memrequest_en = write_axis_valid && !memrequest_busy;
                memrequest_write_enable = write_axis_valid && !memrequest_busy;
                memrequest_write_data = write_axis_data;
            end
            RD_AUDIO: begin
                memrequest_addr = read_addr_axis_data;
                memrequest_en = read_addr_axis_valid && !memrequest_busy;
                memrequest_write_enable = 0;
                memrequest_write_data = 0;
            end
            default: begin
                memrequest_addr = 0;
                memrequest_en = 0;
                memrequest_write_data = 0;
                memrequest_write_enable = 0;
            end
        endcase // case (state)
    end // always_comb
endmodule

`default_nettype wire
