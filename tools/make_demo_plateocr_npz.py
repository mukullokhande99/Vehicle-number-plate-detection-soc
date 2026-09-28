#!/usr/bin/env python3
"""Create a deterministic shape-correct FP32 checkpoint to test the exporter."""
from pathlib import Path
import argparse
import numpy as np

SHAPES = {
 "d0_conv": (24,1,3,3), "d1_dw": (24,1,3,3), "d1_pw": (40,24,1,1),
 "d2_dw": (40,1,3,3), "d2_pw": (64,40,1,1), "d3_dw": (64,1,3,3), "d3_pw": (96,64,1,1),
 "d4_dw": (96,1,3,3), "d4_pw": (96,96,1,1), "d5_dw": (96,1,3,3), "d5_pw": (96,96,1,1), "d6_head": (15,96,1,1),
 "r0_conv": (16,1,3,3), "r1_dw": (16,1,3,3), "r1_pw": (32,16,1,1), "r2_dw": (32,1,3,3), "r2_pw": (48,32,1,1),
 "r3_dw": (48,1,3,3), "r3_pw": (64,48,1,1), "r4_ih": (192,64), "r4_hh": (192,64),
 "r5_ih": (192,64), "r5_hh": (192,64), "r6_ctc": (37,64)
}
def main():
 p=argparse.ArgumentParser(); p.add_argument("--output",type=Path,required=True); a=p.parse_args()
 rng=np.random.default_rng(4); values={}
 for name,shape in SHAPES.items():
  values[f"{name}.weight"]=rng.normal(0,0.05,shape).astype(np.float32)
  values[f"{name}.bias"]=rng.normal(0,0.01,(shape[0],)).astype(np.float32)
 np.savez(a.output,**values); print(f"wrote {a.output}")
if __name__ == "__main__": main()
