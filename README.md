# FSR_drummer

The general idea is a four-instrument drum sequencer. Each row of the grid represents a shift register. Bits shift from left to right; when a high bit reaches the rightmost column, a trigger for the corresponding instrument is sent out via MIDI and/or the crow. Bits can be toggled on/off by pressing grid buttons. Also, feedback taps can be set on the grid, shown as less-bright illuminated switches. The input to the shift registers (shown at the leftmost column) is the XOR of the bit state(s) at the feedback taps.

The gesture for setting/clearing feedback taps is TBD. Possibly holding one of the norns buttons while pressing the grid buttons?
