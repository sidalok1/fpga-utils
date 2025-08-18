/*
Module to interface directly with ps2 data and clock wires as host

This module depends on the edgedetect module for detecting the ps2 clock's
positive and negative edges, and the counter module for meeting various timing
requirements, such as holding the clock low for at least 100 microseconds in
order to request to send.

Note that the counter module counts clock cycles, so in order to count time,
the SYS_CLK_FRQ parameter must have the correct system clock frequency
*/

module ps2driver #(
    parameter I_CLK_FRQ = 100_000_000 // Input clock frequency in Hz
) (
    inout               ps2clk, ps2data,
    input               i_clk,
    input               i_rst,
    input       [7:0]   i_data,
    input               i_we,
    output reg  [7:0]   o_data,
    output reg          o_ready,
    output reg          o_error
);

    // Basic operation of ps2 driver is controlled via fsm
    // The following macros define the states
    localparam IDLE =               'b0000_00_1;
    localparam BEGIN_READ =         'b0000_01_0;
    localparam PROCESS_FRAME =      'b0000_10_0;
    localparam BEGIN_WRITE =        'b0001_00_0;
    localparam AWAIT_DEVICE_READ =  'b0010_00_0;
    localparam BEGIN_TRANSMIT =     'b0100_00_0;
    localparam AWAIT_DEVICE_ACK =   'b1000_00_0;
    reg [6:0] state;

    // Data frames for serial transmission (parity is odd)
    reg [10:0] rx_frame, tx_frame; // "1", parity, 8bit data, "0"  

    // double-flopping for clock and data lines
    wire ps2clk_stable, ps2data_stable;
    debouncer   clk_double_flop  ( i_clk, i_rst, ps2clk, ps2clk_stable ),
                data_double_flop ( i_clk, i_rst, ps2data, ps2data_stable );
    
    // These wires are high for one clock cycle after negedge or posedge
    wire negedge_ps2clk, posedge_ps2clk;
    edgedetect #(1) ps2clk_negedge (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_sig(ps2clk_stable),
        .o_en(negedge_ps2clk)
    );
    edgedetect #(0) ps2clk_posedge (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_sig(ps2clk_stable),
        .o_en(posedge_ps2clk)
    );

    // Used to keep track of bit index during reading or writing
    reg [3:0] bit_idx;

    // ps2clk and ps2data are outputs when pull_clk and pull_data are high
    reg pull_clk, pull_data;

    assign ps2clk = pull_clk == 1 ? 'b0 : 'bz;
    assign ps2data = pull_data == 1 ? tx_frame[bit_idx] : 'bz;

    

    // Counter to meet various timing requirements
    localparam integer c_100us =    I_CLK_FRQ * 0.000_100;
    localparam integer c_20ms =     I_CLK_FRQ * 0.020;
    localparam integer c_15ms =     I_CLK_FRQ * 0.015;
    localparam integer c_2ms =      I_CLK_FRQ * 0.002;
    localparam integer cwidth = $clog2(c_20ms);
    reg [cwidth-1:0] counter_cycles;
    reg counter_request;
    wire counter_finished;
    counter #(cwidth) timer (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(counter_request),
        .i_cycles(counter_cycles),
        .o_done(counter_finished)
    );
    

    // Main logic, as a FSM
    always @ ( posedge i_clk ) begin
        pull_clk <= 0;
        pull_data <= 0;
        counter_request <= 0;
        o_ready <= 0;
        o_error <= 0;
        if ( i_rst ) begin
            state <= IDLE;
            bit_idx <= 0;
            counter_cycles <= 0;
            o_data <= 0;
            rx_frame <= 0;
            tx_frame <= 0;
        end else begin
            case ( state )
            IDLE: begin
                if ( i_we ) begin
                    // Begin host-to-device communication
                    state <= BEGIN_WRITE;
                    tx_frame <= {1'b1, ~^i_data, i_data, 1'b0};
                    // Pull clock low for 100 microseconds
                    counter_cycles <= c_100us;
                    counter_request <= 1;
                    pull_clk <= 1;
                    // "0" start bit
                    pull_data <= 1;
                    bit_idx <= 0;
                end else if ( negedge_ps2clk ) begin
                    // Device-to-host communication begin
                    state <= BEGIN_READ;
                    // First bit ("0" start bit) received
                    rx_frame[0] <= ps2data_stable;
                    bit_idx <= 1;
                    // If entire frame exceeds 2 ms, there must have been a
                    //clock period greater than the 100 us maximum
                    counter_cycles <= c_2ms;
                    counter_request <= 1;
                end
            end
            BEGIN_READ: begin
                if ( counter_finished ) begin
                    // Device took longer than 2ms to send packet
                    state <= IDLE;
                    o_error <= 1;
                end else if ( negedge_ps2clk ) begin
                    rx_frame[bit_idx] <= ps2data_stable;
                    if ( bit_idx == 10 ) begin
                        // Entire frame recieved, but start/stop/parity bit
                        //need to be checked
                        state <= PROCESS_FRAME;
                    end else begin
                        bit_idx <= bit_idx + 1;
                    end
                end
            end
            PROCESS_FRAME: begin
                // This state should take only one clock cycle
                state <= IDLE;
                if (
                    rx_frame[0] == 0 &&
                    rx_frame[10] == 1 &&
                    rx_frame[9] == ~^rx_frame[8:1]
                ) begin 
                    o_data <= rx_frame[8:1];
                    o_ready <= 1;
                end else begin
                    // Malformed frame received
                    o_error <= 1;
                end
            end
            BEGIN_WRITE: begin
                // Host writes begin with pulling clock line low for 100 us
                pull_clk <= 1;
                pull_data <= 1;
                if ( counter_finished ) begin
                    // It should take device no longer than 15 ms to begin clk
                    counter_cycles <= c_15ms;
                    counter_request <= 1;
                    state <= AWAIT_DEVICE_READ;
                end
            end 
            AWAIT_DEVICE_READ: begin
                pull_data <= 1;
                if ( counter_finished ) begin
                    // Device took longer than 15 ms to begin clock
                    state <= IDLE;
                    o_error <= 1;
                end 
                if ( negedge_ps2clk ) begin
                    state <= BEGIN_TRANSMIT;
                    counter_cycles <= c_2ms;
                    counter_request <= 1;
                end
            end
            BEGIN_TRANSMIT: begin
                pull_data <= 1;
                if ( counter_finished ) begin
                    // Device took longer than 2ms to receive frame
                    state <= IDLE;
                    o_error <= 1;
                end else if ( posedge_ps2clk ) begin
                    if ( bit_idx == 10 ) begin
                        state <= AWAIT_DEVICE_ACK;
                        counter_cycles <= c_20ms;
                        counter_request <= 1;
                    end else begin
                        bit_idx <= bit_idx + 1;
                    end
                end
            end
            AWAIT_DEVICE_ACK: begin
                if ( counter_finished ) begin
                    // Device took longer than 20ms to respond
                    state <= IDLE;
                    o_error <= 1;
                end else if ( ps2data_stable == 0 && ps2clk_stable == 0 ) begin
                    state <= IDLE;
                end
            end
            default: state <= IDLE;
            endcase
        end

    end

    initial begin
        state <= IDLE;
        rx_frame <= 0;
        tx_frame <= 0;
        bit_idx <= 0;
        pull_clk <= 0;
        pull_data <= 0;
        counter_cycles <= 0;
        counter_request <= 0;
        o_data <= 0;
        o_ready <= 0;
        o_error <= 0;
    end

endmodule
