#!/usr/bin/env python3
"""Summarize only FM1 CPU samples from an exported Instruments time-profile table.

All trace/XML inputs and reports stay private under Research/. No firmware bytes,
source logs or owner project contents are included in the aggregate summary.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

p=argparse.ArgumentParser()
p.add_argument('xml',type=Path);p.add_argument('--dsym',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
refs={};rows=[];addresses=defaultdict(set)
def ingest(e):
    if 'ref' in e.attrib:return refs.get(e.attrib['ref'],{})
    children=[ingest(c) for c in e]
    value={'tag':e.tag,**e.attrib,'text':e.text or '', 'children':children}
    if 'id' in e.attrib:refs[e.attrib['id']]=value
    return value
for _,elem in ET.iterparse(a.xml,events=('end',)):
    if elem.tag!='row':continue
    row=ingest(elem);items={v['tag']:v for v in row['children']}
    process=items.get('process',{}).get('fmt','')
    if process.startswith(('FM1 (','FM-1 (')):
        frames=items.get('tagged-backtrace',{}).get('children',[])
        record={'process':process,'thread':items.get('thread',{}).get('fmt',''),
                'seconds':int(items.get('sample-time',{}).get('text','0'))/1e9,
                'weightMs':int(items.get('weight',{}).get('text','0'))/1e6,'frames':[]}
        for f in frames:
            b=f.get('children',[{}])[0] if f.get('children') else {}
            name=f.get('name','unknown');addr=f.get('addr','')
            if b.get('name')=='FM1' and addr:
                addresses[b['load-addr']].add(addr)
                record['frames'].append((b['load-addr'],addr))
            else:record['frames'].append(name)
        rows.append(record)
    elem.clear()
resolved={}
for base,items in addresses.items():
    values=sorted(items)
    for offset in range(0,len(values),200):
        batch=values[offset:offset+200]
        names=subprocess.check_output(['atos','-arch','arm64','-o',str(a.dsym),'-l',base,*batch],text=True).splitlines()
        resolved.update({(base,addr):name for addr,name in zip(batch,names)})
processes={}
for process in sorted({r['process'] for r in rows}):
    selected=[r for r in rows if r['process']==process]
    main=[r for r in selected if r['thread'].startswith('Main Thread')]
    inclusive=Counter();leaf=Counter();threads=Counter()
    for r in selected:threads[r['thread']]+=r['weightMs']
    for r in main:
        names=[resolved.get(f,str(f)) if isinstance(f,tuple) else f for f in r['frames']]
        if names:leaf[names[0]]+=r['weightMs']
        for name in set(names):inclusive[name]+=r['weightMs']
    processes[process]={'samples':len(selected),'sampleWeightMs':sum(r['weightMs'] for r in selected),
        'mainSamples':len(main),'mainWeightMs':sum(r['weightMs'] for r in main),
        'sampleSpanSeconds':max((r['seconds'] for r in selected),default=0)-min((r['seconds'] for r in selected),default=0),
        'threadsMs':threads.most_common(12),'mainLeafMs':leaf.most_common(25),
        'mainInclusiveMs':inclusive.most_common(40),
        'applicationMainInclusiveMs':[(n,v) for n,v in inclusive.most_common() if '(in FM1)' in n][:40]}
result={'scope':'Statistical on-CPU samples; inclusive stacks overlap; all host processes excluded. Not a frame or wall-time measure.', 'processes':processes}
a.output.write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
