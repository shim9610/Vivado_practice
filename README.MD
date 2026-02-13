# Verilog Practice

A collection of Verilog modules and testbenches I wrote while learning FPGA development.

These are practice examples — not production-ready IP cores. I built them to understand how digital logic works at the hardware level, from basic building blocks to more practical modules.

## Modules

### Distributed FIFO (`distributed_fifo`)

A simple ring-buffer FIFO using distributed (LUT) RAM with AXI-Stream-style valid/ready handshake.

- Parameterizable data width and buffer depth
- Synthesizes to distributed RAM (LUT RAM) via `(* ram_style = "distributed" *)` attribute
- Backpressure support on both input and output ports
- Includes a comprehensive testbench (`distributed_fifo_tb`) covering:
  - Sequential transfers with/without backpressure
  - Edge values and walking-one patterns
  - Buffer-full stress test
  - Mid-transfer reset recovery

## Environment

- **Tool**: Xilinx Vivado (xvlog / xelab / xsim)
- **Language**: Verilog (IEEE 1364-2005)

## Usage

```bash
# Run simulation
./run.sh

# Clean build artifacts
./run.sh clean
```

## License

MIT