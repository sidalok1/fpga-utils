/*
Synchronously detects clock edge and outputs enable signal for one cycle.

Note that this module expects i_sig to be in the same clock domain as the one
given by i_clk, and if this is not the case, the debouncer module (with the 
default 1 sample) can be used to cross clock domains.
*/

module edgedetect #(
    parameter DETECT_NEGEDGE = 0 // Detect negedge if true (defaults to false) 
) (
    input wire clk,
    input wire rst,
    input wire sig,
    output wire en
);

    reg curr_sig = 0, past_sig = 0;

    assign en = DETECT_NEGEDGE ?
        (past_sig == 1) && (curr_sig == 0)
            :
        (past_sig == 0) && (curr_sig == 1);

    always @ ( posedge clk ) begin
        if ( rst ) begin
            curr_sig <= 0;
            past_sig <= 0;
        end else begin
            curr_sig <= sig;
            past_sig <= curr_sig;
        end
    end

endmodule