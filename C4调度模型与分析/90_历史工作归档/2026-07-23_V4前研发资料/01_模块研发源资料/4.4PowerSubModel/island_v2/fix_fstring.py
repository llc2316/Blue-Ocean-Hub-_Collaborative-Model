import os  
fn = r'C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_v2/final_report.py'  
data = open(fn, 'r', encoding='utf-8').read()  
bs = chr(92)  
dq = chr(34)  
data = data.replace(bs + dq, chr(39))  
open(fn, 'w', encoding='utf-8').write(data)  
print('Fixed:', data.count(chr(39)), 'sq') 
