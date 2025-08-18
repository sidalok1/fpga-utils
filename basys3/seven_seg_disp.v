/*
Module for basys 3 seven segment display

This module depends on the clockdiv module, so be sure to include it in design,
and set I_CLK_FRQ accordingly

The REFRESH parameter for this module is refresh rate, and generally is can 
stay at the default value of 60Hz

The DIGITS parameter is how many segments should be used, and should be either
1, 2, 3, or 4.
*/

module seven_seg_disp #(
    parameter           I_CLK_FRQ = 100_000_000,
    parameter           REFRESH = 60,
    parameter           DIGITS = 4
) (
    input               i_clk, 
    input               i_rst,
    input signed [10:0] i_data,
    input               i_en, 
    output  reg [3:0]   o_anodes,
    output wire [6:0]   o_segment
);
    
    reg                 sign;
    reg         [10:0]  num;
    reg         [1:0]   anode;
    reg         [3:0]   currentNum;
    
    reg         [10:0]  mod10, mod100, mod1000, pipe_num;
    reg         [3:0]   ones, tens, hundreds, thousands;
    
    localparam  [3:0]   an_en = {~(DIGITS == 4), ~(DIGITS >= 3), ~(DIGITS >= 2), ~(DIGITS >= 1)};

    wire                display_clk;

    clockdiv #(
        .I_CLK_FRQ(I_CLK_FRQ),
        .FREQUENCY(REFRESH*4)
    ) disp_clk_div (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .o_clk(display_clk)
    );
    
    DecimalDecoder decode (currentNum, o_segment);
    
    initial begin
        anode = 2'b00;
        num = 16'b0;
        sign = 0;
    end

    always @ ( posedge i_clk ) begin
        if ( i_rst ) begin
            anode <= 0;
            num <= 0;
            sign <= 0;
        end else if ( display_clk ) begin 
            // Cycle through anodes
            anode <= anode + 1;

            // If i_en is asserted, display i_data
            if ( i_en ) begin 
                if (i_data >= 0) begin
                    num <= i_data;
                    sign <= 0;
                end
                else begin
                    num <= ~i_data + 1;
                    sign <= 1;
                end
            end

            case ( anode )
                2'b00: begin
                    o_anodes <= {3'b111, an_en[0]};
                    currentNum <= ones;
                end
                2'b01: begin
                    o_anodes <= {2'b11, an_en[1], 1'b1};
                    currentNum <= (DIGITS == 1 && sign) ? 4'hf : tens;
                end
                2'b10: begin
                    o_anodes <= {1'b1, an_en[2], 2'b11};
                    currentNum <= (DIGITS == 2 && sign) ? 4'hf : hundreds;
                end
                2'b11: begin
                    o_anodes <= {an_en[3], 3'b111};
                    currentNum <= sign ? 4'hf : thousands;
                end
            endcase
        end else begin
            mod10 <= num % 10;
            mod100 <= num % 100;
            mod1000 <= num % 1000;
            pipe_num <= num;
            
            ones <= mod10;
            tens <= mod100 / 10;
            hundreds <= mod1000 / 100;
            thousands <= pipe_num / 1000;
        end
    end
    
endmodule

module DecimalDecoder(bin, cathodes);
    input       [3:0]   bin;
    
    output  reg [6:0]   cathodes;
    
    always @* begin
        case ( bin )
            4'd1:       cathodes = 7'b1111001;
            4'd2:       cathodes = 7'b0100100;
            4'd3:       cathodes = 7'b0110000;
            4'd4:       cathodes = 7'b0011001;
            4'd5:       cathodes = 7'b0010010;
            4'd6:       cathodes = 7'b0000010;
            4'd7:       cathodes = 7'b1111000;
            4'd8:       cathodes = 7'b0000000;
            4'd9:       cathodes = 7'b0011000;
            4'hf:       cathodes = 7'b0111111; // negative sign
            default:    cathodes = 7'b1000000;
        endcase
    end
endmodule 