/*
Module for sending bytes over uart

Parameters include I_CLK_FRQ, or the input clock frequency, BAUD, the desired
baud rate, PARITY, true if a parity bit is to be added, FRAME, the size of the
data frame, and STOP, the number of stop bits. If used, the PARITY bit will
be even parity (0 if even # of 1s)

The acceptable values of the parameters is as follows:

BAUD:
    9600
    19200
    38400
    57600
    115200
    230400
    460800
    921600
    1000000
    1500000

PARITY:
    0   (no parity)
    1   (even parity)

FRAME:
    5
    6
    7
    8
    9

STOP:
    1
    2

Acceptable parameter values are not strictly enforced, but this module may
perform incorrectly if the parameters are specified incorrectly.
*/


module uarttx #(
    parameter I_CLK_FRQ = 100_000_000,
    parameter [20:0] BAUD = 9600,
    parameter [0:0] PARITY = 0,
    parameter [3:0] FRAME = 8,
    parameter [1:0] STOP = 1

) (
    input wire i_clk,
    input wire i_en,
    input wire i_rst,
    input wire [FRAME-1:0] i_data,
    output reg o_tx,
    output wire o_busy
);
    localparam integer FRAMESIZE = FRAME - 1;
    localparam integer PACKETSIZE = FRAMESIZE + 1 + PARITY + STOP;
    
    wire baud_enable;

    clockdiv #(
        .I_CLK_FRQ(I_CLK_FRQ),
        .FREQUENCY(BAUD)
    ) baud_clock (
        .rst(i_rst),
        .en(1),
        .i_clk(i_clk),
        .o_clk(baud_enable)
    );

    reg [$clog2(PACKETSIZE)-1:0] bit_idx;
    reg [FRAMESIZE:0] frame;
    wire [PACKETSIZE:0] packet;
    wire parity = ^frame;
    wire [STOP-1:0] stop = {STOP{1'b1}};
    assign packet = PARITY ? {stop, parity, frame, 1'b0} : {stop, frame, 1'b0};

    
    localparam [1:0] IDLE = 'b01;
    localparam [1:0] SEND = 'b10;
    
    reg [1:0] state;
    
    assign o_busy = state != IDLE;
    
    initial begin
        bit_idx <= 0;
        frame <= 0;
        state = IDLE;
        o_tx = 1;
    end
    
    always @ ( posedge i_clk ) begin
        if ( i_rst ) begin
            state <= IDLE;
            frame <= 0;
            bit_idx <= 0;
            o_tx <= 1;
        end else begin
            case ( state )
            IDLE: begin
                o_tx <= 1;
                if ( i_en ) begin
                    state <= SEND;
                    frame <= i_data;
                    bit_idx <= 0;
                end
            end
            SEND: begin
                if ( baud_enable ) begin
                    if ( bit_idx == PACKETSIZE ) begin
                        state <= IDLE;
                    end
                    o_tx <= packet[bit_idx];
                    bit_idx <= bit_idx + 1;
                end else begin
                    o_tx <= o_tx;
                end
            end
            endcase
        end
    end
endmodule