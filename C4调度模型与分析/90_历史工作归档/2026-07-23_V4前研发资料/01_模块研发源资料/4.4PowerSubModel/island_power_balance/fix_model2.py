import os  
fn = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_power_balance\model.py'  
with open(fn, 'r', encoding='utf-8', errors='replace') as f:  
    data = f.read()  
old = '# Part 7: Report Generator'  
idx = data.find(old)  
if idx >= 0:  
    data = data[:idx]  
old2 = 'max(0, b_net) - (min(0, b_net) + e + d + x + m + sp + lp)'  
new2 = 'b_net - e - d - x - m - sp - lp' 
data = data.replace(old2, new2)  
with open(fn, 'w', encoding='utf-8') as f:  
    f.write(data)  
nlines = len(data.splitlines())  
print(nlines, 'lines') 
