import os  
fn = 'C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_v2/make_charts.py'  
data = open(fn, 'r', encoding='utf-8').read()  
bs = chr(92); dq = chr(34)  
data = data.replace(bs + dq + 'balance' + bs + dq, chr(39) + 'balance' + chr(39))  
data = data.replace(bs + dq + 'inject' + bs + dq, chr(39) + 'inject' + chr(39))  
data = data.replace(bs + dq + 'consume' + bs + dq, chr(39) + 'consume' + chr(39))  
data = data.replace(bs + dq + 'residual' + bs + dq, chr(39) + 'residual' + chr(39))  
data = data.replace(bs + dq + 'status' + bs + dq, chr(39) + 'status' + chr(39))  
open(fn, 'w', encoding='utf-8').write(data)  
print('Fixed:', data.count(chr(39)), 'single quotes') 
