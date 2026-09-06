"""ACT-R confirmation of the frozen fit's secondary manipulations.

These runs have independent seeds and the shared block/practice protocol. They
are kept separate from the mirror's long uninterrupted prevalence blocks.
"""
import argparse
from dataclasses import replace
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from harness.parameters import load, lisp_values, configuration
from harness.run_batch import ACTRSession, run_batch


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root",type=Path,default=ROOT/'data/model/repair_20260905')
    args=ap.parse_args()
    p=load(args.root/'selected.json')
    out=args.root/'actr_studies'
    out.mkdir(parents=True,exist_ok=True)
    studies=[('known_priming',p,'feature',(12,),1000,.5,True,'benchmark'),
             ('unknown_priming',p,'feature',(12,),1000,.5,True,'unknown_priming'),
             ('unknown_no_history',replace(p,w_h=0),'feature',(12,),1000,.5,True,'unknown_priming'),
             ('prevalence10',p,'conjunction',(3,6,12,18),400,.1,False,'benchmark'),
             ('prevalence50',p,'conjunction',(3,6,12,18),400,.5,False,'benchmark'),
             ('capture',p,'feature',(3,4,5,6),250,.5,False,'capture'),
             ('capture_bu3',replace(p,w_bu=3),'feature',(3,4,5,6),250,.5,False,'capture')]
    record=[]
    with ACTRSession(log_path=out/'lisp.log') as session:
        for name,params,task,sizes,n,prevalence,priming,study in studies:
            for seed in (501,502):
                run_batch(session.actr,(task,),sizes,n,seed,lisp_values(params),out,name,
                          prevalence=prevalence,priming=priming,session=session,
                          study=study,progress=False)
            record.append(dict(id=name,params=configuration(params),seeds=[501,502],
                               study=study,practice='30 synthetic trials before each block',n_per_cell=n))
            print('completed',name,flush=True)
    (out/'manifest.json').write_text(json.dumps(record,indent=2))


if __name__=='__main__': main()
