import os  
fn = 'C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_v2/make_charts.py'  
lines = open(fn, 'r', encoding='utf-8').readlines()  
skip_pat = chr(91) + chr(39) + 'balance' + chr(39) + chr(93)  
out = [l for l in lines if skip_pat not in l]  
open(fn, 'w', encoding='utf-8').writelines(out)  
print(len(lines), 'to', len(out), 'lines') 
