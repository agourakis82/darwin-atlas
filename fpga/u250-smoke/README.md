# U250 hardware smoke test

This directory contains the smallest hardware path used to verify the Darwin
Atlas build and deployment chain. It is an engineering smoke test, not a
scientific kernel and not evidence for biological equivalence or speedup.

The target is the installed Alveo U250 shell
`xilinx_u250_gen3x16_xdma_4_1_202210_1`. `build.sh` fails closed when that
exact development platform is unavailable. It compiles a three-buffer integer
vector-add kernel with `v++ -t hw`, links a hardware `.xclbin`, and records
source and artifact SHA-256 values.

The Kubernetes pod requests the extended resource `sounio.dev/u250`. Its
Debian trixie userspace matches the ABI of XRT 2.23 installed on the Debian 13
runtime node. It is not privileged, drops all Linux capabilities, mounts the
node's XRT userspace tree and architecture-specific runtime libraries
read-only, and does not invoke management or flash programming commands.

The intended verification sequence is:

1. Run `./build.sh` on the isolated Vitis builder VM.
2. In the runtime pod, install `g++` and `uuid-dev`, then run
   `./compile-host.sh` against the node's read-only XRT headers and libraries.
3. Apply `kubernetes/smoke-pod.yaml`, copy in the host binary and `.xclbin`, and
   execute `./run-hardware.sh <host> <xclbin>`.
4. Require the exact marker `U250_VECTOR_ADD_PASS elements=4096` and retain the
   Kubernetes pod log plus artifact hashes in a receipt.

Loading the `.xclbin` changes only the reconfigurable user partition through
XRT. This workflow must not flash or replace the persistent shell.

## Verified hardware run

Run `u250-smoke-659ab549-20260803T022116Z` completed on the U250 exposed by the
`dl380-proxmox` Kubernetes node. XRT 2.23.0 reported BDF `0000:d8:00.1`, shell
`xilinx_u250_gen3x16_xdma_shell_4_1`, and `Device Ready=Yes`. The hardware host
validated all 4,096 output elements and emitted both required markers with exit
code 0. The built `.xclbin` SHA-256 is
`005145f4bf863237cab06398222910440e99bfee89d070d4862c3ba45d8ce3e0`.

The immutable evidence and machine-readable receipt are under
`receipts/u250-smoke-659ab549-20260803T022116Z/`. The Vivado implementation log
records 0 errors and 2 critical warnings inherited from the legacy shell DFX
flow; their exact text and the subsequent hardware result are retained. This
PASS closes only the engineering build/load/execute path. It does not establish
biological equivalence, scientific validity, or a performance speedup.
