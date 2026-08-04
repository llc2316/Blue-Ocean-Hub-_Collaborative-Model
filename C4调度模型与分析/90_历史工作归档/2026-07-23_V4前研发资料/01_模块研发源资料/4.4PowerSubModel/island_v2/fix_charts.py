import os  
fn = 'C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_v2/make_charts.py'  
lines = open(fn, 'r', encoding='utf-8').readlines()  
out = []  
for i, line in enumerate(lines):  
    skip = False  
    if 'r1[' + chr(34) + 'balance' + chr(34) + ']' in line: skip = True  
    if 'r2[' + chr(34) + 'balance' + chr(34) + ']' in line: skip = True  
    if not skip: out.append(line)  
open(fn, 'w', encoding='utf-8').writelines(out)  
print(len(lines), 'lines to', len(out), 'lines') 
