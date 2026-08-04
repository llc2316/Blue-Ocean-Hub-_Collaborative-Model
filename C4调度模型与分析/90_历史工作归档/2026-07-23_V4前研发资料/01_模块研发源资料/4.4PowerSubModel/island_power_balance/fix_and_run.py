import os  
fn = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_power_balance\model.py'  
with open(fn, 'r', encoding='utf-8', errors='replace') as f:  
    lines = f.readlines()  
out = []  
for line in lines:  
    if 'Part 7' in line:  
        break  
    fixed = line.replace('max(0, b_net) - (min(0, b_net)', 'b_net')  
    out.append(fixed)  
with open(fn, 'w', encoding='utf-8') as f:  
    f.writelines(out)  
print(len(lines), len(out)) 
