/*
Synchronously detects clock edge and outputs enable signal for one cycle.

Note that this module expects i_sig to be in the same clock domain as the one
given by i_clk, and if this is not the case, the debouncer module (with the 
default 1 sample) can be used to cross clock domains.
*/

module edgedetect #(
    parameter D_NEGEDGE = 0 // Detect negedge if true (defaults to false) 
) (
    input   i_clk,
    input   i_rst, // synchronous reset
    input   i_sig,
    output  o_en
);

    reg curr_sig, past_sig;

    assign o_en = D_NEGEDGE ?
        (past_sig == 1) && (curr_sig == 0)
            :
        (past_sig == 0) && (curr_sig == 1);

    always @ ( posedge i_clk ) begin
        if ( i_rst ) begin
            curr_sig <= i_sig;
            past_sig <= i_sig;
        end else begin
            curr_sig <= i_sig;
            past_sig <= curr_sig;
        end
    end

endmodule