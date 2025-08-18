/*
Module to interface with a ps2 mouse

After mouse initialization process is done (~10 ms), o_new_event will go high
for one i_clk after new data from the mouse is recieved. Currently this module
does not support Intellimouse extensions, but may do so in the future.

Depends on the ps2 driver module, as well as counter module to set timeout
conditions and timing requirements. Make sure the I_CLK_FRQ parameter is set
to the system (or input) clock frequency.
*/

module mousedriver #(
    parameter I_CLK_FRQ = 100_000_000
) (
    inout                       ps2clk, ps2data,
    input                       i_clk,
    input                       i_rst,
    output reg signed [8:0]     o_x, o_y,
    output reg                  o_x_ovfw, o_y_ovfw,
    output reg                  o_left_btn, o_right_btn, o_middle_btn,
    output reg                  o_new_event
);

    // Commands to and from mouse
    localparam host_RESET               = 8'hFF;
    localparam host_ENABLE_REPORTING    = 8'hF4;
    localparam mouse_ACKNOWLEDGE        = 8'hFA;
    localparam mouse_BAT_PASSED         = 8'hAA;

    // Initialization flags
    reg f_BAT, f_mouse_id_received;

    // Byte position flags
    reg f_byte1, f_byte2;

    // FSM states
    localparam RESET            = 1;
    localparam INIT             = 2;
    localparam ACKNOWLEDGE      = 3;
    localparam IDLE             = 4;
    reg [3:0] state, next;

    // Host-to-device data
    reg [7:0] txdata;
    reg tx_en;

    // Device-to-host data
    wire [7:0] rxdata;
    wire ps2_ready;
    wire ps2_error;

    // PS2 driver module. Handles the low level interfacing with the PS2 bus
    ps2driver ps2_interface (
        .ps2clk(ps2clk), .ps2data(ps2data),
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data(txdata),
        .i_we(tx_en),
        .o_data(rxdata),
        .o_ready(ps2_ready),
        .o_error(ps2_error)
    );

    // Counter to ensure 20 ms response times
    localparam integer c_20ms = I_CLK_FRQ * 0.020;
    localparam cwidth = $clog2(c_20ms);
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

    always @ ( posedge i_clk ) begin
        tx_en <= 0;
        counter_request <= 0;
        o_new_event <= 0;
        if ( i_rst | ps2_error ) begin
            // If low level PS2 module receives an error this module will reset
            state <= RESET;
            next <= RESET;
            f_BAT <= 0;
            f_mouse_id_received <= 0;
            f_byte1 <= 0;
            f_byte2 <= 0;
            txdata <= 0;
            counter_cycles <= 0;
            o_x <= 0;
            o_x_ovfw <= 0;
            o_y <= 0;
            o_y_ovfw <= 0;
            o_left_btn <= 0;
            o_right_btn <= 0;
            o_middle_btn <= 0;
        end else begin
            case ( state )
            RESET: begin
                // Reset the flags
                f_BAT <= 0;
                f_mouse_id_received <= 0;
                f_byte1 <= 0;
                f_byte2 <= 0;
                // Send mouse the reset command
                txdata <= host_RESET;
                tx_en <= 1;
                // Await an acknowledgement
                counter_cycles <= c_20ms;
                counter_request <= 1;
                state <= ACKNOWLEDGE;
                // And proceed to initialization
                next <= INIT;
            end
            ACKNOWLEDGE: begin
                // Before entering this state, the previous state should ensure
                //the timer has been started and that the following state on
                //success is specified. Any errors will reset module.
                if ( counter_finished ) begin
                    state <= RESET;
                end else if ( ps2_ready ) begin
                    if ( rxdata == mouse_ACKNOWLEDGE ) begin
                        state <= next;
                    end else begin
                        state <= RESET;
                    end
                end
            end
            INIT: begin
                //Initialization process
                if ( !f_BAT ) begin
                    // Await mouse BAT passed
                    if ( ps2_ready ) begin
                        if ( rxdata == mouse_BAT_PASSED ) begin
                            f_BAT <= 1;
                        end else begin
                            state <= RESET;
                        end
                    end
                end else if ( !f_mouse_id_received ) begin
                    // Await mouse ID
                    if ( ps2_ready ) begin
                        if ( rxdata == 8'h00 ) begin
                            f_mouse_id_received <= 1;
                        end else begin
                            // PS2 device is not a mouse
                            state <= RESET;
                        end
                    end else begin
                        // Enable reporting
                        txdata <= host_ENABLE_REPORTING;
                        tx_en <= 1;
                        // Await acknowledgement
                        counter_cycles <= c_20ms;
                        counter_request <= 1;
                        state <= ACKNOWLEDGE;
                        // Enter idle state
                        next <= IDLE;
                    end
                end
            end
            IDLE: begin
                // The idle state waits for mouse to start sending data
                if ( !f_byte1 ) begin
                    // Await first byte
                    if ( ps2_ready ) begin
                        o_y_ovfw <= rxdata[7];
                        o_x_ovfw <= rxdata[6];
                        o_y[8] <= rxdata[5];
                        o_x[8] <= rxdata[4];
                        o_middle_btn <= rxdata[2];
                        o_right_btn <= rxdata[1];
                        o_left_btn <= rxdata[0];
                        f_byte1 <= 1;
                    end
                end else if ( !f_byte2 ) begin
                    // Await second byte
                    if ( ps2_ready ) begin
                        o_x[7:0] <= rxdata;
                        f_byte2 <= 1;
                    end
                end else begin
                    // Await third byte
                    if ( ps2_ready ) begin
                        o_y[7:0] <= rxdata;
                        f_byte1 <= 0;
                        f_byte2 <= 0;
                        o_new_event <= 1;
                    end
                end
            end
            default: state <= RESET;
            endcase
        end
    end    

    initial begin
        state <= RESET;
        next <= 0;
        f_BAT <= 0;
        f_mouse_id_received <= 0;
        txdata <= 0;
        tx_en <= 0;
        counter_cycles <= 0;
        counter_request <= 0;

        o_x <= 0;
        o_x_ovfw <= 0;
        o_y <= 0;
        o_y_ovfw <= 0;
        o_left_btn <= 0;
        o_right_btn <= 0;
        o_middle_btn <= 0;
    end

endmodule