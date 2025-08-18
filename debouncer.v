/*
Signal debouncing module with synchronous reset

This module has one parameter, how many samples of the input clock to use.
The default is 1 samples, which makes module function as "double-flopping".

The use of this module implies that i_in is entering the module from a seperate
clock domain than the one given by i_clk. Hence, the first flop, which directly
samples the input, has a metastable output. To ensure stability, this flop is
not considered part of the samples. The important thing to note is that the
true delay from this module will always be n + 1.

Also note that with n == 1, this module essentially implements
double-flopping and can be used for clock domain crossing.
*/

module debouncer #(
    parameter       N = 1 // # of samples
) (
    input wire      i_clk,
    input wire      i_rst, // synchronous reset
    input wire      i_in,
    output wire     o_out
);
    // As explained above, an extra flop is used (s[0]) to ensure stability
    reg signed [N:0] s = 0;
    assign o_out = &s[N:1];

    integer i;

    always @( posedge i_clk ) begin
        if ( i_rst ) begin
            s <= 0;
        end else begin
            for ( i = 1; i <= N; i = i + 1 ) begin
                s[i] <= s[i-1];
            end
            s[0] <= i_in; // metastable
        end
    end

endmodule