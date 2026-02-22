// ============================================================================
// Module: sr512_core
// Author: JUHO ARTTURI HEMMINKI
// Year: 2026
// License: Apache 2.0
// Description: Deterministic State Recovery (SR-512) for PCIe Gen6/7.
//              Single-cycle state recovery with Majority Vote delta tracking.
// ============================================================================

module sr512_core #(
    parameter [511:0] KA_ANCHOR = 512'hACE_B00_... // Define your 512-bit Anchor here
)(
    input  logic         clk,
    input  logic         rst_n,      // Active low reset
    input  logic [511:0] m_in,       // 512-bit Measurement Input
    output logic [511:0] s_rec       // 512-bit Recovered State output
);

    // Internal signals
    logic [8:0] delta_reg;           // 9-bit delta state tracking
    logic [8:0] delta_next;          // Calculated next delta

    // --- 1. Delta Update Logic (Majority Vote) ---
    // Extract 9-bit LSBs from prime-shifted positions
    wire [8:0] v1 = m_in[8:0];                   // floor(M_in)_9
    wire [8:0] v2 = (m_in >> 157);               // floor(M_in >> 157)_9
    wire [8:0] v3 = (m_in >> 311);               // floor(M_in >> 311)_9

    // Hardware-level 2-out-of-3 Majority Vote (MV) for noise immunity
    // Formula: (v1 & v2) | (v2 & v3) | (v3 & v1)
    assign delta_next = (v1 & v2) | (v2 & v3) | (v3 & v1);

    // --- 2. State Recovery Logic (Right-Rotate & XOR) ---
    // Right cyclic shift (ROR) using delta_reg
    // SV Syntax: {m_in, m_in} >> delta_reg extracts the rotated 512 bits
    logic [511:0] rotated_data;
    assign rotated_data = (m_in >> delta_reg) | (m_in << (512 - delta_reg));

    // XOR with Kalman Anchor (Ka)
    assign s_rec = rotated_data ^ KA_ANCHOR;

    // --- 3. Sequential Logic (Clocked Process) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delta_reg <= 9'h000;     // Reset to Initial Vector (IV)
        end else begin
            delta_reg <= delta_next; // Update delta for the next cycle
        end
    end

endmodule
