/*
Counter module

Once i_start is asserted, the module saves i_cycles as the counter target. Only
once i_start is deasserted will the module begin counting. If the module 
finishes counting, then o_done will go high until i_start is asserted again. On
reset, the cycles register is cleared and o_done held high until i_start is
asserted once again.

The CWIDTH parameter specifies the width of the cycles port and register, and
defaults to 32 bits
*/

module counter #(
    parameter CWIDTH = 32
) (
    input               i_clk,
    input               i_rst,      // synchronous reset
    input               i_start,
    input [CWIDTH-1:0]  i_cycles,
    output reg          o_done
);

    reg [CWIDTH-1:0] cycles, count;

    initial begin
        o_done = 0;
        cycles = 0;
        count = 0;
    end

    always @ ( posedge i_clk ) begin
        o_done <= 0;
        if ( i_rst ) begin
            count <= 0;
            cycles <= 0;
        end else if ( i_start ) begin
            cycles <= i_cycles;
            count <= 0;
        end else if ( count == cycles - 1 ) begin
            count <= count + 1;
            o_done <= 1;
        end else if ( count < cycles - 1 ) begin
            count <= count + 1;
        end
    end

endmodule