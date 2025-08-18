/*
Module for sending an signed number over uart

This module depends on the lower level uarttx module. As with the uasttx module
parameters for configuring the serial communication include baud rate, parity,
and stop bits, but the frame size is fixed at 8-bits (ascii chars).

Additionally there is the I_CLK_FRQ parameter which should get the input clock
frequency, the RADIX parameter, which can take values 2, 10 or 16, the SIZE
parameter, which sets the i_data width, and the DIGITS parameter, which is the
number of digits to pad to (or no padding if DIGITS == 0). Maximum digits is 63
for positive numbers and 62 for negative numbers
*/

module txnum #(
    parameter               I_CLK_FRQ = 100_000_000,
    parameter [20:0]        BAUD = 9600,
    parameter [0:0]         PARITY = 0,
    parameter [1:0]         STOP = 1,
    parameter [4:0]         RADIX = 10,
    parameter               SIZE = 8,
    parameter [4:0]         DIGITS = 0
) (
    input                   i_clk,
    input                   i_rst,
    input                   i_en,
    input signed [SIZE-1:0] i_data,
    output wire             o_tx,
    output wire             o_busy
);

    localparam IDLE = 'b001;
    localparam CALC = 'b010;
    localparam SEND = 'b100;

    reg [2:0] state;

    assign o_busy = state != IDLE;

    reg signed [SIZE-1:0] data;
    reg f_negative;
    reg [4:0] idx, padding;
    reg uart_en;
    wire uart_busy, uart_ready;
    assign uart_ready = ~uart_busy;
    reg [7:0] char [0:63];
    reg [7:0] current_char;

    integer i;

    uarttx #(
        .I_CLK_FRQ(I_CLK_FRQ),
        .BAUD(BAUD),
        .PARITY(PARITY),
        .FRAME(8),
        .STOP(STOP)
    ) uart_tx_driver (
        .i_clk(i_clk),
        .i_en(uart_en),
        .i_data(current_char),
        .o_tx(o_tx),
        .o_busy(uart_busy)
    );

    always @ ( posedge i_clk ) begin
        uart_en <= 0;
        if ( i_rst ) begin
            state <= IDLE;
            data <= 0;
            for ( i = 0; i < 64; i = i + 1 ) begin
                char[i] = "0";
            end
            char[DIGITS] = "\n";
            idx <= 0;
            current_char <= 0;
            padding <= 0;
            f_negative <= 0;
        end else
        case ( state )
            IDLE: begin
                if ( i_en ) begin
                    data <= i_data < 0 ? i_data * -1 : i_data;
                    f_negative <= i_data < 0;
                    idx <= 0;
                    state <= CALC;
                end
            end
            CALC: begin
                if ( data > 0 ) begin
                    if ( !( RADIX == 2 || RADIX == 10 || RADIX == 16 ) )
                        char[idx] <= "?";
                    else case ( data % RADIX )
                        0:      char[idx] <= "0";
                        1:      char[idx] <= "1";
                        2:      char[idx] <= "2";
                        3:      char[idx] <= "3";
                        4:      char[idx] <= "4";
                        5:      char[idx] <= "5";
                        6:      char[idx] <= "6";
                        7:      char[idx] <= "7";
                        8:      char[idx] <= "8";
                        9:      char[idx] <= "9";
                        10:     char[idx] <= "A";
                        11:     char[idx] <= "B";
                        12:     char[idx] <= "C";
                        13:     char[idx] <= "D";
                        14:     char[idx] <= "E";
                        15:     char[idx] <= "F";
                        default:char[idx] <= "?";
                    endcase
                    idx <= idx + 1;
                    data <= data / RADIX;
                end else if ( idx < DIGITS ) begin
                    padding <= DIGITS - idx;
                end else begin
                    char[idx] = "\n";
                    idx <= 0;
                    current_char <= f_negative ? "-" : " ";
                    uart_en <= 1;
                    state <= SEND;
                end
            end
            SEND: begin
                if ( uart_ready && !uart_en ) begin
                    uart_en <= 1;
                    if ( padding > 0 ) begin
                        current_char <= "0";
                        padding <= padding - 1;
                    end else begin
                        current_char <= char[idx];
                        if ( char[idx] == "\n" ) begin
                            state <= IDLE;
                        end else begin
                            idx <= idx + 1;
                        end
                    end
                end
            end
        endcase
    end

    initial begin
        state <= IDLE;
        data <= 0;
        idx <= 0;
        uart_en <= 0;
        for ( i = 0; i < 64; i = i + 1 ) begin
            char[i] = "0";
        end
        char[DIGITS] = "\n";
        current_char <= 0;
    end
endmodule

