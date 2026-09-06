"""Local development-participant sensitivity at frozen shared settings."""
import argparse
from dataclasses import replace
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from harness.parameters import load
from harness.fit import DE_BOUNDS, quantile_cost
from harness.human_data import targets
from harness.tasks import TASKS


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root",type=Path,default=ROOT/'data/model/repair_20260905')
    args=ap.parse_args()
    p=load(args.root/'selected.json')
    target=targets(args.root/'human','validation')
    rows=[]
    for name,lo,hi in DE_BOUNDS:
        center=getattr(p,name)
        for direction in (-1,0,1):
            value=min(hi,max(lo,center+direction*.1*(hi-lo)))
            if name=='memory': value=int(round(value))
            candidate=replace(p,**{name:value})
            costs=[quantile_cost(t,candidate,100,s,target[t])[0] for s in (251,252) for t in TASKS]
            rows.append(dict(parameter=name,value=getattr(candidate,name),direction=direction,
                             validation_cost=sum(costs)/len(costs),lo=lo,hi=hi,
                             boundary=center<=lo+.01*(hi-lo) or center>=hi-.01*(hi-lo)))
    (args.root/'sensitivity.json').write_text(json.dumps(dict(rows=rows,seeds=[251,252],
        split='validation',use='diagnostic only; no reselection after freeze'),indent=2))
    print('Sensitivity diagnostics saved; frozen selection unchanged')


if __name__=='__main__': main()
